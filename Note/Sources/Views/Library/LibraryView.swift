import SwiftUI

/// 라이브러리 루트. 사이드바(폴더) + 노트북 그리드.
struct LibraryView: View {
    @Environment(DocumentStore.self) private var store
    @State private var router = Router()
    @State private var selectedFolder: URL?

    var body: some View {
        NavigationSplitView {
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
                    case .editor(let url): EditorView(url: url)
                    }
                }
            }
            .environment(router)
        }
        .onChange(of: selectedFolder) { _, _ in router.popToRoot() }
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
        .navigationTitle("Note")
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
    LibraryView().environment(DocumentStore())
}
