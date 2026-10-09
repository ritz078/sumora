import SwiftUI

enum AppTab: Hashable { case overview, holdings, allocation, analytics, settings }

struct MainTabView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .overview
    @State private var keyboardVisible = false

    var body: some View {
        TabView(selection: $tab) {
            tabContent { OverviewView() }
                .tabItem { Label("Overview", systemImage: "square.grid.2x2.fill") }.tag(AppTab.overview)
            tabContent { HoldingsView() }
                .tabItem { Label("Holdings", systemImage: "tray.full") }.tag(AppTab.holdings)
                .badge(store.snapshot?.holdings.count ?? 0)
            tabContent { AllocationView() }
                .tabItem { Label("Allocation", systemImage: "chart.pie") }.tag(AppTab.allocation)
            tabContent { AnalyticsView() }
                .tabItem { Label("Analytics", systemImage: "chart.xyaxis.line") }.tag(AppTab.analytics)
            tabContent { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(AppTab.settings)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 24) {
            if !keyboardVisible {
                PortfolioTabBar(selection: $tab, holdingsCount: store.snapshot?.holdings.count ?? 0)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .overlay(alignment: .top) {
            if let toast = store.errorToast {
                PortfolioErrorToastView(message: toast.message) {
                    store.dismissErrorToast(id: toast.id)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.errorToast?.id)
        .task(id: store.errorToast?.id) {
            guard let id = store.errorToast?.id else { return }
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            store.dismissErrorToast(id: id)
        }
        .onChange(of: dependencies.zerodha.errorMessage) { _, message in
            if let message { store.presentErrorToast(message) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .task(id: RefreshScope(active: scenePhase == .active, tab: tab)) {
            guard scenePhase == .active, tab != .settings else { return }
            await store.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard !Task.isCancelled else { return }
                await store.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.cancelRefresh() }
        }
    }

    private func tabContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .contentMargins(.bottom, 112, for: .scrollContent)
                .toolbar(.hidden, for: .tabBar)
        }

    }

    private struct RefreshScope: Equatable {
        let active: Bool
        let tab: AppTab
    }
}
