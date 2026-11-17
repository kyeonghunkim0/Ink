import Foundation
import InkCore

/// 앱 전역 편집 세션 저장소. 열린 문서(`EditorModel`)를 URL당 하나만 두고 창(`Router`)들 사이에서 조정한다.
///
/// - 한 노트는 한 창에만 열린다. 다른 창에서 열면 문서를 닫지 않고 탭만 옮긴다.
/// - 파일 작업 전 닫기는 모든 창에 적용된다(`closeEverywhere`).
@MainActor
final class EditorSessions {
    private var models: [URL: EditorModel] = [:]
    /// 닫는 중인 문서. 파일 작업 전에 해제 완료를 기다릴 수 있게 한다.
    private var closingTasks: [URL: Task<Void, Never>] = [:]
    /// 탭을 연 적 있는 창들. 창이 사라지면 자동으로 빠진다.
    private var routers: [WeakRouter] = []

    private struct WeakRouter {
        weak var router: Router?
    }

    private var liveRouters: [Router] { routers.compactMap(\.router) }

    /// 열려 있는 문서의 URL. 테스트·진단용.
    var openURLs: Set<URL> { Set(models.keys) }

    /// `router`가 `url`을 탭으로 열려 한다. 다른 창이 갖고 있으면 그 창에서 탭을 뗀다.
    func claim(_ url: URL, for router: Router) {
        routers.removeAll { $0.router == nil }
        if !routers.contains(where: { $0.router === router }) { routers.append(WeakRouter(router: router)) }
        for other in liveRouters where other !== router && other.openNotebooks.contains(url) {
            other.detachTab(url)
        }
    }

    /// 문서의 편집 모델. 없으면 만든다(로드는 뷰가 한다).
    func model(for url: URL) -> EditorModel {
        if let existing = models[url] { return existing }
        let model = EditorModel(url: url)
        models[url] = model
        return model
    }

    func existingModel(for url: URL) -> EditorModel? { models[url] }

    /// 문서를 저장·해제한다. 해제는 비동기로 진행되며 `closingTasks`로 기다릴 수 있다.
    func close(_ url: URL) {
        guard let model = models.removeValue(forKey: url) else { return }
        let previous = closingTasks[url]
        let task = Task {
            await previous?.value
            await model.close()
        }
        closingTasks[url] = task
        Task {
            await task.value
            // 그사이 같은 URL을 다시 열고 닫았으면 새 작업을 지우지 않는다.
            if closingTasks[url] == task { closingTasks[url] = nil }
        }
    }

    /// 모든 창에서 `url` 탭을 닫고 문서 해제가 끝날 때까지 기다린다.
    func closeEverywhere(_ url: URL) async {
        let url = url.normalizedFileURL
        for router in liveRouters where router.openNotebooks.contains(url) {
            router.closeTab(url)
        }
        // 탭이 없는 고아 문서도 닫는다.
        close(url)
        await closingTasks[url]?.value
    }

    /// `folder` 안의 모든 문서를 모든 창에서 닫고 해제를 기다린다.
    func closeEverywhere(under folder: URL) async {
        let prefix = folder.normalizedFileURL.path + "/"
        let urls = Set(models.keys).union(liveRouters.flatMap(\.openNotebooks))
        for url in urls where url.path.hasPrefix(prefix) {
            await closeEverywhere(url)
        }
    }

    /// 어느 창의 탭에도 없는 문서를 닫는다. 창이 닫혀 라우터가 사라졌을 때 부른다.
    func closeOrphans() {
        let open = Set(liveRouters.flatMap(\.openNotebooks))
        for url in models.keys where !open.contains(url) {
            close(url)
        }
    }
}
