import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Bytes read off a scan, a photo or a file, with the words already pulled out.
struct CapturedDocument {
    var data: Data
    var filename: String
    var typeIdentifier: String
    /// What the document says, as recognised on this iPhone.
    var text: String
    var pageCount: Int?
}

/// The one path documents take into the app.
///
/// Scanning, photographing, picking from Photos and importing a file all end
/// with the same question — what are these bytes, and what do they say — so
/// they are answered in one place. The editor's Documents section and the
/// central scan both come through here, which is what stops them drifting into
/// two subtly different readings of the same PDF.
enum DocumentIntake {

    enum Failure: LocalizedError {
        case pdfBuildFailed
        case photoUnreadable
        case fileUnreadable(String)

        var errorDescription: String? {
            switch self {
            case .pdfBuildFailed: "Those pages couldn't be turned into a PDF."
            case .photoUnreadable: "That photo couldn't be saved."
            case .fileUnreadable(let name): "Could not read \(name)."
            }
        }
    }

    /// Scanned pages become one PDF, the way a filed document should look.
    static func scanned(_ pages: [UIImage]) async throws -> CapturedDocument {
        let text = await TextRecognizer.text(from: pages)
        guard let pdf = PDFBuilder.makePDF(from: pages) else { throw Failure.pdfBuildFailed }
        return CapturedDocument(
            data: pdf,
            filename: "Scan \(Date().formatted(date: .abbreviated, time: .omitted)).pdf",
            typeIdentifier: UTType.pdf.identifier,
            text: text,
            pageCount: pages.count
        )
    }

    /// A photo stays a photo — still read for text, but not forced into a PDF.
    static func captured(_ image: UIImage) async throws -> CapturedDocument {
        guard let data = image.jpegData(compressionQuality: 0.85) else { throw Failure.photoUnreadable }
        let text = await TextRecognizer.recognize(image) ?? ""
        return CapturedDocument(
            data: data,
            filename: "Photo \(Date().formatted(date: .abbreviated, time: .shortened)).jpg",
            typeIdentifier: UTType.jpeg.identifier,
            text: text,
            pageCount: nil
        )
    }

    static func picked(_ item: PhotosPickerItem, index: Int) async -> CapturedDocument? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        var text = ""
        if let image = UIImage(data: data) {
            text = await TextRecognizer.recognize(image) ?? ""
        }
        return CapturedDocument(
            data: data,
            filename: "Photo \(Date().formatted(date: .abbreviated, time: .omitted)) \(index + 1).jpg",
            typeIdentifier: UTType.jpeg.identifier,
            text: text,
            pageCount: nil
        )
    }

    static func imported(_ url: URL) async throws -> CapturedDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        // Ask what kind of file this is *before* releasing the scope. A
        // security-scoped URL from Files stops answering resourceValues the
        // moment access ends, so reading it afterwards returned nil and every
        // imported PDF fell back to "public.data" — which conforms to neither
        // .pdf nor .image, so no text was ever extracted from an uploaded
        // document. The file still attached, which is what made this look like
        // an extraction problem rather than an import one.
        let declared = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        if scoped { url.stopAccessingSecurityScopedResource() }

        guard let data else { throw Failure.fileUnreadable(url.lastPathComponent) }

        let type = resolvedType(declared: declared, url: url, data: data)
        var text = ""
        if type.conforms(to: .pdf) {
            text = await TextRecognizer.text(fromPDF: data)
        } else if type.conforms(to: .image), let image = UIImage(data: data) {
            text = await TextRecognizer.recognize(image) ?? ""
        }

        return CapturedDocument(
            data: data,
            filename: url.lastPathComponent,
            typeIdentifier: type.identifier,
            text: text,
            pageCount: nil
        )
    }

    /// What kind of file this actually is.
    ///
    /// Three answers in order of authority: what the system declared, what the
    /// name says, and what the bytes themselves start with. The last one is
    /// the backstop — a file provider that refuses to describe its file cannot
    /// stop a PDF being read as a PDF.
    private static func resolvedType(declared: UTType?, url: URL, data: Data) -> UTType {
        // `.data`, `.item` and `.content` are "some file" — true of everything
        // and useful for nothing.
        let generic: Set<UTType> = [.data, .item, .content]
        if let declared, !generic.contains(declared) { return declared }

        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, let byExtension = UTType(filenameExtension: ext), !generic.contains(byExtension) {
            return byExtension
        }

        if data.starts(with: Array("%PDF".utf8)) { return .pdf }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }

        return declared ?? .data
    }

    /// Whether these bytes are a picture of a payment card.
    ///
    /// Separate from `plasticCardFields` on purpose. That one needs a
    /// Luhn-valid number, and embossed digits OCR badly — so a card can easily
    /// be recognisable as a card while its number is unreadable. Storing the
    /// photo in that case would be the worst outcome: a picture of the plastic
    /// filed in the vault, which is exactly what the card path exists to
    /// avoid. If it looks like a card face, the image is dropped whether or
    /// not the number came through.
    static func isPlasticCardFace(_ text: String) -> Bool {
        let lines = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count <= 18 else { return false }

        if plasticCardFields(in: text) != nil { return true }

        let markers = [
            "valid thru", "valid through", "valid from", "expires end",
            "cardholder", "card holder", "member since",
            "mastercard", "rupay", "american express", "amex", "diners club", "visa"
        ]
        return markers.contains { TextMatching.contains($0, in: text) }
    }

    static func plasticCardFields(in text: String) -> [ExtractedField]? {
        let lines = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // A statement runs to hundreds of lines. Anything this short is
        // plastic, and the Luhn check inside CardScanner has the final say.
        guard lines.count <= 18, CardScanner.read(text).number != nil else { return nil }
        let fields = CardScanner.fields(from: CardScanner.read(text))
        return fields.isEmpty ? nil : fields
    }

    /// Writes what a document said into an entry.
    ///
    /// Shared by every path that fills fields from a scan so the safety rules
    /// live in exactly one place:
    ///
    /// - a value only ever goes into a field that is **empty**, so nothing
    ///   typed by hand is overwritten;
    /// - a **masked** reading — `**** 3417` — is never written at all. It is a
    ///   true reading of the page but not the value.
    ///
    /// Returns which labels were filled confidently and which want a look.
    @discardableResult
    static func fill(_ item: inout VaultItem, from candidates: [ExtractedField]) -> (filled: [String], uncertain: [String]) {
        var filled: [String] = []
        var uncertain: [String] = []

        for candidate in candidates {
            guard !candidate.isMasked else { continue }
            let existing = item.fields.first { $0.label.caseInsensitiveCompare(candidate.label) == .orderedSame }
            if let existing, !existing.isEmpty { continue }

            item.applyExtracted(candidate)

            if candidate.confidence >= DocumentFieldExtractor.autoFillThreshold {
                if !filled.contains(candidate.label) { filled.append(candidate.label) }
            } else if !uncertain.contains(candidate.label) {
                uncertain.append(candidate.label)
            }
        }

        return (filled, uncertain)
    }
}
