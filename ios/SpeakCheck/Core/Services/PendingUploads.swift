import Foundation
import Network
import Observation

/// Записи, которые не удалось отправить (нет сети, сервис недоступен). Хранятся на iPhone и
/// отправляются сами, как только появляется интернет или приложение снова открывают.
/// Повторной платной оценки не будет: у каждой записи свой Idempotency-Key (id черновика).
@MainActor
@Observable
final class PendingUploads {
    static let shared = PendingUploads()

    private(set) var drafts: [RecordingDraft] = []
    private(set) var isSending = false
    /// Сколько записей отправлено в фоне — для подсказки на главной.
    var sentInBackground = 0

    private let key = "sc.pendingDrafts"
    private let monitor = NWPathMonitor()
    private weak var store: AppStore?
    private var started = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([RecordingDraft].self, from: data) {
            drafts = saved.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        }
    }

    func start(store: AppStore) {
        self.store = store
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.sendAll() }
        }
        monitor.start(queue: DispatchQueue(label: "kg.speakcheck.network"))
        sendAll()
    }

    func add(_ draft: RecordingDraft) {
        guard !drafts.contains(where: { $0.id == draft.id }) else { return }
        drafts.append(draft)
        save()
    }

    func remove(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        save()
    }

    func clear() {
        drafts.removeAll()
        save()
    }

    func sendAll() {
        guard !isSending, !drafts.isEmpty, RemoteAssessmentService.isAvailable, let store else { return }
        isSending = true
        Task {
            defer { isSending = false }
            let service = RemoteAssessmentService(api: .shared)
            for draft in drafts {
                guard FileManager.default.fileExists(atPath: draft.fileURL.path),
                      let doc = store.document(id: draft.documentID),
                      doc.segments.contains(where: { $0.id == draft.segmentID }) else {
                    discard(draft)  // текст удалили или файла нет — отправлять нечего
                    continue
                }
                do {
                    let outcome = try await service.assess(draft: draft, document: doc) { _ in }
                    store.record(ReadingAttempt(
                        id: outcome.attemptID, segmentID: draft.segmentID, documentID: doc.id,
                        durationMs: draft.durationMs, status: .completed, createdAt: draft.createdAt,
                        assessment: outcome.assessment, failureReason: nil))
                    discard(draft)
                    sentInBackground += 1
                } catch let error as AssessmentError where !error.canResend {
                    discard(draft)  // запись непригодна (тихо, не тот текст) — повтор не поможет
                } catch {
                    return  // сеть снова пропала — попробуем при следующем подключении
                }
            }
        }
    }

    private func discard(_ draft: RecordingDraft) {
        try? FileManager.default.removeItem(at: draft.fileURL)
        remove(draft.id)
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(drafts), forKey: key)
    }
}
