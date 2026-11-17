import InkCore

/// SwiftUI(DeveloperToolsSupport)에도 `LibraryItem`이 있어 두 모듈을 함께 import하면 모호해진다.
/// 앱 모듈 안에서는 항상 InkCore의 타입을 가리키게 한다.
typealias LibraryItem = InkCore.LibraryItem
