import Foundation
import Testing
@testable import SpeakCheck

struct ScoringTests {
    private func assessment(overall: Double?, accuracy: Double? = nil, words: Int) -> Assessment {
        Assessment(
            id: UUID(), overall: overall, accuracy: accuracy, fluency: nil, completeness: nil, prosody: nil,
            words: (0..<words).map { WordAssessment(index: $0, word: "w", startMs: nil, endMs: nil, score: 80, errorType: WordErrorType.none, phonemes: nil) },
            scoreVersion: "test"
        )
    }

    @Test func bandThresholds() {
        #expect(ScoreBand(score: 85) == .good)
        #expect(ScoreBand(score: 84.9) == .fair)
        #expect(ScoreBand(score: 65) == .fair)
        #expect(ScoreBand(score: 64.9) == .poor)
        #expect(ScoreBand(score: 70, thresholds: .init(good: 70, fair: 50)) == .good)
    }

    @Test func summaryIsWeightedByWordCount() {
        // 10 слов на 90% и 30 слов на 50% → (900 + 1500) / 40 = 60, а не (90+50)/2 = 70.
        let s = AssessmentAggregator.summarize([assessment(overall: 90, words: 10), assessment(overall: 50, words: 30)])
        #expect(s.overall == 60)
        #expect(s.wordCount == 40)
    }

    @Test func missingMetricStaysNil() {
        let s = AssessmentAggregator.summarize([assessment(overall: 80, words: 5)])
        #expect(s.accuracy == nil)
        #expect(s.prosody == nil)
    }

    @Test func metricMissingInSomeSegmentsUsesOnlyAvailable() {
        let s = AssessmentAggregator.summarize([
            assessment(overall: 80, accuracy: 70, words: 10),
            assessment(overall: 60, accuracy: nil, words: 10)
        ])
        #expect(s.accuracy == 70)
        #expect(s.overall == 70)
    }

    @Test func insertionsAndUnscoredWordsDoNotCount() {
        var a = assessment(overall: 80, words: 3)
        a.words.append(WordAssessment(index: 3, word: "extra", startMs: nil, endMs: nil, score: 40, errorType: .insertion, phonemes: nil))
        a.words.append(WordAssessment(index: 4, word: "x", startMs: nil, endMs: nil, score: nil, errorType: .omission, phonemes: nil))
        #expect(a.assessedWordCount == 3)
    }

    @Test func emptyInputGivesNil() {
        #expect(AssessmentAggregator.summarize([]).overall == nil)
    }
}
