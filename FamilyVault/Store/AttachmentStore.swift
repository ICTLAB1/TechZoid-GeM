import CryptoKit
import Foundation
import UIKit
import UniformTypeIdentifiers

/// Attachment bytes never exist as plaintext on disk.
///
/// The file we keep locally is already AES-GCM ciphertext, which means the
/// exact same file can be handed to CloudKit as a `CKAsset` with no extra
/// encryption step — and what iCloud stores is that ciphertext.
enum AttachmentStore {

    /// Anything larger is refused rather than silently truncated.
    static let maximumBytes = 20 * 1024 * 1024
    /// Photos are downscaled before encryption: a 4000px camera scan of a
    /// policy is no more readable than a 2048px one, and syncs far faster.
    static let maximumImageDimension: CGFloat = 2048

    static var directory: URL {
        let dir = AppPaths.appSupport.appendingPathComponent("Attachments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.complete])
        }
        return dir
    }

    static func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).bin")
    }

    static func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    enum Failure: LocalizedError {
        case tooLarge(Int)
        case unreadable
        case notDownloaded

        var errorDescription: String? {
            switch self {
            case .tooLarge(let bytes):
                "That file is \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)). The limit is 20 MB — try a photo instead of a scan, or split the PDF."
            case .unreadable:
                "That file could not be read."
            case .notDownloaded:
                "This attachment hasn't finished downloading from iCloud yet."
            }
        }
    }

    // MARK: - Writing

    @discardableResult
    static func store(data: Data, id: UUID, key: SymmetricKey) throws -> Int {
        guard data.count <= maximumBytes else { throw Failure.tooLarge(data.count) }
        let sealed = try CryptoBox.seal(data, key: key)
        try sealed.write(to: fileURL(for: id), options: [.atomic, .completeFileProtection])
        return data.count
    }

    /// Copies ciphertext straight off a CloudKit asset — no key needed, because
    /// what the asset holds is already encrypted.
    static func storeSealed(from url: URL, id: UUID) throws {
        let data = try Data(contentsOf: url)
        try data.write(to: fileURL(for: id), options: [.atomic, .completeFileProtection])
    }

    // MARK: - Reading

    static func load(id: UUID, key: SymmetricKey) throws -> Data {
        guard exists(id) else { throw Failure.notDownloaded }
        let sealed = try Data(contentsOf: fileURL(for: id))
        return try CryptoBox.open(sealed, key: key)
    }

    static func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Preparing incoming files

    /// Normalises whatever the user picked into bytes worth storing.
    static func prepare(data: Data, filename: String, type: UTType) throws -> (data: Data, attachment: ItemAttachment) {
        var payload = data
        var resolvedType = type
        var resolvedName = filename

        if type.conforms(to: .image), let image = UIImage(data: data) {
            let downscaled = downscale(image, maxDimension: maximumImageDimension)
            if let jpeg = downscaled.jpegData(compressionQuality: 0.8) {
                payload = jpeg
                resolvedType = .jpeg
                if !resolvedName.lowercased().hasSuffix(".jpg") && !resolvedName.lowercased().hasSuffix(".jpeg") {
                    resolvedName = (resolvedName as NSString).deletingPathExtension + ".jpg"
                }
            }
        }

        guard payload.count <= maximumBytes else { throw Failure.tooLarge(payload.count) }

        let attachment = ItemAttachment(
            filename: resolvedName.isEmpty ? "Attachment" : resolvedName,
            typeIdentifier: resolvedType.identifier,
            byteCount: payload.count
        )
        return (payload, attachment)
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
