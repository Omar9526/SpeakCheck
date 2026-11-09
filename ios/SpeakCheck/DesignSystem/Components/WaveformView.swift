import SwiftUI

/// Визуализация уровня сигнала микрофона. `levels` — значения 0…1 (последние N замеров).
struct WaveformView: View {
    var levels: [Float]
    var isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let count = max(levels.count, 1)
            let barWidth = max(2, proxy.size.width / CGFloat(count) * 0.55)
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    let distance = abs(Double(index) - Double(count) / 2) / (Double(count) / 2)
                    Capsule()
                        .fill(isActive ? Theme.Colors.accentLight : Theme.Colors.textTertiary)
                        .opacity(isActive ? 0.45 + 0.55 * (1 - distance) : 0.5)
                        .frame(width: barWidth, height: max(4, proxy.size.height * CGFloat(level)))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.08), value: levels)
        }
        .accessibilityHidden(true)
    }
}
