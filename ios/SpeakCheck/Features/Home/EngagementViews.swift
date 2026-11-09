import SwiftUI

/// Серия дней: мотивирует возвращаться каждый день.
struct StreakBadge: View {
    var streak: Int
    var practicedToday: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: streak > 0 ? "flame.fill" : "sparkles")
                .font(.title2)
                .foregroundStyle(streak > 0 ? Theme.Colors.warning : Theme.Colors.accentLight)
                .frame(width: 44, height: 44)
                .background(Circle().fill((streak > 0 ? Theme.Colors.warning : Theme.Colors.accentLight).opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(streak > 0 ? "\(streak) \(Self.days(streak)) подряд" : "Начните серию сегодня")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(practicedToday ? "Сегодня уже тренировались — так держать!" : "Прочитайте один фрагмент, чтобы не прервать серию")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: practicedToday ? "checkmark.seal.fill" : "circle.dashed")
                .font(.title2)
                .foregroundStyle(practicedToday ? Theme.Colors.success : Theme.Colors.textTertiary)
        }
        .card(padding: Theme.Spacing.m, radius: Theme.Radius.medium)
        .accessibilityElement(children: .combine)
    }

    static func days(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "день" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "дня" }
        return "дней"
    }
}

/// Слово дня: короткая ежедневная тренировка трудного слова.
struct WordOfDayCard: View {
    var word: Engagement.DailyWord
    var onPractice: () -> Void
    @State private var speech = SpeechPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Chip(text: "Слово дня", tint: Theme.Colors.violet)
                Spacer()
                Button {
                    speech.speak(word.word)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Theme.Colors.accentLight)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.Colors.accent.opacity(0.15)))
                }
                .accessibilityLabel("Послушать слово \(word.word)")
            }
            Text(word.word)
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(word.hint)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button(action: onPractice) {
                Label("Произнести", systemImage: "mic.fill")
            }
            .buttonStyle(.secondary)
        }
        .card()
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
