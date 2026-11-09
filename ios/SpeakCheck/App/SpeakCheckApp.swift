import SwiftUI

@main
struct SpeakCheckApp: App {
    @State private var store: AppStore
    @State private var router = Router()

    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        _store = State(initialValue: args.contains("-demoData") ? AppStore.demo() : AppStore())
        #else
        _store = State(initialValue: AppStore())
        #endif
        Self.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .preferredColorScheme(.dark)
                .tint(Theme.Colors.accentLight)
        }
    }

    private static func configureAppearance() {
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = UIColor(Theme.Colors.backgroundDeep)
        tabBar.shadowColor = UIColor.white.withAlphaComponent(0.06)
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.Colors.textPrimary)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.Colors.textPrimary)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
}
