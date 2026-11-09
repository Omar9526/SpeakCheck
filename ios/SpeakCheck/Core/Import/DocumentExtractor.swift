import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
@preconcurrency import Vision

/// Извлечение текста из PDF / DOCX / TXT / изображений. Работает на фоне, не блокируя UI.
enum DocumentExtractor {
    struct Extracted: Sendable {
        var source: DocumentSource
        /// Текст по страницам (для TXT/DOCX — одна «страница»).
        var pages: [String]
    }

    static let maxBytes = ImportViewModel.maxFileMB * 1024 * 1024
    static let maxPDFPages = 60

    static func extract(fileAt url: URL, progress: @escaping @Sendable (String) -> Void) async throws -> Extracted {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, size > maxBytes { throw ImportError.tooLarge }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ImportError.accessDenied
        }
        guard !data.isEmpty else { throw ImportError.empty }
        guard data.count <= maxBytes else { throw ImportError.tooLarge }

        // Тип определяем по сигнатуре содержимого, а не только по расширению (ТЗ, раздел 11).
        switch FileSignature.detect(data, fileExtension: url.pathExtension.lowercased()) {
        case .pdf:
            return Extracted(source: .pdf, pages: try await extractPDF(data, progress: progress))
        case .zip:
            return Extracted(source: .docx, pages: [try await Task.detached { try DOCXReader.text(from: data) }.value])
        case .image:
            progress("Распознаём текст на фото…")
            return Extracted(source: .image, pages: try await recognize(imageData: data))
        case .text:
            return Extracted(source: .txt, pages: [try decodeText(data)])
        case .unknown:
            throw ImportError.unsupported
        }
    }

    // MARK: TXT

    static func decodeText(_ data: Data) throws -> String {
        for encoding in [String.Encoding.utf8, .utf16, .windowsCP1252, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        throw ImportError.unreadable
    }

    // MARK: PDF

    static func extractPDF(_ data: Data, progress: @escaping @Sendable (String) -> Void) async throws -> [String] {
        guard let pdf = PDFDocument(data: data) else { throw ImportError.unreadable }
        if pdf.isLocked { throw ImportError.unreadable }
        let count = min(pdf.pageCount, maxPDFPages)
        var pages: [String] = []
        for index in 0..<count {
            guard let page = pdf.page(at: index) else { continue }
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.count > 20 {
                pages.append(text)
            } else {
                // Скан без текстового слоя — рендерим страницу и распознаём через Vision.
                progress("Распознаём страницу \(index + 1) из \(count)…")
                let image = page.thumbnail(of: CGSize(width: 1700, height: 2200), for: .mediaBox)
                if let jpeg = image.jpegData(compressionQuality: 0.9) {
                    pages.append(contentsOf: try await recognize(imageData: jpeg))
                }
            }
        }
        return pages
    }

    // MARK: OCR

    /// Распознавание английского текста (Apple Vision, на устройстве).
    static func recognize(imageData: Data) async throws -> [String] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else { throw ImportError.unreadable }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                continuation.resume(returning: [OCRLayout.text(from: observations)])
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Восстанавливает абзацы из строк OCR по вертикальным промежуткам.
enum OCRLayout {
    static func text(from observations: [VNRecognizedTextObservation]) -> String {
        let lines = observations
            .compactMap { obs -> (String, CGRect)? in
                guard let candidate = obs.topCandidates(1).first, candidate.confidence > 0.3 else { return nil }
                return (candidate.string, obs.boundingBox)
            }
            .sorted { $0.1.maxY > $1.1.maxY } // Vision: начало координат снизу
        guard !lines.isEmpty else { return "" }

        let medianHeight = lines.map(\.1.height).sorted()[lines.count / 2]
        var result = lines[0].0
        for i in 1..<lines.count {
            let gap = lines[i - 1].1.minY - lines[i].1.maxY
            result += gap > medianHeight * 0.9 ? "\n\n" : "\n"
            result += lines[i].0
        }
        return result
    }
}

enum FileSignature: Equatable {
    case pdf, zip, image, text, unknown

    static func detect(_ data: Data, fileExtension: String) -> FileSignature {
        let head = [UInt8](data.prefix(12))
        if head.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf }              // %PDF
        if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) {                              // PK..
            return fileExtension == "docx" || fileExtension.isEmpty ? .zip : .unknown
        }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return .image }                   // JPEG
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .image }             // PNG
        if head.count >= 12, head[4...7] == [0x66, 0x74, 0x79, 0x70] {              // ....ftyp (HEIC/HEIF)
            return .image
        }
        if ["txt", "text", "md", ""].contains(fileExtension), !head.contains(0) { return .text }
        return .unknown
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
