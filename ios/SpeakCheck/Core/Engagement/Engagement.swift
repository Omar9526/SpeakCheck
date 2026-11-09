import Foundation

/// Удержание: серия дней, слово дня, личный список трудных слов.
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

    // MARK: Слово дня

    struct DailyWord: Hashable, Sendable {
        let word: String
        let hint: String
        let example: String
    }

    static let dailyWords: [DailyWord] = [
        .init(word: "thought", hint: "/θ/ — кончик языка между зубами, не «с» и не «ф»", example: "I thought about it all day."),
        .init(word: "comfortable", hint: "Три слога: COMF-ta-ble, «or» не произносится", example: "This chair is very comfortable."),
        .init(word: "world", hint: "Губы в трубочку для /w/, затем мягкое /ɝl/", example: "People around the world speak English."),
        .init(word: "vegetable", hint: "VEJ-ta-ble — три слога, ударение на первый", example: "Eat a vegetable every day."),
        .init(word: "squirrel", hint: "SKWUR-əl — два слога в американском варианте", example: "A squirrel ran up the tree."),
        .init(word: "rural", hint: "Два /r/ подряд: язык не касается нёба", example: "They live in a rural area."),
        .init(word: "clothes", hint: "Звучит как «klouðz», /ð/ звонкий", example: "I need new clothes."),
        .init(word: "specific", hint: "spə-SIF-ik — ударение на второй слог", example: "Can you be more specific?"),
        .init(word: "entrepreneur", hint: "on-truh-pruh-NUR — ударение в конце", example: "She is a young entrepreneur."),
        .init(word: "colleague", hint: "KOL-eeg — «-ague» читается как /iːɡ/", example: "My colleague helped me."),
        .init(word: "schedule", hint: "Американское SKEJ-ool", example: "What is your schedule today?"),
        .init(word: "three", hint: "/θr/ — сначала язык между зубами, затем /r/", example: "I have three brothers."),
        .init(word: "development", hint: "di-VEL-əp-mənt — ударение на второй слог", example: "Software development is my job."),
        .init(word: "beach", hint: "Долгий /iː/ — иначе получится другое слово", example: "Let's go to the beach."),
        .init(word: "sheet", hint: "Долгий /iː/ и чёткое /ʃ/", example: "Write it on a sheet of paper."),
        .init(word: "think", hint: "/θ/ глухой, не «синк» и не «финк»", example: "I think you are right."),
        .init(word: "breakfast", hint: "BREK-fəst — «ea» как /e/", example: "Breakfast is ready."),
        .init(word: "Wednesday", hint: "WENZ-day — первая «d» не читается", example: "See you on Wednesday."),
        .init(word: "particularly", hint: "pər-TIK-yə-lər-lee — пять слогов", example: "I particularly like this song."),
        .init(word: "receipt", hint: "ri-SEET — «p» не читается", example: "Keep the receipt."),
        .init(word: "island", hint: "EYE-lənd — «s» не читается", example: "We visited a small island."),
        .init(word: "photography", hint: "fə-TOG-rə-fee — ударение на второй слог", example: "Photography is my hobby."),
        .init(word: "pronunciation", hint: "prə-nun-see-AY-shən — не «pronOUnciation»", example: "Your pronunciation is improving."),
        .init(word: "world-class", hint: "Связка /ld/ + /kl/ без лишнего гласного", example: "It is a world-class university."),
        .init(word: "although", hint: "awl-THOH — звонкий /ð/", example: "Although it rained, we went out."),
        .init(word: "worse", hint: "/wɝs/ — не путать с worth", example: "The weather got worse."),
        .init(word: "worth", hint: "/wɝθ/ — на конце /θ/", example: "It was worth the effort."),
        .init(word: "probably", hint: "PROB-ə-blee — в быстрой речи «PROB-lee»", example: "It will probably rain."),
        .init(word: "career", hint: "kə-RIR — ударение на второй слог", example: "She started her career in 2020."),
        .init(word: "lettuce", hint: "LET-is — вторая гласная очень короткая", example: "Add some lettuce to the salad.")
    ]

    static func wordOfTheDay(date: Date = .now, calendar: Calendar = .current) -> DailyWord {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return dailyWords[day % dailyWords.count]
    }
}
