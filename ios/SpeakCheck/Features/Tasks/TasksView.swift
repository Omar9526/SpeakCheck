import SwiftUI

/// Вкладка «Задания» (макет ТЗ): цель, задания на сегодня с автоматическими галочками и каталог готовых ответов.
struct TasksView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var editingGoal: PracticeGoal?
    @State private var launcher = PracticeLauncher()

    private var tasks: [DailyPlan.Task] {
        DailyPlan.tasks(goal: store.goal, documents: store.documents, attempts: store.attempts)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                GoalCard(goal: store.goal, attempts: store.attempts,
                         onEdit: { kind in
                             editingGoal = store.goal.map { var g = $0; g.kind = kind ?? $0.kind; return g }
                                 ?? PracticeGoal(kind: kind ?? .ielts, date: nil)
                         },
                         onPractice: { start(tasks.first { !$0.isComplete } ?? tasks[0]) })

                PracticeCard()

                let list = tasks
                let completed = list.filter(\.isComplete).count
                SectionHeader(title: "На сегодня · \(completed) из \(list.count)")
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(list) { task in
                        Button { start(task) } label: { TaskRow(task: task) }
                            .buttonStyle(.plain)
                    }
                }

                ForEach(sections, id: \.title) { section in
                    SectionHeader(title: section.title)
                    VStack(spacing: Theme.Spacing.s) {
                        ForEach(section.items) { starter in
                            Button { open(starter) } label: { catalogRow(starter) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .screenBackground()
        .navigationTitle("Задания")
        .sheet(item: $editingGoal) { goal in
            GoalSetupSheet(goal: goal) { store.goal = $0 }
        }
    }

    // MARK: Каталог

    private var sections: [(title: String, items: [StarterText])] {
        let groups: [(String, PracticeGoal.Kind?)] = [("IELTS Speaking", .ielts), ("Собеседование", .interview),
                                                       ("Звуковые челленджи", nil)]
        let ordered = groups.sorted { a, b in
            guard let goal = store.goal?.kind else { return false }
            return a.1 == goal && b.1 != goal
        }
        return ordered.map { title, kind in (title, StarterTexts.all.filter { $0.goal == kind }) }
    }

    private func catalogRow(_ starter: StarterText) -> some View {
        let doc = store.documents.first { $0.title == starter.title }
        let finished = doc.map { $0.completedSegments >= $0.segments.count } ?? false
        return HStack(spacing: Theme.Spacing.m) {
            IconTile(systemName: starter.icon, tint: starter.goal == nil ? Theme.Colors.warning : Theme.Colors.accentLight)
            VStack(alignment: .leading, spacing: 2) {
                Text(starter.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(doc.map { "\($0.completedSegments) из \($0.segments.count) · \(starter.subtitle)" } ?? starter.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
            if let score = doc?.bestScore {
                Text("\(Int(score.rounded()))%")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(ScoreBand(score: score).color)
            }
            Image(systemName: finished ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(finished ? Theme.Colors.success : Theme.Colors.textTertiary)
        }
        .card(padding: Theme.Spacing.m, radius: Theme.Radius.medium)
        .accessibilityElement(children: .combine)
        .accessibilityHint(finished ? "Пройдено" : "Открыть задание")
    }

    // MARK: Действия

    private func start(_ task: DailyPlan.Task) {
        switch task.kind {
        case .readFragments:
            if let doc = store.continueDocument {
                router.push(.reader(documentID: doc.id, segmentIndex: min(doc.completedSegments, doc.segments.count - 1)))
            } else if let starter = DailyPlan.nextStarter(goal: store.goal?.kind, documents: store.documents) {
                open(starter)
            }
        case .difficultWords:
            let words = Engagement.difficultWords(attempts: store.attempts, limit: 5).map(\.word)
            guard !words.isEmpty else { return }
            // Каждое слово — отдельный фрагмент: оценка по слову и быстрый повтор.
            let doc = SCDocument(
                id: UUID(), title: "\(DailyPlan.difficultWordsTitle) · \(Date.now.formatted(.dateTime.day().month()))",
                source: .manual, status: .ready,
                segments: words.enumerated().map { ReadingSegment(id: UUID(), sequence: $0.offset, referenceText: $0.element, pageNumber: nil) },
                createdAt: .now, bestScore: nil, completedSegments: 0
            )
            store.add(doc)
            router.push(.reader(documentID: doc.id, segmentIndex: 0))
        case .newAnswer:
            if let id = task.starterID, let starter = StarterTexts.all.first(where: { $0.id == id }) { open(starter) }
            else { launcher.start(topic: PracticeTopic.default(for: store.goal?.kind), store: store, router: router) }
        }
    }

    /// Готовый ответ: продолжаем уже начатый документ, а не создаём дубликат.
    private func open(_ starter: StarterText) {
        let doc = store.starterDocument(starter)
        let index = doc.completedSegments < doc.segments.count ? doc.completedSegments : 0
        router.push(.reader(documentID: doc.id, segmentIndex: index))
    }
}

struct TaskRow: View {
    var task: DailyPlan.Task

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(task.isComplete ? Theme.Colors.success : Theme.Colors.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .strikethrough(task.isComplete, color: Theme.Colors.textTertiary)
                Text(task.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if task.target > 1 {
                Text("\(task.done)/\(task.target)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(task.isComplete ? Theme.Colors.success : Theme.Colors.textSecondary)
            }
        }
        .card(padding: Theme.Spacing.m, radius: Theme.Radius.medium)
        .accessibilityElement(children: .combine)
        .accessibilityValue(task.isComplete ? "выполнено" : "не выполнено")
    }
}
