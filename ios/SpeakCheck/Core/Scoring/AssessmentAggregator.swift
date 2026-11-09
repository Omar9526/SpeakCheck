import Foundation

/// Сводка по нескольким фрагментам: взвешивание по числу оцениваемых слов,
/// а не простое среднее процентов (ТЗ, раздел 6).
enum AssessmentAggregator {
    struct Summary: Equatable, Sendable {
        var overall: Double?
        var accuracy: Double?
        var fluency: Double?
        var completeness: Double?
        var prosody: Double?
        var wordCount: Int
    }

    static func summarize(_ assessments: [Assessment]) -> Summary {
        Summary(
            overall: weighted(assessments, \.overall),
            accuracy: weighted(assessments, \.accuracy),
            fluency: weighted(assessments, \.fluency),
            completeness: weighted(assessments, \.completeness),
            prosody: weighted(assessments, \.prosody),
            wordCount: assessments.reduce(0) { $0 + $1.assessedWordCount }
        )
    }

    /// Взвешенное среднее только по фрагментам, где метрика реально есть.
    /// Если метрики нет ни в одном фрагменте — `nil` (не придумываем значение).
    static func weighted(_ items: [Assessment], _ metric: KeyPath<Assessment, Double?>) -> Double? {
        var sum = 0.0
        var weight = 0
        for item in items {
            guard let value = item[keyPath: metric] else { continue }
            let w = item.assessedWordCount
            guard w > 0 else { continue }
            sum += value * Double(w)
            weight += w
        }
        guard weight > 0 else { return nil }
        return sum / Double(weight)
    }
}
