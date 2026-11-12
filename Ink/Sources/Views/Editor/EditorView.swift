import SwiftUI
import PhotosUI

/// 탭으로 열린 노트들을 전체 화면으로 보여 준다.
struct EditorTabsView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        return NavigationStack {
            VStack(spacing: 0) {
                if router.openNotebooks.count > 1 {
                    EditorTabStrip()
                }
                if let url = router.activeNotebook {
                    EditorView(model: router.editorModel(for: url))
                        .id(url)
                } else {
                    ContentUnavailableView("열린 노트가 없습니다", systemImage: "doc")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { router.isEditorPresented = false } label: { Label("닫기", systemImage: "chevron.left") }
                }
            }
        }
    }
}

/// 상단 탭 스트립. 탭 전환과 닫기.
struct EditorTabStrip: View {
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(router.openNotebooks, id: \.self) { url in
                    let isActive = url == router.activeNotebook
                    HStack(spacing: 6) {
                        Button { router.activeNotebook = url } label: {
                            Text(url.deletingPathExtension().lastPathComponent)
                                .font(.callout.weight(isActive ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        Button { router.closeTab(url) } label: {
                            Image(systemName: "xmark").font(.caption2.bold())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("탭 닫기 \(url.deletingPathExtension().lastPathComponent)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                    .accessibilityIdentifier("editor.tab")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .background(Color(.secondarySystemBackground))
    }
}

/// 노트북 편집 화면. 모델은 라우터가 보관하며, 여기서는 로드만 한다.
struct EditorView: View {
    let model: EditorModel

    var body: some View {
        Group {
            if model.isLoaded {
                EditorContent(model: model)
            } else if let error = model.loadError {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView("여는 중…")
            }
        }
        .task {
            if !model.isLoaded, model.loadError == nil { await model.load() }
        }
        .onDisappear {
            // 탭 전환/백그라운드 시 저장만 하고 문서는 열어 둔다.
            Task { await model.save() }
        }
    }
}

/// 열린 문서의 편집 UI.
struct EditorContent: View {
    @Bindable var model: EditorModel
    @State private var showThumbnails = true
    @State private var shareItem: ShareItem?
    @State private var isExporting = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showStickerSheet = false

    var body: some View {
        // 도구 피커가 하단에 떠 있으므로 보조 UI는 캔버스 위쪽에 둔다.
        VStack(spacing: 10) {
            if showThumbnails && !model.isWhiteboard {
                PageThumbnailStrip(model: model)
                    .padding(.top, 8)
            }
            if !model.searchText.isEmpty {
                SearchResultsBar(model: model)
            }
            if model.recorder.isRecording || model.recorder.playingRecordingID != nil {
                RecordingBar(model: model)
                    .padding(.top, showThumbnails && !model.isWhiteboard ? 0 : 8)
            }
            PDFCanvasView(model: model)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Color(.secondarySystemBackground))
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "손글씨·텍스트 검색")
        .background {
            // 키보드 줌 단축키(⌘+ / ⌘-). 보이지 않는 버튼으로 등록한다.
            Group {
                Button("확대") { model.zoom(by: 1) }.keyboardShortcut("=", modifiers: .command)
                Button("축소") { model.zoom(by: -1) }.keyboardShortcut("-", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url], airDropOnly: item.airDropOnly)
        }
        .sheet(isPresented: $showStickerSheet) {
            StickerSheet { emoji in model.addSticker(emoji) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { model.addImage(data) }
                photoItem = nil
            }
        }
        .alert("오류", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("확인") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay {
            if isExporting {
                ProgressView("내보내는 중…")
                    .padding(24)
                    .adaptiveGlass(cornerRadius: 16)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if !model.isWhiteboard {
                Text("\(model.currentPageIndex + 1) / \(model.pageCount)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(PaperTemplate.allCases) { template in
                        Button { model.addPage(template) } label: {
                            Label(template.displayName, systemImage: template.symbolName)
                        }
                    }
                } label: {
                    Label("페이지 추가", systemImage: "plus.rectangle.portrait")
                } primaryAction: {
                    model.addPage()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button { showThumbnails.toggle() } label: {
                    Label("페이지 목록", systemImage: showThumbnails ? "rectangle.bottomthird.inset.filled" : "rectangle")
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            Menu {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("사진", systemImage: "photo")
                }
                Button { model.addTextBox() } label: { Label("텍스트 상자", systemImage: "textbox") }
                Button { showStickerSheet = true } label: { Label("스티커", systemImage: "face.smiling") }
            } label: {
                Label("삽입", systemImage: "plus.square.on.square")
            }

            Toggle(isOn: $model.isObjectModeEnabled) {
                Label("객체 선택", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
            }

            Toggle(isOn: $model.isFingerDrawingEnabled) {
                Label("손가락 필기", systemImage: "hand.draw")
            }

            Button {
                Task { await model.toggleRecording() }
            } label: {
                Label("녹음", systemImage: model.recorder.isRecording ? "stop.circle.fill" : "mic")
            }
            .tint(model.recorder.isRecording ? .red : nil)
            .keyboardShortcut("r", modifiers: .command)

            Menu {
                Section("녹음") {
                    if model.manifest.recordings.isEmpty {
                        Text("녹음 없음")
                    }
                    ForEach(model.manifest.recordings) { rec in
                        Button { model.play(rec) } label: {
                            Label("\(rec.title) · \(formatDuration(rec.duration))", systemImage: "play.circle")
                        }
                    }
                }
            } label: {
                Label("녹음 목록", systemImage: "waveform")
            }

            Menu {
                Button { export(.pdfAll) } label: { Label("PDF로 내보내기 (전체)", systemImage: "doc.richtext") }
                Button { export(.pdfCurrentPage) } label: { Label("PDF로 내보내기 (현재 페이지)", systemImage: "doc") }
                Button { export(.pngCurrentPage) } label: { Label("이미지로 내보내기 (현재 페이지)", systemImage: "photo") }
                Divider()
                Button { export(.package) } label: { Label("노트 파일 공유 (.inknote)", systemImage: "shippingbox") }
                Section("AirDrop") {
                    Button { export(.pdfAll, airDrop: true) } label: { Label("PDF를 AirDrop으로 보내기", systemImage: "airplane.circle") }
                    Button { export(.package, airDrop: true) } label: { Label("노트 파일을 AirDrop으로 보내기", systemImage: "airplane.circle") }
                }
            } label: {
                Label("공유", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func export(_ kind: EditorModel.ExportKind, airDrop: Bool = false) {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                shareItem = ShareItem(url: try await model.export(kind), airDropOnly: airDrop)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }
}

/// 검색 결과(페이지 목록) 바.
struct SearchResultsBar: View {
    let model: EditorModel

    var body: some View {
        let hits = model.searchHits
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                if hits.isEmpty {
                    Text("“\(model.searchText)” 결과 없음").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(hits) { hit in
                        Button { model.goToPage(hit.pageIndex) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(hit.pageIndex + 1)쪽").font(.caption.bold())
                                Text(hit.snippet).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: 260, alignment: .leading)
                        }
                        .adaptiveGlassButtonStyle()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .adaptiveGlass(cornerRadius: 14)
        .padding(.horizontal, 24)
        .id(model.recognitionVersion)
    }
}

/// 이모지 스티커 선택 시트.
struct StickerSheet: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    private let stickers = ["⭐️", "❤️", "✅", "❌", "⚠️", "💡", "📌", "🔥", "👍", "👀", "🎯", "📝",
                            "😀", "😂", "🥳", "😍", "🤔", "😎", "🙏", "💪", "🌟", "🎉", "📚", "⏰",
                            "➡️", "⬅️", "⬆️", "⬇️", "🔴", "🟢", "🔵", "🟡"]
    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(stickers, id: \.self) { emoji in
                        Button {
                            onPick(emoji)
                            dismiss()
                        } label: {
                            Text(emoji).font(.system(size: 40)).frame(width: 64, height: 64)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("스티커")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
    var airDropOnly = false
}

func formatDuration(_ interval: TimeInterval) -> String {
    let total = Int(interval.rounded())
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

#Preview {
    NavigationStack {
        EditorView(model: EditorModel(url: FileManager.default.temporaryDirectory.appendingPathComponent("Preview.inknote")))
    }
}
