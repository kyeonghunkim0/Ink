import UIKit
import PDFKit
import PencilKit
import UniformTypeIdentifiers

/// `.inknote` 패키지 문서. UIKit이 `load(fromContents:)`와 `contents(forType:)`를 메인 큐에서 호출하므로
/// 내부 상태는 메인 스레드에서만 접근한다(UIDocument는 nonisolated 클래스라 컴파일러가 강제하지 않는다).
final class NotebookDocument: UIDocument, @unchecked Sendable {
    var manifest: NotebookManifest
    var pdfDocument: PDFDocument
    private(set) var drawings: [UUID: PKDrawing] = [:]
    private var drawingsDirty: Set<UUID> = []
    private var pdfDirty = true
    private var thumbnailDirty = true
    /// 아직 패키지에 쓰지 않은 녹음 파일(임시 URL).
    private var pendingAudio: [String: URL] = [:]
    /// 이 세션에서 녹음한 파일의 임시 URL. 저장이 백그라운드에서 끝나기 전에도 재생할 수 있도록 유지한다.
    private var sessionAudio: [String: URL] = [:]
    /// 페이지 객체용 이미지 데이터. 키는 `images/` 안의 파일 이름.
    private(set) var images: [String: Data] = [:]
    private var imagesDirty: Set<String> = []
    private var imageCache: [String: UIImage] = [:]
    /// 마지막으로 읽거나 쓴 패키지 래퍼. 변경된 항목만 교체해 iCloud 전송량을 줄인다.
    private var rootWrapper: FileWrapper?

    init(fileURL: URL, manifest: NotebookManifest, pdfDocument: PDFDocument) {
        self.manifest = manifest
        self.pdfDocument = pdfDocument
        super.init(fileURL: fileURL)
    }

    override init(fileURL: URL) {
        self.manifest = NotebookManifest(title: fileURL.deletingPathExtension().lastPathComponent)
        self.pdfDocument = PDFDocument()
        super.init(fileURL: fileURL)
    }

    // MARK: - Drawing access

    func drawing(for pageID: UUID) -> PKDrawing {
        drawings[pageID] ?? PKDrawing()
    }

    func setDrawing(_ drawing: PKDrawing, for pageID: UUID) {
        drawings[pageID] = drawing
        drawingsDirty.insert(pageID)
        if manifest.pages.first?.id == pageID { thumbnailDirty = true }
        touch()
    }

    func markPDFChanged() {
        normalizePDF()
        pdfDirty = true
        thumbnailDirty = true
        touch()
    }

    /// 다른 문서에서 가져온 페이지가 섞이지 않도록 PDF를 직렬화해 단일 CGPDFDocument로 다시 만든다.
    /// PDFKit은 서로 다른 문서에 속한 페이지가 섞이면 렌더링/접근성 경로에서 불안정하다.
    private func normalizePDF() {
        guard let data = pdfDocument.dataRepresentation(), let fresh = PDFDocument(data: data) else { return }
        pdfDocument = fresh
    }

    func markManifestChanged() {
        touch()
    }

    func addRecording(_ info: RecordingInfo, temporaryURL: URL) {
        manifest.recordings.append(info)
        pendingAudio[info.fileName] = temporaryURL
        sessionAudio[info.fileName] = temporaryURL
        touch()
    }

    func removeRecording(_ info: RecordingInfo) {
        manifest.recordings.removeAll { $0.id == info.id }
        pendingAudio[info.fileName] = nil
        sessionAudio[info.fileName] = nil
        if let audioDir = rootWrapper?.fileWrappers?[NotebookPackage.audioDirectory],
           let file = audioDir.fileWrappers?[info.fileName] {
            audioDir.removeFileWrapper(file)
        }
        touch()
    }

    // MARK: - Images

    /// 이미지를 패키지에 추가하고 파일 이름을 돌려준다.
    func addImage(_ data: Data, fileExtension: String = "jpg") -> String {
        let name = "\(UUID().uuidString).\(fileExtension)"
        images[name] = data
        imagesDirty.insert(name)
        touch()
        return name
    }

    func image(named name: String) -> UIImage? {
        if let cached = imageCache[name] { return cached }
        guard let data = images[name], let img = UIImage(data: data) else { return nil }
        imageCache[name] = img
        return img
    }

    func removeImage(named name: String) {
        images[name] = nil
        imageCache[name] = nil
        imagesDirty.remove(name)
        if let dir = rootWrapper?.fileWrappers?[NotebookPackage.imagesDirectory],
           let file = dir.fileWrappers?[name] {
            dir.removeFileWrapper(file)
        }
    }

    /// 녹음 파일 URL. 이 세션에서 녹음한 파일은 임시 복사본을, 그 외에는 패키지 안의 파일을 돌려준다.
    func audioURL(for info: RecordingInfo) -> URL {
        if let temp = sessionAudio[info.fileName], FileManager.default.fileExists(atPath: temp.path) { return temp }
        return fileURL
            .appendingPathComponent(NotebookPackage.audioDirectory)
            .appendingPathComponent(info.fileName)
    }

    private func touch() {
        manifest.modifiedAt = Date()
        updateChangeCount(.done)
    }

    // MARK: - Page management

    func insertTemplatePage(_ template: PaperTemplate, at index: Int) {
        let page = TemplateRenderer.makePDFPage(
            template: template, size: manifest.pageSize, color: manifest.paperColor)
        pdfDocument.insert(page, at: index)
        manifest.pages.insert(PageInfo(template: template), at: index)
        markPDFChanged()
    }

    func removePage(at index: Int) {
        guard manifest.pages.count > 1, manifest.pages.indices.contains(index) else { return }
        let info = manifest.pages.remove(at: index)
        drawings[info.id] = nil
        for object in manifest.objects where object.pageID == info.id {
            if case .image(let name) = object.kind { removeImage(named: name) }
        }
        manifest.objects.removeAll { $0.pageID == info.id }
        manifest.recognizedText[info.id] = nil
        pdfDocument.removePage(at: index)
        if let pagesDir = rootWrapper?.fileWrappers?[NotebookPackage.pagesDirectory],
           let file = pagesDir.fileWrappers?[Self.drawingFileName(for: info.id)] {
            pagesDir.removeFileWrapper(file)
        }
        markPDFChanged()
    }

    func movePage(from source: Int, to destination: Int) {
        guard source != destination,
              manifest.pages.indices.contains(source),
              (0...manifest.pages.count).contains(destination) else { return }
        let info = manifest.pages.remove(at: source)
        guard let page = pdfDocument.page(at: source) else { return }
        pdfDocument.removePage(at: source)
        let target = destination > source ? destination - 1 : destination
        manifest.pages.insert(info, at: target)
        pdfDocument.insert(page, at: target)
        markPDFChanged()
    }

    /// 화이트보드 페이지를 더 큰 크기로 다시 만든다. 필기는 좌표가 유지된다.
    func growWhiteboard(to size: CGSize) {
        guard manifest.kind == .whiteboard, let info = manifest.pages.first else { return }
        let page = TemplateRenderer.makePDFPage(
            template: info.template ?? .dotted, size: size, color: manifest.paperColor)
        pdfDocument.removePage(at: 0)
        pdfDocument.insert(page, at: 0)
        markPDFChanged()
    }

    // MARK: - UIDocument

    override func contents(forType typeName: String) throws -> Any {
        try buildWrapper()
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let wrapper = contents as? FileWrapper else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try read(wrapper)
    }

    private func read(_ wrapper: FileWrapper) throws {
        let children = wrapper.fileWrappers ?? [:]
        guard let manifestData = children[NotebookPackage.manifestName]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        manifest = try NotebookManifest.decode(manifestData)
        if let pdfData = children[NotebookPackage.backgroundName]?.regularFileContents,
           let pdf = PDFDocument(data: pdfData) {
            pdfDocument = pdf
        } else {
            pdfDocument = PDFDocument()
        }
        var loaded: [UUID: PKDrawing] = [:]
        if let pagesDir = children[NotebookPackage.pagesDirectory]?.fileWrappers {
            for info in manifest.pages {
                if let data = pagesDir[Self.drawingFileName(for: info.id)]?.regularFileContents,
                   let drawing = try? PKDrawing(data: data) {
                    loaded[info.id] = drawing
                }
            }
        }
        drawings = loaded
        drawingsDirty = []
        var loadedImages: [String: Data] = [:]
        if let imagesDir = children[NotebookPackage.imagesDirectory]?.fileWrappers {
            for (name, file) in imagesDir {
                if let data = file.regularFileContents { loadedImages[name] = data }
            }
        }
        images = loadedImages
        imagesDirty = []
        imageCache = [:]
        pdfDirty = false
        thumbnailDirty = false
        rootWrapper = wrapper
    }

    private func buildWrapper() throws -> FileWrapper {
        let root = rootWrapper ?? FileWrapper(directoryWithFileWrappers: [:])
        let children = root.fileWrappers ?? [:]

        replace(in: root, name: NotebookPackage.manifestName,
                with: FileWrapper(regularFileWithContents: try manifest.encoded()))

        if pdfDirty || children[NotebookPackage.backgroundName] == nil {
            if let data = pdfDocument.dataRepresentation() {
                replace(in: root, name: NotebookPackage.backgroundName,
                        with: FileWrapper(regularFileWithContents: data))
            }
            pdfDirty = false
        }

        let pagesDir = children[NotebookPackage.pagesDirectory] ?? {
            let dir = FileWrapper(directoryWithFileWrappers: [:])
            dir.preferredFilename = NotebookPackage.pagesDirectory
            root.addFileWrapper(dir)
            return dir
        }()
        for pageID in drawingsDirty {
            guard let drawing = drawings[pageID] else { continue }
            replace(in: pagesDir, name: Self.drawingFileName(for: pageID),
                    with: FileWrapper(regularFileWithContents: drawing.dataRepresentation()))
        }
        drawingsDirty = []

        if !imagesDirty.isEmpty {
            let imagesDir = children[NotebookPackage.imagesDirectory] ?? {
                let dir = FileWrapper(directoryWithFileWrappers: [:])
                dir.preferredFilename = NotebookPackage.imagesDirectory
                root.addFileWrapper(dir)
                return dir
            }()
            for name in imagesDirty {
                guard let data = images[name] else { continue }
                replace(in: imagesDir, name: name, with: FileWrapper(regularFileWithContents: data))
            }
            imagesDirty = []
        }

        if !pendingAudio.isEmpty {
            let audioDir = children[NotebookPackage.audioDirectory] ?? {
                let dir = FileWrapper(directoryWithFileWrappers: [:])
                dir.preferredFilename = NotebookPackage.audioDirectory
                root.addFileWrapper(dir)
                return dir
            }()
            for (name, url) in pendingAudio {
                if let data = try? Data(contentsOf: url) {
                    replace(in: audioDir, name: name, with: FileWrapper(regularFileWithContents: data))
                }
            }
            pendingAudio = [:]
        }

        if thumbnailDirty || children[NotebookPackage.thumbnailName] == nil {
            let png = Exporter.thumbnail(for: self, pageIndex: 0, maxDimension: 400)?.pngData()
            if let png {
                replace(in: root, name: NotebookPackage.thumbnailName,
                        with: FileWrapper(regularFileWithContents: png))
            }
            thumbnailDirty = false
        }

        rootWrapper = root
        return root
    }

    private func replace(in directory: FileWrapper, name: String, with wrapper: FileWrapper) {
        if let existing = directory.fileWrappers?[name] {
            directory.removeFileWrapper(existing)
        }
        wrapper.preferredFilename = name
        directory.addFileWrapper(wrapper)
    }

    static func drawingFileName(for pageID: UUID) -> String {
        "\(pageID.uuidString).\(NotebookPackage.drawingExtension)"
    }

    override func handleError(_ error: any Error, userInteractionPermitted: Bool) {
        NSLog("NotebookDocument error: \(error)")
        super.handleError(error, userInteractionPermitted: userInteractionPermitted)
    }
}
