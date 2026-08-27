import Foundation
import PDFKit
import UIKit

/// Scanned pages become one PDF, because a policy is a document, not a pile of
/// photos — and a PDF is what an insurer or a bank will accept back.
enum PDFBuilder {

    /// Long edge in points. A4 is 842pt; anything larger is storage spent on
    /// detail no one will read.
    private static let maximumLongEdge: CGFloat = 1_240

    /// However large a page's declared MediaBox is, this is the most pixels
    /// (long edge) we'll ever render it at. A well-formed page never gets
    /// near it; a PDF engineered with an enormous page size doesn't get to
    /// force an unbounded bitmap allocation.
    private static let maximumRenderedLongEdge: CGFloat = 4_000

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

    /// Renders one page of an already-open document to an image, for OCR
    /// when the file carries no text layer — which is every PDF that started
    /// life as a scan.
    ///
    /// Callers processing several pages should open the `PDFDocument` once
    /// and call this per page rather than materialising every page image up
    /// front: a full document's worth of full-resolution pages held at once
    /// is real memory on an older phone, and this way only one is ever alive.
    static func renderedPage(from document: PDFDocument, at index: Int) -> UIImage? {
        guard let page = document.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        // 2x gives Vision enough pixels on 8pt body text without ballooning
        // memory — but only once we've also capped how large that can get
        // for a page whose declared size is itself abnormal.
        let resolutionScale: CGFloat = 2
        let rawSize = CGSize(width: bounds.width * resolutionScale, height: bounds.height * resolutionScale)
        let longestRaw = max(rawSize.width, rawSize.height)
        let clampFactor = longestRaw > maximumRenderedLongEdge ? maximumRenderedLongEdge / longestRaw : 1
        let size = CGSize(width: rawSize.width * clampFactor, height: rawSize.height * clampFactor)
        let effectiveScale = resolutionScale * clampFactor

        // Force scale 1: `size` already is the pixel size we want. Letting
        // the renderer additionally apply the device's own screen scale
        // (2x/3x) would render — and hold in memory — several times more
        // pixels than intended, with no benefit to OCR accuracy.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: effectiveScale, y: -effectiveScale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    /// All pages of a PDF at once, for callers that need the whole set
    /// together. Prefer `renderedPage(from:at:)` in a loop when processing
    /// pages one at a time is an option — it holds far less in memory.
    static func pageImages(from data: Data, limit: Int = 8) -> [UIImage] {
        guard let document = PDFDocument(data: data) else { return [] }
        var images: [UIImage] = []
        for index in 0 ..< min(document.pageCount, limit) {
            if let image = renderedPage(from: document, at: index) { images.append(image) }
        }
        return images
    }

    private static func downscale(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maximumLongEdge else { return image }
        let factor = maximumLongEdge / longest
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)

        // Force scale 1. `size` is in points and is meant to become the
        // page's dimensions once this image goes through `PDFPage(image:)`.
        // Left at the renderer's default (the device's screen scale), the
        // image's pixel buffer would be 2–3x `size`; compressing it to JPEG
        // and reloading it (below, and unavoidably, since `PDFPage(image:)`
        // needs a fully-decoded image) then produces a `UIImage` whose
        // `.size` is that inflated pixel count — because `UIImage(data:)`
        // always comes back at scale 1 — so the resulting PDF page would be
        // 2–3x the intended physical size instead of roughly A4.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
