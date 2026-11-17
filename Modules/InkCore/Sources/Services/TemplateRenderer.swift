import UIKit
import PDFKit

/// 템플릿 페이지를 벡터로 그려 PDF 페이지를 만든다.
public enum TemplateRenderer {
    public static func backgroundColor(for color: PaperColor) -> UIColor {
        switch color {
        case .white: UIColor(white: 1, alpha: 1)
        case .yellow: UIColor(red: 1.0, green: 0.98, blue: 0.88, alpha: 1)
        case .dark: UIColor(white: 0.12, alpha: 1)
        }
    }

    public static func lineColor(for color: PaperColor) -> UIColor {
        switch color {
        case .white: UIColor(white: 0.82, alpha: 1)
        case .yellow: UIColor(red: 0.85, green: 0.80, blue: 0.62, alpha: 1)
        case .dark: UIColor(white: 0.28, alpha: 1)
        }
    }

    /// 템플릿 PDF 페이지. 반환된 페이지는 `PDFDocument.insert(_:at:)`로 추가할 수 있다.
    public static func makePDFPage(template: PaperTemplate, size: CGSize, color: PaperColor) -> PDFPage {
        let data = makePDFData(template: template, size: size, color: color)
        guard let doc = PDFDocument(data: data), let page = doc.page(at: 0) else {
            let page = PDFPage()
            page.setBounds(CGRect(origin: .zero, size: size), for: .mediaBox)
            return page
        }
        return page
    }

    /// 여러 페이지로 구성된 템플릿 PDF 문서.
    public static func makePDFDocument(template: PaperTemplate, size: CGSize, color: PaperColor, pageCount: Int) -> PDFDocument {
        let doc = PDFDocument()
        for i in 0..<max(pageCount, 1) {
            doc.insert(makePDFPage(template: template, size: size, color: color), at: i)
        }
        return doc
    }

    public static func makePDFData(template: PaperTemplate, size: CGSize, color: PaperColor) -> Data {
        let bounds = CGRect(origin: .zero, size: size)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            draw(template: template, in: bounds, color: color, context: ctx.cgContext)
        }
    }

    public static func draw(template: PaperTemplate, in bounds: CGRect, color: PaperColor, context cg: CGContext) {
        cg.setFillColor(backgroundColor(for: color).cgColor)
        cg.fill(bounds)
        cg.setStrokeColor(lineColor(for: color).cgColor)
        cg.setFillColor(lineColor(for: color).cgColor)
        cg.setLineWidth(0.6)

        let spacing: CGFloat = 28
        let margin: CGFloat = 36

        switch template {
        case .blank:
            break
        case .lined:
            var y = margin + spacing
            while y < bounds.maxY - margin / 2 {
                cg.move(to: CGPoint(x: bounds.minX + margin / 2, y: y))
                cg.addLine(to: CGPoint(x: bounds.maxX - margin / 2, y: y))
                y += spacing
            }
            cg.strokePath()
        case .grid:
            var x = bounds.minX
            while x <= bounds.maxX {
                cg.move(to: CGPoint(x: x, y: bounds.minY))
                cg.addLine(to: CGPoint(x: x, y: bounds.maxY))
                x += spacing / 2
            }
            var y = bounds.minY
            while y <= bounds.maxY {
                cg.move(to: CGPoint(x: bounds.minX, y: y))
                cg.addLine(to: CGPoint(x: bounds.maxX, y: y))
                y += spacing / 2
            }
            cg.strokePath()
        case .dotted:
            let step = spacing / 2
            var y = bounds.minY + step
            while y < bounds.maxY {
                var x = bounds.minX + step
                while x < bounds.maxX {
                    cg.fillEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                    x += step
                }
                y += step
            }
        case .cornell:
            let cueWidth = bounds.width * 0.28
            let summaryHeight = bounds.height * 0.2
            cg.setLineWidth(1.2)
            cg.move(to: CGPoint(x: bounds.minX + cueWidth, y: bounds.minY + margin))
            cg.addLine(to: CGPoint(x: bounds.minX + cueWidth, y: bounds.maxY - summaryHeight))
            cg.move(to: CGPoint(x: bounds.minX, y: bounds.maxY - summaryHeight))
            cg.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - summaryHeight))
            cg.move(to: CGPoint(x: bounds.minX, y: bounds.minY + margin))
            cg.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY + margin))
            cg.strokePath()
            cg.setLineWidth(0.6)
            var y = bounds.minY + margin + spacing
            while y < bounds.maxY - summaryHeight - spacing / 2 {
                cg.move(to: CGPoint(x: bounds.minX + cueWidth + 8, y: y))
                cg.addLine(to: CGPoint(x: bounds.maxX - margin / 2, y: y))
                y += spacing
            }
            cg.strokePath()
        }
    }

    /// 라이브러리 미리보기용 작은 이미지.
    public static func previewImage(template: PaperTemplate, color: PaperColor, size: CGSize = CGSize(width: 90, height: 120)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            let scale = size.width / 300
            ctx.cgContext.scaleBy(x: scale, y: scale)
            draw(template: template, in: CGRect(x: 0, y: 0, width: 300, height: 300 * size.height / size.width),
                 color: color, context: ctx.cgContext)
        }
    }
}
