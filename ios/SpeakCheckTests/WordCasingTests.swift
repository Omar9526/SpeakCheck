import Testing
@testable import SpeakCheck

struct WordCasingTests {
    private func word(_ w: String, _ i: Int) -> WordAssessment {
        WordAssessment(index: i, word: w, startMs: nil, endMs: nil, score: 90, errorType: nil, phonemes: nil)
    }

    @Test func restoresCasingFromReference() {
        let text = "I come from Bishkek. The city is big, and the people speak English."
        #expect(word("i", 0).displayText(reference: text) == "I")
        #expect(word("bishkek", 3).displayText(reference: text) == "Bishkek")
        #expect(word("the", 4).displayText(reference: text) == "The")
        #expect(word("the", 8).displayText(reference: text) == "the")
        #expect(word("english", 11).displayText(reference: text) == "English")
    }

    @Test func shiftedIndexStillFindsCasing() {
        // Вставка лишнего слова сдвигает индексы — регистр берём по совпадению.
        #expect(word("english", 2).displayText(reference: "We speak English.") == "English")
        #expect(word("i", 5).displayText(reference: "Yes I do.") == "I")
        #expect(word("extra", 1).displayText(reference: "Hello world") == "extra")
    }
}
