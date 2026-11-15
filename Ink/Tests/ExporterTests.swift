import Testing
import Foundation
import PDFKit
import PencilKit
import UIKit
@testable import Ink

struct ExporterTests {
    /// 다크 모드에서도 검정 잉크는 썸네일에 검게 찍혀야 한다(PencilKit은 다크 모드에서 잉크를 흰색으로 뒤집는다).
    @Test @MainActor func thumbnailKeepsBlackInkInDarkMode() throws {
        var manifest = NotebookManifest(title: "잉크")
        manifest.pages = [PageInfo(template: .blank)]
        let pdf = TemplateRenderer.makePDFDocument(template: .blank, size: manifest.pageSize, color: .white, pageCount: 1)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ink-\(UUID().uuidString).inknote")
        let document = NotebookDocument(fileURL: url, manifest: manifest, pdfDocument: pdf)

        let ink = PKInk(.pen, color: .black)
        let points = stride(from: 0, through: 200, by: 10).map {
            PKStrokePoint(location: CGPoint(x: 100 + CGFloat($0), y: 100 + CGFloat($0)), timeOffset: 0,
                          size: CGSize(width: 30, height: 30), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        document.setDrawing(PKDrawing(strokes: [PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()))]),
                            for: manifest.pages[0].id)

        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            image = Exporter.thumbnail(for: document, pageIndex: 0, maxDimension: 400)
        }
        let cg = try #require(image?.cgImage)
        #expect(hasDarkPixel(cg), "다크 모드에서 렌더한 썸네일에 검정 잉크가 없다")
    }

    private func hasDarkPixel(_ image: CGImage) -> Bool {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in stride(from: 0, to: data.count, by: 4) {
            let sum = Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2])
            if sum < 150 { return true }
        }
        return false
    }
}
