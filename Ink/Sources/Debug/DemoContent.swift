#if DEBUG
import UIKit
import PencilKit
import PDFKit
import InkCore

/// 스크린샷용 데모 노트북을 만든다(`--screenshot-demo` 실행 인자).
@MainActor
enum DemoContent {
    static let notebookTitles = ["선형대수 3강", "아이디어 보드", "독서 노트", "프로젝트 회의"]

    static func install(store: DocumentStore, in folder: URL) async {
        // 스크린샷용이므로 라이브러리를 비우고 시작한다(디버그 빌드 전용).
        for item in store.items(in: folder) { try? store.delete(item) }
        // 최근 수정 순으로 정렬되므로 첫 칸에 둘 노트를 마지막에 만든다.
        await makeMeeting(store: store, folder: folder)
        await makeReadingNote(store: store, folder: folder)
        await makeIdeaBoard(store: store, folder: folder)
        await makeLinearAlgebra(store: store, folder: folder)
        store.refresh()
    }

    // MARK: - Notebooks

    private static func makeLinearAlgebra(store: DocumentStore, folder: URL) async {
        var options = NewNotebookOptions()
        options.title = "선형대수 3강"; options.template = .lined; options.isLandscape = false
        guard let url = try? await store.createNotebook(options, in: folder) else { return }
        await edit(url) { doc in
            doc.insertTemplatePage(.grid, at: 1)
            doc.insertTemplatePage(.cornell, at: 2)
            let p0 = doc.manifest.pages[0].id, p1 = doc.manifest.pages[1].id, p2 = doc.manifest.pages[2].id
            let w = doc.manifest.pageSize.width

            // 1쪽: 제목 + 정의 + 벡터 그림
            text(doc, p0, "고유값과 고유벡터", at: CGPoint(x: 48, y: 52), size: CGSize(width: 420, height: 56), font: 34)
            text(doc, p0, "Eigenvalues & Eigenvectors · 3강", at: CGPoint(x: 48, y: 104), size: CGSize(width: 360, height: 30), font: 15)
            text(doc, p0, "정의   Av = λv  (v ≠ 0)\n\n•  λ : 고유값 (eigenvalue)\n•  v : 고유벡터 (eigenvector)\n•  det(A − λI) = 0  →  특성방정식",
                 at: CGPoint(x: 48, y: 164), size: CGSize(width: 480, height: 150), font: 18)
            sticker(doc, p0, "📌", at: CGPoint(x: w - 110, y: 48), side: 60)
            sticker(doc, p0, "⭐️", at: CGPoint(x: w - 180, y: 48), side: 60)
            text(doc, p0, "v", at: CGPoint(x: 300, y: 500), size: CGSize(width: 40, height: 30), font: 20)
            text(doc, p0, "Av = 2v", at: CGPoint(x: 392, y: 396), size: CGSize(width: 110, height: 30), font: 20)
            text(doc, p0, "A가 v를 같은 방향으로 2배 늘인다 → λ = 2", at: CGPoint(x: 48, y: 700), size: CGSize(width: 440, height: 32), font: 17)

            var strokes: [PKStroke] = []
            strokes += highlighter(from: CGPoint(x: 44, y: 78), to: CGPoint(x: 420, y: 78), color: UIColor.systemYellow)
            strokes += highlighter(from: CGPoint(x: 90, y: 185), to: CGPoint(x: 300, y: 185), color: UIColor.systemPink)
            // 좌표축
            strokes += arrow(from: CGPoint(x: 120, y: 640), to: CGPoint(x: 520, y: 640), color: .darkGray, width: 2.5)
            strokes += arrow(from: CGPoint(x: 120, y: 640), to: CGPoint(x: 120, y: 360), color: .darkGray, width: 2.5)
            // v (파랑), Av (빨강)
            strokes += arrow(from: CGPoint(x: 120, y: 640), to: CGPoint(x: 280, y: 520), color: .systemBlue, width: 5)
            strokes += arrow(from: CGPoint(x: 120, y: 640), to: CGPoint(x: 440, y: 400), color: .systemRed, width: 5)
            strokes += circle(center: CGPoint(x: 466, y: 410), radius: 46, color: .systemRed, width: 2.5)
            strokes += underline(from: CGPoint(x: 48, y: 728), to: CGPoint(x: 350, y: 730), color: .systemBlue, width: 3)
            doc.setDrawing(PKDrawing(strokes: strokes), for: p0)

            // 2쪽: 그래프 예제
            text(doc, p1, "예제 1.  A = [2 0; 0 3] 의 고유값", at: CGPoint(x: 48, y: 48), size: CGSize(width: 480, height: 40), font: 24)
            text(doc, p1, "det(A − λI) = (2 − λ)(3 − λ) = 0\n∴ λ₁ = 2,  λ₂ = 3", at: CGPoint(x: 48, y: 100), size: CGSize(width: 420, height: 70), font: 18)
            text(doc, p1, "y = x²  (λ = 2 인 방향으로 늘어남)", at: CGPoint(x: 120, y: 690), size: CGSize(width: 380, height: 30), font: 16)
            sticker(doc, p1, "✅", at: CGPoint(x: 470, y: 112), side: 44)
            var s2: [PKStroke] = []
            s2 += arrow(from: CGPoint(x: 100, y: 620), to: CGPoint(x: 520, y: 620), color: .darkGray, width: 2.5)
            s2 += arrow(from: CGPoint(x: 310, y: 640), to: CGPoint(x: 310, y: 230), color: .darkGray, width: 2.5)
            s2 += curve(points: (0...80).map { i in
                let x = CGFloat(i) / 80 * 360 - 180
                return CGPoint(x: 310 + x, y: 620 - (x * x) / 95)
            }, color: .systemBlue, width: 4)
            s2 += curve(points: (0...80).map { i in
                let x = CGFloat(i) / 80 * 360 - 180
                return CGPoint(x: 310 + x, y: 620 - (x * x) / 190)
            }, color: .systemGreen, width: 4)
            s2 += highlighter(from: CGPoint(x: 100, y: 142), to: CGPoint(x: 260, y: 142), color: .systemYellow)
            doc.setDrawing(PKDrawing(strokes: s2), for: p1)

            // 3쪽: 코넬 요약
            let cue = doc.manifest.pageSize.width * 0.28
            text(doc, p2, "핵심 용어", at: CGPoint(x: 16, y: 56), size: CGSize(width: cue - 24, height: 30), font: 17)
            text(doc, p2, "• 고유값\n• 고유벡터\n• 특성다항식\n• 대각화", at: CGPoint(x: 16, y: 92), size: CGSize(width: cue - 24, height: 130), font: 15)
            text(doc, p2, "노트", at: CGPoint(x: cue + 16, y: 56), size: CGSize(width: 120, height: 30), font: 17)
            text(doc, p2, "A가 대각화 가능 ⇔ n개의 선형독립 고유벡터 존재\nP⁻¹AP = D  (D의 대각 성분 = 고유값)\n\n대칭행렬은 항상 직교 대각화 가능하다.",
                 at: CGPoint(x: cue + 16, y: 92), size: CGSize(width: w - cue - 40, height: 160), font: 16)
            let summaryY = doc.manifest.pageSize.height * 0.8
            text(doc, p2, "요약 — 고유값은 변환이 늘이는 배율, 고유벡터는 그 방향이다.", at: CGPoint(x: 16, y: summaryY + 12), size: CGSize(width: w - 32, height: 40), font: 16)
            var s3: [PKStroke] = []
            s3 += highlighter(from: CGPoint(x: cue + 20, y: 110), to: CGPoint(x: w - 60, y: 110), color: .systemYellow)
            s3 += circle(center: CGPoint(x: 60, y: 160), radius: 28, color: .systemRed, width: 2.5)
            doc.setDrawing(PKDrawing(strokes: s3), for: p2)
        }
    }

    private static func makeIdeaBoard(store: DocumentStore, folder: URL) async {
        var options = NewNotebookOptions()
        options.title = "아이디어 보드"; options.kind = .whiteboard; options.template = .dotted
        guard let url = try? await store.createNotebook(options, in: folder) else { return }
        await edit(url) { doc in
            let p = doc.manifest.pages[0].id
            let center = CGPoint(x: 1200, y: 1100)
            text(doc, p, "Ink 1.0 출시", at: CGPoint(x: center.x - 150, y: center.y - 36), size: CGSize(width: 300, height: 72), font: 40)
            let branches: [(String, CGPoint, UIColor, String)] = [
                ("필기 엔진", CGPoint(x: 520, y: 620), .systemBlue, "✍️"),
                ("PDF · Office 가져오기", CGPoint(x: 1880, y: 620), .systemOrange, "📄"),
                ("녹음 동기화", CGPoint(x: 440, y: 1560), .systemGreen, "🎙️"),
                ("손글씨 검색", CGPoint(x: 1960, y: 1560), .systemPurple, "🔍"),
                ("iCloud 동기화", CGPoint(x: 1200, y: 1900), .systemTeal, "☁️"),
            ]
            var strokes: [PKStroke] = []
            strokes += circle(center: center, radius: 220, color: .systemIndigo, width: 8)
            for (title, pos, color, emoji) in branches {
                strokes += curve(points: [center, CGPoint(x: (center.x + pos.x) / 2, y: (center.y + pos.y) / 2 - 80), pos], color: color, width: 7)
                strokes += circle(center: pos, radius: 170, color: color, width: 7)
                text(doc, p, title, at: CGPoint(x: pos.x - 150, y: pos.y - 24), size: CGSize(width: 300, height: 60), font: 30)
                sticker(doc, p, emoji, at: CGPoint(x: pos.x - 40, y: pos.y - 130), side: 80)
            }
            strokes += highlighter(from: CGPoint(x: 1060, y: 1160), to: CGPoint(x: 1340, y: 1160), color: .systemYellow)
            sticker(doc, p, "💡", at: CGPoint(x: center.x - 50, y: center.y - 190), side: 100)
            doc.setDrawing(PKDrawing(strokes: strokes), for: p)
        }
    }

    private static func makeReadingNote(store: DocumentStore, folder: URL) async {
        var options = NewNotebookOptions()
        options.title = "독서 노트"; options.template = .cornell; options.paperColor = .yellow; options.isLandscape = false
        guard let url = try? await store.createNotebook(options, in: folder) else { return }
        await edit(url) { doc in
            let p = doc.manifest.pages[0].id
            let w = doc.manifest.pageSize.width, cue = w * 0.28
            text(doc, p, "『생각에 관한 생각』 — 대니얼 카너먼", at: CGPoint(x: 16, y: 6), size: CGSize(width: w - 32, height: 30), font: 17)
            text(doc, p, "시스템 1\n빠름 · 직관\n\n시스템 2\n느림 · 숙고", at: CGPoint(x: 16, y: 60), size: CGSize(width: cue - 24, height: 160), font: 15)
            text(doc, p, "우리는 대부분의 판단을 시스템 1에 맡긴다. 노력이 드는 시스템 2는 게으르고, 시스템 1이 내놓은 답을 그대로 승인하는 경우가 많다.\n\n→ 휴리스틱과 편향은 시스템 1의 지름길에서 생긴다.",
                 at: CGPoint(x: cue + 16, y: 60), size: CGSize(width: w - cue - 40, height: 200), font: 16)
            text(doc, p, "요약 — 중요한 결정 앞에서는 의도적으로 시스템 2를 깨울 장치를 만들자.", at: CGPoint(x: 16, y: doc.manifest.pageSize.height * 0.8 + 12), size: CGSize(width: w - 32, height: 40), font: 16)
            sticker(doc, p, "📚", at: CGPoint(x: w - 70, y: 230), side: 48)
            var s: [PKStroke] = []
            s += highlighter(from: CGPoint(x: cue + 20, y: 78), to: CGPoint(x: w - 40, y: 78), color: .systemOrange)
            s += underline(from: CGPoint(x: cue + 20, y: 180), to: CGPoint(x: cue + 260, y: 182), color: .systemRed, width: 2.5)
            s += circle(center: CGPoint(x: 70, y: 78), radius: 30, color: .systemBlue, width: 2.5)
            doc.setDrawing(PKDrawing(strokes: s), for: p)
        }
    }

    private static func makeMeeting(store: DocumentStore, folder: URL) async {
        var options = NewNotebookOptions()
        options.title = "프로젝트 회의"; options.template = .grid; options.isLandscape = false
        guard let url = try? await store.createNotebook(options, in: folder) else { return }
        await edit(url) { doc in
            let p = doc.manifest.pages[0].id
            text(doc, p, "11/12 스프린트 회의", at: CGPoint(x: 48, y: 48), size: CGSize(width: 360, height: 44), font: 28)
            text(doc, p, "참석: 디자인 2 · iOS 3 · PM 1", at: CGPoint(x: 48, y: 96), size: CGSize(width: 360, height: 28), font: 15)
            let items = ["온보딩 화면 시안 확정", "PDF 가져오기 속도 개선", "녹음 동기화 QA", "앱 스토어 스크린샷 준비"]
            for (i, item) in items.enumerated() {
                let y: CGFloat = 170 + CGFloat(i) * 56
                sticker(doc, p, i < 2 ? "✅" : "⬜️", at: CGPoint(x: 48, y: y - 4), side: 36)
                text(doc, p, item, at: CGPoint(x: 96, y: y), size: CGSize(width: 380, height: 32), font: 18)
            }
            text(doc, p, "다음 주 목표: 베타 테스터 20명 모집", at: CGPoint(x: 48, y: 440), size: CGSize(width: 420, height: 32), font: 18)
            sticker(doc, p, "🎯", at: CGPoint(x: 470, y: 436), side: 40)
            var s: [PKStroke] = []
            s += highlighter(from: CGPoint(x: 44, y: 72), to: CGPoint(x: 330, y: 72), color: .systemGreen)
            s += underline(from: CGPoint(x: 96, y: 196), to: CGPoint(x: 330, y: 198), color: .systemGray, width: 2)
            s += underline(from: CGPoint(x: 96, y: 252), to: CGPoint(x: 350, y: 254), color: .systemGray, width: 2)
            s += arrow(from: CGPoint(x: 120, y: 560), to: CGPoint(x: 330, y: 520), color: .systemRed, width: 4)
            s += curve(points: [CGPoint(x: 340, y: 500), CGPoint(x: 360, y: 540), CGPoint(x: 400, y: 480)], color: .systemRed, width: 4)
            doc.setDrawing(PKDrawing(strokes: s), for: p)
        }
    }

    // MARK: - Helpers

    /// 문서를 열어 수정하고 저장·닫기까지 한다.
    private static func edit(_ url: URL, _ body: (NotebookDocument) -> Void) async {
        let doc = NotebookDocument(fileURL: url)
        guard await withCheckedContinuation({ c in doc.open { c.resume(returning: $0) } }) else { return }
        body(doc)
        doc.markPDFChanged()
        _ = await withCheckedContinuation { c in doc.save(to: url, for: .forOverwriting) { c.resume(returning: $0) } }
        await withCheckedContinuation { c in doc.close { _ in c.resume() } }
    }

    private static func text(_ doc: NotebookDocument, _ page: UUID, _ string: String, at origin: CGPoint, size: CGSize, font: CGFloat) {
        doc.manifest.objects.append(PageObject(pageID: page, kind: .text(string), frame: CGRect(origin: origin, size: size), fontSize: font))
    }

    private static func sticker(_ doc: NotebookDocument, _ page: UUID, _ emoji: String, at origin: CGPoint, side: CGFloat) {
        doc.manifest.objects.append(PageObject(pageID: page, kind: .sticker(emoji), frame: CGRect(origin: origin, size: CGSize(width: side, height: side))))
    }

    private static func stroke(_ points: [CGPoint], ink: PKInk, width: CGFloat) -> PKStroke {
        let pts = points.map {
            PKStrokePoint(location: $0, timeOffset: 0, size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: pts, creationDate: Date()))
    }

    private static func curve(points: [CGPoint], color: UIColor, width: CGFloat) -> [PKStroke] {
        [stroke(points, ink: PKInk(.pen, color: color), width: width)]
    }

    private static func underline(from a: CGPoint, to b: CGPoint, color: UIColor, width: CGFloat) -> [PKStroke] {
        curve(points: [a, CGPoint(x: (a.x + b.x) / 2, y: a.y + 3), b], color: color, width: width)
    }

    private static func highlighter(from a: CGPoint, to b: CGPoint, color: UIColor) -> [PKStroke] {
        [stroke([a, b], ink: PKInk(.marker, color: color.withAlphaComponent(0.55)), width: 22)]
    }

    private static func arrow(from a: CGPoint, to b: CGPoint, color: UIColor, width: CGFloat) -> [PKStroke] {
        let angle = atan2(b.y - a.y, b.x - a.x)
        let head: CGFloat = 16
        let left = CGPoint(x: b.x - head * cos(angle - .pi / 6), y: b.y - head * sin(angle - .pi / 6))
        let right = CGPoint(x: b.x - head * cos(angle + .pi / 6), y: b.y - head * sin(angle + .pi / 6))
        return curve(points: [a, b], color: color, width: width) + curve(points: [left, b, right], color: color, width: width)
    }

    private static func circle(center: CGPoint, radius: CGFloat, color: UIColor, width: CGFloat) -> [PKStroke] {
        let pts = (0...72).map { i -> CGPoint in
            let t = CGFloat(i) / 72 * .pi * 2
            return CGPoint(x: center.x + cos(t) * radius, y: center.y + sin(t) * radius * 0.96)
        }
        return curve(points: pts, color: color, width: width)
    }
}
#endif
