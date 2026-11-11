import UIKit
import PDFKit
import PencilKit

/// 배경 PDF와 필기를 합성해 내보낸다.
enum Exporter {
    /// 한 페이지를 이미지로 렌더링한다. `scale`은 포인트당 픽셀 수.
    static func renderPage(document: NotebookDocument, pageIndex: Int, scale: CGFloat) -> UIImage? {
        guard let page = document.pdfDocument.page(at: pageIndex),
              document.manifest.pages.indices.contains(pageIndex) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let drawing = document.drawing(for: document.manifest.pages[pageIndex].id)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: bounds.size))
            cg.saveGState()
            cg.translateBy(x: 0, y: bounds.height)
            cg.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
            let ink = drawing.image(from: CGRect(origin: .zero, size: bounds.size), scale: scale)
            ink.draw(in: CGRect(origin: .zero, size: bounds.size))
        }
    }

    static func thumbnail(for document: NotebookDocument, pageIndex: Int, maxDimension: CGFloat) -> UIImage? {
        guard let page = document.pdfDocument.page(at: pageIndex) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = maxDimension / max(bounds.width, bounds.height)
        return renderPage(document: document, pageIndex: pageIndex, scale: scale)
    }

    /// 필기를 평탄화한 PDF 데이터. `pageIndices`가 nil이면 전체.
    static func flattenedPDF(document: NotebookDocument, pageIndices: [Int]? = nil) -> Data {
        let indices = pageIndices ?? Array(0..<document.pdfDocument.pageCount)
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, .zero, nil)
        for index in indices {
            guard let page = document.pdfDocument.page(at: index),
                  document.manifest.pages.indices.contains(index),
                  let cg = UIGraphicsGetCurrentContext() else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let pageRect = CGRect(origin: .zero, size: bounds.size)
            UIGraphicsBeginPDFPageWithInfo(pageRect, nil)
            cg.saveGState()
            cg.translateBy(x: 0, y: bounds.height)
            cg.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
            let drawing = document.drawing(for: document.manifest.pages[index].id)
            let ink = drawing.image(from: pageRect, scale: 3)
            ink.draw(in: pageRect)
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    /// 공유용 임시 파일을 만든다.
    static func writeTemporary(data: Data, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
