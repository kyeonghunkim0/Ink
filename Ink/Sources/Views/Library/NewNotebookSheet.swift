import SwiftUI
import InkCore

/// 새 노트북 옵션 선택.
struct NewNotebookSheet: View {
    let onCreate: (NewNotebookOptions) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var options = NewNotebookOptions()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("제목", text: $options.title)
                    Picker("종류", selection: $options.kind) {
                        Text("노트북").tag(NotebookKind.notebook)
                        Text("화이트보드").tag(NotebookKind.whiteboard)
                    }
                    .pickerStyle(.segmented)
                }
                Section("템플릿") {
                    TemplatePicker(selection: $options.template, color: options.paperColor)
                }
                Section("용지") {
                    Picker("색", selection: $options.paperColor) {
                        ForEach(PaperColor.allCases) { Text($0.displayName).tag($0) }
                    }
                    if options.kind == .notebook {
                        Picker("크기", selection: $options.paperSize) {
                            ForEach(PaperSize.allCases) { Text($0.displayName).tag($0) }
                        }
                        Toggle("가로 방향", isOn: $options.isLandscape)
                    }
                }
            }
            .navigationTitle("새 노트")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("만들기") {
                        if options.title.trimmingCharacters(in: .whitespaces).isEmpty { options.title = "새 노트" }
                        onCreate(options)
                        dismiss()
                    }
                    .adaptiveProminentButtonStyle()
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// 템플릿 미리보기 가로 목록.
struct TemplatePicker: View {
    @Binding var selection: PaperTemplate
    let color: PaperColor

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(PaperTemplate.allCases) { template in
                    VStack(spacing: 6) {
                        Image(uiImage: TemplateRenderer.previewImage(template: template, color: color))
                            .resizable()
                            .frame(width: 72, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selection == template ? Color.accentColor : Color.secondary.opacity(0.3),
                                            lineWidth: selection == template ? 3 : 1)
                            }
                        Text(template.displayName).font(.caption)
                    }
                    .onTapGesture { selection = template }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    NewNotebookSheet { _ in }
}
