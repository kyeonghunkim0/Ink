import SwiftUI
import UniformTypeIdentifiers

/// 한 폴더의 노트북/하위 폴더 그리드.
struct NotebookGridView: View {
    let folder: URL

    @Environment(DocumentStore.self) private var store
    @Environment(Router.self) private var router
    @State private var items: [LibraryItem] = []
    @State private var showNewNotebook = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var renamingItem: LibraryItem?
    @State private var renameText = ""
    @State private var movingItem: LibraryItem?
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)]

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView(
                    "노트가 없습니다", systemImage: "note.text",
                    description: Text("오른쪽 위 + 버튼으로 새 노트를 만들거나 PDF, Word, PowerPoint, Excel 파일을 가져오세요."))
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(items) { item in
                        LibraryItemCell(item: item)
                            .onTapGesture { open(item) }
                            .contextMenu { contextMenu(for: item) }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(store.displayName(for: folder))
        .toolbar { toolbarContent }
        .overlay {
            if isImporting {
                ProgressView("가져오는 중…")
                    .padding(24)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
        .sheet(isPresented: $showNewNotebook) {
            NewNotebookSheet { options in
                Task { await create(options) }
            }
        }
        .sheet(item: $movingItem) { item in
            MoveItemSheet(item: item) { target in
                attempt { try store.move(item, to: target) }
            }
        }
        .alert("새 폴더", isPresented: $showNewFolder) {
            TextField("폴더 이름", text: $newFolderName)
            Button("만들기") {
                attempt { try store.createFolder(named: newFolderName, in: folder) }
                newFolderName = ""
            }
            Button("취소", role: .cancel) { newFolderName = "" }
        }
        .alert("이름 변경", isPresented: Binding(get: { renamingItem != nil }, set: { if !$0 { renamingItem = nil } })) {
            TextField("이름", text: $renameText)
            Button("변경") {
                if let item = renamingItem { attempt { try store.rename(item, to: renameText) } }
                renamingItem = nil
            }
            Button("취소", role: .cancel) { renamingItem = nil }
        }
        .alert("오류", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("확인") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: OfficeConverter.supportedTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await importFiles(urls) }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .task(id: store.changeCounter) { items = store.items(in: folder) }
        .task { await openDebugSampleIfRequested() }
    }

    /// `--open-sample` 실행 인자가 있으면 샘플 노트를 만들어 바로 연다(시뮬레이터 검증용).
    private func openDebugSampleIfRequested() async {
        #if DEBUG
        guard CommandLine.arguments.contains("--open-sample"), folder == store.rootURL else { return }
        for item in store.items(in: folder) where item.name.hasPrefix("샘플") {
            try? store.delete(item)
        }
        var options = NewNotebookOptions()
        options.title = "샘플"
        options.template = CommandLine.arguments.contains("--grid") ? .grid : .lined
        if CommandLine.arguments.contains("--whiteboard") { options.kind = .whiteboard }
        await create(options)
        #endif
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showImporter = true } label: { Label("가져오기", systemImage: "square.and.arrow.down") }
            Button { showNewFolder = true } label: { Label("새 폴더", systemImage: "folder.badge.plus") }
            Button { showNewNotebook = true } label: { Label("새 노트", systemImage: "plus") }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: LibraryItem) -> some View {
        Button { renameText = item.name; renamingItem = item } label: { Label("이름 변경", systemImage: "pencil") }
        Button { attempt { try store.duplicate(item) } } label: { Label("복제", systemImage: "plus.square.on.square") }
        Button { movingItem = item } label: { Label("이동", systemImage: "folder") }
        Divider()
        Button(role: .destructive) { attempt { try store.delete(item) } } label: { Label("삭제", systemImage: "trash") }
    }

    private func open(_ item: LibraryItem) {
        guard !item.isDownloading else { return }
        switch item.kind {
        case .folder: router.navigate(to: .folder(item.url))
        case .notebook: router.openEditor(item.url)
        }
    }

    private func create(_ options: NewNotebookOptions) async {
        do {
            let url = try await store.createNotebook(options, in: folder)
            router.openEditor(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importFiles(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        var lastURL: URL?
        for url in urls {
            do { lastURL = try await store.importFile(at: url, in: folder) } catch { errorMessage = error.localizedDescription }
        }
        if urls.count == 1, let lastURL { router.openEditor(lastURL) }
    }

    private func attempt(_ body: () throws -> Void) {
        do { try body() } catch { errorMessage = error.localizedDescription }
    }
}

/// 그리드 셀. 노트북은 썸네일, 폴더는 아이콘.
struct LibraryItemCell: View {
    let item: LibraryItem
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .aspectRatio(0.75, contentMode: .fit)
                switch item.kind {
                case .folder:
                    Image(systemName: "folder.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.tint)
                case .notebook:
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(radius: 2, y: 1)
                    } else if item.isDownloading {
                        ProgressView()
                    } else {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text(item.name)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if item.kind == .notebook {
                Text(item.modifiedAt, style: .date)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task(id: item.modifiedAt) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard item.kind == .notebook else { return }
        let url = item.url.appendingPathComponent(NotebookPackage.thumbnailName)
        thumbnail = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
    }
}

/// 이동 대상 폴더 선택.
struct MoveItemSheet: View {
    let item: LibraryItem
    let onSelect: (URL) -> Void
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.allFolders(), id: \.self) { url in
                Button {
                    onSelect(url)
                    dismiss()
                } label: {
                    Label(store.displayName(for: url), systemImage: url == store.rootURL ? "house" : "folder")
                }
                .disabled(url == item.url || url == item.url.deletingLastPathComponent())
            }
            .navigationTitle("“\(item.name)” 이동")
            .toolbar { Button("취소") { dismiss() } }
        }
    }
}

#Preview {
    NavigationStack {
        NotebookGridView(folder: FileManager.default.temporaryDirectory)
    }
    .environment(DocumentStore())
    .environment(Router())
}
