import SwiftUI

/// Маршруты внутри вкладок.
enum Route: Hashable {
    case importDocument
    case textReview(documentID: UUID)
    case document(UUID)
    case reader(documentID: UUID, segmentIndex: Int)
    case processing(RecordingDraft)
    case result(attemptID: UUID)
    case wordDetail(attemptID: UUID, wordIndex: Int)
}

enum AppTab: Hashable {
    case home, progress, profile
}

@MainActor
@Observable
final class Router {
    var tab: AppTab = .home
    var homePath = NavigationPath()
    var progressPath = NavigationPath()

    func push(_ route: Route) {
        switch tab {
        case .home, .profile: homePath.append(route)
        case .progress: progressPath.append(route)
        }
    }

    /// Заменяет верхний экран (Processing → Result), чтобы «назад» не возвращал в анализ.
    func replaceTop(with route: Route) {
        switch tab {
        case .home, .profile:
            if !homePath.isEmpty { homePath.removeLast() }
            homePath.append(route)
        case .progress:
            if !progressPath.isEmpty { progressPath.removeLast() }
            progressPath.append(route)
        }
    }

    func popToRoot() {
        switch tab {
        case .home, .profile: homePath = NavigationPath()
        case .progress: progressPath = NavigationPath()
        }
    }
}

extension View {
    /// Регистрирует все экраны маршрутов в навигационном стеке.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .importDocument:
                ImportView()
            case .textReview(let id):
                TextReviewView(documentID: id)
            case .document(let id):
                DocumentView(documentID: id)
            case .reader(let id, let index):
                ReaderView(documentID: id, segmentIndex: index)
            case .processing(let draft):
                ProcessingView(draft: draft)
            case .result(let id):
                ResultView(attemptID: id)
            case .wordDetail(let id, let index):
                WordDetailView(attemptID: id, wordIndex: index)
            }
        }
    }
}
