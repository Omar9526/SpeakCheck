import Foundation
import Observation

/// Локальное хранилище документов и попыток (гостевой режим / офлайн-кеш).
/// На этапе 3 станет кешем поверх серверного API.
@MainActor
@Observable
final class AppStore {
    private(set) var documents: [SCDocument] = []
    private(set) var attempts: [ReadingAttempt] = []
    var hasCompletedOnboarding: Bool {
        didSet { if persists { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }
    }

    /// Цель подготовки (экзамен/собеседование и дата). nil — ещё не выбрана.
    var goal: PracticeGoal? {
        didSet {
            guard persists else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(goal), forKey: Keys.goal)
            ProfileSync.push(.init(goal: goal?.kind.rawValue))
        }
    }

    private let fileURL: URL
    private let persists: Bool

    private enum Keys {
        static let onboarding = "sc.onboardingDone"
        static let goal = "sc.goal"
        static let firstLaunch = "sc.firstLaunchAt"
        static let firstScoreReported = "sc.firstScoreReported"
    }

    private struct Snapshot: Codable {
        var documents: [SCDocument]
        var attempts: [ReadingAttempt]
    }

    init(persists: Bool = true) {
        self.persists = persists
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeakCheck", isDirectory: true)
        fileURL = dir.appendingPathComponent("library.json")
        hasCompletedOnboarding = persists && UserDefaults.standard.bool(forKey: Keys.onboarding)
        if persists {
            goal = UserDefaults.standard.data(forKey: Keys.goal).flatMap { try? JSONDecoder().decode(PracticeGoal.self, from: $0) }
            if UserDefaults.standard.object(forKey: Keys.firstLaunch) == nil {
                UserDefaults.standard.set(Date.now, forKey: Keys.firstLaunch)
            }
            load()
        }
    }

    // MARK: Queries

    func document(id: UUID) -> SCDocument? {
        documents.first { $0.id == id }
    }

    func document(challenge: ChallengeInfo) -> SCDocument? {
        documents.first { $0.challenge?.code == challenge.code }
    }

    func attempt(id: UUID) -> ReadingAttempt? {
        attempts.first { $0.id == id }
    }

    func attempts(for documentID: UUID) -> [ReadingAttempt] {
        attempts.filter { $0.documentID == documentID }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Последний документ, который не дочитан, — для карточки «Продолжить чтение».
    var continueDocument: SCDocument? {
        documents
            .filter { $0.status == .ready && $0.practice == nil && $0.completedSegments < $0.segments.count }
            .max { $0.createdAt < $1.createdAt }
    }

    // MARK: Mutations

    /// Документ готового ответа: уже начатый (без дубликатов) или новый.
    func starterDocument(_ starter: StarterText) -> SCDocument {
        if let existing = documents.first(where: { $0.title == starter.title && $0.source == .manual }) { return existing }
        return add(StarterTexts.document(from: starter))
    }

    @discardableResult
    func add(_ document: SCDocument) -> SCDocument {
        documents.insert(document, at: 0)
        save()
        return document
    }

    func update(_ document: SCDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[index] = document
        save()
    }

    func deleteDocument(id: UUID) {
        documents.removeAll { $0.id == id }
        attempts.removeAll { $0.documentID == id }
        save()
    }

    func add(_ attempt: ReadingAttempt) {
        attempts.insert(attempt, at: 0)
        save()
    }

    /// Сохраняет новую попытку (старые не перезаписываются, ТЗ 4.2) и пересчитывает прогресс документа.
    func record(_ attempt: ReadingAttempt) {
        attempts.insert(attempt, at: 0)
        refreshProgress(documentID: attempt.documentID)
        save()
        reportFirstScoreIfNeeded(attempt)
    }

    /// Метрика совета «первая оценка за 60 секунд»: один раз отправляем, сколько прошло от первого запуска.
    private func reportFirstScoreIfNeeded(_ attempt: ReadingAttempt) {
        let defaults = UserDefaults.standard
        guard persists, attempt.status == .completed, !defaults.bool(forKey: Keys.firstScoreReported),
              let firstLaunch = defaults.object(forKey: Keys.firstLaunch) as? Date else { return }
        defaults.set(true, forKey: Keys.firstScoreReported)
        let seconds = max(0, min(Int(Date.now.timeIntervalSince(firstLaunch)), 30 * 86400))
        ProfileSync.push(.init(firstScoreSeconds: seconds))
    }

    func deleteAttempt(id: UUID) {
        guard let attempt = attempt(id: id) else { return }
        attempts.removeAll { $0.id == id }
        refreshProgress(documentID: attempt.documentID)
        save()
    }

    /// Прогресс = число фрагментов с завершённой оценкой; лучший результат —
    /// взвешенная по словам сводка лучших попыток каждого фрагмента.
    private func refreshProgress(documentID: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
        let completed = attempts.filter { $0.documentID == documentID && $0.status == .completed && $0.assessment != nil }
        var bestPerSegment: [UUID: Assessment] = [:]
        for attempt in completed {
            guard let a = attempt.assessment else { continue }
            if let current = bestPerSegment[attempt.segmentID], (current.overall ?? 0) >= (a.overall ?? 0) { continue }
            bestPerSegment[attempt.segmentID] = a
        }
        let segmentIDs = Set(documents[index].segments.map(\.id))
        let relevant = bestPerSegment.filter { segmentIDs.contains($0.key) }
        documents[index].completedSegments = relevant.count
        documents[index].bestScore = AssessmentAggregator.summarize(Array(relevant.values)).overall
    }

    /// Все завершённые оценки по хронологии — для графика прогресса.
    var completedAttempts: [ReadingAttempt] {
        attempts.filter { $0.status == .completed && $0.assessment?.overall != nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func eraseAll() {
        documents = []
        attempts = []
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        documents = snapshot.documents
        attempts = snapshot.attempts
    }

    private func save() {
        guard persists else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Snapshot(documents: documents, attempts: attempts))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            // Логи без содержимого документов (ТЗ, раздел 11).
            print("AppStore save failed: \(type(of: error))")
        }
    }

    #if DEBUG
    /// Отладочное наполнение для скриншотов (`-demoData`). Только Debug.
    static func demo() -> AppStore {
        let store = AppStore(persists: false)
        store.documents = MockData.documents
        store.attempts = MockData.attempts
        store.hasCompletedOnboarding = true
        store.goal = PracticeGoal(kind: .ielts, date: Calendar.current.date(byAdding: .day, value: 24, to: .now), dailyTarget: 3)
        return store
    }
    #endif
}
