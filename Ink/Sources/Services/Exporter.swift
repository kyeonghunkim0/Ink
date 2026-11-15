import UIKit
import PDFKit
import PencilKit

/// 페이지 객체를 CoreGraphics로 그린다(화면·내보내기 공용).
enum PageObjectRenderer {
    static func draw(_ object: PageObject, document: NotebookDocument, in cg: CGContext) {
        switch object.kind {
        case .image(let name):
            guard let image = document.image(named: name) else { return }
            image.draw(in: object.frame)
        case .text(let text):
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: object.fontSize),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph,
            ]
            (text as NSString).draw(in: object.frame.insetBy(dx: 6, dy: 6), withAttributes: attrs)
        case .sticker(let emoji):
            let font = UIFont.systemFont(ofSize: object.frame.height * 0.8)
            let size = (emoji as NSString).size(withAttributes: [.font: font])
            let origin = CGPoint(x: object.frame.midX - size.width / 2, y: object.frame.midY - size.height / 2)
            (emoji as NSString).draw(at: origin, withAttributes: [.font: font])
        }
    }

    static func drawAll(for pageID: UUID, document: NotebookDocument, in cg: CGContext) {
        for object in document.manifest.objects where object.pageID == pageID {
            draw(object, document: document, in: cg)
        }
    }
}

/// 배경 PDF와 필기를 합성해 내보낸다.
enum Exporter {
    /// PencilKit은 다크 모드에서 검정 잉크를 흰색으로 뒤집어 그리므로, 용지 색에 맞는 테마로 고정해 래스터화한다.
    static func inkImage(_ drawing: PKDrawing, from rect: CGRect, scale: CGFloat, paperColor: PaperColor) -> UIImage {
        let style: UIUserInterfaceStyle = paperColor == .dark ? .dark : .light
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: style).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        return image
    }
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
            PageObjectRenderer.drawAll(for: document.manifest.pages[pageIndex].id, document: document, in: cg)
            let ink = inkImage(drawing, from: CGRect(origin: .zero, size: bounds.size), scale: scale, paperColor: document.manifest.paperColor)
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
            PageObjectRenderer.drawAll(for: document.manifest.pages[index].id, document: document, in: cg)
            let drawing = document.drawing(for: document.manifest.pages[index].id)
            let ink = inkImage(drawing, from: pageRect, scale: 3, paperColor: document.manifest.paperColor)
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
