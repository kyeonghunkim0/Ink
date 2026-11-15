import SwiftUI

/// 라이브러리 루트. 사이드바(폴더) + 노트북 그리드.
struct LibraryView: View {
    @Environment(DocumentStore.self) private var store
    @Environment(Router.self) private var router
    @State private var selectedFolder: URL?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        return NavigationSplitView {
            FolderSidebar(selection: $selectedFolder)
        } detail: {
            NavigationStack(path: $router.path) {
                Group {
                    if let root = selectedFolder ?? store.rootURL {
                        NotebookGridView(folder: root)
                    } else {
                        ProgressView("저장소 준비 중…")
                    }
                }
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .folder(let url): NotebookGridView(folder: url)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $router.isEditorPresented) {
            EditorTabsView()
                .environment(router)
        }
        .onChange(of: selectedFolder) { _, _ in router.popToRoot() }
        // 로컬 폴백에서 iCloud로 전환되면 루트가 바뀌므로 선택 폴더를 새 루트로 되돌린다.
        .onChange(of: store.rootURL) { _, _ in selectedFolder = nil }
        // 백그라운드에 있는 동안 iCloud가 바꾼 파일을 다시 읽는다.
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.refresh() } }
        .onChange(of: router.isEditorPresented) { _, presented in
            // 편집기를 내리면 열린 문서를 먼저 저장한 뒤 썸네일·수정일을 다시 읽는다.
            guard !presented else { return }
            Task {
                await router.saveAllOpen()
                store.refresh()
            }
        }
    }
}

/// 루트 폴더 목록 사이드바.
struct FolderSidebar: View {
    @Environment(DocumentStore.self) private var store
    @Binding var selection: URL?
    @State private var folders: [LibraryItem] = []

    var body: some View {
        List(selection: $selection) {
            if let root = store.rootURL {
                Label("모든 노트", systemImage: "square.grid.2x2").tag(root)
            }
            Section("폴더") {
                ForEach(folders) { folder in
                    Label(folder.name, systemImage: "folder").tag(folder.url)
                }
            }
        }
        .navigationTitle("Ink")
        .overlay(alignment: .bottom) {
            if !store.isICloud {
                Text("iCloud 미연결 · 로컬에 저장됨")
                    .font(.footnote).foregroundStyle(.secondary).padding(8)
            }
        }
        .task(id: store.changeCounter) { reload() }
    }

    private func reload() {
        guard let root = store.rootURL else { return }
        folders = store.items(in: root).filter { $0.kind == .folder }
        if selection == nil { selection = root }
    }
}

#Preview {
    LibraryView().environment(DocumentStore()).environment(Router())
}
