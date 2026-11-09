import SwiftUI

struct ResultView: View {
    let attemptID: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.assessmentService) private var service
    @State private var explanation: AIExplanation?
    @State private var explanationFailed = false
    @State private var loadingExplanation = false

    var body: some View {
        Group {
            if let attempt = store.attempt(id: attemptID), let assessment = attempt.assessment,
               let doc = store.document(id: attempt.documentID) {
                content(attempt: attempt, assessment: assessment, doc: doc)
            } else {
                EmptyStateView(icon: "chart.pie", title: "Результат недоступен", message: "Попытка была удалена.")
                    .padding()
            }
        }
        .screenBackground()
        .navigationTitle("Результат")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(attempt: ReadingAttempt, assessment: Assessment, doc: SCDocument) -> some View {
        let segmentIndex = doc.segments.firstIndex { $0.id == attempt.segmentID } ?? 0
        let segmentText = doc.segments.indices.contains(segmentIndex) ? doc.segments[segmentIndex].referenceText : ""
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                scoreCard(assessment)
                wordsCard(assessment)
                explanationCard(assessment: assessment, text: segmentText)

                HStack(spacing: Theme.Spacing.m) {
                    Button {
                        router.replaceTop(with: .reader(documentID: doc.id, segmentIndex: segmentIndex))
                    } label: {
                        Label("Прочитать ещё раз", systemImage: "mic.fill")
                    }
                    .buttonStyle(.primary)

                    if segmentIndex + 1 < doc.segments.count {
                        Button {
                            router.replaceTop(with: .reader(documentID: doc.id, segmentIndex: segmentIndex + 1))
                        } label: {
                            Label("Дальше", systemImage: "arrow.right")
                        }
                        .buttonStyle(.secondary)
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: ShareCard.text(score: assessment.overall), preview: SharePreview("Мой результат SpeakCheck")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Поделиться результатом")
            }
        }
    }

    // MARK: Score

    @ViewBuilder
    private func scoreCard(_ a: Assessment) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Spacer()
                Chip(text: "Анализ завершён", tint: Theme.Colors.success)
            }
            HStack(alignment: .center, spacing: Theme.Spacing.l) {
                if let overall = a.overall {
                    ScoreRing(score: overall)
                        .frame(width: 128, height: 128)
                } else {
                    VStack {
                        Text("—").font(.largeTitle.weight(.bold))
                        Text("Недоступно").font(.caption)
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 128, height: 128)
                }
                VStack(spacing: Theme.Spacing.m) {
                    MetricBar(title: "Точность звуков", value: a.accuracy, tint: Theme.Colors.accent)
                    MetricBar(title: "Беглость", value: a.fluency, tint: Theme.Colors.success)
                    MetricBar(title: "Полнота", value: a.completeness, tint: Theme.Colors.accentLight)
                    if let prosody = a.prosody {
                        MetricBar(title: "Интонация", value: prosody, tint: Theme.Colors.warning)
                    }
                }
            }
        }
        .card()
    }

    // MARK: Words

    private func wordsCard(_ a: Assessment) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Текст с анализом")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            HStack(spacing: Theme.Spacing.m) {
                legend(Theme.Colors.danger, "Ошибка")
                legend(Theme.Colors.warning, "Улучшить")
                legend(Theme.Colors.success, "Правильно")
            }
            FlowLayout(spacing: 4, lineSpacing: 8) {
                ForEach(a.words) { word in
                    WordChip(word: word) {
                        router.push(.wordDetail(attemptID: attemptID, wordIndex: word.index))
                    }
                }
            }
            Text("Нажмите на слово, чтобы послушать и повторить")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .card()
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: AI explanation

    @ViewBuilder
    private func explanationCard(assessment: Assessment, text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Label("Разбор ошибок", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if loadingExplanation { ProgressView().tint(Theme.Colors.accentLight) }
            }
            if let explanation {
                Text(explanation.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                ForEach(explanation.tips, id: \.self) { tip in
                    TipView(tip: tip)
                }
                Text(explanation.encouragement)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.success)
            } else if explanationFailed || !loadingExplanation {
                ForEach(LocalTips.tips(for: assessment), id: \.self) { tip in
                    TipView(tip: tip)
                }
            }
        }
        .card()
        .task(id: assessment.id) {
            guard explanation == nil else { return }
            loadingExplanation = true
            defer { loadingExplanation = false }
            do {
                explanation = try await service.explain(assessment: assessment, referenceText: text)
            } catch {
                explanationFailed = true
            }
        }
    }
}

/// Слово с цветовой подсветкой по оценке Azure; пропущенные — зачёркнуты.
struct WordChip: View {
    var word: WordAssessment
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(word.word)
                .font(.body)
                .strikethrough(word.isOmitted, color: Theme.Colors.danger)
                .foregroundStyle(foreground)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(background))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(word.word)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Открыть разбор слова")
    }

    private var band: ScoreBand? {
        if word.isOmitted { return .poor }
        if word.errorType == .insertion { return nil }
        return word.score.map { ScoreBand(score: $0) }
    }

    private var foreground: Color {
        switch band {
        case .good, nil: Theme.Colors.textPrimary
        case .fair, .poor: Theme.Colors.background
        }
    }

    private var background: Color {
        switch band {
        case .good: Theme.Colors.success.opacity(0.14)
        case .fair: Theme.Colors.warning
        case .poor: Theme.Colors.danger
        case nil: Theme.Colors.surfaceRaised
        }
    }

    private var accessibilityValue: String {
        if word.isOmitted { return "пропущено" }
        if let s = word.score { return "\(Int(s)) процентов, \(ScoreBand(score: s).title)" }
        return word.errorType?.title ?? "не оценено"
    }
}

struct TipView: View {
    var tip: TipItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(tip.word)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("· \(tip.issue)")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }
            Text(tip.explanation)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            if !tip.exercise.isEmpty {
                Label(tip.exercise, systemImage: "figure.mind.and.body")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.accentLight)
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Theme.Colors.surfaceRaised.opacity(0.7)))
    }
}

/// Шаблонные подсказки — fallback, если DeepSeek недоступен (ТЗ, раздел 8). Числа не меняются.
enum LocalTips {
    static func tips(for assessment: Assessment) -> [TipItem] {
        let problems = assessment.words
            .filter { $0.isOmitted || ($0.score ?? 100) < ScoreThresholds.default.fair }
            .sorted { ($0.score ?? 0) < ($1.score ?? 0) }
            .prefix(3)
        guard !problems.isEmpty else {
            return [TipItem(word: "Отлично", issue: "без серьёзных ошибок",
                            explanation: "Все слова прочитаны уверенно. Попробуйте текст сложнее или читайте чуть быстрее.",
                            exercise: "")]
        }
        return problems.map { w in
            let clean = w.word.trimmingCharacters(in: .punctuationCharacters)
            if w.isOmitted {
                return TipItem(word: clean, issue: "пропущено",
                               explanation: "Слово не было прочитано. Следите за текстом пальцем или курсором.",
                               exercise: "Перечитайте предложение со словом «\(clean)» медленно.")
            }
            return TipItem(word: clean, issue: "неточное произношение",
                           explanation: "Послушайте образец и обратите внимание на ударение и звуки, отмеченные красным.",
                           exercise: "Повторите слово 3 раза медленно, затем в предложении.")
        }
    }
}

/// Текст для «Поделиться» (на этапе 6 — картинка-карточка для сторис).
enum ShareCard {
    static func text(score: Double?) -> String {
        if let score {
            return "Я прочитал(а) текст на английском на \(Int(score.rounded()))% в SpeakCheck 🎙️ Сможешь лучше?"
        }
        return "Проверяю своё английское произношение в SpeakCheck 🎙️"
    }
}

#if DEBUG
#Preview {
    let store = AppStore.demo()
    return NavigationStack { ResultView(attemptID: store.attempts[0].id) }
        .environment(store)
        .environment(Router())
}
#endif
