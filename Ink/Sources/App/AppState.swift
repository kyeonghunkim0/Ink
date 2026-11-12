import Foundation
import Observation
import SwiftUI

/// 네비게이션 목적지.
enum Destination: Hashable {
    case folder(URL)
}

/// 타입 안전 라우터.
@MainActor
@Observable
final class Router {
    var path = NavigationPath()
    /// 탭으로 열린 노트들. 순서가 탭 순서다.
    private(set) var openNotebooks: [URL] = []
    /// 현재 보고 있는 탭.
    var activeNotebook: URL?
    /// 편집기 전체 화면 표시 여부.
    var isEditorPresented = false
    /// 탭별 편집 모델. 탭을 전환해도 문서를 닫지 않는다.
    @ObservationIgnored private var sessions: [URL: EditorModel] = [:]

    func navigate(to destination: Destination) {
        path.append(destination)
    }

    func openEditor(_ url: URL) {
        if !openNotebooks.contains(url) { openNotebooks.append(url) }
        activeNotebook = url
        isEditorPresented = true
    }

    /// 탭의 편집 모델. 없으면 만든다(로드는 뷰가 한다).
    func editorModel(for url: URL) -> EditorModel {
        if let existing = sessions[url] { return existing }
        let model = EditorModel(url: url)
        sessions[url] = model
        return model
    }

    /// 탭을 닫고 문서를 저장·해제한다. 마지막 탭이면 편집기를 내린다.
    func closeTab(_ url: URL) {
        guard let index = openNotebooks.firstIndex(of: url) else { return }
        openNotebooks.remove(at: index)
        if let model = sessions.removeValue(forKey: url) {
            Task { await model.close() }
        }
        if activeNotebook == url {
            activeNotebook = openNotebooks.indices.contains(index) ? openNotebooks[index] : openNotebooks.last
        }
        if openNotebooks.isEmpty { isEditorPresented = false }
    }

    /// 모든 탭을 닫는다.
    func closeAllTabs() {
        for url in openNotebooks { closeTab(url) }
    }

    func popToRoot() {
        path = NavigationPath()
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
