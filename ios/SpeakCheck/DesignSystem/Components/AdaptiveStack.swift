import SwiftUI

/// Горизонтальный ряд, который при крупном шрифте (размеры доступности) встаёт в колонку,
/// чтобы подписи кнопок и метрик не рвались по слогам.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat
    var vertical: VerticalAlignment = .center
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .center, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: vertical, spacing: spacing))
        layout { content }
    }
}
