# Ink — GoodNotes 스타일 iPadOS 노트 앱

## 프로젝트 개요
- 앱 이름: **Ink** (번들 ID `com.gimgyeonghun.Ink`, iCloud 컨테이너 `iCloud.com.gimgyeonghun.Ink`)
- iPad 전용, iPadOS 18.0+ (26에서 Liquid Glass 활성화), Swift 6 strict concurrency, SwiftUI + UIKit 브리징
- 프로젝트는 tuist로 생성: `tuist generate` → `Ink.xcworkspace`
- 빌드: `xcodebuild -workspace Ink.xcworkspace -scheme Ink -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build`
- 테스트: 같은 명령에 `test`
- fastlane: Homebrew Ruby 필요 → `export PATH="/opt/homebrew/opt/ruby/bin:$PATH"` 후 `bundle exec fastlane ios <lane>`
  - 레인: `build`(시뮬레이터), `test`, `beta`(TestFlight, 환경변수 ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_CONTENT 필요)
  - 버전은 Project.swift의 `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`에서 읽음 (Info.plist 직접 수정 금지)
- 스펙/로드맵: ~/.claude/plans/ipados-synchronous-teacup.md

## 아키텍처
- 모듈(tuist 타깃)
  - `InkCore` 프레임워크 (`Modules/InkCore/Sources`): Models(Codable 매니페스트, UIDocument) / Services(저장소, 변환, 내보내기, 녹음) / Support. SwiftUI 뷰 금지, 앱에서 쓰는 API는 `public`
  - `Ink` 앱 (`Ink/Sources`): App(진입점·Router·EditorSessions) / Views(SwiftUI) / Debug(데모 데이터)
  - 테스트: `InkCoreTests`(Core 로직) · `InkTests`(앱 라우팅·세션) · `InkUITests`
  - 새 파일을 추가하면 `tuist generate` 다시 실행(소스 glob은 생성 시점에 확정)
  - SwiftUI에도 `LibraryItem`이 있어 앱 모듈은 `App/CoreTypeAliases.swift`의 별칭으로 InkCore 타입을 가리킴
- 창(씬)마다 `Router`(경로·탭·편집기 표시), 앱 전역 `EditorSessions`(URL당 EditorModel 하나)
  - 한 노트는 한 창에만 열림: 다른 창에서 열면 탭이 옮겨 감
  - 파일 이동·이름 변경·삭제 전 `closeTabAndWait`/`closeTabsAndWait`는 모든 창에 적용됨
- 문서 = `.inknote` 패키지 디렉터리 (manifest.json, background.pdf, pages/*.drawing, audio/*)
- 필기: PencilKit / PDF: PDFKit / Office→PDF: WKWebView + UIPrintPageRenderer / 동기화: iCloud ubiquity 컨테이너

## 코딩 표준 (스킬 `swiftui` 준수)
- 상태는 `@Observable` 클래스 + `@State`/`@Bindable`/`@Environment`만. ObservableObject, @Published, @StateObject, @EnvironmentObject 금지
- 네비게이션은 `NavigationStack` + `Router`(@Observable) + `enum Destination: Hashable`
- 뷰는 작게 분리, `ForEach`는 안정적 ID, 큰 목록은 Lazy 컨테이너
- `body`/`init`에서 I/O·무거운 연산 금지 → `.task {}` 또는 명시적 load 메서드
- `AnyView` 금지, `@ViewBuilder`/`Group` 사용
- 모든 뷰에 `#Preview` 작성(mock 데이터)
- UIKit 브리징은 `UIViewRepresentable`/`UIViewControllerRepresentable` + Coordinator로 한정

## UI 표준 (스킬 `glass` 준수)
- 글래스 API는 직접 호출하지 않고 `Views/Shared/AdaptiveGlass.swift`의 헬퍼만 사용
  (`adaptiveGlass(cornerRadius:)`, `adaptiveGlassCapsule()`, `adaptiveGlassButtonStyle()`, `adaptiveProminentButtonStyle()`, `AdaptiveGlassContainer`)
- 헬퍼 내부에서 `#available(iOS 26, *)`로 분기하고 18에서는 머티리얼/bordered로 대체
- 형제 글래스 뷰는 `AdaptiveGlassContainer`로 감쌈
- 글래스는 인터랙티브 요소·툴바·카드에만. 캔버스 위 불투명 배경 금지
- 라이트/다크 모두 확인

## 워크플로
- 새 SwiftUI 작업 전 Skill `swiftui`, 글래스 UI 작업 전 Skill `glass` 호출
- 리뷰: `/review <기준 커밋>` (표준 = 이 문서, 스펙 = 플랜 파일)
- 세션 인계: `/handoff`
- `ios-clean`은 gstack DebugBridge 전용이며 이 프로젝트에는 해당 없음
- 커밋은 사용자가 요청할 때만, 메시지는 `/caveman-commit`

## 금지/주의
- 26 전용 API는 반드시 `#available(iOS 26, *)` 분기 (배포 타깃 18.0)
- 문서 저장은 항상 UIDocument 경유(직접 FileManager 쓰기 금지)
- 오디오 세션은 AudioRecorder 서비스에서만 설정
