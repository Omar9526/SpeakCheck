import Foundation

/// Темы бесконечной тренировки (совпадают с сервером).
enum PracticeTopic: String, CaseIterable, Identifiable, Sendable {
    case ielts, interview, life, surprise

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ielts: "IELTS"
        case .interview: "Собеседование"
        case .life: "Жизнь"
        case .surprise: "Сюрприз"
        }
    }
    var icon: String {
        switch self {
        case .ielts: "graduationcap.fill"
        case .interview: "briefcase.fill"
        case .life: "cup.and.saucer.fill"
        case .surprise: "sparkles"
        }
    }

    private static let key = "sc.practiceTopic"
    static var last: PracticeTopic {
        get { UserDefaults.standard.string(forKey: key).flatMap(PracticeTopic.init(rawValue:)) ?? .surprise }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Тема по цели пользователя — для первой тренировки.
    static func `default`(for goal: PracticeGoal.Kind?) -> PracticeTopic {
        switch goal {
        case .ielts: .ielts
        case .interview: .interview
        default: last
        }
    }
}

struct PracticeTextDTO: Decodable, Sendable {
    let id: UUID
    let title: String
    let text: String
    let level: String
    let topic: String
    let topicName: String
    let focusSound: String?
    let focusExample: String?
}

enum PracticeService {
    /// Последний известный уровень — для подписи на главной.
    static var level: String? { UserDefaults.standard.string(forKey: "sc.practiceLevel") }

    static func next(topic: PracticeTopic) async throws -> PracticeTextDTO {
        let dto: PracticeTextDTO = try await APIClient.shared.post("practice/next", json: ["topic": topic.rawValue])
        UserDefaults.standard.set(dto.level, forKey: "sc.practiceLevel")
        PracticeTopic.last = topic
        return dto
    }
}

@MainActor
extension AppStore {
    /// Новый текст тренировки → документ из одного фрагмента.
    func addPractice(_ dto: PracticeTextDTO) -> SCDocument {
        add(SCDocument(
            id: UUID(), title: dto.title, source: .manual, status: .ready,
            segments: [ReadingSegment(id: UUID(), sequence: 0, referenceText: dto.text, pageNumber: nil)],
            createdAt: .now, bestScore: nil, completedSegments: 0,
            practice: PracticeInfo(topic: dto.topic, topicName: dto.topicName, level: dto.level,
                                   focusSound: dto.focusSound, focusExample: dto.focusExample)))
    }
}
