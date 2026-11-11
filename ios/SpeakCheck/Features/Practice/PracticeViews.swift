import SwiftUI

/// Запуск нового текста тренировки: сервер подбирает текст под уровень и слабые звуки.
@MainActor
@Observable
final class PracticeLauncher {
    private(set) var isLoading = false
    var errorMessage: String?

    func start(topic: PracticeTopic, store: AppStore, router: Router, replace: Bool = false) {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let dto = try await PracticeService.next(topic: topic)
                let doc = store.addPractice(dto)
                let route = Route.reader(documentID: doc.id, segmentIndex: 0)
                replace ? router.replaceTop(with: route) : router.push(route)
            } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                errorMessage = "Нет подключения к интернету. Новые тексты приходят с сервера — проверьте сеть."
            } catch {
                errorMessage = "Не удалось получить новый текст. Попробуйте ещё раз через минуту."
            }
        }
    }
}

/// Карточка «Бесконечная тренировка» на главной и во вкладке «Задания».
struct PracticeCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var launcher = PracticeLauncher()
    @State private var topic: PracticeTopic = .surprise
    @State private var didSetTopic = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                IconTile(systemName: "infinity", tint: Theme.Colors.violet)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Бесконечная тренировка")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Каждый раз новый текст — под ваши ошибки и уровень")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let level = PracticeService.level {
                    Text(level)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Colors.violet)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.Colors.violet.opacity(0.15), in: Capsule())
                        .accessibilityLabel("Уровень \(level)")
                }
            }

            ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(PracticeTopic.allCases) { item in
                        let selected = item == topic
                        Button { topic = item } label: {
                            Label(item.title, systemImage: item.icon)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(selected ? Theme.Colors.background : Theme.Colors.textPrimary)
                                .background(selected ? Theme.Colors.accentLight : Theme.Colors.surfaceRaised, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .id(item)
                    }
                }
            }
            // Выбранная тема всегда видна, даже если она в конце ленты.
            .onChange(of: topic) { _, new in withAnimation { proxy.scrollTo(new, anchor: .center) } }
            .onAppear { proxy.scrollTo(topic, anchor: .center) }
            }

            Button {
                launcher.start(topic: topic, store: store, router: router)
            } label: {
                HStack(spacing: 8) {
                    if launcher.isLoading { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
                    Text(launcher.isLoading ? "Подбираем текст…" : "Новый текст")
                }
            }
            .buttonStyle(.primary)
            .disabled(launcher.isLoading)
        }
        .card()
        .task {
            guard !didSetTopic else { return }
            topic = PracticeTopic.default(for: store.goal?.kind)
            didSetTopic = true
        }
        .alert("Новый текст", isPresented: Binding(get: { launcher.errorMessage != nil },
                                                   set: { if !$0 { launcher.errorMessage = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(launcher.errorMessage ?? "")
        }
    }
}

/// Кнопка «Новый текст» на экране результата — тренировка без конца.
struct NewPracticeButton: View {
    var topic: PracticeTopic
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var launcher = PracticeLauncher()

    var body: some View {
        Button {
            launcher.start(topic: topic, store: store, router: router, replace: true)
        } label: {
            HStack(spacing: 6) {
                if launcher.isLoading { ProgressView() } else { Image(systemName: "sparkles") }
                Text("Новый текст").lineLimit(1)
            }
        }
        .buttonStyle(.secondary)
        .disabled(launcher.isLoading)
        .alert("Новый текст", isPresented: Binding(get: { launcher.errorMessage != nil },
                                                   set: { if !$0 { launcher.errorMessage = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(launcher.errorMessage ?? "")
        }
    }
}

/// Плашка над текстом тренировки: тема, уровень и звук, на который нацелен текст.
struct PracticeFocusBanner: View {
    var info: PracticeInfo

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "target")
                .foregroundStyle(Theme.Colors.violet)
            Group {
                if let sound = info.focusSound {
                    Text("Тренируем звук **/\(sound)/**") + Text(info.focusExample.map { " — как в *\($0)*" } ?? "")
                } else {
                    Text("\(info.topicName) · уровень \(info.level)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.Colors.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
        .accessibilityElement(children: .combine)
    }
}
