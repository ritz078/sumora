import SwiftUI

@main
struct SumoraApp: App {
    @State private var dependencies = AppDependencies()
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(dependencies)
                .environment(dependencies.portfolio)
                .environment(dependencies.preferences)
                .font(.inter(.body))
                .foregroundStyle(DashboardStyle.ink)
                .tint(.accentColor)
                .preferredColorScheme(dependencies.preferences.appearance.colorScheme)
        }
    }
}
