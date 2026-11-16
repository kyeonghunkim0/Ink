# Ink

Apple Pencil로 필기하는 iPad 전용 노트 앱입니다. 노트북·PDF·Office 문서 위에 손글씨를 쓰고, 녹음과 함께 기록하며, iCloud로 기기 간 동기화합니다.

- iPadOS 18.0 이상 (iPadOS 26에서 Liquid Glass UI 적용)
- Swift 6 (strict concurrency), SwiftUI + UIKit
- 현재 버전 0.1.0

## 주요 기능

**라이브러리**
- 폴더로 노트 정리: 만들기, 이름 변경, 복제, 이동, 삭제, 여러 개 선택해 한꺼번에 처리
- 노트 제목과 손글씨 인식 결과로 검색 (⌘F)
- iCloud Drive 동기화, iCloud를 쓸 수 없으면 로컬에 저장

**노트 만들기와 가져오기**
- 노트북: 템플릿(빈 페이지, 줄, 모눈, 점, 코넬), 용지 크기(A4, Letter, A5, 정사각형), 용지 색, 가로/세로 방향 선택
- 무한 화이트보드: 그릴수록 넓어지는 캔버스
- PDF 가져오기
- Word, PowerPoint, Excel, RTF 가져오기 (PDF로 변환해서 가져옴)

**편집기**
- PencilKit 필기 (펜, 형광펜, 지우개, 올가미, 자)
- 펜을 잠시 멈췄다 떼면 획이 직선으로 바뀜
- 사진, 텍스트 상자, 이모지 스티커 넣기
- 페이지 추가 (⌘N), 이동, 삭제, 썸네일 목록 (⌘T)
- 여러 노트를 탭으로 열기
- Vision 손글씨 인식으로 노트 안 검색
- 확대/축소 (⌘+ / ⌘−)

**녹음**
- 필기하면서 녹음 (⌘R), 노트 하나에 녹음 여러 개 저장
- 재생하면 그 시점에 쓴 필기가 함께 표시됨

**공유와 내보내기**
- PDF (전체 또는 현재 페이지), PNG (현재 페이지). 필기가 합쳐진 상태로 내보냄
- `.inknote` 원본 공유, AirDrop 바로 보내기

## 시작하기

필요한 도구: Xcode 26 이상, [tuist](https://tuist.io)

```sh
tuist generate          # Ink.xcworkspace 생성
open Ink.xcworkspace
```

명령줄에서 빌드하고 테스트하기:

```sh
xcodebuild -workspace Ink.xcworkspace -scheme Ink \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build

# 단위 테스트와 UI 테스트
xcodebuild -workspace Ink.xcworkspace -scheme Ink \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' test
```

실기기에서 iCloud 동기화를 쓰려면 iCloud 컨테이너 `iCloud.com.gimgyeonghun.Ink`에 접근할 수 있는 팀으로 서명해야 합니다. 시뮬레이터에서는 로컬 저장소를 씁니다.

## fastlane

fastlane은 Homebrew Ruby로 실행합니다. 모든 레인은 시작할 때 `tuist generate`를 먼저 실행합니다.

```sh
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
bundle install
bundle exec fastlane ios <lane>
```

| 레인 | 하는 일 |
|---|---|
| `build` | 시뮬레이터용 디버그 빌드 (서명 없음) |
| `test` | 시뮬레이터에서 단위 테스트와 UI 테스트 실행 |
| `screenshots` | App Store 스크린샷 촬영 (데모 노트 자동 생성) |
| `upload_screenshots` | 스크린샷을 App Store Connect에 업로드 |
| `beta` | TestFlight 업로드 (빌드 번호 = 최신 TestFlight 빌드 + 1) |

`beta`와 `upload_screenshots`는 App Store Connect API 키 환경변수가 필요합니다: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`(base64).

버전은 `Project.swift`의 `MARKETING_VERSION`과 `CURRENT_PROJECT_VERSION`에서 관리합니다. Info.plist를 직접 고치지 마세요.

## 프로젝트 구조

```
Project.swift              tuist 프로젝트 정의 (타깃, Info.plist, 문서 타입)
Ink/
  Sources/
    App/                   앱 진입점, 앱 상태
    Models/                노트 매니페스트(Codable), NotebookDocument(UIDocument)
    Services/              저장소, PDF·Office 가져오기, 템플릿 렌더링,
                           내보내기, 녹음, 손글씨 인식, 직선 보정
    Views/
      Library/             라이브러리, 새 노트 시트
      Editor/              편집기, 캔버스, 페이지 썸네일, 녹음 바
      Shared/              Liquid Glass 헬퍼(AdaptiveGlass), 검색 바
  Resources/               에셋 (앱 아이콘, 강조 색)
  Tests/                   단위 테스트
  UITests/                 UI 테스트, 스크린샷 촬영
  Design/                  앱 아이콘 생성 스크립트
fastlane/                  빌드·테스트·배포 레인
```

### 노트 파일 형식 (`.inknote`)

노트 하나는 패키지 디렉터리 하나입니다. iCloud 동기화 때 바뀐 파일만 전송됩니다.

```
노트 이름.inknote/
  manifest.json        제목, 종류(노트북/화이트보드), 용지 설정, 페이지 순서,
                       녹음 목록, 페이지 객체, 손글씨 인식 결과
  background.pdf       페이지 배경 (템플릿 또는 가져온 PDF)
  pages/<id>.drawing   페이지별 PencilKit 필기
  audio/<id>.m4a       녹음
  images/              페이지에 넣은 사진
  thumbnail.png        라이브러리 썸네일
```

## 알려진 한계

- Office 문서는 WebKit으로 렌더링한 뒤 PDF로 바꾸기 때문에, 복잡한 레이아웃이나 PowerPoint 슬라이드 경계가 원본과 다를 수 있습니다.

## 기여

코딩 규칙과 아키텍처 원칙은 [CLAUDE.md](CLAUDE.md)에 정리되어 있습니다.
