import Foundation

/// Ссылки-вызовы: `speakcheck://c/<code>` и `https://<домен>/c/<code>`.
enum DeepLink {
    static func challengeCode(from url: URL) -> String? {
        let parts: [String]
        if url.scheme == "speakcheck" {
            parts = ([url.host].compactMap { $0 } + url.pathComponents).filter { $0 != "/" }
        } else if url.scheme == "https" || url.scheme == "http" {
            parts = url.pathComponents.filter { $0 != "/" }
        } else {
            return nil
        }
        guard parts.count == 2, parts[0] == "c" else { return nil }
        let code = parts[1]
        let allowed = CharacterSet(charactersIn: "abcdefghjkmnpqrstuvwxyz23456789")
        guard (4...16).contains(code.count), code.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return code
    }

    static func document(from challenge: ChallengeInfo) -> SCDocument {
        var doc = SCDocument(
            id: UUID(), title: "Вызов: \(challenge.title)", source: .manual, status: .ready,
            segments: TextSegmenter.segments(from: challenge.referenceText),
            createdAt: .now, bestScore: nil, completedSegments: 0
        )
        if doc.segments.isEmpty {
            doc.segments = [ReadingSegment(id: UUID(), sequence: 0, referenceText: challenge.referenceText, pageNumber: nil)]
        }
        doc.challenge = challenge
        return doc
    }
}
