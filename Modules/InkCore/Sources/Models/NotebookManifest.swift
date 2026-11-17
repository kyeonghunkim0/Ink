import Foundation
import CoreGraphics

/// 노트북 종류. 일반 노트북(페이지 단위) 또는 무한 화이트보드(단일 확장 페이지).
public enum NotebookKind: String, Codable, Sendable {
    case notebook
    case whiteboard
}

/// 템플릿 종류. 배경 PDF를 생성할 때 사용한다.
public enum PaperTemplate: String, Codable, CaseIterable, Sendable, Identifiable {
    case blank, lined, grid, dotted, cornell

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .blank: "빈 페이지"
        case .lined: "줄"
        case .grid: "모눈"
        case .dotted: "점"
        case .cornell: "코넬"
        }
    }

    public var symbolName: String {
        switch self {
        case .blank: "rectangle"
        case .lined: "text.justify"
        case .grid: "squareshape.split.3x3"
        case .dotted: "circle.grid.3x3"
        case .cornell: "rectangle.split.2x1"
        }
    }
}

/// 용지 크기(포인트 단위). PDF 미디어 박스로 사용한다.
public enum PaperSize: String, Codable, CaseIterable, Sendable, Identifiable {
    case a4, letter, a5, square

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .a4: "A4"
        case .letter: "Letter"
        case .a5: "A5"
        case .square: "정사각형"
        }
    }

    /// 세로 방향 기준 포인트 크기.
    public var portraitSize: CGSize {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
        case .a5: CGSize(width: 419.53, height: 595.28)
        case .square: CGSize(width: 700, height: 700)
        }
    }

    public func size(landscape: Bool) -> CGSize {
        let s = portraitSize
        return landscape ? CGSize(width: s.height, height: s.width) : s
    }
}

/// 용지 색.
public enum PaperColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case white, yellow, dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .white: "흰색"
        case .yellow: "노란색"
        case .dark: "어두운색"
        }
    }
}

/// 페이지 메타데이터. 순서는 `NotebookManifest.pages`의 배열 순서이며 `background.pdf`의 페이지 순서와 일치한다.
public struct PageInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID()
    /// 템플릿으로 생성된 페이지면 템플릿 종류, PDF/Office에서 가져온 페이지면 nil.
    public var template: PaperTemplate?

    public init(id: UUID = UUID(), template: PaperTemplate? = nil) {
        self.id = id; self.template = template
    }
}

/// 녹음 메타데이터. 스트로크 동기화는 `PKStrokePath.creationDate`와 `startedAt`의 차이로 계산한다.
public struct RecordingInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var title: String
    public var startedAt: Date
    public var duration: TimeInterval
    /// 녹음을 시작할 때 보고 있던 페이지.
    public var pageID: UUID?

    public init(id: UUID = UUID(), title: String, startedAt: Date, duration: TimeInterval, pageID: UUID? = nil) {
        self.id = id; self.title = title; self.startedAt = startedAt; self.duration = duration; self.pageID = pageID
    }

    public var fileName: String { "\(id.uuidString).m4a" }
}

/// 페이지 위에 올리는 객체 종류.
public enum PageObjectKind: Codable, Hashable, Sendable {
    /// `images/<fileName>`에 저장된 사진.
    case image(fileName: String)
    /// 텍스트 상자.
    case text(String)
    /// 이모지 스티커.
    case sticker(String)
}

/// 필기 아래에 놓이는 페이지 객체. 좌표는 페이지 포인트(좌상단 원점).
public struct PageObject: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var pageID: UUID
    public var kind: PageObjectKind
    public var frame: CGRect
    public var fontSize: CGFloat = 20

    public init(pageID: UUID, kind: PageObjectKind, frame: CGRect, fontSize: CGFloat = 20) {
        self.pageID = pageID; self.kind = kind; self.frame = frame; self.fontSize = fontSize
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        pageID = try c.decode(UUID.self, forKey: .pageID)
        kind = try c.decode(PageObjectKind.self, forKey: .kind)
        frame = try c.decode(CGRect.self, forKey: .frame)
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 20
    }

    public var isText: Bool { if case .text = kind { return true } else { return false } }
}

/// `.inknote` 패키지의 `manifest.json`.
public struct NotebookManifest: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int = NotebookManifest.currentVersion
    public var id: UUID = UUID()
    public var title: String
    public var kind: NotebookKind = .notebook
    public var createdAt: Date = Date()
    public var modifiedAt: Date = Date()
    public var paperSize: PaperSize = .a4
    public var paperColor: PaperColor = .white
    public var isLandscape: Bool = false
    public var defaultTemplate: PaperTemplate = .blank
    public var pages: [PageInfo] = []
    public var recordings: [RecordingInfo] = []
    public var objects: [PageObject] = []
    /// 페이지별 손글씨 인식 결과(검색용).
    public var recognizedText: [UUID: String] = [:]

    public var pageSize: CGSize { paperSize.size(landscape: isLandscape) }

    public init(title: String) {
        self.title = title
    }

    /// 예전 빌드가 쓴 매니페스트에는 나중에 추가된 키가 없다. 없는 키는 기본값으로 읽어 기존 노트가 계속 열리게 한다.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kind = try c.decodeIfPresent(NotebookKind.self, forKey: .kind) ?? .notebook
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        paperSize = try c.decodeIfPresent(PaperSize.self, forKey: .paperSize) ?? .a4
        paperColor = try c.decodeIfPresent(PaperColor.self, forKey: .paperColor) ?? .white
        isLandscape = try c.decodeIfPresent(Bool.self, forKey: .isLandscape) ?? false
        defaultTemplate = try c.decodeIfPresent(PaperTemplate.self, forKey: .defaultTemplate) ?? .blank
        pages = try c.decodeIfPresent([PageInfo].self, forKey: .pages) ?? []
        recordings = try c.decodeIfPresent([RecordingInfo].self, forKey: .recordings) ?? []
        objects = try c.decodeIfPresent([PageObject].self, forKey: .objects) ?? []
        recognizedText = try c.decodeIfPresent([UUID: String].self, forKey: .recognizedText) ?? [:]
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func encoded() throws -> Data { try Self.encoder.encode(self) }

    public static func decode(_ data: Data) throws -> NotebookManifest {
        try decoder.decode(NotebookManifest.self, from: data)
    }
}

/// 패키지 내부 경로 상수.
public enum NotebookPackage {
    public static let fileExtension = "inknote"
    public static let contentType = "com.gimgyeonghun.ink.notebook"
    public static let manifestName = "manifest.json"
    public static let backgroundName = "background.pdf"
    public static let pagesDirectory = "pages"
    public static let audioDirectory = "audio"
    public static let imagesDirectory = "images"
    public static let thumbnailName = "thumbnail.png"
    public static let drawingExtension = "drawing"
}
