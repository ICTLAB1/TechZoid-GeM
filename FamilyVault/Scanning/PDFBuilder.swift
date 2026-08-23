import Foundation
import PDFKit
import UIKit

/// Scanned pages become one PDF, because a policy is a document, not a pile of
/// photos — and a PDF is what an insurer or a bank will accept back.
enum PDFBuilder {

    /// Long edge in points. A4 is 842pt; anything larger is storage spent on
    /// detail no one will read.
    private static let maximumLongEdge: CGFloat = 1_240

    static func makePDF(from images: [UIImage]) -> Data? {
        guard !images.isEmpty else { return nil }

        let document = PDFDocument()
        var insertedPages = 0

        for image in images {
            let scaled = downscale(image)
            // JPEG-compress before embedding: a raw scan page is ~8 MB, the
            // same page at 0.72 quality is a few hundred KB and looks identical.
            guard let jpeg = scaled.jpegData(compressionQuality: 0.72),
                  let compressed = UIImage(data: jpeg),
                  let page = PDFPage(image: compressed)
            else { continue }
            document.insert(page, at: insertedPages)
            insertedPages += 1
        }

        guard insertedPages > 0 else { return nil }
        return document.dataRepresentation()
    }

    /// Renders each page of a PDF to an image, for OCR when the file carries no
    /// text layer — which is every PDF that started life as a scan.
    static func pageImages(from data: Data, limit: Int = 8) -> [UIImage] {
        guard let document = PDFDocument(data: data) else { return [] }
        var images: [UIImage] = []

        for index in 0 ..< min(document.pageCount, limit) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 1, bounds.height > 1 else { continue }

            // 2x gives Vision enough pixels on 8pt body text without ballooning memory.
            let scale: CGFloat = 2
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)

            let image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context.cgContext)
            }
            images.append(image)
        }
        return images
    }

    private static func downscale(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maximumLongEdge else { return image }
        let factor = maximumLongEdge / longest
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
