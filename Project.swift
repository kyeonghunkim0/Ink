import ProjectDescription

let bundleIDPrefix = "com.gimgyeonghun"
let iCloudContainer = "iCloud.\(bundleIDPrefix).Ink"

let infoPlist: [String: Plist.Value] = [
    "CFBundleDisplayName": "Ink",
    "CFBundleShortVersionString": "0.1.0",
    "CFBundleVersion": "1",
    "UILaunchScreen": [:],
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
    organizationName: "gimgyeonghun",
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
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            ])
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
            buildAction: .buildAction(targets: ["Ink"]),
            testAction: .targets(["InkTests", "InkUITests"]),
            runAction: .runAction(executable: "Ink")
        ),
    ]
)
