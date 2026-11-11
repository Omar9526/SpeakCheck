import Foundation

// Доменные модели клиента. Повторяют модель данных ТЗ (раздел 9);
// числовые оценки приходят только от Azure — клиент их не вычисляет и не придумывает.

enum DocumentSource: String, Codable, Sendable, CaseIterable {
    case pdf, docx, txt, image, manual

    var badge: String {
        switch self {
        case .pdf: "PDF"
        case .docx: "DOCX"
        case .txt: "TXT"
        case .image: "Фото"
        case .manual: "Текст"
        }
    }
}

enum DocumentStatus: String, Codable, Sendable {
    case processing, ready, failed
}

struct ReadingSegment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var sequence: Int
    var referenceText: String
    var pageNumber: Int?

    var wordCount: Int {
        referenceText.split(whereSeparator: \.isWhitespace).count
    }
}

struct SCDocument: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var source: DocumentSource
    var status: DocumentStatus
    var segments: [ReadingSegment]
    var createdAt: Date
    /// Лучшая взвешенная оценка по документу (если есть завершённые попытки).
    var bestScore: Double?
    var completedSegments: Int
    /// Документ создан из вызова друга — для сравнения результатов.
    var challenge: ChallengeInfo? = nil

    var progress: Double {
        guard !segments.isEmpty else { return 0 }
        return Double(completedSegments) / Double(segments.count)
    }
}

enum AttemptStatus: String, Codable, Sendable {
    case queued, processing, completed, failed
}

enum WordErrorType: String, Codable, Sendable {
    case none = "None"
    case mispronunciation = "Mispronunciation"
    case omission = "Omission"
    case insertion = "Insertion"
    case unexpectedBreak = "UnexpectedBreak"
    case missingBreak = "MissingBreak"
    case monotone = "Monotone"

    var title: String {
        switch self {
        case .none: "Без ошибок"
        case .mispronunciation: "Неточное произношение"
        case .omission: "Пропущено"
        case .insertion: "Лишнее слово"
        case .unexpectedBreak: "Лишняя пауза"
        case .missingBreak: "Нет паузы"
        case .monotone: "Монотонно"
        }
    }
}

struct PhonemeAssessment: Hashable, Codable, Sendable {
    var phoneme: String
    var score: Double?
}

struct WordAssessment: Identifiable, Hashable, Codable, Sendable {
    var id: Int { index }
    var index: Int
    var word: String
    var startMs: Int?
    var endMs: Int?
    var score: Double?
    var errorType: WordErrorType?
    var phonemes: [PhonemeAssessment]?

    var isOmitted: Bool { errorType == .omission }

    /// Azure возвращает слова в нижнем регистре. Показываем как в исходном тексте:
    /// «I», «English», «The» в начале предложения.
    func displayText(reference: String) -> String {
        let tokens = reference.split { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’") }.map(String.init)
        let key = word.lowercased()
        if tokens.indices.contains(index), tokens[index].lowercased() == key { return tokens[index] }
        let matches = tokens.filter { $0.lowercased() == key }
        if matches.contains(key) || matches.isEmpty { return key == "i" ? "I" : word }
        return matches[0]
    }
}

/// Метрики Azure. `nil` — показатель не вернулся, в UI показываем «Недоступно».
struct Assessment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var overall: Double?
    var accuracy: Double?
    var fluency: Double?
    var completeness: Double?
    var prosody: Double?
    var words: [WordAssessment]
    var scoreVersion: String

    /// Число слов, которые движок реально оценил — вес для сводки.
    var assessedWordCount: Int {
        words.filter { $0.score != nil && $0.errorType != .insertion }.count
    }
}

struct TipItem: Hashable, Codable, Sendable {
    var word: String
    var issue: String
    var explanation: String
    var exercise: String
}

struct AIExplanation: Hashable, Codable, Sendable {
    var summary: String
    var tips: [TipItem]
    var encouragement: String
    var isFallback: Bool
}

struct ReadingAttempt: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var segmentID: UUID
    var documentID: UUID
    var durationMs: Int
    var status: AttemptStatus
    var createdAt: Date
    var assessment: Assessment?
    var failureReason: String?
}

/// Локальный черновик записи: хранится до успешной отправки, чтобы при сбое сети можно было повторить (ТЗ, раздел 12).
struct RecordingDraft: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var documentID: UUID
    var segmentID: UUID
    var fileName: String
    var durationMs: Int
    var createdAt: Date

    var fileURL: URL { AudioRecorder.draftsDirectory.appendingPathComponent(fileName) }
}

/// Вызов друга (сервер: /challenges). Балл автора — из его реальной попытки.
struct ChallengeInfo: Hashable, Codable, Sendable {
    var code: String
    var title: String
    var referenceText: String
    var ownerScore: Double?
    var url: URL
}
