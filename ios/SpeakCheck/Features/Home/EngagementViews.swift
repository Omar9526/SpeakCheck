import SwiftUI

enum RussianPlural {
    /// 1 день, 3 дня, 5 дней, 11 дней, 22 дня.
    static func days(_ n: Int) -> String {
        form(n, one: "день", few: "дня", many: "дней")
    }

    static func fragments(_ n: Int) -> String {
        form(n, one: "фрагмент", few: "фрагмента", many: "фрагментов")
    }

    static func form(_ n: Int, one: String, few: String, many: String) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }
}

/// Цель подготовки на главном экране: выбор цели или обратный отсчёт + план на сегодня + серия дней.
struct GoalCard: View {
    var goal: PracticeGoal?
    var attempts: [ReadingAttempt]
    var onEdit: (PracticeGoal.Kind?) -> Void
    var onPractice: () -> Void

    var body: some View {
        if let goal { progress(goal) } else { chooser }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("К чему готовитесь?")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Поставьте дату — покажем, сколько осталось, и план на каждый день.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            AdaptiveStack(spacing: Theme.Spacing.s) {
                ForEach(PracticeGoal.Kind.allCases, id: \.self) { kind in
                    Button { onEdit(kind) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: kind.icon).font(.title3)
                            Text(kind.title)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .padding(.vertical, Theme.Spacing.s)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium).fill(Theme.Colors.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private func progress(_ goal: PracticeGoal) -> some View {
        let done = PracticeGoal.doneToday(attempts: attempts)
        let streak = Engagement.streak(attempts: attempts)
        let complete = done >= goal.dailyTarget
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Chip(text: goal.kind.title, tint: Theme.Colors.accentLight)
                Spacer()
                Button { onEdit(goal.kind) } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Изменить цель")
            }
            Text(countdown(goal))
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(complete ? "План на сегодня выполнен" : "Сегодня: \(done) из \(goal.dailyTarget) \(RussianPlural.fragments(goal.dailyTarget))")
                        .font(.subheadline)
                        .foregroundStyle(complete ? Theme.Colors.success : Theme.Colors.textSecondary)
                    Spacer()
                    if streak > 0 {
                        Label("\(streak) \(RussianPlural.days(streak))", systemImage: "flame.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Colors.warning)
                            .accessibilityLabel("Серия: \(streak) \(RussianPlural.days(streak)) подряд")
                    }
                }
                ThinProgress(value: Double(min(done, goal.dailyTarget)) / Double(max(goal.dailyTarget, 1)),
                             tint: complete ? Theme.Colors.success : Theme.Colors.accent)
            }
            if !complete {
                Button(action: onPractice) {
                    Label("Тренироваться", systemImage: "mic.fill")
                }
                .buttonStyle(.primary)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }

    private func countdown(_ goal: PracticeGoal) -> String {
        guard let days = goal.daysLeft() else {
            return goal.date == nil ? "Тренируйтесь каждый день" : "Дата прошла — поставьте новую цель"
        }
        if days == 0 { return "\(goal.kind == .ielts ? "Экзамен" : "Собеседование") сегодня — удачи!" }
        return "До \(goal.kind.eventName) \(days) \(RussianPlural.days(days))"
    }
}

/// Настройка цели: тип, дата (необязательно) и сколько фрагментов в день.
struct GoalSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var goal: PracticeGoal
    @State private var hasDate: Bool
    var onSave: (PracticeGoal?) -> Void

    init(goal: PracticeGoal, onSave: @escaping (PracticeGoal?) -> Void) {
        _goal = State(initialValue: goal)
        _hasDate = State(initialValue: goal.date != nil || goal.kind != .general)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Цель") {
                    Picker("Готовлюсь к", selection: $goal.kind) {
                        ForEach(PracticeGoal.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Toggle("Есть дата", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Дата", selection: Binding(
                            get: { goal.date ?? Calendar.current.date(byAdding: .day, value: 30, to: .now)! },
                            set: { goal.date = $0 }
                        ), in: Date.now..., displayedComponents: .date)
                    }
                } footer: {
                    Text("Покажем обратный отсчёт до экзамена или собеседования.")
                }
                Section {
                    Stepper("\(goal.dailyTarget) \(RussianPlural.fragments(goal.dailyTarget)) в день",
                            value: $goal.dailyTarget, in: 1...10)
                } footer: {
                    Text("Один фрагмент — около 15–30 секунд чтения. 3 в день — хороший старт.")
                }
            }
            .navigationTitle("Моя цель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        var saved = goal
                        if hasDate {
                            saved.date = goal.date ?? Calendar.current.date(byAdding: .day, value: 30, to: .now)
                        } else {
                            saved.date = nil
                        }
                        onSave(saved)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Персональный список слов, которые даются труднее всего (по реальным оценкам).
struct DifficultWordsCard: View {
    var words: [Engagement.DifficultWord]
    var onPractice: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Нажмите на слово, чтобы потренировать его отдельно")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(words) { item in
                    Button { onPractice(item.word) } label: {
                        HStack(spacing: 6) {
                            Text(item.word).font(.subheadline.weight(.semibold))
                            if let s = item.bestScore {
                                Text("\(Int(s))").font(.caption2.monospacedDigit())
                                    .foregroundStyle(ScoreBand(score: s).color)
                            }
                        }
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.Colors.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Потренировать слово")
                }
            }
        }
        .card()
    }
}
