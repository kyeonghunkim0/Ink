import SwiftUI

/// 툴바의 검색 아이콘을 누르면 펼쳐지는 검색 바. 나타날 때 바로 입력 포커스를 받는다.
struct InlineSearchBar: View {
    @Binding var text: String
    var prompt: String
    var onClose: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.search)
                .accessibilityAddTraits(.isSearchField)
                .accessibilityIdentifier("search.field")
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("검색어 지우기")
            }
            Button("취소", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .adaptiveGlass(cornerRadius: 14)
        .padding(.horizontal, 24)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear { isFocused = true }
    }
}

#Preview {
    @Previewable @State var text = ""
    InlineSearchBar(text: $text, prompt: "검색") {}
        .padding()
}
