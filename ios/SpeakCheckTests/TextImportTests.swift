import Foundation
import Testing
@testable import SpeakCheck

struct TextImportTests {
    @Test func paragraphsSplitOnBlankLinesAndJoinBrokenLines() {
        let text = "First line of\nparagraph one.\n\n\nSecond para-\ngraph here.\r\n\r\nThird."
        let p = TextSegmenter.paragraphs(in: text)
        #expect(p == ["First line of paragraph one.", "Second paragraph here.", "Third."])
    }

    @Test func longParagraphIsSplitBySentences() {
        let sentence = "This is a fairly simple sentence with exactly twelve words in it. "
        let long = String(repeating: sentence, count: 10) // 120 слов
        let parts = TextSegmenter.split(paragraph: long)
        #expect(parts.count >= 2)
        #expect(parts.allSatisfy { TextSegmenter.wordCount($0) <= TextSegmenter.maxWordsPerSegment })
        #expect(parts.joined(separator: " ").split(separator: " ").count == 120)
    }

    @Test func segmentsAreSequential() {
        let segs = TextSegmenter.segments(from: "One.\n\nTwo.\n\nThree.", pageNumber: 2, startSequence: 5)
        #expect(segs.map(\.sequence) == [5, 6, 7])
        #expect(segs.allSatisfy { $0.pageNumber == 2 })
    }

    @Test func englishDetection() {
        #expect(TextSegmenter.latinRatio("Hello world, how are you?") > 0.9)
        #expect(TextSegmenter.latinRatio("Привет, как дела?") < 0.1)
    }

    @Test func factoryRejectsEmptyAndNonEnglish() {
        #expect(throws: ImportError.empty) { try DocumentFactory.make(title: "x", source: .txt, pages: ["  \n\n "]) }
        #expect(throws: ImportError.noText) { try DocumentFactory.make(title: "x", source: .image, pages: [""]) }
        #expect(throws: ImportError.notEnglish) { try DocumentFactory.make(title: "x", source: .txt, pages: ["Это русский текст для проверки"]) }
        let doc = try? DocumentFactory.make(title: "x", source: .txt, pages: ["Hello there.\n\nSecond paragraph."])
        #expect(doc?.segments.count == 2)
    }

    @Test func signatureDetection() {
        #expect(FileSignature.detect(Data("%PDF-1.7".utf8), fileExtension: "pdf") == .pdf)
        #expect(FileSignature.detect(Data([0x50, 0x4B, 0x03, 0x04, 0, 0]), fileExtension: "docx") == .zip)
        // ZIP, замаскированный под .txt, не принимается как текст
        #expect(FileSignature.detect(Data([0x50, 0x4B, 0x03, 0x04, 0, 0]), fileExtension: "txt") == .unknown)
        #expect(FileSignature.detect(Data([0xFF, 0xD8, 0xFF, 0xE0]), fileExtension: "jpg") == .image)
        #expect(FileSignature.detect(Data("plain text".utf8), fileExtension: "txt") == .text)
        // PDF под видом .txt определяется по содержимому
        #expect(FileSignature.detect(Data("%PDF-1.4".utf8), fileExtension: "txt") == .pdf)
    }

    @Test func docxExtraction() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "sample", withExtension: "docx"))
        let text = try DOCXReader.text(from: Data(contentsOf: url))
        let paragraphs = TextSegmenter.paragraphs(in: text)
        #expect(paragraphs.first == "Learning English is important.")
        #expect(paragraphs.count == 2)
    }

    @Test func corruptDocxIsRejected() {
        #expect(throws: ImportError.self) { try DOCXReader.text(from: Data([0x50, 0x4B, 0x03, 0x04, 1, 2, 3])) }
    }
}

final class BundleToken {}

struct EngagementTests {
    private func attempt(daysAgo: Int, score: Double = 80, words: [WordAssessment] = []) -> ReadingAttempt {
        ReadingAttempt(id: UUID(), segmentID: UUID(), documentID: UUID(), durationMs: 1000, status: .completed,
                       createdAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
                       assessment: Assessment(id: UUID(), overall: score, accuracy: nil, fluency: nil, completeness: nil,
                                              prosody: nil, words: words, scoreVersion: "t"),
                       failureReason: nil)
    }

    @Test func streakCountsConsecutiveDays() {
        #expect(Engagement.streak(attempts: []) == 0)
        #expect(Engagement.streak(attempts: [attempt(daysAgo: 0), attempt(daysAgo: 1), attempt(daysAgo: 2)]) == 3)
        // вчера и позавчера — серия жива, пока сегодня не закончилось
        #expect(Engagement.streak(attempts: [attempt(daysAgo: 1), attempt(daysAgo: 2)]) == 2)
        #expect(Engagement.streak(attempts: [attempt(daysAgo: 2), attempt(daysAgo: 3)]) == 0)
    }

    @Test func difficultWordsSkipLearned() {
        func w(_ word: String, _ score: Double?, _ e: WordErrorType = .none) -> WordAssessment {
            WordAssessment(index: 0, word: word, startMs: nil, endMs: nil, score: score, errorType: e, phonemes: nil)
        }
        let list = Engagement.difficultWords(attempts: [
            attempt(daysAgo: 0, words: [w("Thought,", 40), w("world", 50), w("access", nil, .omission), w("extra", 10, .insertion)]),
            attempt(daysAgo: 1, words: [w("thought", 55), w("world", 92)]),
        ])
        #expect(list.map(\.word) == ["thought", "access"])
        #expect(list.first?.misses == 2)
    }

    @Test func deepLinkParsing() {
        #expect(DeepLink.challengeCode(from: URL(string: "speakcheck://c/abcd2345")!) == "abcd2345")
        #expect(DeepLink.challengeCode(from: URL(string: "https://speakcheck.example.com/c/abcd2345")!) == "abcd2345")
        #expect(DeepLink.challengeCode(from: URL(string: "speakcheck://c/../../etc")!) == nil)
        #expect(DeepLink.challengeCode(from: URL(string: "https://x.com/other/abcd2345")!) == nil)
    }

    @Test func russianPlural() {
        #expect(StreakBadge.days(1) == "день")
        #expect(StreakBadge.days(3) == "дня")
        #expect(StreakBadge.days(5) == "дней")
        #expect(StreakBadge.days(11) == "дней")
        #expect(StreakBadge.days(22) == "дня")
    }
}
