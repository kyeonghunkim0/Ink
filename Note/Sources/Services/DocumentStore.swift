import Foundation
import Observation
import PDFKit
import UIKit

/// 라이브러리 항목(폴더 또는 노트북).
struct LibraryItem: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case folder, notebook }

    var url: URL
    var kind: Kind
    var modifiedAt: Date
    /// iCloud에서 아직 내려받지 않은 항목.
    var isDownloading: Bool = false

    var id: URL { url }
    var name: String { kind == .notebook ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent }
}

/// 노트북 생성 옵션.
struct NewNotebookOptions: Sendable {
    var title = "새 노트"
    var kind: NotebookKind = .notebook
    var template: PaperTemplate = .lined
    var paperSize: PaperSize = .a4
    var paperColor: PaperColor = .white
    var isLandscape = false
}

/// iCloud(또는 로컬 폴백) 문서 저장소. 폴더는 실제 디렉터리, 노트북은 `.gnote` 패키지다.
@MainActor
@Observable
final class DocumentStore {
    private(set) var rootURL: URL?
    private(set) var isICloud = false
    /// 파일 시스템이 바뀔 때마다 증가. 뷰는 이 값을 관찰해 목록을 다시 읽는다.
    private(set) var changeCounter = 0
    private(set) var lastError: String?

    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func start() async {
        guard rootURL == nil else { return }
        let container = await Task.detached(priority: .userInitiated) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }.value
        if let container {
            let docs = container.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            rootURL = docs
            isICloud = true
            startMetadataQuery()
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            rootURL = docs
            isICloud = false
        }
        changeCounter += 1
    }

    func refresh() { changeCounter += 1 }

    // MARK: - Listing

    func items(in folder: URL) -> [LibraryItem] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .isPackageKey],
            options: []) else { return [] }

        var items: [LibraryItem] = []
        for url in urls {
            let name = url.lastPathComponent
            if name.hasPrefix(".") {
                // iCloud 플레이스홀더(.이름.icloud)는 다운로드를 시작하고 다운로드 중으로 표시.
                if name.hasSuffix(".icloud") {
                    try? fm.startDownloadingUbiquitousItem(at: url)
                    let realName = String(name.dropFirst().dropLast(".icloud".count))
                    let realURL = folder.appendingPathComponent(realName)
                    let kind: LibraryItem.Kind = realURL.pathExtension == NotebookPackage.fileExtension ? .notebook : .folder
                    items.append(LibraryItem(url: realURL, kind: kind, modifiedAt: .distantPast, isDownloading: true))
                }
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true else { continue }
            let date = values?.contentModificationDate ?? .distantPast
            if url.pathExtension == NotebookPackage.fileExtension {
                items.append(LibraryItem(url: url, kind: .notebook, modifiedAt: date))
            } else {
                items.append(LibraryItem(url: url, kind: .folder, modifiedAt: date))
            }
        }
        return items.sorted {
            if $0.kind != $1.kind { return $0.kind == .folder }
            return $0.modifiedAt > $1.modifiedAt
        }
    }

    func allFolders() -> [URL] {
        guard let rootURL else { return [] }
        var result: [URL] = [rootURL]
        var queue: [URL] = [rootURL]
        while let dir = queue.popLast() {
            for item in items(in: dir) where item.kind == .folder {
                result.append(item.url)
                queue.append(item.url)
            }
        }
        return result
    }

    func displayName(for folder: URL) -> String {
        folder == rootURL ? "모든 노트" : folder.lastPathComponent
    }

    // MARK: - Creation

    func createFolder(named name: String, in folder: URL) throws {
        let url = uniqueURL(in: folder, baseName: name, pathExtension: nil)
        try coordinatedWrite(url) { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
        changeCounter += 1
    }

    @discardableResult
    func createNotebook(_ options: NewNotebookOptions, in folder: URL) async throws -> URL {
        var manifest = NotebookManifest(title: options.title)
        manifest.kind = options.kind
        manifest.paperSize = options.paperSize
        manifest.paperColor = options.paperColor
        manifest.isLandscape = options.isLandscape
        manifest.defaultTemplate = options.template

        let pdf: PDFDocument
        switch options.kind {
        case .notebook:
            manifest.pages = [PageInfo(template: options.template)]
            pdf = TemplateRenderer.makePDFDocument(
                template: options.template, size: manifest.pageSize, color: options.paperColor, pageCount: 1)
        case .whiteboard:
            let template: PaperTemplate = options.template == .blank ? .blank : .dotted
            manifest.pages = [PageInfo(template: template)]
            pdf = TemplateRenderer.makePDFDocument(
                template: template, size: WhiteboardGeometry.initialSize, color: options.paperColor, pageCount: 1)
        }
        return try await saveNewNotebook(manifest: manifest, pdf: pdf, in: folder)
    }

    /// PDF 또는 Office 파일을 노트북으로 가져온다.
    @discardableResult
    func importFile(at sourceURL: URL, in folder: URL) async throws -> URL {
        let data = try PDFImporter.readData(from: sourceURL)
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension.lowercased()

        let pdfData: Data
        if ext == "pdf" {
            pdfData = data
        } else if OfficeConverter.officeExtensions.contains(ext) {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let copy = temp.appendingPathComponent(sourceURL.lastPathComponent)
            try data.write(to: copy)
            defer { try? FileManager.default.removeItem(at: temp) }
            pdfData = try await OfficeConverter().convertToPDF(fileURL: copy)
        } else {
            throw ImportError.unsupportedType
        }

        let (manifest, pdf) = try PDFImporter.makeNotebook(title: title, pdfData: pdfData)
        return try await saveNewNotebook(manifest: manifest, pdf: pdf, in: folder)
    }

    private func saveNewNotebook(manifest: NotebookManifest, pdf: PDFDocument, in folder: URL) async throws -> URL {
        let url = uniqueURL(in: folder, baseName: manifest.title, pathExtension: NotebookPackage.fileExtension)
        let document = NotebookDocument(fileURL: url, manifest: manifest, pdfDocument: pdf)
        let ok = await withCheckedContinuation { cont in document.save(to: url, for: .forCreating) { cont.resume(returning: $0) } }
        guard ok else { throw CocoaError(.fileWriteUnknown) }
        await withCheckedContinuation { cont in document.close { _ in cont.resume() } }
        changeCounter += 1
        return url
    }

    // MARK: - Mutation

    func rename(_ item: LibraryItem, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let folder = item.url.deletingLastPathComponent()
        let ext: String? = item.kind == .notebook ? NotebookPackage.fileExtension : nil
        let target = uniqueURL(in: folder, baseName: trimmed, pathExtension: ext)
        try coordinatedMove(from: item.url, to: target)
        if item.kind == .notebook {
            try updateManifestTitle(at: target, title: trimmed)
        }
        changeCounter += 1
    }

    func delete(_ item: LibraryItem) throws {
        var coordinatorError: NSError?
        var inner: Error?
        NSFileCoordinator().coordinate(writingItemAt: item.url, options: .forDeleting, error: &coordinatorError) { url in
            do { try FileManager.default.removeItem(at: url) } catch { inner = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let inner { throw inner }
        changeCounter += 1
    }

    func move(_ item: LibraryItem, to folder: URL) throws {
        guard item.url.deletingLastPathComponent() != folder, !folder.path.hasPrefix(item.url.path + "/") else { return }
        let ext: String? = item.kind == .notebook ? NotebookPackage.fileExtension : nil
        let target = uniqueURL(in: folder, baseName: item.name, pathExtension: ext)
        try coordinatedMove(from: item.url, to: target)
        changeCounter += 1
    }

    func duplicate(_ item: LibraryItem) throws {
        let folder = item.url.deletingLastPathComponent()
        let ext: String? = item.kind == .notebook ? NotebookPackage.fileExtension : nil
        let target = uniqueURL(in: folder, baseName: item.name + " 복사본", pathExtension: ext)
        var coordinatorError: NSError?
        var inner: Error?
        NSFileCoordinator().coordinate(readingItemAt: item.url, options: [], writingItemAt: target, options: .forReplacing, error: &coordinatorError) { src, dst in
            do { try FileManager.default.copyItem(at: src, to: dst) } catch { inner = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let inner { throw inner }
        if item.kind == .notebook {
            try? updateManifestTitle(at: target, title: target.deletingPathExtension().lastPathComponent)
        }
        changeCounter += 1
    }

    // MARK: - Helpers

    private func updateManifestTitle(at notebookURL: URL, title: String) throws {
        let manifestURL = notebookURL.appendingPathComponent(NotebookPackage.manifestName)
        var manifest = try NotebookManifest.decode(try Data(contentsOf: manifestURL))
        manifest.title = title
        manifest.id = UUID()
        try coordinatedWrite(manifestURL) { try manifest.encoded().write(to: $0, options: .atomic) }
    }

    private func uniqueURL(in folder: URL, baseName: String, pathExtension: String?) -> URL {
        let safe = baseName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        func make(_ suffix: Int) -> URL {
            let name = suffix == 0 ? safe : "\(safe) \(suffix + 1)"
            var url = folder.appendingPathComponent(name)
            if let pathExtension { url.appendPathExtension(pathExtension) }
            return url
        }
        var i = 0
        while FileManager.default.fileExists(atPath: make(i).path) { i += 1 }
        return make(i)
    }

    private func coordinatedWrite(_ url: URL, _ body: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var inner: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinatorError) { u in
            do { try body(u) } catch { inner = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let inner { throw inner }
    }

    private func coordinatedMove(from: URL, to: URL) throws {
        var coordinatorError: NSError?
        var inner: Error?
        NSFileCoordinator().coordinate(writingItemAt: from, options: .forMoving, writingItemAt: to, options: .forReplacing, error: &coordinatorError) { src, dst in
            do { try FileManager.default.moveItem(at: src, to: dst) } catch { inner = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let inner { throw inner }
    }

    private func startMetadataQuery() {
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        q.notificationBatchingInterval = 0.5
        let center = NotificationCenter.default
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleQueryUpdate() }
            })
        }
        q.start()
        query = q
    }

    private func handleQueryUpdate() {
        guard let query else { return }
        query.disableUpdates()
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String else { continue }
            if status == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
        query.enableUpdates()
        changeCounter += 1
    }
}

/// 무한 화이트보드 크기 정책.
enum WhiteboardGeometry {
    static let initialSize = CGSize(width: 2400, height: 2400)
    static let growthStep: CGFloat = 1200
    static let edgeMargin: CGFloat = 300
    static let maxDimension: CGFloat = 16_000

    /// 필기 범위가 가장자리에 가까우면 더 큰 크기를 돌려준다.
    static func grownSize(current: CGSize, drawingBounds: CGRect) -> CGSize? {
        guard !drawingBounds.isNull, !drawingBounds.isEmpty else { return nil }
        var size = current
        if drawingBounds.maxX > current.width - edgeMargin { size.width = min(current.width + growthStep, maxDimension) }
        if drawingBounds.maxY > current.height - edgeMargin { size.height = min(current.height + growthStep, maxDimension) }
        return size == current ? nil : size
    }
}
