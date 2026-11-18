import Testing
import Foundation
@testable import InkCore

@MainActor
struct DocumentStoreTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func manifestTitle(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url.appendingPathComponent(NotebookPackage.manifestName))
        return try NotebookManifest.decode(data).title
    }

    private func known(_ url: URL, downloaded: Bool = true) -> (String, DocumentStore.UbiquitousItem) {
        (url.standardizedFileURL.path, .init(url: url, isFolder: false, isDownloaded: downloaded))
    }

    /// 같은 제목으로 만들면 파일은 "새 노트 2"가 되고, 매니페스트 제목도 그에 맞아야 한다.
    @Test func newNotebookTitleMatchesUniqueFileName() async throws {
        let store = DocumentStore()
        let first = try await store.createNotebook(NewNotebookOptions(), in: folder)
        let second = try await store.createNotebook(NewNotebookOptions(), in: folder)
        #expect(first.lastPathComponent == "새 노트.inknote")
        #expect(second.lastPathComponent == "새 노트 2.inknote")
        #expect(try manifestTitle(second) == "새 노트 2")
    }

    /// '.'으로 시작하는 제목은 숨김 파일이 되어 목록에서 사라지므로 점을 뗀다.
    @Test func leadingDotTitleStaysVisible() async throws {
        let store = DocumentStore()
        var options = NewNotebookOptions()
        options.title = "..메모"
        let url = try await store.createNotebook(options, in: folder)
        #expect(url.lastPathComponent == "메모.inknote")
        #expect(store.items(in: folder).map(\.name) == ["메모"])
    }

    /// 아직 내려받지 않은 iCloud 노트와 같은 이름은 쓰지 않는다.
    @Test func uniqueNameSkipsUbiquitousItems() throws {
        let store = DocumentStore()
        FileManager.default.createFile(atPath: folder.appendingPathComponent(".새 노트.inknote.icloud").path, contents: Data())
        let pending = folder.appendingPathComponent("새 노트 2.inknote")
        store.applyMetadataSnapshot(Dictionary(uniqueKeysWithValues: [known(pending, downloaded: false)]))
        let url = store.uniqueURL(in: folder, baseName: "새 노트", pathExtension: NotebookPackage.fileExtension)
        #expect(url.lastPathComponent == "새 노트 3.inknote")
    }

    /// 디스크에 없는 메타데이터 항목은 "내려받음"이어도 탭할 수 없는 내려받는 중 항목으로만 보인다.
    @Test func metadataOnlyItemIsNeverOpenable() {
        let store = DocumentStore()
        let ghost = folder.appendingPathComponent("유령.inknote")
        store.applyMetadataSnapshot(Dictionary(uniqueKeysWithValues: [known(ghost, downloaded: true)]))
        let items = store.items(in: folder)
        #expect(items.count == 1)
        #expect(items.first?.isDownloading == true)
    }

    /// 지운 노트를 늦은 쿼리 갱신이 다시 보고해도 목록에 되살리지 않는다.
    @Test func deletedNotebookDoesNotComeBackFromStaleQuery() async throws {
        let store = DocumentStore()
        let url = try await store.createNotebook(NewNotebookOptions(), in: folder)
        let stale = Dictionary(uniqueKeysWithValues: [known(url)])
        store.applyMetadataSnapshot(stale)

        try store.delete(LibraryItem(url: url, kind: .notebook, modifiedAt: Date()))
        store.applyMetadataSnapshot(stale)
        #expect(store.items(in: folder).isEmpty)

        // 묘비가 만료되면 쿼리를 다시 믿는다(그래도 탭할 수 없는 항목으로만).
        store.applyMetadataSnapshot(stale, now: Date().addingTimeInterval(DocumentStore.removedPathLifetime + 1))
        #expect(store.items(in: folder).map(\.isDownloading) == [true])
    }

    /// 이름을 바꾼 뒤 늦은 쿼리 갱신이 옛 이름을 보고해도 노트가 두 개로 보이지 않는다.
    @Test func renamedNotebookLeavesNoGhost() async throws {
        let store = DocumentStore()
        let url = try await store.createNotebook(NewNotebookOptions(), in: folder)
        let stale = Dictionary(uniqueKeysWithValues: [known(url)])
        store.applyMetadataSnapshot(stale)

        try store.rename(LibraryItem(url: url, kind: .notebook, modifiedAt: Date()), to: "수학")
        store.applyMetadataSnapshot(stale)

        let items = store.items(in: folder)
        #expect(items.map(\.name) == ["수학"])
        #expect(try manifestTitle(folder.appendingPathComponent("수학.inknote")) == "수학")
    }

    /// 지운 뒤 같은 이름으로 다시 만들면 새 노트는 정상으로 보인다.
    @Test func recreatingDeletedNameClearsTombstone() async throws {
        let store = DocumentStore()
        let url = try await store.createNotebook(NewNotebookOptions(), in: folder)
        try store.delete(LibraryItem(url: url, kind: .notebook, modifiedAt: Date()))
        let again = try await store.createNotebook(NewNotebookOptions(), in: folder)
        #expect(again == url)
        store.applyMetadataSnapshot(Dictionary(uniqueKeysWithValues: [known(again)]))
        #expect(store.items(in: folder).map(\.isDownloading) == [false])
    }

    /// 복제는 비동기로 복사하고 복제본 제목·ID를 새로 정한다.
    @Test func duplicateGetsOwnTitle() async throws {
        let store = DocumentStore()
        let url = try await store.createNotebook(NewNotebookOptions(), in: folder)
        try await store.duplicate(LibraryItem(url: url, kind: .notebook, modifiedAt: Date()))
        let copy = folder.appendingPathComponent("새 노트 복사본.inknote")
        #expect(try manifestTitle(copy) == "새 노트 복사본")
    }

    /// 이름을 다듬은 결과가 지금 이름과 같으면 바꾸지 않는다.
    @Test func renameToSanitizedSameNameIsNoOp() async throws {
        let store = DocumentStore()
        var options = NewNotebookOptions()
        options.title = "수학"
        let url = try await store.createNotebook(options, in: folder)
        try store.rename(LibraryItem(url: url, kind: .notebook, modifiedAt: Date()), to: ".수학")
        #expect(store.items(in: folder).map(\.name) == ["수학"])
    }
}
