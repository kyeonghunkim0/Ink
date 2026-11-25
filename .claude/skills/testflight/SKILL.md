---
name: testflight
description: Ink 앱을 fastlane `beta` 레인으로 아카이브해 TestFlight에 올린다. 사전 점검(브랜치·작업 트리·API 키), 선택적 버전 올리기, 단위 테스트, 업로드, 결과 보고까지 한 번에 진행한다.
argument-hint: "[새 버전 예: 0.2.0] [--skip-tests]"
disable-model-invocation: true
---

# TestFlight 업로드

사용자가 `/testflight`를 부른 것 자체가 업로드 요청이다. 아래 순서대로 진행하되, 중간에 사용자 판단이 필요한 상황(아래 "멈추고 물을 때")에서만 멈춘다.
업로드는 되돌릴 수 없고(같은 빌드 번호는 다시 못 씀) 테스터에게 바로 보일 수 있으므로, 무엇을 올리는지 정확히 알고 올리는 것이 이 스킬의 핵심이다.

## 1. 사전 점검

저장소 루트(`Ink.xcworkspace`가 생기는 곳)에서 확인한다.

- `git status --short`, `git branch --show-current`, `git log --oneline -1`
  - 빌드는 **작업 트리 그대로** 아카이브된다. 커밋하지 않은 변경이 있으면 그대로 TestFlight에 들어간다.
- `fastlane/.env`에 `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT` 키가 있는지 **이름만** 확인한다:
  `sed -E 's/=.*/=<숨김>/' fastlane/.env`
  - 값(특히 `ASC_KEY_CONTENT`, base64 .p8 키)은 절대 출력·로그·커밋하지 않는다. fastlane이 이 파일을 자동으로 읽으므로 따로 export할 필요 없다.
- Homebrew Ruby 존재: `/opt/homebrew/opt/ruby/bin/ruby` (시스템 Ruby로는 bundler가 깨진다)
- 버전: `Project.swift`의 `MARKETING_VERSION`. 빌드 번호는 레인이 "최신 TestFlight 빌드 + 1"로 자동으로 정하므로 손대지 않는다.
- AI 프록시: `Project.swift`의 `INK_AI_PROXY_URL`이 비어 있으면 TestFlight 빌드의 AI 채팅은 **데모 응답**만 나온다. 보고에 한 줄로 알린다(막지는 않음).

### 멈추고 물을 때
- 커밋하지 않은 변경이 있다 → 변경 파일 목록을 보여 주고 "이대로 올릴지 / 먼저 커밋할지"를 묻는다. 커밋은 사용자가 원할 때만, 메시지는 `/caveman-commit` 규칙(Conventional Commits 타입만 영어, 요약 한국어).
- 기본 브랜치(`master`)가 아니다 → 브랜치 이름을 알리고 이 브랜치로 올릴지 확인한다. 기능 브랜치 테스트 배포는 흔한 일이라 막지는 않는다.
- `.env` 키가 없다 → 진행하지 말고 무엇이 빠졌는지 알린다.

## 2. 버전 올리기 (인자로 버전을 받았을 때만)

- `Project.swift`의 `"MARKETING_VERSION": "x.y.z"`만 바꾼다. Info.plist는 직접 고치지 않는다(빌드 설정에서 읽음).
- 바꾼 사실을 보고에 적는다. 커밋은 사용자가 요청할 때만 한다.
- 버전을 올리지 않아도 빌드 번호가 자동 증가하므로 같은 버전으로 여러 번 올릴 수 있다.

## 3. 단위 테스트 (`--skip-tests`면 건너뜀)

UI 테스트는 오래 걸리고 기존 실패가 있으므로 업로드 전에는 단위 테스트만 돌린다.

```bash
tuist generate --no-open
xcodebuild -workspace Ink.xcworkspace -scheme Ink \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' test \
  -only-testing:InkCoreTests -only-testing:InkStoreTests -only-testing:InkAITests -only-testing:InkTests
```

- `PremiumStoreTests`의 "known issue"(CLI에서 .storekit 상품이 안 오는 Xcode 26.5 버그)는 실패가 아니다.
- 진짜 실패가 있으면 멈추고 실패한 테스트와 오류를 보여 준 뒤 그래도 올릴지 묻는다.

## 4. 업로드

아카이브·서명·업로드에 수 분~십수 분 걸리므로 **백그라운드로** 실행하고 로그를 파일로 남긴다.

```bash
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
bundle exec fastlane ios beta > <scratchpad>/testflight-<날짜시각>.log 2>&1
```

- `beta` 레인이 하는 일: `tuist generate` → 최신 TestFlight 빌드 번호 조회 +1 → Release 아카이브(`-allowProvisioningUpdates`, 자동 서명) → `upload_to_testflight`(처리 완료는 기다리지 않음).
- 끝나면 로그 끝부분과 `fastlane.tools finished successfully` 여부를 확인한다. 로그를 통째로 붙이지 말고 필요한 줄만 인용한다.

### 자주 나는 오류
| 로그 단서 | 원인 / 조치 |
|---|---|
| `No Accounts` / `No signing certificate` / provisioning 관련 | Xcode에 Apple 계정이 로그인돼 있지 않거나 배포 인증서가 없다. Xcode → Settings → Accounts 확인을 안내한다. |
| `The bundle version must be higher` / redundant binary | 같은 빌드 번호가 이미 있다. 처리 대기 중인 빌드가 조회에 안 잡힌 경우라 잠시 뒤 다시 실행한다. |
| `Invalid API key` / 401 | `.env`의 키가 만료·오입력. 값은 보여 주지 말고 App Store Connect에서 키를 확인하라고 안내한다. |
| `ENV.fetch ... key not found` | `.env`에 키 이름이 빠졌다. |
| Swift 컴파일 오류 | 단위 테스트를 건너뛴 경우 흔하다. 오류 줄을 보여 주고 고칠지 묻는다. |

## 5. 결과 보고

짧게, 다음만 알린다.
- 올린 버전과 빌드 번호(로그의 `CURRENT_PROJECT_VERSION=` 또는 업로드 단계 출력), 브랜치, 커밋 해시
- 성공/실패. 성공이면 "App Store Connect에서 처리(보통 10–30분)가 끝나면 TestFlight에 나타난다"
- 함께 알릴 것: 커밋 안 된 변경을 포함했는지, 버전을 바꿨는지(커밋 필요), AI 데모 모드인지, 구독 상품을 App Store Connect에 아직 등록하지 않았다면 TestFlight에서 결제 화면이 "불러올 수 없음" 안내로 뜬다는 점
- 로그 파일의 전체 경로
