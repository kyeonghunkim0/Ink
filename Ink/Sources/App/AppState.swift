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
    /// 전체 화면으로 열린 편집기의 노트 URL.
    var presentedNotebook: URL?

    func navigate(to destination: Destination) {
        path.append(destination)
    }

    func openEditor(_ url: URL) {
        presentedNotebook = url
    }

    func popToRoot() {
        path = NavigationPath()
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
