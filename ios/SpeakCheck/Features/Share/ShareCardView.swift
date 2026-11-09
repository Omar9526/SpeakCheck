import SwiftUI

/// Карточка 9:16 для сторис (Instagram/Telegram/WhatsApp). Рендерится в PNG 1080×1920.
struct ShareCardView: View {
    var score: Double
    var title: String
    var excerpt: String
    var hardWord: String?
    var streak: Int

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x15254A), Theme.Colors.backgroundDeep], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.Colors.accent.opacity(0.45), .clear], center: .init(x: 0.5, y: 0.32),
                           startRadius: 0, endRadius: 260)

            VStack(spacing: 22) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.Colors.accentGradient)
                    Text("SpeakCheck").font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .padding(.top, 54)

                Text("Моё английское произношение")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)

                ScoreRing(score: score, lineWidth: 18, showsVerdict: true, animate: false)
                    .frame(width: 210, height: 210)
                    .padding(.vertical, 6)

                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Colors.accentLight)
                        .lineLimit(1)
                    Text("“\(excerpt)”")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hardWord {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.Colors.danger).frame(width: 8, height: 8)
                            Text("Самое трудное слово: ").foregroundStyle(Theme.Colors.textSecondary)
                                + Text(hardWord).foregroundStyle(Theme.Colors.textPrimary).bold()
                        }
                        .font(.system(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.Colors.surface.opacity(0.9)))
                .padding(.horizontal, 26)

                if streak > 1 {
                    Label("\(streak) \(RussianPlural.days(streak)) подряд", systemImage: "flame.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.Colors.warning)
                }

                Spacer(minLength: 0)

                Text("А ты сможешь лучше?")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Проверь своё произношение в SpeakCheck")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.bottom, 56)
            }
        }
        .frame(width: 360, height: 640)
        .environment(\.colorScheme, .dark)
    }
}

enum ShareCardRenderer {
    @MainActor
    static func image(score: Double, title: String, excerpt: String, hardWord: String?, streak: Int) -> Image? {
        let renderer = ImageRenderer(content: ShareCardView(score: score, title: title, excerpt: excerpt,
                                                            hardWord: hardWord, streak: streak))
        renderer.scale = 3 // 1080×1920
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}

#Preview {
    ShareCardView(score: 85, title: "Зачем учить английский",
                  excerpt: "Learning English is important because it helps us communicate with people around the world.",
                  hardWord: "communicate", streak: 4)
}
