import SwiftUI

struct WordDetailView: View {
    let attemptID: UUID
    let wordIndex: Int

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var speech = SpeechPlayer()

    var body: some View {
        Group {
            if let attempt = store.attempt(id: attemptID),
               let word = attempt.assessment?.words.first(where: { $0.index == wordIndex }) {
                content(word: word, attempt: attempt)
            } else {
                EmptyStateView(icon: "textformat", title: "Слово не найдено", message: "Попытка была удалена.")
                    .padding()
            }
        }
        .screenBackground()
        .navigationTitle("Разбор слова")
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speech.stop() }
    }

    private func content(word: WordAssessment, attempt: ReadingAttempt) -> some View {
        let reference = store.documents.lazy.flatMap(\.segments).first { $0.id == attempt.segmentID }?.referenceText ?? ""
        let clean = word.displayText(reference: reference).trimmingCharacters(in: .punctuationCharacters)
        let band: ScoreBand? = word.isOmitted ? .poor : word.score.map { ScoreBand(score: $0) }
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: band == .good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(band?.color ?? Theme.Colors.textSecondary)
                        Text(clean)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { scoreLine(word) }
                        VStack(alignment: .leading, spacing: 4) { scoreLine(word) }
                    }
                    .font(.headline)
                    if let error = word.errorType, error != .none {
                        Chip(text: error.title, tint: Theme.Colors.warning)
                    }

                    AdaptiveStack(spacing: Theme.Spacing.m) {
                        Button {
                            speech.speak(clean)
                        } label: {
                            Label("Послушать", systemImage: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.secondary)
                        Button {
                            speech.speak(clean, slow: true)
                        } label: {
                            Label("Медленно", systemImage: "tortoise.fill")
                        }
                        .buttonStyle(.secondary)
                    }
                }
                .card()

                if let phonemes = word.phonemes, !phonemes.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Text("Звуки")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        FlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(Array(phonemes.enumerated()), id: \.offset) { _, p in
                                VStack(spacing: 2) {
                                    Text("/\(p.phoneme)/")
                                        .font(.body.monospaced().weight(.semibold))
                                    Text(p.score.map { "\(Int($0))" } ?? "—")
                                        .font(.caption2.monospacedDigit())
                                }
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill((p.score.map { ScoreBand(score: $0).color } ?? Theme.Colors.textTertiary).opacity(0.25))
                                )
                                .accessibilityElement(children: .combine)
                            }
                        }
                        Text("Красным отмечены звуки, которые прозвучали неточно.")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .card()
                }

                Text("Потренироваться")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Button {
                    practice(word: clean, attempt: attempt)
                } label: {
                    Label("Повторить слово", systemImage: "mic.fill")
                }
                .buttonStyle(.primary)
            }
            .padding(Theme.Spacing.l)
        }
    }

    /// Повтор: создаём мини-документ из одного слова/предложения и открываем чтение.
    /// Исторические попытки не перезаписываются (ТЗ 4.2).
    private func practice(word: String, attempt: ReadingAttempt) {
        let doc = SCDocument(
            id: UUID(), title: "Тренировка: \(word)", source: .manual, status: .ready,
            segments: [ReadingSegment(id: UUID(), sequence: 0, referenceText: word, pageNumber: nil)],
            createdAt: .now, bestScore: nil, completedSegments: 0
        )
        store.add(doc)
        router.push(.reader(documentID: doc.id, segmentIndex: 0))
    }

    @ViewBuilder
    private func scoreLine(_ word: WordAssessment) -> some View {
        Text("Ваше произношение:")
            .foregroundStyle(Theme.Colors.textSecondary)
        if let score = word.score {
            Text("\(Int(score.rounded()))%")
                .fontWeight(.bold)
                .foregroundStyle(ScoreBand(score: score).color)
        } else {
            Text(word.isOmitted ? "пропущено" : "Недоступно")
                .fontWeight(.semibold)
                .foregroundStyle(word.isOmitted ? Theme.Colors.danger : Theme.Colors.textTertiary)
        }
    }
}

#if DEBUG
#Preview {
    let store = AppStore.demo()
    return NavigationStack { WordDetailView(attemptID: store.attempts[0].id, wordIndex: 7) }
        .environment(store)
        .environment(Router())
}
#endif
