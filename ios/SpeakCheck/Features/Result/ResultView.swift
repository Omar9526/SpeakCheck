import SwiftUI

struct ResultView: View {
    let attemptID: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.assessmentService) private var service
    @State private var explanation: AIExplanation?
    @State private var explanationFailed = false
    @State private var loadingExplanation = false
    @State private var sharePayload: SharePayload?
    @State private var challengeBusy = false
    @State private var shareError: String?

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
                if let challenge = doc.challenge, let mine = assessment.overall {
                    ChallengeComparison(mine: mine, friend: challenge.ownerScore)
                }
                scoreCard(assessment)
                if let overall = assessment.overall {
                    shareCard(score: overall, assessment: assessment, doc: doc, text: segmentText, attempt: attempt)
                }
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
                Button {
                    shareStory(assessment: assessment, doc: doc, text: segmentText)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Поделиться результатом")
                .disabled(assessment.overall == nil)
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items).presentationDetents([.medium, .large])
        }
        .alert("Не получилось", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
    }

    // MARK: Share & challenge (вирусность)

    private func shareCard(score: Double, assessment: Assessment, doc: SCDocument, text: String, attempt: ReadingAttempt) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(score >= ScoreThresholds.default.good ? "Отличный результат — похвастайтесь!" : "Позовите друга попробовать")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            HStack(spacing: Theme.Spacing.m) {
                Button {
                    shareStory(assessment: assessment, doc: doc, text: text)
                } label: {
                    Label("В сторис", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(.secondary)
                Button {
                    Task { await challengeFriend(attempt: attempt, score: score) }
                } label: {
                    if challengeBusy {
                        ProgressView().tint(.white)
                    } else {
                        Label("Вызов другу", systemImage: "flag.2.crossed.fill")
                    }
                }
                .buttonStyle(.primary)
                .disabled(challengeBusy)
            }
        }
        .card()
    }

    private func shareStory(assessment: Assessment, doc: SCDocument, text: String) {
        guard let score = assessment.overall else { return }
        let hard = assessment.words
            .filter { $0.score != nil && !$0.isOmitted && $0.errorType != .insertion }
            .min { ($0.score ?? 100) < ($1.score ?? 100) }
            .flatMap { ($0.score ?? 100) < ScoreThresholds.default.good ? $0.word.trimmingCharacters(in: .punctuationCharacters) : nil }
        let renderer = ImageRenderer(content: ShareCardView(
            score: score, title: doc.title, excerpt: String(text.prefix(160)), hardWord: hard,
            streak: Engagement.streak(attempts: store.attempts)))
        renderer.scale = 3
        var items: [Any] = [ShareCard.text(score: score)]
        if let image = renderer.uiImage { items.insert(image, at: 0) }
        sharePayload = SharePayload(items: items)
    }

    private func challengeFriend(attempt: ReadingAttempt, score: Double) async {
        challengeBusy = true
        defer { challengeBusy = false }
        do {
            let challenge = try await service.createChallenge(attemptID: attempt.id)
            let message = "Я прочитал(а) этот текст на английском на \(Int(score.rounded()))% 🎙️ Сможешь лучше? Прими вызов в SpeakCheck:"
            sharePayload = SharePayload(items: [message, challenge.url])
        } catch let error as AssessmentError {
            shareError = error == .notConfigured ? "Вызовы заработают, когда подключится сервер." : error.reason
        } catch {
            shareError = "Проверьте подключение к интернету и попробуйте ещё раз."
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

/// Сравнение с другом, бросившим вызов.
struct ChallengeComparison: View {
    var mine: Double
    var friend: Double?

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            column("Вы", mine, highlight: friend.map { mine >= $0 } ?? true)
            Text("vs").font(.headline).foregroundStyle(Theme.Colors.textTertiary)
            column("Друг", friend, highlight: friend.map { $0 > mine } ?? false)
            Spacer(minLength: 0)
            Text(verdict)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var verdict: String {
        guard let friend else { return "Вызов принят!" }
        if mine > friend { return "Вы победили! 🏆" }
        if mine == friend { return "Ничья 🤝" }
        return "Ещё попытка? 💪"
    }

    private func column(_ title: String, _ value: Double?, highlight: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.Colors.textSecondary)
            Text(value.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(highlight ? Theme.Colors.success : Theme.Colors.textPrimary)
        }
    }
}

/// Текст для «Поделиться».
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
