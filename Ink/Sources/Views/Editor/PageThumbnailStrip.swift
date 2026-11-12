import SwiftUI

/// 하단 페이지 썸네일 목록. 탭으로 이동, 길게 눌러 삭제/이동.
struct PageThumbnailStrip: View {
    let model: EditorModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(model.manifest.pages.enumerated()), id: \.element.id) { index, page in
                        PageThumbnailCell(
                            model: model, pageID: page.id, index: index,
                            version: model.drawingVersions[page.id, default: 0],
                            structureVersion: model.structureVersion,
                            isCurrent: index == model.currentPageIndex)
                        .id(page.id)
                        .onTapGesture { model.goToPage(index) }
                        .contextMenu {
                            Button { model.addPage(after: index) } label: { Label("뒤에 페이지 추가", systemImage: "plus") }
                            if index > 0 {
                                Button { model.movePage(from: index, to: index - 1) } label: { Label("앞으로 이동", systemImage: "arrow.left") }
                            }
                            if index < model.pageCount - 1 {
                                Button { model.movePage(from: index, to: index + 2) } label: { Label("뒤로 이동", systemImage: "arrow.right") }
                            }
                            if model.pageCount > 1 {
                                Divider()
                                Button(role: .destructive) { model.deletePage(at: index) } label: { Label("페이지 삭제", systemImage: "trash") }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .frame(height: 112)
            .adaptiveGlass(cornerRadius: 18)
            .padding(.horizontal, 24)
            .onChange(of: model.currentPageIndex) { _, index in
                if let id = model.pageID(at: index) {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }
}

struct PageThumbnailCell: View {
    let model: EditorModel
    let pageID: UUID
    let index: Int
    let version: Int
    let structureVersion: Int
    let isCurrent: Bool
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Color.white
                }
            }
            .frame(height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isCurrent ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isCurrent ? 2.5 : 1)
            }
            Text("\(index + 1)").font(.caption2).foregroundStyle(isCurrent ? .primary : .secondary)
        }
        .task(id: "\(version)-\(structureVersion)") {
            guard let document = model.document else { return }
            image = Exporter.thumbnail(for: document, pageIndex: index, maxDimension: 160)
        }
    }
}
