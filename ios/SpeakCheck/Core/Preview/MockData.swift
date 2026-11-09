#if DEBUG
import Foundation

/// Mock-данные ТОЛЬКО для SwiftUI Preview, тестов и отладочных скриншотов (ТЗ, раздел 15).
/// В Release-сборку не попадают.
enum MockData {
    static let segment = ReadingSegment(
        id: UUID(), sequence: 0,
        referenceText: StarterTexts.all[0].paragraphs[0],
        pageNumber: 1
    )

    static let document: SCDocument = {
        var doc = StarterTexts.document(from: StarterTexts.all[0])
        doc.segments[0] = segment
        doc.bestScore = 85
        doc.completedSegments = 1
        return doc
    }()

    static let documents: [SCDocument] = [
        document,
        SCDocument(
            id: UUID(), title: "Cover letter.docx", source: .docx, status: .ready,
            segments: (0..<5).map { ReadingSegment(id: UUID(), sequence: $0, referenceText: "Paragraph \($0)", pageNumber: 1) },
            createdAt: .now.addingTimeInterval(-86_400), bestScore: 72, completedSegments: 3
        ),
        SCDocument(
            id: UUID(), title: "Скан учебника", source: .image, status: .ready,
            segments: (0..<2).map { ReadingSegment(id: UUID(), sequence: $0, referenceText: "Page \($0)", pageNumber: $0 + 1) },
            createdAt: .now.addingTimeInterval(-3 * 86_400), bestScore: nil, completedSegments: 0
        )
    ]

    static let words: [WordAssessment] = {
        let tokens = segment.referenceText.split(separator: " ").map(String.init)
        return tokens.enumerated().map { index, raw in
            let word = raw.trimmingCharacters(in: .punctuationCharacters)
            switch word.lowercased() {
            case "communicate":
                return WordAssessment(
                    index: index, word: raw, startMs: index * 380, endMs: index * 380 + 420, score: 54,
                    errorType: .mispronunciation,
                    phonemes: [
                        .init(phoneme: "k", score: 40), .init(phoneme: "ə", score: 88),
                        .init(phoneme: "m", score: 92), .init(phoneme: "j", score: 61),
                        .init(phoneme: "u", score: 70), .init(phoneme: "n", score: 95),
                        .init(phoneme: "ɪ", score: 35), .init(phoneme: "k", score: 80),
                        .init(phoneme: "eɪ", score: 52), .init(phoneme: "t", score: 90)
                    ]
                )
            case "opportunities":
                return WordAssessment(index: index, word: raw, startMs: index * 380, endMs: index * 380 + 500,
                                      score: 71, errorType: .mispronunciation, phonemes: nil)
            case "access":
                return WordAssessment(index: index, word: raw, startMs: nil, endMs: nil,
                                      score: nil, errorType: .omission, phonemes: nil)
            default:
                return WordAssessment(index: index, word: raw, startMs: index * 380, endMs: index * 380 + 300,
                                      score: Double(88 + index % 10), errorType: WordErrorType.none, phonemes: nil)
            }
        }
    }()

    static let assessment = Assessment(
        id: UUID(), overall: 85, accuracy: 82, fluency: 88, completeness: 92, prosody: 79,
        words: words, scoreVersion: "azure-pa-2025"
    )

    static let attempt = ReadingAttempt(
        id: UUID(), segmentID: segment.id, documentID: document.id, durationMs: 24_000,
        status: .completed, createdAt: .now, assessment: assessment, failureReason: nil
    )

    static let attempts: [ReadingAttempt] = [
        attempt,
        ReadingAttempt(id: UUID(), segmentID: segment.id, documentID: document.id, durationMs: 27_000,
                       status: .completed, createdAt: .now.addingTimeInterval(-86_400),
                       assessment: Assessment(id: UUID(), overall: 76, accuracy: 74, fluency: 80, completeness: 95,
                                              prosody: nil, words: words, scoreVersion: "azure-pa-2025"),
                       failureReason: nil),
        ReadingAttempt(id: UUID(), segmentID: segment.id, documentID: document.id, durationMs: 31_000,
                       status: .completed, createdAt: .now.addingTimeInterval(-2 * 86_400),
                       assessment: Assessment(id: UUID(), overall: 68, accuracy: 65, fluency: 71, completeness: 88,
                                              prosody: nil, words: words, scoreVersion: "azure-pa-2025"),
                       failureReason: nil)
    ]

    static let explanation = AIExplanation(
        summary: "Хорошее чтение! Основная сложность — ударение в длинных словах и пропуск слова «access».",
        tips: [
            TipItem(word: "communicate", issue: "Ударение не на том слоге",
                    explanation: "Ударение падает на второй слог: com-MU-ni-cate. Звук /k/ в начале, не /s/.",
                    exercise: "Произнесите медленно по слогам 5 раз, затем в обычном темпе."),
            TipItem(word: "access", issue: "Слово пропущено",
                    explanation: "Вы пропустили слово при чтении. Ударение на первый слог: AC-cess.",
                    exercise: "Прочитайте последнюю фразу ещё раз, следя за каждым словом.")
        ],
        encouragement: "Вы на верном пути — ещё пара попыток, и будет 90+!",
        isFallback: false
    )
}
#endif
