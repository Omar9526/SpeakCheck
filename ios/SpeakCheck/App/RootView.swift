import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        Group {
            if store.hasCompletedOnboarding {
                TabView(selection: $router.tab) {
                    NavigationStack(path: $router.homePath) {
                        HomeView().routeDestinations()
                    }
                    .tabItem { Label("Главная", systemImage: "house.fill") }
                    .tag(AppTab.home)

                    NavigationStack(path: $router.progressPath) {
                        HistoryView().routeDestinations()
                    }
                    .tabItem { Label("Прогресс", systemImage: "chart.bar.fill") }
                    .tag(AppTab.progress)

                    NavigationStack {
                        SettingsView()
                    }
                    .tabItem { Label("Профиль", systemImage: "person.fill") }
                    .tag(AppTab.profile)
                }
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut, value: store.hasCompletedOnboarding)
        #if DEBUG
        .onAppear(perform: applyDebugRoute)
        #endif
    }

    #if DEBUG
    /// `-screen <name>` открывает экран напрямую — для скриншотов из симулятора.
    private func applyDebugRoute() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return }
        let doc = store.documents.first
        let attempt = store.attempts.first
        switch args[i + 1] {
        case "import": router.homePath.append(Route.importDocument)
        case "review": if let doc { router.homePath.append(Route.textReview(documentID: doc.id)) }
        case "document": if let doc { router.homePath.append(Route.document(doc.id)) }
        case "reader": if let doc { router.homePath.append(Route.reader(documentID: doc.id, segmentIndex: 0)) }
        case "processing":
            if let doc {
                router.homePath.append(Route.processing(RecordingDraft(
                    id: UUID(), documentID: doc.id, segmentID: doc.segments[0].id,
                    fileName: "demo.wav", durationMs: 24_000, createdAt: .now)))
            }
        case "result": if let attempt { router.homePath.append(Route.result(attemptID: attempt.id)) }
        case "word":
            if let attempt, let word = attempt.assessment?.words.first(where: { $0.errorType == .mispronunciation }) {
                router.homePath.append(Route.wordDetail(attemptID: attempt.id, wordIndex: word.index))
            }
        case "history": router.tab = .progress
        case "settings": router.tab = .profile
        default: break
        }
    }
    #endif
}
