import Foundation
import InkCore
import Observation
import SwiftUI

/// 네비게이션 목적지.
enum Destination: Hashable {
    case folder(URL)
}

/// 창(씬) 하나의 라우터. 라이브러리 경로, 열린 탭, 편집기 표시 여부를 갖는다.
/// 창마다 따로 만들고, 문서 세션은 앱 전역 `EditorSessions`와 공유한다.
@MainActor
@Observable
final class Router {
    var path = NavigationPath()
    /// 이 창에 탭으로 열린 노트들. 순서가 탭 순서다.
    private(set) var openNotebooks: [URL] = []
    /// 현재 보고 있는 탭.
    var activeNotebook: URL?
    /// 편집기 전체 화면 표시 여부.
    var isEditorPresented = false

    let sessions: EditorSessions

    init(sessions: EditorSessions) {
        self.sessions = sessions
    }

    deinit {
        // 창이 닫혀 라우터가 사라지면 어느 창에도 열려 있지 않은 문서를 저장·해제한다.
        // (`isolated deinit`은 iOS 18.4부터라 메인 액터로 넘겨 처리한다.)
        let sessions = sessions
        Task { @MainActor in sessions.closeOrphans() }
    }

    func navigate(to destination: Destination) {
        path.append(destination)
    }

    /// 노트를 이 창의 탭으로 연다. 다른 창에 열려 있으면 그 창에서 이 창으로 옮긴다.
    /// 같은 파일을 UIDocument 두 개로 동시에 열지 않기 위해서다.
    func openEditor(_ url: URL) {
        // 디렉터리 목록에서 온 URL은 끝에 '/'가 붙어 생성 시 URL과 달라진다. 같은 노트가 탭 두 개로 열리지 않도록 정규화한다.
        let url = url.normalizedFileURL
        sessions.claim(url, for: self)
        // 전에 열다가 실패한 노트는 새로 시도한다.
        sessions.discardFailedModel(for: url)
        if !openNotebooks.contains(url) { openNotebooks.append(url) }
        activeNotebook = url
        isEditorPresented = true
    }

    /// 탭의 편집 모델. 없으면 만든다(로드는 뷰가 한다).
    func editorModel(for url: URL) -> EditorModel {
        sessions.model(for: url)
    }

    /// 탭을 닫고 문서를 저장·해제한다. 마지막 탭이면 편집기를 내린다.
    func closeTab(_ url: URL) {
        let url = url.normalizedFileURL
        guard removeTab(url) else { return }
        sessions.close(url)
    }

    /// 탭만 빼고 문서는 열어 둔다. 다른 창이 이 노트를 가져갈 때 `EditorSessions`가 부른다.
    func detachTab(_ url: URL) {
        removeTab(url)
    }

    /// 탭을 닫고 문서 해제가 끝날 때까지 기다린다. 다른 창에 열려 있어도 닫는다.
    /// 파일을 옮기거나 이름을 바꾸거나 지우기 전에 반드시 호출한다. 열린 UIDocument가 파일 프리젠터로 남아 있으면
    /// 메인 스레드의 NSFileCoordinator가 그 문서의 응답을 기다리며 교착된다.
    func closeTabAndWait(_ url: URL) async {
        await sessions.closeEverywhere(url)
    }

    /// `folder` 안에 열린 모든 탭을 모든 창에서 닫고 해제를 기다린다. 폴더를 옮기거나 이름을 바꾸거나 지우기 전에 쓴다.
    func closeTabsAndWait(under folder: URL) async {
        await sessions.closeEverywhere(under: folder)
    }

    /// 이 창에 열린 탭의 문서를 저장한다.
    func saveAllOpen() async {
        for url in openNotebooks { await sessions.existingModel(for: url)?.save() }
    }

    /// 이 창의 모든 탭을 닫는다.
    func closeAllTabs() {
        for url in openNotebooks { closeTab(url) }
    }

    func popToRoot() {
        path = NavigationPath()
    }

    /// 탭 목록에서 빼고 활성 탭·편집기 표시를 맞춘다. 탭이 없었으면 false.
    @discardableResult
    private func removeTab(_ url: URL) -> Bool {
        guard let index = openNotebooks.firstIndex(of: url) else { return false }
        openNotebooks.remove(at: index)
        if activeNotebook == url {
            activeNotebook = openNotebooks.indices.contains(index) ? openNotebooks[index] : openNotebooks.last
        }
        if openNotebooks.isEmpty { isEditorPresented = false }
        return true
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
