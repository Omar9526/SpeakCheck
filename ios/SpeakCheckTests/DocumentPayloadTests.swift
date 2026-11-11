import Foundation
import Testing
@testable import SpeakCheck

/// Что приложение реально отправляет на POST/PATCH /documents.
struct DocumentPayloadTests {
    private let doc = SCDocument(
        id: UUID(), title: "IELTS", source: .manual, status: .ready,
        segments: [ReadingSegment(id: UUID(), sequence: 0, referenceText: "Hello world.", pageNumber: nil),
                   ReadingSegment(id: UUID(), sequence: 1, referenceText: "Second part.", pageNumber: nil)],
        createdAt: .now, bestScore: nil, completedSegments: 0)

    private func json(_ payload: DocumentPayload) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase  // как в APIClient
        return try #require(JSONSerialization.jsonObject(with: encoder.encode(payload)) as? [String: Any])
    }

    @Test func firstTrySendsLocalIDs() throws {
        let body = try json(DocumentPayload(document: doc, id: doc.id, segmentIDs: nil))
        #expect(body["id"] as? String == doc.id.uuidString)
        let segments = try #require(body["segments"] as? [[String: Any]])
        #expect(segments.map { $0["id"] as? String } == doc.segments.map { $0.id.uuidString })
    }

    @Test func retryAfterConflictSendsNoIDs() throws {
        // Именно этот запрос раньше по ошибке снова содержал занятый id.
        let body = try json(DocumentPayload(document: doc, id: nil, segmentIDs: []))
        #expect(body["id"] == nil)
        let segments = try #require(body["segments"] as? [[String: Any]])
        #expect(segments.count == 2 && segments.allSatisfy { $0["id"] == nil })
        #expect(segments.map { $0["reference_text"] as? String } == ["Hello world.", "Second part."])
    }

    @Test func patchUsesServerSegmentIDsByPosition() throws {
        let server = (UUID(), [UUID(), UUID()])
        let body = try json(DocumentPayload(document: doc, id: server.0, segmentIDs: server.1))
        #expect(body["id"] as? String == server.0.uuidString)
        let segments = try #require(body["segments"] as? [[String: Any]])
        #expect(segments.map { $0["id"] as? String } == server.1.map(\.uuidString))
    }
}
