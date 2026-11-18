import Foundation
import Observation
import PDFKit
import UIKit

/// 라이브러리 항목(폴더 또는 노트북).
public struct LibraryItem: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case folder, notebook }

    public var url: URL
    public var kind: Kind
    public var modifiedAt: Date
    /// iCloud에서 아직 내려받지 않은 항목.
    public var isDownloading: Bool = false

    public init(url: URL, kind: Kind, modifiedAt: Date, isDownloading: Bool = false) {
        self.url = url; self.kind = kind; self.modifiedAt = modifiedAt; self.isDownloading = isDownloading
    }

    public var id: URL { url }
    public var name: String { kind == .notebook ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent }
}

/// 노트북 생성 옵션.
public struct NewNotebookOptions: Sendable {
    public var title = "새 노트"
    public var kind: NotebookKind = .notebook
    public var template: PaperTemplate = .lined
    public var paperSize: PaperSize = .a4
    public var paperColor: PaperColor = .white
    public var isLandscape = true

    public init() {}
}

/// iCloud(또는 로컬 폴백) 문서 저장소. 폴더는 실제 디렉터리, 노트북은 `.inknote` 패키지다.
@MainActor
@Observable
public final class DocumentStore {
    public private(set) var rootURL: URL?
    public private(set) var isICloud = false
    /// 파일 시스템이 바뀔 때마다 증가. 뷰는 이 값을 관찰해 목록을 다시 읽는다.
    public private(set) var changeCounter = 0
    public private(set) var lastError: String?

    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// 메타데이터 쿼리가 알고 있는 iCloud 항목. 데몬이 아직 디렉터리에 항목을 만들지 않았을 때 목록을 보강한다.
    @ObservationIgnored private var knownUbiquitousItems: [String: UbiquitousItem] = [:]
    /// 우리가 직접 옮기거나 지운 경로와 그 시각. 쿼리 인덱스가 늦게 따라와 옛 경로를 다시 보고해도 목록에 되살리지 않는다.
    @ObservationIgnored private var removedPaths: [String: Date] = [:]
    /// 쿼리가 옛 경로를 끝내 지우지 않는 경우를 대비한 묘비 유지 시간.
    static let removedPathLifetime: TimeInterval = 120

    struct UbiquitousItem {
        var url: URL
        var isFolder: Bool
        var isDownloaded: Bool
    }

    public init() {}

    public func start() async {
        guard rootURL == nil else { return }
        // 콜드 스타트 직후에는 컨테이너 조회가 일시적으로 nil을 돌려줄 수 있어 몇 번 더 시도한다.
        var container: URL?
        for delay in [0.0, 0.5, 1.0, 2.0] {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            container = await Self.ubiquityContainer()
            if container != nil { break }
        }
        if let container {
            useICloud(container)
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            rootURL = docs
            isICloud = false
        }
        changeCounter += 1
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.recheckContainer() }
            })
    }

    private nonisolated static func ubiquityContainer() async -> URL? {
        await Task.detached(priority: .userInitiated) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }.value
    }

    private func useICloud(_ container: URL) {
        let docs = container.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        rootURL = docs
        isICloud = true
        startMetadataQuery()
    }

    /// 로컬 폴백 상태에서 iCloud가 나중에 사용 가능해지면 iCloud 저장소로 전환한다.
    public func recheckContainer() async {
        guard !isICloud, let container = await Self.ubiquityContainer() else { return }
        useICloud(container)
        changeCounter += 1
    }

    public func refresh() { changeCounter += 1 }

    // MARK: - Listing

    public func items(in folder: URL) -> [LibraryItem] {
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
            var date = values?.contentModificationDate ?? .distantPast
            if url.pathExtension == NotebookPackage.fileExtension {
                // 패키지 안의 파일만 바뀌면 디렉터리 수정일은 그대로이므로 매니페스트 수정일도 본다.
                let manifestURL = url.appendingPathComponent(NotebookPackage.manifestName)
                if let inner = (try? manifestURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                    date = max(date, inner)
                }
                items.append(LibraryItem(url: url, kind: .notebook, modifiedAt: date))
            } else {
                items.append(LibraryItem(url: url, kind: .folder, modifiedAt: date))
            }
        }
        // 메타데이터 쿼리에는 있는데 디렉터리 목록에 아직 없는 항목(동기화 직후)을 내려받는 중으로 보탠다.
        // 디스크에 없는 항목은 열 수 없으므로 쿼리가 "내려받음"이라 해도 항상 내려받는 중(탭 불가)으로 둔다.
        // 쿼리 인덱스가 늦어 지운·옮긴 옛 경로를 다시 보고하면 열 수 없는 유령 노트가 되기 때문이다.
        let folderPath = folder.standardizedFileURL.path
        let listed = Set(items.map { $0.url.standardizedFileURL.path })
        for (path, known) in knownUbiquitousItems
        where known.url.deletingLastPathComponent().standardizedFileURL.path == folderPath
            && !listed.contains(path) && !isRemoved(path) {
            let isNotebook = known.url.pathExtension == NotebookPackage.fileExtension
            guard isNotebook || known.isFolder else { continue }
            items.append(LibraryItem(url: known.url, kind: isNotebook ? .notebook : .folder,
                                     modifiedAt: .distantPast, isDownloading: true))
        }
        return items.sorted {
            if $0.kind != $1.kind { return $0.kind == .folder }
            return $0.modifiedAt > $1.modifiedAt
        }
    }

    public func allFolders() -> [URL] {
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

    /// 노트북의 검색용 텍스트(제목 + 손글씨 인식 결과 + 텍스트 상자). 매니페스트를 읽어 만든다.
    public nonisolated static func searchableText(forNotebookAt url: URL) -> String {
        let manifestURL = url.appendingPathComponent(NotebookPackage.manifestName)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? NotebookManifest.decode(data) else { return "" }
        var parts = [manifest.title]
        parts.append(contentsOf: manifest.recognizedText.values)
        for object in manifest.objects {
            if case .text(let t) = object.kind { parts.append(t) }
        }
        return parts.joined(separator: "\n")
    }

    public func displayName(for folder: URL) -> String {
        folder == rootURL ? "모든 노트" : folder.lastPathComponent
    }

    // MARK: - Creation

    public func createFolder(named name: String, in folder: URL) throws {
        let url = uniqueURL(in: folder, baseName: name, pathExtension: nil, fallbackName: "새 폴더")
        try coordinatedWrite(url) { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
        unmarkRemoved(url)
        changeCounter += 1
    }

    @discardableResult
    public func createNotebook(_ options: NewNotebookOptions, in folder: URL) async throws -> URL {
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
    public func importFile(at sourceURL: URL, in folder: URL) async throws -> URL {
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
        // "새 노트"가 이미 있으면 파일은 "새 노트 2"가 된다. 편집기 제목·검색·내보내기 이름이 라이브러리와 같도록 맞춘다.
        var manifest = manifest
        manifest.title = url.deletingPathExtension().lastPathComponent
        let document = NotebookDocument(fileURL: url, manifest: manifest, pdfDocument: pdf)
        let ok = await withCheckedContinuation { cont in document.save(to: url, for: .forCreating) { cont.resume(returning: $0) } }
        guard ok else { throw CocoaError(.fileWriteUnknown) }
        await withCheckedContinuation { cont in document.close { _ in cont.resume() } }
        unmarkRemoved(url)
        changeCounter += 1
        return url
    }

    // MARK: - Mutation

    public func rename(_ item: LibraryItem, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        // 다듬은 이름이 지금 이름과 같으면(".수학" → "수학") 자기 자신과 겹쳐 "수학 2"가 되지 않게 그대로 둔다.
        guard !trimmed.isEmpty, Self.sanitizedFileName(trimmed, fallback: item.name) != item.name else { return }
        let folder = item.url.deletingLastPathComponent()
        let ext: String? = item.kind == .notebook ? NotebookPackage.fileExtension : nil
        let target = uniqueURL(in: folder, baseName: trimmed, pathExtension: ext, fallbackName: item.name)
        try coordinatedMove(from: item.url, to: target)
        if item.kind == .notebook {
            // 이름이 겹치거나 다듬어졌으면 실제 파일 이름을 제목으로 쓴다.
            try updateManifestTitle(at: target, title: target.deletingPathExtension().lastPathComponent, newIdentity: false)
        }
        changeCounter += 1
    }

    public func delete(_ item: LibraryItem) throws {
        var coordinatorError: NSError?
        var inner: Error?
        NSFileCoordinator().coordinate(writingItemAt: item.url, options: .forDeleting, error: &coordinatorError) { url in
            do { try FileManager.default.removeItem(at: url) } catch { inner = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let inner { throw inner }
        markRemoved(item.url)
        changeCounter += 1
    }

    public func move(_ item: LibraryItem, to folder: URL) throws {
        guard item.url.deletingLastPathComponent() != folder, !folder.path.hasPrefix(item.url.path + "/") else { return }
        let ext: String? = item.kind == .notebook ? NotebookPackage.fileExtension : nil
        let target = uniqueURL(in: folder, baseName: item.name, pathExtension: ext)
        try coordinatedMove(from: item.url, to: target)
        changeCounter += 1
    }

    /// 항목을 같은 폴더에 복제한다. 원본 노트가 편집기에 열려 있어도 된다.
    /// 조정 읽기는 열린 UIDocument에 저장을 요청하고, UIDocument는 메인 스레드에서 저장하므로
    /// 메인 스레드에서 코디네이터를 돌리면 교착된다. 그래서 복사는 백그라운드에서 한다.
    public func duplicate(_ item: LibraryItem) async throws {
        let folder = item.url.deletingLastPathComponent()
        let ext: String? = item.kind == .notebook ? NotebookPackage.fileExtension : nil
        let target = uniqueURL(in: folder, baseName: item.name + " 복사본", pathExtension: ext)
        let source = item.url
        let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            var coordinatorError: NSError?
            var inner: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], writingItemAt: target, options: .forReplacing, error: &coordinatorError) { src, dst in
                do { try FileManager.default.copyItem(at: src, to: dst) } catch { inner = error }
            }
            if let coordinatorError { return .failure(coordinatorError) }
            if let inner { return .failure(inner) }
            return .success(())
        }.value
        try result.get()
        unmarkRemoved(target)
        if item.kind == .notebook {
            try? updateManifestTitle(at: target, title: target.deletingPathExtension().lastPathComponent, newIdentity: true)
        }
        changeCounter += 1
    }

    // MARK: - Helpers

    /// 매니페스트 제목을 바꾼다. 복제본은 원본과 구분되도록 `newIdentity`로 새 ID를 받는다.
    private func updateManifestTitle(at notebookURL: URL, title: String, newIdentity: Bool) throws {
        let manifestURL = notebookURL.appendingPathComponent(NotebookPackage.manifestName)
        var manifest = try NotebookManifest.decode(try Data(contentsOf: manifestURL))
        manifest.title = title
        if newIdentity { manifest.id = UUID() }
        try coordinatedWrite(manifestURL) { try manifest.encoded().write(to: $0, options: .atomic) }
    }

    /// 파일 시스템에 쓸 수 있는 이름으로 다듬는다. '.'으로 시작하면 숨김 파일이 되어 목록에서 사라지므로 앞의 점을 뗀다.
    nonisolated static func sanitizedFileName(_ name: String, fallback: String) -> String {
        var safe = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while safe.hasPrefix(".") { safe.removeFirst() }
        safe = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? fallback : safe
    }

    func uniqueURL(in folder: URL, baseName: String, pathExtension: String?, fallbackName: String = "새 노트") -> URL {
        let safe = Self.sanitizedFileName(baseName, fallback: fallbackName)
        func make(_ suffix: Int) -> URL {
            let name = suffix == 0 ? safe : "\(safe) \(suffix + 1)"
            var url = folder.appendingPathComponent(name)
            if let pathExtension { url.appendPathExtension(pathExtension) }
            return url
        }
        var i = 0
        while isNameTaken(make(i)) { i += 1 }
        return make(i)
    }

    /// 디스크에 있거나, 아직 내려받지 않은 iCloud 항목(플레이스홀더·메타데이터)이 같은 이름을 쓰고 있으면 사용 중이다.
    /// 내려받지 않은 같은 이름의 노트 자리에 새로 만들면 iCloud 충돌이 나거나 한쪽이 덮어써진다.
    private func isNameTaken(_ url: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return true }
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        if fm.fileExists(atPath: placeholder.path) { return true }
        let path = url.standardizedFileURL.path
        return knownUbiquitousItems[path] != nil && !isRemoved(path)
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
        markRemoved(from)
        unmarkRemoved(to)
    }

    // MARK: - Removed-path tombstones

    /// 우리가 직접 옮기거나 지운 경로를 기억하고 메타데이터 스냅샷에서도 바로 뺀다.
    /// 쿼리 갱신은 인덱스가 따라오기 전의 옛 경로를 다시 담아 올 수 있으므로, 스냅샷을 지우는 것만으로는 부족하다.
    /// `removedPathLifetime`이 지나면 묘비를 치운다. 인덱스가 아직 옛 경로를 모르다가 뒤늦게 보고하는 경우도 있어 쿼리 결과만으로는 치우지 않는다.
    func markRemoved(_ url: URL, at date: Date = Date()) {
        let path = url.standardizedFileURL.path
        removedPaths[path] = date
        knownUbiquitousItems = knownUbiquitousItems.filter { key, _ in !Self.isSameOrInside(key, path) }
    }

    /// 같은 경로에 새 항목을 만들었으면 묘비를 치운다(지운 뒤 같은 이름으로 다시 만든 경우).
    private func unmarkRemoved(_ url: URL) {
        let path = url.standardizedFileURL.path
        removedPaths = removedPaths.filter { key, _ in !Self.isSameOrInside(key, path) && !Self.isSameOrInside(path, key) }
    }

    private func isRemoved(_ path: String) -> Bool {
        removedPaths.keys.contains { Self.isSameOrInside(path, $0) }
    }

    private nonisolated static func isSameOrInside(_ path: String, _ ancestor: String) -> Bool {
        path == ancestor || path.hasPrefix(ancestor + "/")
    }

    /// 쿼리 결과를 반영한다. 묘비가 있는 경로는 버리고, 오래된 묘비는 치운다.
    func applyMetadataSnapshot(_ known: [String: UbiquitousItem], now: Date = Date()) {
        removedPaths = removedPaths.filter { _, removedAt in now.timeIntervalSince(removedAt) < Self.removedPathLifetime }
        knownUbiquitousItems = known.filter { path, _ in !isRemoved(path) }
        changeCounter += 1
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
        var known: [String: UbiquitousItem] = [:]
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String else { continue }
            if status == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            let contentType = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String
            known[url.standardizedFileURL.path] = UbiquitousItem(
                url: url, isFolder: contentType == "public.folder",
                isDownloaded: status != NSMetadataUbiquitousItemDownloadingStatusNotDownloaded)
        }
        query.enableUpdates()
        applyMetadataSnapshot(known)
    }
}

/// 무한 화이트보드 크기 정책.
public enum WhiteboardGeometry {
    public static let initialSize = CGSize(width: 2400, height: 2400)
    public static let growthStep: CGFloat = 1200
    public static let edgeMargin: CGFloat = 300
    public static let maxDimension: CGFloat = 16_000

    /// 필기 범위가 가장자리에 가까우면 더 큰 크기를 돌려준다.
    public static func grownSize(current: CGSize, drawingBounds: CGRect) -> CGSize? {
        guard !drawingBounds.isNull, !drawingBounds.isEmpty else { return nil }
        var size = current
        if drawingBounds.maxX > current.width - edgeMargin { size.width = min(current.width + growthStep, maxDimension) }
        if drawingBounds.maxY > current.height - edgeMargin { size.height = min(current.height + growthStep, maxDimension) }
        return size == current ? nil : size
    }
}
