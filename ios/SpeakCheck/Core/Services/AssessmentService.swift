import Foundation

/// Оценка чтения. Реализация ходит на backend, который вызывает Azure Speech;
/// клиент никогда не вычисляет и не подставляет проценты сам (ТЗ, раздел 15).
/// Результат оценки: id попытки на сервере + метрики Azure.
struct AssessmentOutcome: Sendable {
    let attemptID: UUID
    let assessment: Assessment
}

protocol AssessmentService: Sendable {
    func assess(draft: RecordingDraft, document: SCDocument,
                onStatus: @escaping @Sendable (AssessmentStage) -> Void) async throws -> AssessmentOutcome
    func createChallenge(attemptID: UUID) async throws -> ChallengeInfo
    func fetchChallenge(code: String) async throws -> ChallengeInfo
    func explain(assessment: Assessment, referenceText: String) async throws -> AIExplanation
}

enum AssessmentStage: Sendable, Equatable {
    case uploading, queued, analyzing, finishing
}

enum AssessmentError: Error, Equatable {
    case notConfigured
    case offline
    case serviceUnavailable
    case tooQuiet
    case textMismatch
    case lowConfidence
    case cancelled
    case server(String)

    /// Человеческая причина для экрана «Не удалось надёжно оценить» (ТЗ 4.3).
    var reason: String {
        switch self {
        case .notConfigured: "Сервер оценки ещё не подключён. Запись сохранена — её можно отправить позже."
        case .offline: "Нет подключения к интернету. Запись сохранена — повторите отправку, когда сеть появится."
        case .serviceUnavailable: "Сервис оценки временно недоступен. Запись сохранена, попробуйте через минуту."
        case .tooQuiet: "Запись слишком тихая или с сильным шумом."
        case .textMismatch: "Речь не совпадает с текстом фрагмента. Убедитесь, что читаете выбранный абзац."
        case .lowConfidence: "Движок не уверен в результате. Попробуйте прочитать чуть медленнее и чётче."
        case .cancelled: "Оценка отменена."
        case .server(let message): message
        }
    }

    /// Можно ли переотправить ту же запись (или нужна новая).
    var canResend: Bool {
        switch self {
        case .notConfigured, .offline, .serviceUnavailable, .server: true
        case .tooQuiet, .textMismatch, .lowConfidence, .cancelled: false
        }
    }
}

/// Используется, пока backend не настроен (нет BASE_URL). Честно сообщает об этом.
struct UnconfiguredAssessmentService: AssessmentService {
    func assess(draft: RecordingDraft, document: SCDocument,
                onStatus: @escaping @Sendable (AssessmentStage) -> Void) async throws -> AssessmentOutcome {
        onStatus(.uploading)
        try await Task.sleep(for: .milliseconds(600))
        throw AssessmentError.notConfigured
    }

    func explain(assessment: Assessment, referenceText: String) async throws -> AIExplanation {
        throw AssessmentError.notConfigured
    }

    func createChallenge(attemptID: UUID) async throws -> ChallengeInfo { throw AssessmentError.notConfigured }
    func fetchChallenge(code: String) async throws -> ChallengeInfo { throw AssessmentError.notConfigured }
}
