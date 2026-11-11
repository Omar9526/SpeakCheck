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

struct PracticeTextDTO: Codable, Sendable {
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

    /// Следующий текст: из запаса на iPhone (мгновенно, без сети), иначе — с сервера.
    @MainActor
    static func next(topic: PracticeTopic) async throws -> PracticeTextDTO {
        PracticeTopic.last = topic
        let dto: PracticeTextDTO
        if let stocked = PracticeStock.shared.take(topic) {
            dto = stocked
        } else {
            dto = try await fetch(topic: topic)
        }
        UserDefaults.standard.set(dto.level, forKey: "sc.practiceLevel")
        return dto
    }

    static func fetch(topic: PracticeTopic) async throws -> PracticeTextDTO {
        try await APIClient.shared.post("practice/next", json: ["topic": topic.rawValue])
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


/// Запас текстов тренировки на iPhone: «Новый текст» открывается мгновенно и работает без интернета
/// (в метро можно читать и записывать — оценки придут, когда появится сеть).
@MainActor
final class PracticeStock {
    static let shared = PracticeStock()
    static let target = 3

    private let key = "sc.practiceStock"
    private var stock: [String: [PracticeTextDTO]]
    private var refilling: Set<String> = []

    private init() {
        stock = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: [PracticeTextDTO]].self, from: $0) } ?? [:]
    }

    func count(_ topic: PracticeTopic) -> Int { stock[topic.rawValue]?.count ?? 0 }

    /// Берёт текст из запаса (если есть) и сразу начинает пополнять запас.
    func take(_ topic: PracticeTopic) -> PracticeTextDTO? {
        defer { refill(topic: topic) }
        guard var list = stock[topic.rawValue], !list.isEmpty else { return nil }
        let text = list.removeFirst()
        stock[topic.rawValue] = list
        save()
        return text
    }

    func refill(topic: PracticeTopic) {
        guard APIClient.baseURL != nil, !refilling.contains(topic.rawValue), count(topic) < Self.target else { return }
        refilling.insert(topic.rawValue)
        Task {
            defer { refilling.remove(topic.rawValue) }
            while count(topic) < Self.target {
                guard let dto = try? await PracticeService.fetch(topic: topic) else { return }  // нет сети — позже
                stock[topic.rawValue, default: []].append(dto)
                save()
            }
        }
    }

    func clear() {
        stock = [:]
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(stock), forKey: key)
    }
}
