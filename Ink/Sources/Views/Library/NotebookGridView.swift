import SwiftUI
import UniformTypeIdentifiers
import InkCore

/// 한 폴더의 노트북/하위 폴더 그리드.
struct NotebookGridView: View {
    let folder: URL

    @Environment(DocumentStore.self) private var store
    @Environment(Router.self) private var router
    @State private var items: [LibraryItem] = []
    /// 첫 목록 읽기가 끝났는지. 끝나기 전에는 빈 상태 문구 대신 로딩 표시를 보여준다.
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var filteredItems: [LibraryItem] = []
    @State private var showNewNotebook = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var renamingItem: LibraryItem?
    @State private var renameText = ""
    /// 이동 시트 요청. 컨텍스트 메뉴(한 개)와 선택 모드(여러 개)가 같은 시트를 쓴다.
    @State private var moveRequest: MoveRequest?
    @State private var errorMessage: String?
    /// 선택 모드. 셀을 탭하면 열지 않고 선택한다.
    @State private var isSelecting = false
    @State private var selection: Set<URL> = []
    @State private var showDeleteConfirmation = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)]

    var body: some View {
        let shown = searchText.isEmpty ? items : filteredItems
        return ScrollView {
            if isSearchVisible {
                InlineSearchBar(text: $searchText, prompt: "노트 제목·손글씨 검색") {
                    searchText = ""
                    isSearchVisible = false
                }
                .padding(.top, 12)
            }
            if !hasLoaded {
                ProgressView("불러오는 중…")
                    .padding(.top, 80)
            } else if shown.isEmpty {
                ContentUnavailableView(
                    "노트가 없습니다", systemImage: "note.text",
                    description: Text("오른쪽 위 + 버튼으로 새 노트를 만들거나 PDF, Word, PowerPoint, Excel 파일을 가져오세요."))
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(shown) { item in
                        LibraryItemCell(item: item, selectionState: selectionState(for: item))
                            .onTapGesture { isSelecting ? toggleSelection(item) : open(item) }
                            .contextMenu { if !isSelecting { contextMenu(for: item) } }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(isSelecting ? "\(selection.count)개 선택됨" : store.displayName(for: folder))
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionBar }
        }
        .animation(.default, value: isSelecting)
        .task(id: "\(searchText)-\(store.changeCounter)") { await filterItems() }
        .overlay {
            if isImporting {
                ProgressView("가져오는 중…")
                    .padding(24)
                    .adaptiveGlass(cornerRadius: 16)
            }
        }
        .sheet(isPresented: $showNewNotebook) {
            NewNotebookSheet { options in
                Task { await create(options) }
            }
        }
        .sheet(item: $moveRequest) { request in
            MoveItemsSheet(items: request.items) { target in
                Task { await move(request.items, to: target) }
            }
        }
        .confirmationDialog(
            "선택한 \(selection.count)개 항목을 삭제할까요?",
            isPresented: $showDeleteConfirmation, titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) { Task { await deleteSelected() } }
        } message: {
            Text("폴더를 삭제하면 안의 노트도 함께 삭제됩니다.")
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
                if let item = renamingItem { Task { await rename(item, to: renameText) } }
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
        .task(id: store.changeCounter) {
            items = store.items(in: folder)
            hasLoaded = true
            // 밖에서 지워지거나 이동한 항목은 선택에서 뺀다.
            selection.formIntersection(items.map(\.url))
        }
        .task { await openDebugSampleIfRequested() }
    }

    /// `--open-sample` 실행 인자가 있으면 샘플 노트를 만들어 바로 연다(시뮬레이터 검증용).
    private func openDebugSampleIfRequested() async {
        #if DEBUG
        guard folder == store.rootURL else { return }
        if CommandLine.arguments.contains("--screenshot-demo") {
            await DemoContent.install(store: store, in: folder)
            return
        }
        // `--import <경로>`: 호스트 파일을 바로 가져와 연다(시뮬레이터는 Mac 파일 시스템을 읽을 수 있다).
        if let i = CommandLine.arguments.firstIndex(of: "--import"), CommandLine.arguments.indices.contains(i + 1) {
            for item in store.items(in: folder) where item.name.hasPrefix("sample") { try? store.delete(item) }
            await importFiles([URL(fileURLWithPath: CommandLine.arguments[i + 1])])
            return
        }
        guard CommandLine.arguments.contains("--open-sample") else { return }
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
        if isSelecting {
            ToolbarItemGroup(placement: .primaryAction) {
                let shown = searchText.isEmpty ? items : filteredItems
                let allSelected = !shown.isEmpty && shown.allSatisfy { selection.contains($0.url) }
                Button(allSelected ? "선택 해제" : "전체 선택") {
                    if allSelected { selection.removeAll() } else { selection = Set(shown.map(\.url)) }
                }
                .disabled(shown.isEmpty)
                Button("완료") { endSelecting() }
                    .adaptiveProminentButtonStyle()
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation { isSearchVisible.toggle() }
                    if !isSearchVisible { searchText = "" }
                } label: {
                    Label("검색", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                Button { isSelecting = true } label: { Label("선택", systemImage: "checkmark.circle") }
                    .disabled(items.isEmpty)
                Button { showImporter = true } label: { Label("가져오기", systemImage: "square.and.arrow.down") }
                Button { showNewFolder = true } label: { Label("새 폴더", systemImage: "folder.badge.plus") }
                Button { showNewNotebook = true } label: { Label("새 노트", systemImage: "plus") }
            }
        }
    }

    /// 선택 모드 하단 바: 이동·삭제.
    private var selectionBar: some View {
        // 캡슐 글래스를 HStack 전체에 씌우면 iOS 26에서 안쪽 버튼이 탭을 받지 못하므로 버튼마다 글래스 스타일을 준다.
        AdaptiveGlassContainer(spacing: 16) {
            HStack(spacing: 16) {
                Button { moveRequest = MoveRequest(items: selectedItems) } label: { Label("이동", systemImage: "folder") }
                    .adaptiveGlassButtonStyle()
                Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("삭제", systemImage: "trash") }
                    .adaptiveGlassButtonStyle()
                    .tint(.red)
            }
            .disabled(selection.isEmpty)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Selection

    private var selectedItems: [LibraryItem] { items.filter { selection.contains($0.url) } }

    private func selectionState(for item: LibraryItem) -> LibraryItemCell.SelectionState {
        guard isSelecting else { return .none }
        return selection.contains(item.url) ? .selected : .unselected
    }

    private func toggleSelection(_ item: LibraryItem) {
        if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
    }

    private func endSelecting() {
        isSelecting = false
        selection.removeAll()
    }

    private func deleteSelected() async {
        let targets = selectedItems
        endSelecting()
        var failed: [String] = []
        for item in targets {
            do { try await delete(item) } catch { failed.append(item.name) }
        }
        if !failed.isEmpty { errorMessage = "삭제하지 못했습니다: \(failed.joined(separator: ", "))" }
    }

    private func move(_ targets: [LibraryItem], to folder: URL) async {
        if isSelecting { endSelecting() }
        var failed: [String] = []
        for item in targets {
            await closeOpenTabs(in: item)
            do { try store.move(item, to: folder) } catch { failed.append(item.name) }
        }
        if !failed.isEmpty { errorMessage = "이동하지 못했습니다: \(failed.joined(separator: ", "))" }
    }

    private func rename(_ item: LibraryItem, to name: String) async {
        await closeOpenTabs(in: item)
        attempt { try store.rename(item, to: name) }
    }

    /// 항목(또는 폴더 안)의 열린 탭을 닫고 문서 해제를 기다린다.
    /// 열린 UIDocument가 남아 있으면 파일 코디네이터 이동·삭제가 메인 스레드에서 교착된다.
    private func closeOpenTabs(in item: LibraryItem) async {
        switch item.kind {
        case .notebook: await router.closeTabAndWait(item.url)
        case .folder: await router.closeTabsAndWait(under: item.url)
        }
    }

    /// 열려 있던 탭을 먼저 닫은 뒤 항목을 지운다.
    private func delete(_ item: LibraryItem) async throws {
        await closeOpenTabs(in: item)
        try store.delete(item)
    }

    @ViewBuilder
    private func contextMenu(for item: LibraryItem) -> some View {
        Button { renameText = item.name; renamingItem = item } label: { Label("이름 변경", systemImage: "pencil") }
        Button { attempt { try store.duplicate(item) } } label: { Label("복제", systemImage: "plus.square.on.square") }
        Button { moveRequest = MoveRequest(items: [item]) } label: { Label("이동", systemImage: "folder") }
        Divider()
        Button(role: .destructive) {
            Task { do { try await delete(item) } catch { errorMessage = error.localizedDescription } }
        } label: { Label("삭제", systemImage: "trash") }
    }

    /// 제목과 매니페스트의 인식 텍스트로 노트를 거른다. 폴더는 이름으로만 거른다.
    private func filterItems() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { filteredItems = items; return }
        let candidates = items
        let matched = await Task.detached(priority: .userInitiated) { () -> [URL] in
            candidates.filter { item in
                if item.name.localizedCaseInsensitiveContains(query) { return true }
                guard item.kind == .notebook else { return false }
                return DocumentStore.searchableText(forNotebookAt: item.url).localizedCaseInsensitiveContains(query)
            }.map(\.url)
        }.value
        filteredItems = items.filter { matched.contains($0.url) }
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
    enum SelectionState { case none, unselected, selected }

    let item: LibraryItem
    var selectionState: SelectionState = .none
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            // 썸네일은 노트 용지 방향(가로/세로)에 맞는 비율로 보이고, 셀 높이만 맞춘다.
            preview
                .overlay(alignment: .topTrailing) {
                    if selectionState != .none {
                        Image(systemName: selectionState == .selected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, selectionState == .selected ? Color.accentColor : Color.secondary)
                            .shadow(radius: 1)
                            .padding(8)
                    }
                }
                .overlay {
                    if selectionState == .selected {
                        RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
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
        .accessibilityAddTraits(selectionState == .selected ? .isSelected : [])
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .folder:
            placeholder(aspectRatio: 1) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
            }
        case .notebook:
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2, y: 1)
            } else {
                placeholder(aspectRatio: 4 / 3) {
                    if item.isDownloading {
                        ProgressView()
                    } else {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func placeholder<Content: View>(aspectRatio: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { content() }
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

/// 이동 시트 요청. `sheet(item:)`용 식별자.
struct MoveRequest: Identifiable {
    let id = UUID()
    let items: [LibraryItem]
}

/// 이동 대상 폴더 선택. 선택한 항목 자신(과 그 안), 현재 폴더는 고를 수 없다.
struct MoveItemsSheet: View {
    let items: [LibraryItem]
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
                .disabled(items.contains { url == $0.url || url.path.hasPrefix($0.url.path + "/") || url == $0.url.deletingLastPathComponent() })
            }
            .navigationTitle(items.count == 1 ? "“\(items[0].name)” 이동" : "\(items.count)개 항목 이동")
            .toolbar { Button("취소") { dismiss() } }
        }
    }
}

#Preview {
    NavigationStack {
        NotebookGridView(folder: FileManager.default.temporaryDirectory)
    }
    .environment(DocumentStore())
    .environment(Router(sessions: EditorSessions()))
}
