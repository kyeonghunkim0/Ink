import ProjectDescription

let bundleIDPrefix = "com.gimgyeonghun"
let iCloudContainer = "iCloud.\(bundleIDPrefix).Ink"

let infoPlist: [String: Plist.Value] = [
    "CFBundleDisplayName": "Ink",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "UILaunchScreen": [:],
    "ITSAppUsesNonExemptEncryption": false,
    "UISupportedInterfaceOrientations~ipad": [
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationPortraitUpsideDown",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    ],
    "UIApplicationSceneManifest": [
        "UIApplicationSupportsMultipleScenes": true,
    ],
    "UISupportsDocumentBrowser": true,
    "LSSupportsOpeningDocumentsInPlace": true,
    "NSMicrophoneUsageDescription": "강의나 회의를 녹음해 필기와 함께 저장하기 위해 마이크를 사용합니다.",
    "NSUbiquitousContainers": [
        iCloudContainer: [
            "NSUbiquitousContainerIsDocumentScopePublic": true,
            "NSUbiquitousContainerName": "Ink",
            "NSUbiquitousContainerSupportedFolderLevels": "Any",
        ],
    ],
    "CFBundleDocumentTypes": [
        [
            "CFBundleTypeName": "Ink Notebook",
            "CFBundleTypeRole": "Editor",
            "LSHandlerRank": "Owner",
            "LSTypeIsPackage": true,
            "LSItemContentTypes": ["\(bundleIDPrefix).ink.notebook"],
        ],
    ],
    "UTExportedTypeDeclarations": [
        [
            "UTTypeIdentifier": "\(bundleIDPrefix).ink.notebook",
            "UTTypeDescription": "Ink Notebook",
            "UTTypeConformsTo": ["com.apple.package", "public.composite-content"],
            "UTTypeTagSpecification": [
                "public.filename-extension": ["inknote"],
            ],
        ],
    ],
]

let project = Project(
    name: "Ink",
    organizationName: "KyeongHun Kim",
    options: .options(
        automaticSchemesOptions: .disabled,
        developmentRegion: "ko"
    ),
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "TARGETED_DEVICE_FAMILY": "2",
            "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "CODE_SIGN_STYLE": "Automatic",
            "DEVELOPMENT_TEAM": "2N94PZ8R58",
            "MARKETING_VERSION": "0.1.0",
            "CURRENT_PROJECT_VERSION": "1",
        ]
    ),
    targets: [
        .target(
            name: "Ink",
            destinations: [.iPad],
            product: .app,
            bundleId: "\(bundleIDPrefix).Ink",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .extendingDefault(with: infoPlist),
            sources: ["Ink/Sources/**"],
            resources: ["Ink/Resources/**"],
            entitlements: .file(path: "Ink/Ink.entitlements"),
            dependencies: [.target(name: "InkCore")],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            ])
        ),
        // 문서 모델과 서비스(저장소·변환·내보내기·녹음). SwiftUI 뷰는 두지 않는다.
        .target(
            name: "InkCore",
            destinations: [.iPad],
            product: .framework,
            bundleId: "\(bundleIDPrefix).InkCore",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .default,
            sources: ["Modules/InkCore/Sources/**"]
        ),
        .target(
            name: "InkCoreTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "\(bundleIDPrefix).InkCoreTests",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .default,
            sources: ["Modules/InkCore/Tests/**"],
            dependencies: [.target(name: "InkCore")]
        ),
        .target(
            name: "InkTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "\(bundleIDPrefix).InkTests",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .default,
            sources: ["Ink/Tests/**"],
            dependencies: [.target(name: "Ink")]
        ),
        .target(
            name: "InkUITests",
            destinations: [.iPad],
            product: .uiTests,
            bundleId: "\(bundleIDPrefix).InkUITests",
            deploymentTargets: .iOS("18.0"),
            infoPlist: .default,
            sources: ["Ink/UITests/**"],
            dependencies: [.target(name: "Ink")]
        ),
    ],
    schemes: [
        .scheme(
            name: "Ink",
            shared: true,
            buildAction: .buildAction(targets: ["InkCore", "Ink"]),
            testAction: .targets(["InkCoreTests", "InkTests", "InkUITests"]),
            runAction: .runAction(executable: "Ink")
        ),
    ]
)
