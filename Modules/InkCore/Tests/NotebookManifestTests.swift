import Testing
import Foundation
import PDFKit
import PencilKit
import UIKit
@testable import InkCore

struct NotebookManifestTests {
    @Test func roundTripsThroughJSON() throws {
        var manifest = NotebookManifest(title: "테스트")
        // ISO8601은 초 단위까지만 저장하므로 비교를 위해 정수 초로 맞춘다.
        manifest.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        manifest.modifiedAt = manifest.createdAt
        manifest.pages = [PageInfo(template: .lined), PageInfo(template: nil)]
        manifest.recordings = [RecordingInfo(title: "녹음 1", startedAt: Date(timeIntervalSince1970: 1000), duration: 12.5, pageID: manifest.pages[0].id)]
        let data = try manifest.encoded()
        let decoded = try NotebookManifest.decode(data)
        #expect(decoded == manifest)
    }

    @Test func paperSizeRespectsOrientation() {
        let portrait = PaperSize.a4.size(landscape: false)
        let landscape = PaperSize.a4.size(landscape: true)
        #expect(portrait.width < portrait.height)
        #expect(landscape.width == portrait.height)
    }

    @Test @MainActor func templateProducesPDFPage() {
        let doc = TemplateRenderer.makePDFDocument(template: .grid, size: PaperSize.letter.portraitSize, color: .white, pageCount: 3)
        #expect(doc.pageCount == 3)
        #expect(doc.page(at: 0)?.bounds(for: .mediaBox).size == PaperSize.letter.portraitSize)
    }

    @Test func whiteboardGrowsNearEdge() {
        let size = WhiteboardGeometry.initialSize
        let farFromEdge = CGRect(x: 100, y: 100, width: 200, height: 200)
        #expect(WhiteboardGeometry.grownSize(current: size, drawingBounds: farFromEdge) == nil)
        let nearRight = CGRect(x: 100, y: 100, width: size.width - 150, height: 200)
        #expect(WhiteboardGeometry.grownSize(current: size, drawingBounds: nearRight)?.width == size.width + WhiteboardGeometry.growthStep)
    }
}

struct ManifestCompatibilityTests {
    /// 예전 빌드가 쓴 매니페스트(kind·paperColor·objects·recognizedText 없음)도 열려야 한다.
    @Test func decodesManifestWithoutNewerKeys() throws {
        let json = """
        {"version":1,"id":"5C7F8B5A-0A5B-4B5C-9C1E-0A0A0A0A0A0A","title":"옛 노트",
         "createdAt":"2025-11-01T10:00:00Z","modifiedAt":"2025-11-01T10:00:00Z",
         "paperSize":"a4","isLandscape":false,"defaultTemplate":"lined",
         "pages":[{"id":"6C7F8B5A-0A5B-4B5C-9C1E-0A0A0A0A0A0A","template":"lined"}],"recordings":[]}
        """
        let m = try NotebookManifest.decode(Data(json.utf8))
        #expect(m.title == "옛 노트")
        #expect(m.kind == .notebook)
        #expect(m.paperColor == .white)
        #expect(m.pages.count == 1)
        #expect(m.objects.isEmpty)
    }

    @Test func normalizedURLIgnoresTrailingSlash() {
        let a = URL(fileURLWithPath: "/tmp/x/a.inknote", isDirectory: true)
        let b = URL(fileURLWithPath: "/tmp/x/a.inknote", isDirectory: false)
        #expect(a != b)
        #expect(a.normalizedFileURL == b.normalizedFileURL)
    }
}

struct InkRenderingTests {
    /// 다크 모드(현재 트레이트)에서도 검정 잉크는 검정으로 래스터화돼야 썸네일·인식 이미지에 보인다.
    @Test @MainActor func blackInkStaysDarkUnderDarkTrait() {
        let pts = (0..<20).map { i in
            PKStrokePoint(location: CGPoint(x: 10 + CGFloat(i) * 4, y: 50), timeOffset: 0, size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: pts, creationDate: Date()))
        let drawing = PKDrawing(strokes: [stroke])
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        var rendered = UIImage()
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            rendered = Exporter.inkImage(drawing, from: rect, scale: 1, paperColor: .white)
        }
        // 흰 배경에 합성한 뒤 획 중앙 픽셀의 밝기를 본다.
        let composed = UIGraphicsImageRenderer(size: rect.size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { ctx in
            UIColor.white.setFill(); ctx.fill(rect); rendered.draw(in: rect)
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(composed.cgImage!, in: CGRect(x: -50, y: -49, width: 100, height: 100))
        #expect(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) < 200)
    }
}
