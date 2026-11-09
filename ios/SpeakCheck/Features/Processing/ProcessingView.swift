import SwiftUI

struct ProcessingView: View {
    let draft: RecordingDraft

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.assessmentService) private var service
    @Environment(\.dismiss) private var dismiss

    @State private var stage: AssessmentStage = .uploading
    @State private var failure: AssessmentError?
    @State private var task: Task<Void, Never>?
    @State private var pulse = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            if let failure {
                failureView(failure)
            } else {
                progressView
            }
            Spacer()
        }
        .padding(Theme.Spacing.l)
        .screenBackground()
        .navigationTitle("Анализ")
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(failure == nil)
        .onAppear(perform: start)
        .onDisappear { task?.cancel() }
    }

    private var progressView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.15))
                    .frame(width: 150, height: 150)
                    .scaleEffect(pulse ? 1.1 : 0.9)
                Circle()
                    .fill(Theme.Colors.accentGradient)
                    .frame(width: 96, height: 96)
                Image(systemName: "waveform")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            }
            .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.s) {
                Text("Анализируем произношение")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Сравниваем каждое слово с эталоном")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                stepRow("Отправка записи", done: stage != .uploading, active: stage == .uploading)
                stepRow("В очереди", done: [.analyzing, .finishing].contains(stage), active: stage == .queued)
                stepRow("Оценка слов и звуков", done: stage == .finishing, active: stage == .analyzing)
                stepRow("Подготовка отчёта", done: false, active: stage == .finishing)
            }
            .card()

            Button("Отменить", role: .cancel) {
                task?.cancel()
                dismiss()
            }
            .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func stepRow(_ title: String, done: Bool, active: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.success)
                } else if active {
                    ProgressView().controlSize(.small).tint(Theme.Colors.accentLight)
                } else {
                    Image(systemName: "circle").foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(width: 22)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(done || active ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "готово" : active ? "выполняется" : "ожидает")
    }

    private func failureView(_ error: AssessmentError) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            IconTile(systemName: "exclamationmark.triangle.fill", tint: Theme.Colors.warning, size: 72)
            Text("Не удалось надёжно оценить")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(error.reason)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textSecondary)

            if error.canResend {
                Button {
                    start()
                } label: {
                    Label("Отправить ещё раз", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.primary)
            }
            Button {
                deleteDraft()
                dismiss()
            } label: {
                Label("Записать заново", systemImage: "mic.fill")
            }
            .buttonStyle(.secondary)
        }
        .card(padding: Theme.Spacing.xl)
    }

    private func start() {
        failure = nil
        stage = .uploading
        guard let doc = store.document(id: draft.documentID),
              let segment = doc.segments.first(where: { $0.id == draft.segmentID }) else {
            failure = .server("Фрагмент был изменён или удалён.")
            return
        }
        task?.cancel()
        task = Task {
            do {
                let outcome = try await service.assess(draft: draft, document: doc) { stage in
                    Task { @MainActor in self.stage = stage }
                }
                let assessment = outcome.assessment
                let attempt = ReadingAttempt(
                    id: outcome.attemptID, segmentID: segment.id, documentID: doc.id, durationMs: draft.durationMs,
                    status: .completed, createdAt: .now, assessment: assessment, failureReason: nil
                )
                store.record(attempt)
                deleteDraft() // По умолчанию аудио удаляется после анализа (ТЗ, раздел 11).
                router.replaceTop(with: .result(attemptID: attempt.id))
            } catch is CancellationError {
                return
            } catch let error as AssessmentError {
                failure = error
            } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                failure = .offline
            } catch {
                failure = .serviceUnavailable
            }
        }
    }

    private func deleteDraft() {
        try? FileManager.default.removeItem(at: draft.fileURL)
    }
}

private struct AssessmentServiceKey: EnvironmentKey {
    static let defaultValue: any AssessmentService = RemoteAssessmentService.isAvailable
        ? RemoteAssessmentService(api: .shared)
        : UnconfiguredAssessmentService()
}

extension EnvironmentValues {
    var assessmentService: any AssessmentService {
        get { self[AssessmentServiceKey.self] }
        set { self[AssessmentServiceKey.self] = newValue }
    }
}
