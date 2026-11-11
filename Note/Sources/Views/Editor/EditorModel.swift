import Foundation
import Observation
import PencilKit
import PDFKit
import UIKit

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
    var isFingerDrawingEnabled = false
    var errorMessage: String?

    let recorder = AudioRecorder()
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    var manifest: NotebookManifest { document?.manifest ?? NotebookManifest(title: "") }
    var title: String { manifest.title }
    var pageCount: Int { manifest.pages.count }
    var isWhiteboard: Bool { manifest.kind == .whiteboard }

    var drawingPolicy: PKCanvasViewDrawingPolicy { isFingerDrawingEnabled ? .anyInput : .default }

    var playbackFilter: PlaybackFilter? {
        guard let id = recorder.playingRecordingID,
              let rec = manifest.recordings.first(where: { $0.id == id }) else { return nil }
        return PlaybackFilter(startedAt: rec.startedAt, duration: rec.duration, time: recorder.playbackTime)
    }

    // MARK: - Lifecycle

    func load() async {
        let doc = NotebookDocument(fileURL: url)
        let ok = await withCheckedContinuation { cont in doc.open { cont.resume(returning: $0) } }
        if ok {
            document = doc
            isLoaded = true
        } else {
            loadError = "노트를 열 수 없습니다."
        }
    }

    func save() async {
        guard let document, document.hasUnsavedChanges else { return }
        let ok = await withCheckedContinuation { cont in document.save(to: url, for: .forOverwriting) { cont.resume(returning: $0) } }
        if !ok { errorMessage = "저장에 실패했습니다." }
    }

    func close() async {
        saveTask?.cancel()
        if recorder.isRecording { finishRecording() }
        recorder.stopPlayback()
        guard let document else { return }
        await withCheckedContinuation { cont in document.close { _ in cont.resume() } }
        self.document = nil
    }

    private func scheduleSave() {
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
        if isWhiteboard, let page = document.pdfDocument.page(at: 0) {
            let current = page.bounds(for: .mediaBox).size
            if let grown = WhiteboardGeometry.grownSize(current: current, drawingBounds: drawing.bounds) {
                document.growWhiteboard(to: grown)
                structureVersion += 1
            }
        }
        scheduleSave()
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
        guard let document, let result = recorder.stopRecording() else { return }
        let number = manifest.recordings.count + 1
        let info = RecordingInfo(
            title: "녹음 \(number)", startedAt: result.startedAt, duration: result.duration,
            pageID: pageID(at: currentPageIndex))
        document.addRecording(info, temporaryURL: result.url)
        Task { await save() }
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
        let base = title.isEmpty ? "Note" : title
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
            return url
        }
    }
}
