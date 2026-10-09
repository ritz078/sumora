import SwiftUI

struct HoldingDetailView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    let holdingID: String

    var body: some View {
        Group {
            if let snapshot = store.snapshot, let holding = snapshot.holding(id: holdingID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: holding.assetClass.symbol)
                                .font(.title2).foregroundStyle(holding.assetClass.color)
                                .frame(width: 56, height: 56)
                                .background(holding.assetClass.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(holding.name).font(.title2.bold()).accessibilityIdentifier("holdingName")
                                Text("\(holding.symbol) · \(holding.assetClass.title)").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(holding.assetClass == .fixedDeposit ? "MATURITY AMOUNT" : holding.assetClass == .bond ? "STATEMENT VALUE" : "CURRENT VALUE").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                            MoneyText(amount: holding.value, currency: snapshot.reportingCurrency)
                                .font(.largeTitle.bold()).minimumScaleFactor(0.7).lineLimit(1)
                            if holding.assetClass == .fixedDeposit {
                                Text("Includes future interest · counted toward net worth").font(.caption).foregroundStyle(.secondary)
                            } else if holding.assetClass == .bond {
                                Text("As of the latest CAS · return unavailable").font(.caption).foregroundStyle(.secondary)
                            } else {
                                GainLossLabel(gain: holding.gain, percent: holding.gainPercent, currency: snapshot.reportingCurrency)
                                Text("Unrealized return").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).portfolioCard()
                        if holding.value == nil {
                            Label("This holding has no current price and is excluded from the portfolio valuation.", systemImage: "exclamationmark.circle")
                                .font(.subheadline).foregroundStyle(.orange)
                        }
                        VStack(spacing: 18) {
                            detailRow("Quantity") {
                                Text(preferences.hideBalances ? "••••" : "\(DisplayFormat.decimal(holding.quantity.value, digits: 6)) \(holding.unit)")
                                    .accessibilityLabel(preferences.hideBalances ? "Hidden quantity" : "\(DisplayFormat.decimal(holding.quantity.value, digits: 6)) \(holding.unit)")
                            }
                            Divider()
                            detailRow("Invested") {
                                if let amount = holding.bondTerms?.investedAmount { MoneyText(amount:amount,currency:snapshot.reportingCurrency) }
                                else if holding.costBasisKnown == false { Text("Unavailable") }
                                else { MoneyText(amount: holding.invested, currency: snapshot.reportingCurrency) }
                            }
                            if holding.assetClass != .fixedDeposit {
                                Divider()
                                detailRow("Unit price") { MoneyText(amount: holding.quote, currency: holding.quoteCurrency, fractionDigits: 2) }
                            }
                            if holding.quoteCurrency != snapshot.reportingCurrency {
                                Text("Price quoted in \(holding.quoteCurrency); portfolio value reported in \(snapshot.reportingCurrency).")
                                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.portfolioCard()
                        if let terms = holding.depositTerms {
                            VStack(spacing: 18) {
                                detailRow("Original principal") { MoneyText(amount: terms.originalPrincipal) }
                                detailRow("Interest rate") { Text("\(DisplayFormat.decimal(terms.rate.value))% p.a.") }
                                detailRow("Opened / renewed") { Text(terms.openedOn) }
                                detailRow("Matures") { Text(terms.maturesOn) }
                                detailRow("Lien") { MoneyText(amount: terms.lien) }
                            }.portfolioCard()
                        }
                        if let terms = holding.bondTerms {
                            VStack(alignment: .leading, spacing: 18) {
                                if let coupon = terms.coupon { detailRow("Stated coupon") { Text("\(DisplayFormat.decimal(coupon.value))%") } }
                                if let maturity = terms.maturesOn { detailRow("Stated maturity") { Text(maturity) } }
                                if terms.redemptionCheck {
                                    Label("Maturity passed. Verify redemption; this value is from the last CAS.",systemImage:"exclamationmark.circle").font(.footnote).foregroundStyle(.orange)
                                }
                                if let quoted = terms.quotedCoupon, quoted.value != terms.coupon?.value {
                                    detailRow("Wint quoted rate") { Text("\(DisplayFormat.decimal(quoted.value))%") }
                                }
                                if let ytm = terms.ytm { detailRow("YTM after brokerage") { Text("\(DisplayFormat.decimal(ytm.value))% p.a.") } }
                                if let projected = terms.projectedMaturityValue {
                                    detailRow("Projected value at maturity") { MoneyText(amount:projected,fractionDigits:2) }
                                    Text("Estimated from invested cash and purchase YTM, from settlement to maturity. Assumes all payouts are reinvested at the same rate, with annual compounding and actual days / 365, before tax. This is separate from today’s net worth and the final bond payment.").font(.caption).foregroundStyle(.secondary)
                                }
                                if let frequency = terms.frequency { detailRow("Interest frequency") { Text(frequency) } }
                                if let repayment = terms.repayment { detailRow("Principal repayment") { Text(repayment) } }
                                if let accrued = terms.accruedAtPurchase { detailRow("Interest paid at purchase") { MoneyText(amount:accrued,fractionDigits:2) } }
                                if let gross = terms.interestGross { detailRow("Imported gross interest") { MoneyText(amount:gross,fractionDigits:2) } }
                                if let tds = terms.tds { detailRow("Imported TDS") { MoneyText(amount:tds,fractionDigits:2) } }
                                if let net = terms.interestNet { detailRow("Imported net interest") { MoneyText(amount:net,fractionDigits:2) } }
                                if let principal = terms.principalReceived, principal.value > 0 { detailRow("Principal received") { MoneyText(amount:principal,fractionDigits:2) } }
                                if let next = terms.nextPayout { detailRow("Reported next payout") { Text(next) } }
                                if let difference = terms.payoutDifference, difference.value > 0 {
                                    Text("Some reported payouts differ slightly from gross interest less TDS. The email amounts are preserved.").font(.caption).foregroundStyle(.orange)
                                }
                                if let note = terms.reconciliationNote { Text(note).font(.caption).foregroundStyle(.orange) }
                                Text("Cash flows come from matched Wint emails. Imported totals may be incomplete. They are shown separately from the CAS value; accrued interest is not estimated.").font(.caption).foregroundStyle(.secondary)
                            }.portfolioCard()
                        }
                        if holding.assetClass != .fixedDeposit && holding.assetClass != .bond {
                        PortfolioHistoryChart(history: holding.history, referenceDate: snapshot.capturedAt, currency: snapshot.reportingCurrency, title: "Holding history").portfolioCard()
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Valuation details").font(.title3.bold())
                            sourceRow("Price source", value: holding.source)
                            sourceRow("Price basis", value: holding.priceBasis)
                            if let rate = holding.fxRate {
                                sourceRow("Currency conversion", value: preferences.hideBalances ? "Hidden conversion rate" : "1 \(holding.quoteCurrency) = \(DisplayFormat.money(rate.value, currency: snapshot.reportingCurrency, fractionDigits: 2))")
                                if let date = holding.fxAt {
                                    sourceRow("Exchange rate updated", value: DisplayFormat.age(date, relativeTo: dependencies.demoDate))
                                }
                            }
                            sourceRow("Price updated", value: holding.quoteAt.map { DisplayFormat.age($0, relativeTo: dependencies.demoDate) } ?? "Unavailable")
                            sourceRow("Holdings synced", value: DisplayFormat.age(snapshot.connections.first { $0.id == holding.accountID }?.lastSyncAt ?? snapshot.holdingsSyncAt, relativeTo: dependencies.demoDate))
                            sourceRow("Account", value: snapshot.connections.first { $0.id == holding.accountID }?.name ?? holding.accountID)
                        }.portfolioCard()
                        DemoBadge()
                    }.padding(20)
                }.refreshable { await store.refresh() }
            } else {
                ContentUnavailableView("Holding unavailable", systemImage: "questionmark.folder", description: Text("This holding is no longer in the current portfolio."))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Investment").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { BalanceVisibilityButton() } }
    }

    private func detailRow<Content: View>(_ label: String, @ViewBuilder value: () -> Content) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(label).foregroundStyle(.secondary)
                    value().fontWeight(.semibold)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top) {
                    Text(label).foregroundStyle(.secondary)
                    Spacer()
                    value().fontWeight(.semibold).multilineTextAlignment(.trailing)
                }
            }
        }.font(.subheadline)
    }
    private func sourceRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline)
        }
    }
}
