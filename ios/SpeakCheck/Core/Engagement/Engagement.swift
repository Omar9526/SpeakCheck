import Foundation

/// Удержание: серия дней и личный список трудных слов.
enum Engagement {
    // MARK: Серия дней

    /// Дни подряд (по локальному календарю) хотя бы с одной завершённой оценкой.
    /// Серия не обрывается, пока сегодняшний день ещё не закончился.
    static func streak(attempts: [ReadingAttempt], now: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(attempts.filter { $0.status == .completed }.map { calendar.startOfDay(for: $0.createdAt) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    static func practicedToday(attempts: [ReadingAttempt], now: Date = .now, calendar: Calendar = .current) -> Bool {
        attempts.contains { $0.status == .completed && calendar.isDate($0.createdAt, inSameDayAs: now) }
    }

    // MARK: Трудные слова

    struct DifficultWord: Identifiable, Hashable, Sendable {
        var id: String { word }
        let word: String
        let bestScore: Double?
        let misses: Int
    }

    /// Слова, которые чаще всего звучали неточно или пропускались (по реальным оценкам Azure).
    static func difficultWords(attempts: [ReadingAttempt], threshold: Double = ScoreThresholds.default.fair,
                               limit: Int = 8) -> [DifficultWord] {
        var misses: [String: Int] = [:]
        var best: [String: Double] = [:]
        for attempt in attempts {
            for w in attempt.assessment?.words ?? [] {
                let key = w.word.trimmingCharacters(in: .punctuationCharacters).lowercased()
                guard key.count > 1, w.errorType != .insertion else { continue }
                if let s = w.score { best[key] = max(best[key] ?? 0, s) }
                if w.isOmitted || (w.score ?? 100) < threshold { misses[key, default: 0] += 1 }
            }
        }
        let good = ScoreThresholds.default.good
        // Слово, которое уже хоть раз прозвучало хорошо, считаем выученным.
        let open: [(key: String, value: Int)] = misses.filter { entry in (best[entry.key] ?? 0) < good }
        let sorted = open.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        return sorted.prefix(limit).map { entry in
            DifficultWord(word: entry.key, bestScore: best[entry.key], misses: entry.value)
        }
    }
}
