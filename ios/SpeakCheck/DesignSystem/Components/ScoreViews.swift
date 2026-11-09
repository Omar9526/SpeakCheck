import SwiftUI

/// Круговой показатель общей оценки.
struct ScoreRing: View {
    var score: Double
    var lineWidth: CGFloat = 12
    var showsVerdict = true

    @State private var animated: Double = 0

    private var band: ScoreBand { ScoreBand(score: score) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.surfaceRaised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animated / 100)
                .stroke(
                    AngularGradient(
                        colors: [Theme.Colors.accent, Theme.Colors.accentLight, Theme.Colors.accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int(score.rounded()))%")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .minimumScaleFactor(0.6)
                if showsVerdict {
                    Text(band.verdict)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(lineWidth)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { animated = score }
        }
        .onChange(of: score) { _, new in
            withAnimation(.easeOut(duration: 0.5)) { animated = new }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Общая оценка")
        .accessibilityValue("\(Int(score.rounded())) из 100, \(band.verdict)")
    }
}

/// Строка метрики: название, процент, тонкий прогресс-бар.
/// Если значение `nil` — показывает «Недоступно» (ТЗ, раздел 6).
struct MetricBar: View {
    var title: String
    var value: Double?
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(value.map { "\(Int($0.rounded()))%" } ?? "Недоступно")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(value == nil ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.surfaceRaised)
                    if let value {
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * min(max(value, 0), 100) / 100)
                    }
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { "\(Int($0.rounded())) процентов" } ?? "Недоступно")
    }
}

/// Тонкий линейный прогресс (абзацы, документы).
struct ThinProgress: View {
    var value: Double
    var tint: Color = Theme.Colors.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.surfaceRaised)
                Capsule()
                    .fill(Theme.Colors.accentGradient)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
        .accessibilityValue("\(Int(value * 100)) процентов")
    }
}
