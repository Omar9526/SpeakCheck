import SwiftUI

struct ReaderView: View {
    let documentID: UUID
    @State var segmentIndex: Int

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var recorder = AudioRecorder()
    @State private var speech = SpeechPlayer()
    @State private var alert: ReaderAlert?
    @State private var textSize: CGFloat = 20
    /// Масштаб системного размера текста (Dynamic Type): 100 при стандартном.
    @ScaledMetric(relativeTo: .title3) private var typeScale: CGFloat = 100
    private var readingSize: CGFloat { textSize * min(typeScale / 100, 2.2) }

    init(documentID: UUID, segmentIndex: Int) {
        self.documentID = documentID
        _segmentIndex = State(initialValue: segmentIndex)
    }

    var body: some View {
        Group {
            if let doc = store.document(id: documentID), doc.segments.indices.contains(segmentIndex) {
                content(doc, segment: doc.segments[segmentIndex])
            } else {
                EmptyStateView(icon: "text.badge.xmark", title: "Фрагмент не найден", message: "Вернитесь к документу.")
                    .padding()
            }
        }
        .screenBackground()
        .navigationTitle("Чтение текста")
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Крупнее", systemImage: "textformat.size.larger") { textSize = min(textSize + 2, 30) }
                    Button("Мельче", systemImage: "textformat.size.smaller") { textSize = max(textSize - 2, 15) }
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Настройки чтения")
            }
        }
        .onDisappear {
            if recorder.state != .stopped { recorder.discard() }
            speech.stop()
        }
        .alert(item: $alert) { item in
            switch item {
            case .permission:
                Alert(
                    title: Text("Нет доступа к микрофону"),
                    message: Text("Разрешите микрофон в Настройках, чтобы записать чтение."),
                    primaryButton: .default(Text("Открыть Настройки")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    },
                    secondaryButton: .cancel(Text("Отмена"))
                )
            case .message(let title, let text):
                Alert(title: Text(title), message: Text(text), dismissButton: .default(Text("Понятно")))
            }
        }
    }

    private func content(_ doc: SCDocument, segment: ReadingSegment) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(doc.practice != nil ? "Тренировка · \(doc.title)" : "\(segmentIndex + 1) из \(doc.segments.count) фрагментов")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accentLight)
                ThinProgress(value: Double(segmentIndex + 1) / Double(max(doc.segments.count, 1)))
                if let info = doc.practice {
                    PracticeFocusBanner(info: info)
                }
            }

            ScrollView {
                Text(segment.referenceText)
                    .font(.system(size: readingSize, weight: .regular))
                    .lineSpacing(readingSize * 0.35)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(Theme.Spacing.l)
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(Theme.Colors.surface.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .stroke(recorder.state == .recording ? Theme.Colors.accent.opacity(0.6) : Theme.Colors.stroke, lineWidth: 1.5)
            )
            .frame(maxHeight: .infinity)

            if recorder.state == .idle {
                HStack(spacing: Theme.Spacing.m) {
                    Button {
                        speech.isSpeaking ? speech.stop() : speech.speak(segment.referenceText)
                    } label: {
                        Label(speech.isSpeaking ? "Стоп" : "Послушать образец", systemImage: speech.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.accentLight)
                    Spacer()
                    navButtons(doc)
                }
            }

            WaveformView(levels: recorder.levels, isActive: recorder.state == .recording)
                .frame(height: 56)

            Text("\(format(recorder.elapsed)) / \(format(AudioRecorder.maxDuration))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityLabel("Время записи \(Int(recorder.elapsed)) секунд")

            controls(doc, segment: segment)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.m)
        .onAppear {
            recorder.onAutoStop = {
                alert = .message("Достигнут лимит", "Запись приостановлена на \(Int(AudioRecorder.maxDuration)) секундах. Нажмите «Стоп», чтобы отправить на оценку.")
            }
        }
    }

    private func navButtons(_ doc: SCDocument) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Button { segmentIndex -= 1 } label: { Image(systemName: "chevron.left") }
                .disabled(segmentIndex == 0)
                .accessibilityLabel("Предыдущий фрагмент")
            Button { segmentIndex += 1 } label: { Image(systemName: "chevron.right") }
                .disabled(segmentIndex >= doc.segments.count - 1)
                .accessibilityLabel("Следующий фрагмент")
        }
        .buttonStyle(.bordered)
        .tint(Theme.Colors.textSecondary)
    }

    @ViewBuilder
    private func controls(_ doc: SCDocument, segment: ReadingSegment) -> some View {
        HStack(spacing: Theme.Spacing.xxl) {
            Button {
                recorder.discard()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(CircleControlStyle())
            .disabled(recorder.state == .idle)
            .opacity(recorder.state == .idle ? 0.4 : 1)
            .accessibilityLabel("Записать заново")

            Button {
                Task { await mainAction() }
            } label: {
                Image(systemName: mainIcon)
            }
            .buttonStyle(CircleControlStyle(size: 80, prominent: true))
            .accessibilityLabel(mainLabel)

            Button {
                finish(doc, segment: segment)
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(CircleControlStyle())
            .disabled(recorder.state == .idle)
            .opacity(recorder.state == .idle ? 0.4 : 1)
            .accessibilityLabel("Завершить и оценить")
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var mainIcon: String {
        switch recorder.state {
        case .recording: "pause.fill"
        case .paused: "play.fill"
        case .idle, .stopped: "mic.fill"
        }
    }

    private var mainLabel: String {
        switch recorder.state {
        case .recording: "Пауза"
        case .paused: "Продолжить запись"
        case .idle, .stopped: "Начать запись"
        }
    }

    private func mainAction() async {
        speech.stop()
        do {
            switch recorder.state {
            case .idle, .stopped:
                recorder.discard()
                try await recorder.start()
            case .recording:
                recorder.pause()
            case .paused:
                try recorder.resume()
            }
        } catch AudioRecorder.RecorderError.permissionDenied {
            alert = .permission
        } catch {
            alert = .message("Не удалось начать запись", "Проверьте, что микрофон не занят другим приложением, и попробуйте ещё раз.")
        }
    }

    private func finish(_ doc: SCDocument, segment: ReadingSegment) {
        do {
            let result = try recorder.stop()
            let draft = RecordingDraft(
                id: UUID(), documentID: doc.id, segmentID: segment.id,
                fileName: result.url.lastPathComponent, durationMs: result.durationMs, createdAt: .now
            )
            recorder.discardStateOnly()
            router.push(.processing(draft))
        } catch AudioRecorder.RecorderError.tooShort {
            recorder.discard()
            alert = .message("Слишком короткая запись", "Прочитайте фрагмент целиком, а затем нажмите «Стоп».")
        } catch AudioRecorder.RecorderError.tooQuiet {
            recorder.discard()
            alert = .message("Вас почти не слышно", "Говорите громче или поднесите телефон ближе и попробуйте снова.")
        } catch {
            recorder.discard()
            alert = .message("Запись не сохранилась", "Попробуйте записать ещё раз.")
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

enum ReaderAlert: Identifiable {
    case permission
    case message(String, String)

    var id: String {
        switch self {
        case .permission: "permission"
        case .message(let t, _): t
        }
    }
}

#if DEBUG
#Preview {
    let store = AppStore.demo()
    return NavigationStack { ReaderView(documentID: store.documents[0].id, segmentIndex: 0) }
        .environment(store)
        .environment(Router())
}
#endif
