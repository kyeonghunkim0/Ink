import Foundation
import Observation
import PencilKit
import PDFKit
import UIKit
import InkCore

/// 재생 중 스트로크 동기 표시용 필터.
struct PlaybackFilter: Equatable {
    var startedAt: Date
    var duration: TimeInterval
    var time: TimeInterval

    /// 아직 재생 시점에 도달하지 않은 스트로크를 제외한 드로잉.
    func apply(to drawing: PKDrawing) -> PKDrawing {
        PKDrawing(strokes: drawing.strokes.filter { stroke in
            let offset = stroke.path.creationDate.timeIntervalSince(startedAt)
            guard offset >= 0, offset <= duration + 1 else { return true }
            return offset <= time
        })
    }
}

/// 편집기 상태. 문서 열기/저장, 페이지 조작, 녹음, 내보내기를 담당한다.
@MainActor
@Observable
final class EditorModel {
    let url: URL
    private(set) var document: NotebookDocument?
    private(set) var loadError: String?
    private(set) var isLoaded = false

    var currentPageIndex = 0
    /// 페이지 구조(추가/삭제/순서/크기)가 바뀔 때 증가. 캔버스 뷰는 이 값으로 PDFView를 다시 읽는다.
    private(set) var structureVersion = 0
    /// 특정 페이지로 스크롤 요청. 값이 바뀔 때마다 캔버스 뷰가 `currentPageIndex`로 이동한다.
    private(set) var navigationToken = 0
    /// 페이지별 필기 변경 횟수. 썸네일 갱신에 사용.
    private(set) var drawingVersions: [UUID: Int] = [:]
    /// 손가락 필기. 기본은 꺼짐(애플 펜슬만 인식).
    var isFingerDrawingEnabled = CommandLine.arguments.contains("--finger")
    /// 객체 모드: 켜면 필기 대신 이미지/텍스트/스티커를 선택·이동·편집한다.
    var isObjectModeEnabled = false {
        didSet { if !isObjectModeEnabled { selectedObjectID = nil } }
    }
    var selectedObjectID: UUID?
    /// 도구 피커의 삽입 메뉴에서 띄우는 사진 선택기/스티커 시트.
    var isPhotoPickerPresented = false
    var isStickerSheetPresented = false
    /// 객체 목록이 바뀔 때 증가. 오버레이가 이 값으로 동기화한다.
    private(set) var objectsVersion = 0
    var errorMessage: String?

    let recorder = AudioRecorder()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var recognitionTask: Task<Void, Never>?
    @ObservationIgnored private var recognitionDirty: Set<UUID> = []
    /// 편집기 검색어.
    var searchText = ""
    /// 손글씨 인식이 끝날 때마다 증가. 검색 결과 갱신에 사용.
    private(set) var recognitionVersion = 0
    @ObservationIgnored private var hasSecurityScope = false
    /// 닫는 중이면 새 저장을 예약하지 않는다(닫기와 저장이 겹치지 않게).
    @ObservationIgnored private var isClosing = false
    /// 줌 요청. 양수는 확대, 음수는 축소. 캔버스 뷰가 소비한다.
    private(set) var zoomRequest: (token: Int, delta: Int) = (0, 0)

    init(url: URL) {
        self.url = url
    }

    var manifest: NotebookManifest { document?.manifest ?? NotebookManifest(title: "") }
    var title: String { manifest.title }
    var pageCount: Int { manifest.pages.count }
    var isWhiteboard: Bool { manifest.kind == .whiteboard }

    var drawingPolicy: PKCanvasViewDrawingPolicy { isFingerDrawingEnabled ? .anyInput : .pencilOnly }

    var playbackFilter: PlaybackFilter? {
        guard let id = recorder.playingRecordingID,
              let rec = manifest.recordings.first(where: { $0.id == id }) else { return nil }
        return PlaybackFilter(startedAt: rec.startedAt, duration: rec.duration, time: recorder.playbackTime)
    }

    // MARK: - Lifecycle

    func load() async {
        guard document == nil else { return }
        // 앱 컨테이너 밖의 파일(파일 앱에서 열기)은 보안 범위 접근이 필요하다.
        hasSecurityScope = url.startAccessingSecurityScopedResource()
        let doc = NotebookDocument(fileURL: url)
        let ok = await withCheckedContinuation { cont in doc.open { cont.resume(returning: $0) } }
        if ok {
            document = doc
            isLoaded = true
            #if DEBUG
            if CommandLine.arguments.contains("--open-sample"), doc.manifest.title == "샘플", doc.manifest.pages.count == 1 {
                insertDebugStrokes(into: doc)
            }
            #endif
        } else {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
                hasSecurityScope = false
            }
            loadError = FileManager.default.fileExists(atPath: url.path)
                ? "노트를 열 수 없습니다."
                : "노트를 찾을 수 없습니다. 삭제되었거나 이동되었을 수 있습니다."
        }
    }

    /// 로드에 실패한 모델. 다시 열 때 새 모델로 바꿔 재시도한다.
    var didFailToLoad: Bool { loadError != nil }

    func save() async {
        guard !isClosing, let document, document.hasUnsavedChanges else { return }
        // 열려 있는 동안 다른 기기에서 이름이 바뀌면 UIDocument는 새 경로를 따라간다.
        // 처음 받은 `url`에 저장하면 옛 자리에 패키지를 다시 만들어 중복·유령 노트가 생긴다.
        let target = document.fileURL
        let ok = await withCheckedContinuation { cont in document.save(to: target, for: .forOverwriting) { cont.resume(returning: $0) } }
        if !ok { errorMessage = "저장에 실패했습니다." }
    }

    func close() async {
        guard !isClosing else { return }
        saveTask?.cancel()
        recognitionTask?.cancel()
        if !recognitionDirty.isEmpty { await recognizeDirtyPages() }
        if recorder.isRecording { finishRecording() }
        recorder.stopPlayback()
        // 여기부터는 새 저장을 예약하지 않는다. 남은 변경은 `UIDocument.close`가 저장한다.
        isClosing = true
        saveTask?.cancel()
        guard let document else { return }
        await withCheckedContinuation { cont in document.close { _ in cont.resume() } }
        self.document = nil
        if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
    }

    func zoom(by delta: Int) {
        zoomRequest = (zoomRequest.token + 1, delta)
    }

    /// 현재 페이지의 필기와 객체를 모두 지운다.
    func clearCurrentPage() {
        guard let document, let pageID = pageID(at: currentPageIndex) else { return }
        document.setDrawing(PKDrawing(), for: pageID)
        var removed = false
        for object in document.manifest.objects where object.pageID == pageID {
            if case .image(let name) = object.kind { document.removeImage(named: name) }
            removed = true
        }
        if removed {
            document.manifest.objects.removeAll { $0.pageID == pageID }
            document.markManifestChanged()
            selectedObjectID = nil
            objectsVersion += 1
        }
        drawingVersions[pageID, default: 0] += 1
        recognitionDirty.insert(pageID)
        scheduleRecognition()
        scheduleSave()
    }

    private func scheduleSave() {
        guard !isClosing else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    // MARK: - Drawings

    func pageID(at index: Int) -> UUID? {
        manifest.pages.indices.contains(index) ? manifest.pages[index].id : nil
    }

    func drawing(forPageAt index: Int) -> PKDrawing {
        guard let document, let id = pageID(at: index) else { return PKDrawing() }
        return document.drawing(for: id)
    }

    func updateDrawing(_ drawing: PKDrawing, forPageAt index: Int) {
        guard let document, let id = pageID(at: index) else { return }
        document.setDrawing(drawing, for: id)
        drawingVersions[id, default: 0] += 1
        recognitionDirty.insert(id)
        scheduleRecognition()
        if isWhiteboard, let page = document.pdfDocument.page(at: 0) {
            let current = page.bounds(for: .mediaBox).size
            if let grown = WhiteboardGeometry.grownSize(current: current, drawingBounds: drawing.bounds) {
                document.growWhiteboard(to: grown)
                structureVersion += 1
            }
        }
        scheduleSave()
    }

    // MARK: - Handwriting recognition & search

    /// 필기가 멈추고 잠시 뒤 바뀐 페이지의 손글씨를 인식한다.
    private func scheduleRecognition() {
        recognitionTask?.cancel()
        recognitionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.recognizeDirtyPages()
        }
    }

    private func recognizeDirtyPages() async {
        guard let document else { return }
        let targets = recognitionDirty
        recognitionDirty = []
        for pageID in targets {
            guard let index = manifest.pages.firstIndex(where: { $0.id == pageID }),
                  let page = document.pdfDocument.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let drawing = document.drawing(for: pageID)
            let text: String
            if drawing.strokes.isEmpty {
                text = ""
            } else {
                // 배경 없이 잉크만 흰 바탕에 그려 인식 정확도를 높인다.
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = 2
                let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: bounds.size))
                    // 다크 모드에서 잉크가 흰색으로 뒤집히지 않도록 라이트 테마로 고정한다.
                    Exporter.inkImage(drawing, from: CGRect(origin: .zero, size: bounds.size), scale: 2, paperColor: .white)
                        .draw(in: CGRect(origin: .zero, size: bounds.size))
                }
                guard let cg = image.cgImage else { continue }
                text = (try? await HandwritingRecognizer.recognize(cg)) ?? ""
            }
            guard let document = self.document else { return }
            if document.manifest.recognizedText[pageID] != text {
                document.manifest.recognizedText[pageID] = text
                document.markManifestChanged()
                recognitionVersion += 1
                scheduleSave()
            }
        }
    }

    struct SearchHit: Identifiable, Hashable {
        var id: UUID { pageID }
        let pageID: UUID
        let pageIndex: Int
        let snippet: String
    }

    /// 검색어가 들어 있는 페이지 목록. 손글씨 인식 결과, 텍스트 상자, PDF 본문을 함께 찾는다.
    var searchHits: [SearchHit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let document else { return [] }
        return manifest.pages.enumerated().compactMap { index, info in
            var sources: [String] = []
            if let ink = manifest.recognizedText[info.id] { sources.append(ink) }
            for object in manifest.objects where object.pageID == info.id {
                if case .text(let t) = object.kind { sources.append(t) }
            }
            if let pdfText = document.pdfDocument.page(at: index)?.string { sources.append(pdfText) }
            for source in sources {
                if let range = source.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
                    let start = source.index(range.lowerBound, offsetBy: -20, limitedBy: source.startIndex) ?? source.startIndex
                    let end = source.index(range.upperBound, offsetBy: 40, limitedBy: source.endIndex) ?? source.endIndex
                    let snippet = source[start..<end].replacingOccurrences(of: "\n", with: " ")
                    return SearchHit(pageID: info.id, pageIndex: index, snippet: String(snippet))
                }
            }
            return nil
        }
    }

    // MARK: - Objects

    func objects(forPageAt index: Int) -> [PageObject] {
        guard let id = pageID(at: index) else { return [] }
        return manifest.objects.filter { $0.pageID == id }
    }

    /// 현재 페이지 가운데에 객체를 추가한다.
    private func insertObject(kind: PageObjectKind, size: CGSize, fontSize: CGFloat = 20) {
        guard let document, let pageID = pageID(at: currentPageIndex),
              let page = document.pdfDocument.page(at: currentPageIndex) else { return }
        let bounds = page.bounds(for: .mediaBox)
        let w = min(size.width, bounds.width * 0.8), h = size.height * (w / size.width)
        let frame = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
        let object = PageObject(pageID: pageID, kind: kind, frame: frame, fontSize: fontSize)
        document.manifest.objects.append(object)
        document.markManifestChanged()
        objectsVersion += 1
        isObjectModeEnabled = true
        selectedObjectID = object.id
        bumpThumbnail(for: pageID)
        scheduleSave()
    }

    func addImage(_ data: Data) {
        guard let document, let image = UIImage(data: data) else { return }
        // 저장 용량을 위해 긴 변 2048px로 줄여 JPEG로 저장한다.
        let maxSide: CGFloat = 2048
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return }
        let name = document.addImage(jpeg)
        insertObject(kind: .image(fileName: name), size: CGSize(width: 320, height: 320 * target.height / target.width))
    }

    func addTextBox() {
        insertObject(kind: .text("텍스트"), size: CGSize(width: 260, height: 80))
    }

    func addSticker(_ emoji: String) {
        insertObject(kind: .sticker(emoji), size: CGSize(width: 96, height: 96))
    }

    func moveObject(_ id: UUID, to frame: CGRect) {
        guard let document, let i = document.manifest.objects.firstIndex(where: { $0.id == id }) else { return }
        var object = document.manifest.objects[i]
        if object.isText, object.frame.height > 0 {
            object.fontSize = max(8, object.fontSize * (frame.height / object.frame.height))
        }
        object.frame = frame
        document.manifest.objects[i] = object
        document.markManifestChanged()
        bumpThumbnail(for: object.pageID)
        scheduleSave()
    }

    func updateObjectText(_ id: UUID, text: String) {
        guard let document, let i = document.manifest.objects.firstIndex(where: { $0.id == id }) else { return }
        document.manifest.objects[i].kind = .text(text)
        document.markManifestChanged()
        bumpThumbnail(for: document.manifest.objects[i].pageID)
        scheduleSave()
    }

    func deleteObject(_ id: UUID) {
        guard let document, let i = document.manifest.objects.firstIndex(where: { $0.id == id }) else { return }
        let object = document.manifest.objects.remove(at: i)
        if case .image(let name) = object.kind { document.removeImage(named: name) }
        document.markManifestChanged()
        if selectedObjectID == id { selectedObjectID = nil }
        objectsVersion += 1
        bumpThumbnail(for: object.pageID)
        scheduleSave()
    }

    private func bumpThumbnail(for pageID: UUID) {
        drawingVersions[pageID, default: 0] += 1
        document?.invalidateThumbnail(for: pageID)
    }

    // MARK: - Pages

    func addPage(_ template: PaperTemplate? = nil, after index: Int? = nil) {
        guard let document else { return }
        let insertAt = min((index ?? currentPageIndex) + 1, pageCount)
        document.insertTemplatePage(template ?? manifest.defaultTemplate, at: insertAt)
        structureVersion += 1
        goToPage(insertAt)
        scheduleSave()
    }

    func deletePage(at index: Int) {
        guard let document, pageCount > 1 else { return }
        document.removePage(at: index)
        structureVersion += 1
        goToPage(min(index, pageCount - 1))
        scheduleSave()
    }

    func movePage(from source: Int, to destination: Int) {
        guard let document else { return }
        document.movePage(from: source, to: destination)
        structureVersion += 1
        scheduleSave()
    }

    func goToPage(_ index: Int) {
        guard pageCount > 0 else { return }
        currentPageIndex = max(0, min(index, pageCount - 1))
        navigationToken += 1
    }

    /// PDFView가 스크롤로 페이지를 바꿨을 때 호출. 네비게이션 요청을 만들지 않는다.
    func noteVisiblePage(_ index: Int) {
        if currentPageIndex != index { currentPageIndex = index }
    }

    // MARK: - Recording

    func toggleRecording() async {
        if recorder.isRecording {
            finishRecording()
            return
        }
        guard await recorder.requestPermission() else {
            errorMessage = "마이크 권한이 필요합니다. 설정에서 허용해 주세요."
            return
        }
        do { _ = try recorder.startRecording() } catch { errorMessage = error.localizedDescription }
    }

    private func finishRecording() {
        guard let document else { return }
        let result: (url: URL, startedAt: Date, duration: TimeInterval)
        do { result = try recorder.stopRecording() } catch {
            errorMessage = error.localizedDescription
            return
        }
        let number = manifest.recordings.count + 1
        let info = RecordingInfo(
            title: "녹음 \(number)", startedAt: result.startedAt, duration: result.duration,
            pageID: pageID(at: currentPageIndex))
        document.addRecording(info, temporaryURL: result.url)
        // 닫는 중이면 `UIDocument.close`가 녹음까지 저장한다.
        if !isClosing { Task { await save() } }
    }

    func play(_ recording: RecordingInfo) {
        guard let document else { return }
        if let pageID = recording.pageID, let index = manifest.pages.firstIndex(where: { $0.id == pageID }) {
            goToPage(index)
        }
        do { try recorder.play(url: document.audioURL(for: recording), recordingID: recording.id) } catch {
            errorMessage = "재생할 수 없습니다: \(error.localizedDescription)"
        }
    }

    func deleteRecording(_ recording: RecordingInfo) {
        if recorder.playingRecordingID == recording.id { recorder.stopPlayback() }
        document?.removeRecording(recording)
        scheduleSave()
    }

    // MARK: - Export

    enum ExportKind { case pdfAll, pdfCurrentPage, pngCurrentPage, package }

    func export(_ kind: ExportKind) async throws -> URL {
        guard let document else { throw CocoaError(.fileNoSuchFile) }
        await save()
        let base = title.isEmpty ? "Ink" : title
        switch kind {
        case .pdfAll:
            return try Exporter.writeTemporary(data: Exporter.flattenedPDF(document: document), name: "\(base).pdf")
        case .pdfCurrentPage:
            let data = Exporter.flattenedPDF(document: document, pageIndices: [currentPageIndex])
            return try Exporter.writeTemporary(data: data, name: "\(base) - \(currentPageIndex + 1).pdf")
        case .pngCurrentPage:
            guard let image = Exporter.renderPage(document: document, pageIndex: currentPageIndex, scale: 3),
                  let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            return try Exporter.writeTemporary(data: png, name: "\(base) - \(currentPageIndex + 1).png")
        case .package:
            return document.fileURL
        }
    }
}

#if DEBUG
import PencilKit

extension EditorModel {
    /// 시뮬레이터 검증용 샘플 스트로크와 페이지.
    fileprivate func insertDebugStrokes(into doc: NotebookDocument) {
        let ink = PKInk(.pen, color: .systemBlue)
        func stroke(_ points: [CGPoint], start: Date) -> PKStroke {
            let pts = points.map {
                PKStrokePoint(location: $0, timeOffset: 0, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: ink, path: PKStrokePath(controlPoints: pts, creationDate: start))
        }
        var pts: [CGPoint] = []
        for i in 0..<200 {
            let t = CGFloat(i) / 200
            pts.append(CGPoint(x: 80 + t * 400, y: 200 + sin(t * .pi * 4) * 60))
        }
        let drawing = PKDrawing(strokes: [
            stroke(pts, start: Date()),
            stroke([CGPoint(x: 100, y: 400), CGPoint(x: 300, y: 500), CGPoint(x: 100, y: 600)], start: Date()),
        ])
        if let id = pageID(at: 0) {
            doc.setDrawing(drawing, for: id)
            drawingVersions[id, default: 0] += 1
        }
        if !isWhiteboard {
            doc.insertTemplatePage(.grid, at: 1)
            doc.insertTemplatePage(.cornell, at: 2)
            structureVersion += 1
        }
        if CommandLine.arguments.contains("--objects") {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { ctx in
                UIColor.systemOrange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
                UIColor.white.setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 120, y: 70, width: 160, height: 160))
            }
            if let data = image.pngData() { addImage(data) }
            addTextBox()
            addSticker("⭐️")
            if let id = pageID(at: 0), let page = doc.pdfDocument.page(at: 0) {
                // 겹치지 않게 페이지 아래쪽에 가로로 늘어놓는다.
                let bounds = page.bounds(for: .mediaBox)
                let objs = doc.manifest.objects.filter { $0.pageID == id }
                for (i, o) in objs.enumerated() {
                    let idx = doc.manifest.objects.firstIndex(of: o)!
                    doc.manifest.objects[idx].frame.size = CGSize(width: 160, height: 120)
                    doc.manifest.objects[idx].frame.origin = CGPoint(x: 40 + CGFloat(i) * 190, y: bounds.height * 0.62)
                }
                objectsVersion += 1
            }
            isObjectModeEnabled = false
        }
    }
}
#endif
