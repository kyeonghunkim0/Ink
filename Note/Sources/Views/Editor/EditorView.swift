import SwiftUI

/// 노트북 편집 화면. 문서를 열고 닫는 책임을 가진다.
struct EditorView: View {
    let url: URL
    @State private var model: EditorModel?

    var body: some View {
        Group {
            if let model {
                if model.isLoaded {
                    EditorContent(model: model)
                } else if let error = model.loadError {
                    ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView("여는 중…")
                }
            } else {
                ProgressView("여는 중…")
            }
        }
        .task {
            let m = EditorModel(url: url)
            model = m
            await m.load()
        }
        .onDisappear {
            let m = model
            Task { await m?.close() }
        }
    }
}

/// 열린 문서의 편집 UI.
struct EditorContent: View {
    @Bindable var model: EditorModel
    @State private var showThumbnails = true
    @State private var shareItem: ShareItem?
    @State private var isExporting = false

    var body: some View {
        // 도구 피커가 하단에 떠 있으므로 보조 UI는 캔버스 위쪽에 둔다.
        VStack(spacing: 10) {
            if showThumbnails && !model.isWhiteboard {
                PageThumbnailStrip(model: model)
                    .padding(.top, 8)
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
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
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

                Button { showThumbnails.toggle() } label: {
                    Label("페이지 목록", systemImage: showThumbnails ? "rectangle.bottomthird.inset.filled" : "rectangle")
                }
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
                Button { export(.package) } label: { Label("노트 파일 공유 (.gnote)", systemImage: "shippingbox") }
            } label: {
                Label("공유", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func export(_ kind: EditorModel.ExportKind) {
        isExporting = true
        Task {
            defer { isExporting = false }
            do { shareItem = ShareItem(url: try await model.export(kind)) } catch { model.errorMessage = error.localizedDescription }
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

func formatDuration(_ interval: TimeInterval) -> String {
    let total = Int(interval.rounded())
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

#Preview {
    NavigationStack {
        EditorView(url: FileManager.default.temporaryDirectory.appendingPathComponent("Preview.gnote"))
    }
}
