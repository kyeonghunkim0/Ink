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
    /// 닫는 중인 문서. 파일 작업 전에 해제 완료를 기다릴 수 있게 한다.
    @ObservationIgnored private var closingTasks: [URL: Task<Void, Never>] = [:]

    func navigate(to destination: Destination) {
        path.append(destination)
    }

    func openEditor(_ url: URL) {
        // 디렉터리 목록에서 온 URL은 끝에 '/'가 붙어 생성 시 URL과 달라진다. 같은 노트가 탭 두 개로 열리지 않도록 정규화한다.
        let url = url.normalizedFileURL
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
        let url = url.normalizedFileURL
        guard let index = openNotebooks.firstIndex(of: url) else { return }
        openNotebooks.remove(at: index)
        if let model = sessions.removeValue(forKey: url) {
            closingTasks[url] = Task {
                await model.close()
                closingTasks[url] = nil
            }
        }
        if activeNotebook == url {
            activeNotebook = openNotebooks.indices.contains(index) ? openNotebooks[index] : openNotebooks.last
        }
        if openNotebooks.isEmpty { isEditorPresented = false }
    }

    /// 탭을 닫고 문서 해제가 끝날 때까지 기다린다.
    /// 파일을 옮기거나 이름을 바꾸거나 지우기 전에 반드시 호출한다. 열린 UIDocument가 파일 프리젠터로 남아 있으면
    /// 메인 스레드의 NSFileCoordinator가 그 문서의 응답을 기다리며 교착된다.
    func closeTabAndWait(_ url: URL) async {
        let url = url.normalizedFileURL
        closeTab(url)
        await closingTasks[url]?.value
    }

    /// `folder` 안에 열린 모든 탭을 닫고 해제를 기다린다. 폴더를 옮기거나 이름을 바꾸거나 지우기 전에 쓴다.
    func closeTabsAndWait(under folder: URL) async {
        let prefix = folder.normalizedFileURL.path + "/"
        for url in openNotebooks where url.path.hasPrefix(prefix) {
            await closeTabAndWait(url)
        }
    }

    /// 열려 있는 모든 탭의 문서를 저장한다.
    func saveAllOpen() async {
        for model in sessions.values { await model.save() }
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

extension URL {
    /// 끝의 '/'와 `.`/`..`를 제거한 파일 URL. 같은 경로를 가리키는 URL끼리 `==`가 성립하도록 맞춘다.
    var normalizedFileURL: URL {
        URL(fileURLWithPath: standardizedFileURL.path, isDirectory: false)
    }
}
