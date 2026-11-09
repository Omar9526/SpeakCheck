import Foundation
import NaturalLanguage

/// Делит текст на фрагменты для чтения: по абзацам, а длинные абзацы — по предложениям,
/// чтобы каждая запись укладывалась в лимиты движка оценки (ТЗ, разделы 6–7).
enum TextSegmenter {
    /// Мягкий предел слов на фрагмент: ~40 слов читаются быстрее 30 секунд, а до 30 с Azure
    /// сам надёжно размечает пропуски и лишние слова (режим miscue).
    static let maxWordsPerSegment = 40

    static func segments(from text: String, pageNumber: Int? = nil, startSequence: Int = 0) -> [ReadingSegment] {
        let chunks = paragraphs(in: text).flatMap(split(paragraph:))
        return chunks.enumerated().map { offset, chunk in
            ReadingSegment(id: UUID(), sequence: startSequence + offset, referenceText: chunk, pageNumber: pageNumber)
        }
    }

    /// Абзацы: разделение по пустым строкам; одиночные переносы внутри абзаца склеиваются
    /// (PDF и OCR часто рвут строки посередине предложения).
    static func paragraphs(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00AD}", with: "") // мягкие переносы
        let blocks = normalized.components(separatedBy: "\n\n")
        return blocks
            .map { block in
                block
                    .replacingOccurrences(of: "-\n", with: "")
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: " ")
                    .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    static func split(paragraph: String) -> [String] {
        guard wordCount(paragraph) > maxWordsPerSegment else { return [paragraph] }

        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraph
        tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
            let sentence = paragraph[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }

        var result: [String] = []
        var current = ""
        for sentence in sentences {
            let candidate = current.isEmpty ? sentence : current + " " + sentence
            if !current.isEmpty, wordCount(candidate) > maxWordsPerSegment {
                result.append(current)
                current = sentence
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Доля латинских букв — грубая проверка, что текст английский.
    static func latinRatio(_ text: String) -> Double {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return 0 }
        let latin = letters.filter { ("a"..."z").contains(Character($0).lowercased()) }
        return Double(latin.count) / Double(letters.count)
    }
}
