import Charts
import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if store.completedAttempts.isEmpty {
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Здесь появится ваш прогресс",
                        message: "Прочитайте первый текст — и мы покажем динамику оценок по дням."
                    )
                } else {
                    summaryCard
                    chartCard
                }

                if !store.documents.isEmpty {
                    SectionHeader(title: "Документы и попытки")
                    ForEach(store.documents) { doc in
                        documentSection(doc)
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .screenBackground()
        .navigationTitle("Мой прогресс")
    }

    private var summaryCard: some View {
        let latest = Array(store.completedAttempts.suffix(10)).compactMap(\.assessment)
        let summary = AssessmentAggregator.summarize(latest)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Последние 10 попыток")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            AdaptiveStack(spacing: Theme.Spacing.l) {
                if let overall = summary.overall {
                    ScoreRing(score: overall, lineWidth: 10)
                        .frame(width: 110, height: 110)
                }
                VStack(spacing: Theme.Spacing.m) {
                    MetricBar(title: "Точность звуков", value: summary.accuracy, tint: Theme.Colors.accent)
                    MetricBar(title: "Беглость", value: summary.fluency, tint: Theme.Colors.success)
                    MetricBar(title: "Полнота", value: summary.completeness, tint: Theme.Colors.accentLight)
                }
            }
            AdaptiveStack(spacing: Theme.Spacing.s) {
                stat("\(store.completedAttempts.count)", "попыток")
                stat("\(summary.wordCount)", "слов оценено")
                stat("\(store.documents.count)", "документов")
            }
        }
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Динамика общей оценки")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Chart(store.completedAttempts) { attempt in
                if let score = attempt.assessment?.overall {
                    LineMark(x: .value("Дата", attempt.createdAt), y: .value("Оценка", score))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.Colors.accentLight)
                    AreaMark(x: .value("Дата", attempt.createdAt), y: .value("Оценка", score))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Theme.Colors.accent.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    PointMark(x: .value("Дата", attempt.createdAt), y: .value("Оценка", score))
                        .foregroundStyle(ScoreBand(score: score).color)
                        .symbolSize(40)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { _ in
                    AxisGridLine().foregroundStyle(Theme.Colors.stroke)
                    AxisValueLabel().foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(height: 160)
        }
        .card()
    }

    private func documentSection(_ doc: SCDocument) -> some View {
        let attempts = store.attempts(for: doc.id)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button { router.push(.document(doc.id)) } label: {
                DocumentRow(document: doc)
            }
            .buttonStyle(.plain)
            ForEach(attempts.prefix(5)) { attempt in
                attemptRow(attempt, doc: doc)
            }
        }
    }

    private func attemptRow(_ attempt: ReadingAttempt, doc: SCDocument) -> some View {
        let index = (doc.segments.firstIndex { $0.id == attempt.segmentID } ?? 0) + 1
        return Button {
            router.push(.result(attemptID: attempt.id))
        } label: {
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text("Фрагмент \(index)")
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(attempt.createdAt, format: .dateTime.day().month().hour().minute())
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                if let score = attempt.assessment?.overall {
                    Text("\(Int(score.rounded()))%")
                        .fontWeight(.semibold)
                        .foregroundStyle(ScoreBand(score: score).color)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Удалить попытку", systemImage: "trash", role: .destructive) {
                store.deleteAttempt(id: attempt.id)
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { HistoryView() }
        .environment(AppStore.demo())
        .environment(Router())
}
#endif
