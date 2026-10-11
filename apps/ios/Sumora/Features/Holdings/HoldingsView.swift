import SwiftUI

struct HoldingsView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppPreferences.self) private var preferences
    @State private var query = HoldingsQuery()
    @State private var selectedHolding: String?
    @FocusState private var searchFocused: Bool

    init(assetClass: AssetClass? = nil) {
        _query = State(initialValue: HoldingsQuery(assetClass: assetClass))
    }

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if store.errorMessage != nil || snapshot.coverage != .complete ||
                            dependencies.isLivePortfolio && snapshot.connections.contains(where: { $0.status == .attention }) ||
                            dependencies.demoDate.timeIntervalSince(snapshot.capturedAt) > 86400 {
                            PortfolioStatusView()
                        }
                        summary(snapshot)
                        categories(snapshot)
                        let holdings = query.apply(to: snapshot.holdings)
                        if holdings.isEmpty {
                            ContentUnavailableView {
                                Label(snapshot.holdings.isEmpty ? "No holdings yet" : "No matching holdings", systemImage: "magnifyingglass")
                            } description: {
                                Text(snapshot.holdings.isEmpty ? "Your investments will appear here." : "Try another search or asset filter.")
                            } actions: {
                                if !snapshot.holdings.isEmpty {
                                    Button("Clear filters") { query = HoldingsQuery(); searchFocused = false }
                                }
                            }
                        } else {
                            ForEach(AssetClass.allCases) { asset in
                                let items = holdings.filter { $0.assetClass == asset }
                                if !items.isEmpty { holdingGroup(asset, items: items, currency: snapshot.reportingCurrency) }
                            }
                        }
                        DemoBadge()
                        Text(dependencies.isLivePortfolio ? "Imported from Zerodha’s primary demat account and Coin. Secondary demat holdings are excluded." : "Sample portfolio · Illustrative values, not live prices.")
                            .font(.appFont(.caption2)).foregroundStyle(HoldingsStyle.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await store.refresh() }
                .safeAreaInset(edge: .top, spacing: 0) { header(snapshot) }
            } else { PortfolioLoadingView() }
        }
        .background(HoldingsStyle.background).foregroundStyle(HoldingsStyle.ink)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedHolding) {
            HoldingDetailView(holdingID: $0).toolbar(.visible, for: .navigationBar)
        }
        .onChange(of: query.assetClass) { _, _ in searchFocused = false }
    }

    private func header(_ snapshot: PortfolioSnapshot) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("Holdings").font(.appFont(.title2, weight: .semibold, size: 24)).tracking(-0.6)
                Spacer()
                BalanceVisibilityButton()
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 18)).frame(width: 32, height: 32)
                }.accessibilityLabel("Sync holdings").tint(HoldingsStyle.secondary)
            }.frame(minHeight: 36)
            HStack(spacing: 8) {
                Image("SearchIcon").renderingMode(.template).resizable().frame(width: 18, height: 18).accessibilityHidden(true)
                TextField("Search positions", text: $query.search, prompt: Text("Search \(snapshot.holdings.count) positions across custodians…").foregroundStyle(HoldingsStyle.secondary))
                    .font(.appFont(.caption)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                    .accessibilityIdentifier("holdingsSearch")
                if !query.search.isEmpty {
                    Button { query.search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search")
                }
                Menu {
                    Picker("Sort holdings", selection: $query.sort) {
                        ForEach(HoldingSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 14)) }
                    .accessibilityLabel("Sort holdings")
            }
            .foregroundStyle(HoldingsStyle.secondary).padding(.horizontal, 12).padding(.vertical, 6)
            .background(HoldingsStyle.fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(HoldingsStyle.border, lineWidth: 1))
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        .background(HoldingsStyle.card)
        .overlay(alignment: .bottom) { Rectangle().fill(HoldingsStyle.border).frame(height: 1) }
    }

    private func summary(_ snapshot: PortfolioSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("TOTAL NET ASSETS").font(.appFont(.caption2, weight: .medium)).tracking(0.55).foregroundStyle(HoldingsStyle.secondary)
                Spacer(minLength: 8)
                if let gain = snapshot.gainPercent, !preferences.hideBalances {
                    Text("\(gain.value >= 0 ? "+" : "")\(DisplayFormat.decimal(gain.value, digits: 1))% All-time")
                        .font(.appFont(.caption2, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(gain.value >= 0 ? DashboardStyle.positive : .red)
                }
            }
            MoneyText(amount: snapshot.value, currency: snapshot.reportingCurrency)
                .font(.appFont(.largeTitle, weight: .semibold)).tracking(-0.8).monospacedDigit()
                .accessibilityIdentifier("holdingsTotalValue")
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).holdingsSurface()
    }

    private func categories(_ snapshot: PortfolioSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton("All assets", count: snapshot.holdings.count, asset: nil)
                ForEach(AssetClass.allCases) { asset in
                    let count = snapshot.holdings.filter { $0.assetClass == asset }.count
                    if count > 0 { filterButton(asset.title, count: count, asset: asset) }
                }
            }.padding(.vertical, 2)
        }
    }

    private func filterButton(_ title: String, count: Int, asset: AssetClass?) -> some View {
        Button { query.assetClass = asset } label: {
            Text("\(asset == nil ? "All" : title) (\(count))").font(.appFont(.footnote, weight: .medium)).fixedSize()
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(query.assetClass == asset ? .white : HoldingsStyle.secondary)
                .background(query.assetClass == asset ? HoldingsStyle.primary : HoldingsStyle.fill, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityAddTraits(query.assetClass == asset ? .isSelected : [])
    }

    private func holdingGroup(_ asset: AssetClass, items: [Holding], currency: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(asset.title.uppercased()) (\(items.count))")
                .font(.appFont(.caption2, weight: .semibold)).tracking(0.55).foregroundStyle(HoldingsStyle.secondary)
                .padding(.horizontal, 4).padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(items) { holding in
                    if holding.assetClass == .indianEquity || holding.assetClass == .usEquity {
                        HoldingsPositionRow(holding: holding, currency: currency).padding(14)
                            .accessibilityElement(children: .combine).accessibilityIdentifier("holding-\(holding.id)")
                    } else {
                    Button { searchFocused = false; selectedHolding = holding.id } label: {
                        HoldingsPositionRow(holding: holding, currency: currency).padding(14).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("holding-\(holding.id)")
                    }
                    if holding.id != items.last?.id { Divider().overlay(HoldingsStyle.fill).padding(.horizontal, 14) }
                }
            }.holdingsSurface()
        }
    }
}

private struct HoldingsPositionRow: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    let holding: Holding
    let currency: String

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { identity; valuation }
            } else {
                HStack(spacing: 12) {
                    identity.frame(maxWidth: .infinity, alignment: .leading)
                    valuation.fixedSize(horizontal: true, vertical: false)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(holding.name).font(.appFont(.headline, weight: .medium)).lineLimit(1).truncationMode(.tail)
            Text("\(DisplayFormat.decimal(holding.quantity.value)) \(holding.unit)\(holding.assetClass == .usEquity ? " · \(holding.symbol)" : "")")
                .font(.appFont(.caption)).foregroundStyle(HoldingsStyle.secondary)
        }
    }

    private var valuation: some View {
        VStack(alignment: .trailing, spacing: 2) {
            MoneyText(amount: holding.value, currency: currency).font(.appFont(.subheadline, weight: .semibold, size: 14)).monospacedDigit()
            if let gain = holding.gainPercent, holding.value != nil {
                Text(preferences.hideBalances ? "••••" : "\(gain.value >= 0 ? "+" : "")\(DisplayFormat.decimal(gain.value, digits: 1))%")
                    .font(.appFont(.caption2, weight: .medium)).tracking(0.44).monospacedDigit()
                    .foregroundStyle(preferences.hideBalances ? HoldingsStyle.secondary : gain.value >= 0 ? DashboardStyle.positive : .red)
            } else {
                Text(holding.value == nil ? "Price unavailable" : "Return unavailable").font(.appFont(.caption2)).foregroundStyle(HoldingsStyle.secondary)
            }
        }
    }
}

private enum HoldingsStyle {
    static let background = adaptive(UIColor(red: 247/255, green: 249/255, blue: 251/255, alpha: 1), dark: .systemGroupedBackground)
    static let fill = adaptive(UIColor(red: 242/255, green: 244/255, blue: 246/255, alpha: 1), dark: .tertiarySystemGroupedBackground)
    static let card = adaptive(.white, dark: .secondarySystemGroupedBackground)
    static let ink = adaptive(UIColor(red: 25/255, green: 28/255, blue: 30/255, alpha: 1), dark: .label)
    static let secondary = adaptive(UIColor(red: 86/255, green: 94/255, blue: 116/255, alpha: 1), dark: .secondaryLabel)
    static let primary = adaptive(UIColor(red: 53/255, green: 37/255, blue: 205/255, alpha: 1), dark: .systemIndigo)
    static let border = adaptive(UIColor(red: 199/255, green: 196/255, blue: 216/255, alpha: 0.4), dark: .separator)
    private static func adaptive(_ light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

private extension View {
    func holdingsSurface() -> some View {
        background(HoldingsStyle.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(HoldingsStyle.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }
}
