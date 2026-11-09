import Foundation

/// Реальная оценка через backend → Azure Speech. Проценты берутся только из ответа сервера.
struct RemoteAssessmentService: AssessmentService {
    let api: APIClient

    static var isAvailable: Bool { APIClient.baseURL != nil }

    func assess(draft: RecordingDraft, document: SCDocument,
                onStatus: @escaping @Sendable (AssessmentStage) -> Void) async throws -> AssessmentOutcome {
        do {
            onStatus(.uploading)
            try await sync(document)
            // Idempotency-Key = id черновика: повторная отправка той же записи не создаёт новую платную оценку.
            var attempt: AttemptDTO = try await api.upload(
                "segments/\(draft.segmentID.uuidString.lowercased())/attempts",
                fileURL: draft.fileURL, field: "audio", mimeType: "audio/wav",
                headers: ["Idempotency-Key": draft.id.uuidString]
            )
            let deadline = Date.now.addingTimeInterval(150)
            while attempt.status == "queued" || attempt.status == "processing" {
                onStatus(attempt.status == "queued" ? .queued : .analyzing)
                guard Date.now < deadline else { throw AssessmentError.serviceUnavailable }
                try await Task.sleep(for: .milliseconds(900))
                attempt = try await api.get("attempts/\(attempt.id.uuidString.lowercased())")
            }
            onStatus(.finishing)
            if attempt.status == "failed" { throw Self.map(failure: attempt.failureCode) }
            guard let dto = attempt.assessment else { throw AssessmentError.lowConfidence }
            return AssessmentOutcome(attemptID: attempt.id, assessment: dto.model)
        } catch let error as APIClient.ClientError {
            throw Self.map(error)
        }
    }

    func explain(assessment: Assessment, referenceText: String) async throws -> AIExplanation {
        struct Body: Encodable, Sendable { let language: String }
        let language = UserDefaults.standard.string(forKey: "sc.explanationLanguage") ?? "ru"
        do {
            let dto: ExplanationDTO = try await api.post(
                "assessments/\(assessment.id.uuidString.lowercased())/explanation", json: Body(language: language))
            return AIExplanation(summary: dto.summary, tips: dto.tips, encouragement: dto.encouragement, isFallback: dto.isFallback)
        } catch let error as APIClient.ClientError {
            throw Self.map(error)
        }
    }

    func createChallenge(attemptID: UUID) async throws -> ChallengeInfo {
        struct Body: Encodable, Sendable { let attemptId: UUID }
        do {
            return try await api.post("challenges", json: Body(attemptId: attemptID))
        } catch let error as APIClient.ClientError {
            throw Self.map(error)
        }
    }

    func fetchChallenge(code: String) async throws -> ChallengeInfo {
        do {
            return try await api.get("challenges/\(code)")
        } catch let error as APIClient.ClientError {
            throw Self.map(error)
        }
    }

    /// Документ создаётся на сервере с теми же id; если текст правили — обновляем сегменты.
    private func sync(_ doc: SCDocument) async throws {
        let path = "documents/\(doc.id.uuidString.lowercased())"
        let payload = DocumentPayload(document: doc)
        do {
            let remote: DocumentDTO = try await api.get(path)
            let same = remote.segments.map { [$0.id.uuidString, $0.referenceText] } ==
                doc.segments.map { [$0.id.uuidString, $0.referenceText] }
            if !same { let _: DocumentDTO = try await api.patch(path, json: payload) }
        } catch APIClient.ClientError.server(_, let status) where status == 404 {
            let _: DocumentDTO = try await api.post("documents", json: payload)
        }
    }

    // MARK: Errors

    static func map(failure code: String?) -> AssessmentError {
        switch code {
        case "service_not_configured": .notConfigured
        case "provider_unavailable", "provider_error": .serviceUnavailable
        case "no_speech", "audio_too_quiet": .tooQuiet
        case "text_mismatch": .textMismatch
        case "low_confidence": .lowConfidence
        default: .server("Не удалось оценить запись. Попробуйте ещё раз.")
        }
    }

    static func map(_ error: APIClient.ClientError) -> AssessmentError {
        switch error {
        case .notConfigured: return .notConfigured
        case .unauthorized, .invalidResponse: return .serviceUnavailable
        case .server(let e, let status):
            if status == 422 || status == 413 || status == 429 { return .server(e.message) }
            if status >= 500 { return .serviceUnavailable }
            return map(failure: e.code)
        }
    }
}

// MARK: DTO

private struct DocumentPayload: Encodable, Sendable {
    struct Segment: Encodable, Sendable {
        let id: UUID
        let referenceText: String
        let pageNumber: Int?
    }

    let id: UUID
    let filename: String
    let source: String
    let segments: [Segment]
    /// Документ из «Вызова другу» — сервер считает, сколько вызовов приняли.
    let challengeCode: String?

    init(document: SCDocument) {
        id = document.id
        challengeCode = document.challenge?.code
        filename = String(document.title.prefix(255))
        source = document.source.rawValue
        segments = document.segments.map { Segment(id: $0.id, referenceText: $0.referenceText, pageNumber: $0.pageNumber) }
    }
}

struct DocumentDTO: Decodable, Sendable {
    struct Segment: Decodable, Sendable {
        let id: UUID
        let referenceText: String
    }

    let id: UUID
    let segments: [Segment]
}

struct AttemptDTO: Decodable, Sendable {
    let id: UUID
    let status: String
    let failureCode: String?
    let assessment: AssessmentDTO?
}

struct AssessmentDTO: Decodable, Sendable {
    struct Word: Decodable, Sendable {
        let index: Int
        let word: String
        let startMs: Int?
        let endMs: Int?
        let score: Double?
        let errorType: String?
        let phonemes: [PhonemeAssessment]?
    }

    let id: UUID
    let overall: Double?
    let accuracy: Double?
    let fluency: Double?
    let completeness: Double?
    let prosody: Double?
    let words: [Word]

    var model: Assessment {
        Assessment(
            id: id, overall: overall, accuracy: accuracy, fluency: fluency, completeness: completeness, prosody: prosody,
            words: words.map {
                WordAssessment(index: $0.index, word: $0.word, startMs: $0.startMs, endMs: $0.endMs, score: $0.score,
                               errorType: $0.errorType.flatMap(WordErrorType.init(rawValue:)), phonemes: $0.phonemes)
            },
            scoreVersion: "server"
        )
    }
}

struct ExplanationDTO: Decodable, Sendable {
    let summary: String
    let tips: [TipItem]
    let encouragement: String
    let isFallback: Bool
}
