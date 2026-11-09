import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ImportViewModel {
    nonisolated static let maxFileMB = 25
    static let fileTypes: [UTType] = [.pdf, .plainText, .text, UTType("org.openxmlformats.wordprocessingml.document") ?? .data, .image]

    var isWorking = false
    var progressText = "Извлекаем текст…"
    var errorMessage: String?

    func importPasted(_ text: String) async -> SCDocument? {
        await run {
            try DocumentFactory.make(title: Self.titleFromText(text), source: .manual, pages: [text])
        }
    }

    func importFile(_ result: Result<URL, Error>) async -> SCDocument? {
        await run {
            let url = try result.get()
            let extracted = try await DocumentExtractor.extract(fileAt: url) { [weak self] status in
                Task { @MainActor in self?.progressText = status }
            }
            return try DocumentFactory.make(title: url.lastPathComponent, source: extracted.source, pages: extracted.pages)
        }
    }

    func importPhoto(_ item: PhotosPickerItem) async -> SCDocument? {
        await run {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw ImportError.unreadable }
            let pages = try await DocumentExtractor.recognize(imageData: data)
            return try DocumentFactory.make(title: "Фото текста", source: .image, pages: pages)
        }
    }

    func importCameraImage(_ image: UIImage) async -> SCDocument? {
        await run {
            guard let data = image.jpegData(compressionQuality: 0.9) else { throw ImportError.unreadable }
            let pages = try await DocumentExtractor.recognize(imageData: data)
            return try DocumentFactory.make(title: "Фото текста", source: .image, pages: pages)
        }
    }

    private func run(_ work: () async throws -> SCDocument) async -> SCDocument? {
        isWorking = true
        progressText = "Извлекаем текст…"
        defer { isWorking = false }
        do {
            return try await work()
        } catch let error as ImportError {
            errorMessage = error.message
        } catch {
            errorMessage = ImportError.unreadable.message
        }
        return nil
    }

    static func titleFromText(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).prefix(5).joined(separator: " ")
        return words.isEmpty ? "Мой текст" : words + "…"
    }
}

enum ImportError: Error, Equatable {
    case tooLarge
    case unsupported
    case unreadable
    case empty
    case noText
    case notEnglish
    case accessDenied

    var message: String {
        switch self {
        case .tooLarge: "Файл больше \(ImportViewModel.maxFileMB) МБ. Разделите его или выберите нужные страницы."
        case .unsupported: "Этот формат не поддерживается. Используйте PDF, DOCX, TXT или изображение."
        case .unreadable: "Файл повреждён или не читается."
        case .empty: "Файл пустой."
        case .noText: "Не удалось найти текст. Если это скан — попробуйте сфотографировать страницу ровнее и при хорошем свете."
        case .notEnglish: "Похоже, текст не на английском. SpeakCheck оценивает чтение только на английском языке."
        case .accessDenied: "Нет доступа к файлу. Попробуйте выбрать его ещё раз."
        }
    }
}

/// Собирает документ из извлечённых страниц.
enum DocumentFactory {
    static func make(title: String, source: DocumentSource, pages: [String]) throws -> SCDocument {
        var segments: [ReadingSegment] = []
        for (index, page) in pages.enumerated() {
            let pageNumber = pages.count > 1 ? index + 1 : nil
            segments += TextSegmenter.segments(from: page, pageNumber: pageNumber, startSequence: segments.count)
        }
        let allText = segments.map(\.referenceText).joined(separator: " ")
        guard !allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw source == .image ? ImportError.noText : ImportError.empty
        }
        guard TextSegmenter.latinRatio(allText) > 0.6 else { throw ImportError.notEnglish }
        return SCDocument(
            id: UUID(), title: title, source: source, status: .ready,
            segments: segments, createdAt: .now, bestScore: nil, completedSegments: 0
        )
    }
}
