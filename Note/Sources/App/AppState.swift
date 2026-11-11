import Foundation
import Observation
import SwiftUI

/// 네비게이션 목적지.
enum Destination: Hashable {
    case folder(URL)
    case editor(URL)
}

/// 타입 안전 라우터.
@MainActor
@Observable
final class Router {
    var path = NavigationPath()

    func navigate(to destination: Destination) {
        path.append(destination)
    }

    func popToRoot() {
        path = NavigationPath()
    }
}
