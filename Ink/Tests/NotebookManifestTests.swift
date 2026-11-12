import Testing
import Foundation
import PDFKit
@testable import Ink

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
