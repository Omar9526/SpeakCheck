import Foundation

/// Задания на сегодня (вкладка «Задания»): строятся из цели, реальных оценок и каталога готовых ответов.
/// Галочки ставятся автоматически по завершённым попыткам — отмечать вручную ничего не нужно.
enum DailyPlan {
    static let difficultWordsTitle = "Трудные слова"

    enum Kind: String, Sendable { case readFragments, difficultWords, newAnswer }

    struct Task: Identifiable, Hashable, Sendable {
        var id: Kind { kind }
        let kind: Kind
        let title: String
        let detail: String
        let done: Int
        let target: Int
        /// Для «нового ответа» — какой готовый текст открыть.
        let starterID: String?

        var isComplete: Bool { done >= target }
    }

    static func tasks(goal: PracticeGoal?, documents: [SCDocument], attempts: [ReadingAttempt],
                      now: Date = .now, calendar: Calendar = .current) -> [Task] {
        let today = attempts.filter { $0.status == .completed && calendar.isDate($0.createdAt, inSameDayAs: now) }
        let todayDocs = Set(today.map(\.documentID))
        let docsByID = Dictionary(documents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [Task] = []

        let target = goal?.dailyTarget ?? 3
        result.append(Task(kind: .readFragments,
                           title: "Прочитать \(target) \(RussianPlural.fragments(target))",
                           detail: "Любой текст: готовый ответ или свой документ",
                           done: min(today.count, target), target: target, starterID: nil))

        let difficult = Engagement.difficultWords(attempts: attempts, limit: 5)
        let wordsDone = todayDocs.contains { docsByID[$0]?.title.hasPrefix(difficultWordsTitle) == true }
        if !difficult.isEmpty || wordsDone {
            result.append(Task(kind: .difficultWords,
                               title: "Повторить трудные слова",
                               detail: difficult.isEmpty ? "Все слова уже звучат хорошо"
                                   : difficult.prefix(5).map(\.word).joined(separator: ", "),
                               done: wordsDone ? 1 : 0, target: 1, starterID: nil))
        }

        let starterTitles = Set(StarterTexts.all.map(\.title))
        let answerDone = todayDocs.contains { id in
            guard let doc = docsByID[id] else { return false }
            return starterTitles.contains(doc.title)
        }
        let next = nextStarter(goal: goal?.kind, documents: documents)
        result.append(Task(kind: .newAnswer,
                           title: "Готовый ответ дня",
                           detail: next?.title ?? "Все ответы пройдены — загрузите свой текст",
                           done: answerDone ? 1 : 0, target: 1, starterID: next?.id))
        return result
    }

    /// Первый готовый ответ под цель, который ещё не дочитан до конца.
    static func nextStarter(goal: PracticeGoal.Kind?, documents: [SCDocument]) -> StarterText? {
        StarterTexts.ordered(for: goal).first { starter in
            !documents.contains { $0.title == starter.title && $0.completedSegments >= $0.segments.count }
        }
    }
}
