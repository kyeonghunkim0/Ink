import ProjectDescription

let bundleIDPrefix = "com.gimgyeonghun"
let iCloudContainer = "iCloud.\(bundleIDPrefix).Note"

let infoPlist: [String: Plist.Value] = [
    "CFBundleDisplayName": "Note",
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
            "NSUbiquitousContainerName": "Note",
            "NSUbiquitousContainerSupportedFolderLevels": "Any",
        ],
    ],
    "CFBundleDocumentTypes": [
        [
            "CFBundleTypeName": "Note Notebook",
            "CFBundleTypeRole": "Editor",
            "LSHandlerRank": "Owner",
            "LSTypeIsPackage": true,
            "LSItemContentTypes": ["\(bundleIDPrefix).note.gnote"],
        ],
    ],
    "UTExportedTypeDeclarations": [
        [
            "UTTypeIdentifier": "\(bundleIDPrefix).note.gnote",
            "UTTypeDescription": "Note Notebook",
            "UTTypeConformsTo": ["com.apple.package", "public.composite-content"],
            "UTTypeTagSpecification": [
                "public.filename-extension": ["gnote"],
            ],
        ],
    ],
]

let project = Project(
    name: "Note",
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
            "IPHONEOS_DEPLOYMENT_TARGET": "26.0",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "CODE_SIGN_STYLE": "Automatic",
        ]
    ),
    targets: [
        .target(
            name: "Note",
            destinations: [.iPad],
            product: .app,
            bundleId: "\(bundleIDPrefix).Note",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: infoPlist),
            sources: ["Note/Sources/**"],
            resources: ["Note/Resources/**"],
            entitlements: .file(path: "Note/Note.entitlements"),
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            ])
        ),
        .target(
            name: "NoteTests",
            destinations: [.iPad],
            product: .unitTests,
            bundleId: "\(bundleIDPrefix).NoteTests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default,
            sources: ["Note/Tests/**"],
            dependencies: [.target(name: "Note")]
        ),
        .target(
            name: "NoteUITests",
            destinations: [.iPad],
            product: .uiTests,
            bundleId: "\(bundleIDPrefix).NoteUITests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default,
            sources: ["Note/UITests/**"],
            dependencies: [.target(name: "Note")]
        ),
    ],
    schemes: [
        .scheme(
            name: "Note",
            shared: true,
            buildAction: .buildAction(targets: ["Note"]),
            testAction: .targets(["NoteTests", "NoteUITests"]),
            runAction: .runAction(executable: "Note")
        ),
    ]
)
