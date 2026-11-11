import Foundation
import CoreGraphics

/// 노트북 종류. 일반 노트북(페이지 단위) 또는 무한 화이트보드(단일 확장 페이지).
enum NotebookKind: String, Codable, Sendable {
    case notebook
    case whiteboard
}

/// 템플릿 종류. 배경 PDF를 생성할 때 사용한다.
enum PaperTemplate: String, Codable, CaseIterable, Sendable, Identifiable {
    case blank, lined, grid, dotted, cornell

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blank: "빈 페이지"
        case .lined: "줄"
        case .grid: "모눈"
        case .dotted: "점"
        case .cornell: "코넬"
        }
    }

    var symbolName: String {
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
enum PaperSize: String, Codable, CaseIterable, Sendable, Identifiable {
    case a4, letter, a5, square

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .a4: "A4"
        case .letter: "Letter"
        case .a5: "A5"
        case .square: "정사각형"
        }
    }

    /// 세로 방향 기준 포인트 크기.
    var portraitSize: CGSize {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
        case .a5: CGSize(width: 419.53, height: 595.28)
        case .square: CGSize(width: 700, height: 700)
        }
    }

    func size(landscape: Bool) -> CGSize {
        let s = portraitSize
        return landscape ? CGSize(width: s.height, height: s.width) : s
    }
}

/// 용지 색.
enum PaperColor: String, Codable, CaseIterable, Sendable, Identifiable {
    case white, yellow, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: "흰색"
        case .yellow: "노란색"
        case .dark: "어두운색"
        }
    }
}

/// 페이지 메타데이터. 순서는 `NotebookManifest.pages`의 배열 순서이며 `background.pdf`의 페이지 순서와 일치한다.
struct PageInfo: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    /// 템플릿으로 생성된 페이지면 템플릿 종류, PDF/Office에서 가져온 페이지면 nil.
    var template: PaperTemplate?
}

/// 녹음 메타데이터. 스트로크 동기화는 `PKStrokePath.creationDate`와 `startedAt`의 차이로 계산한다.
struct RecordingInfo: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var startedAt: Date
    var duration: TimeInterval
    /// 녹음을 시작할 때 보고 있던 페이지.
    var pageID: UUID?

    var fileName: String { "\(id.uuidString).m4a" }
}

/// `.gnote` 패키지의 `manifest.json`.
struct NotebookManifest: Codable, Hashable, Sendable {
    static let currentVersion = 1

    var version: Int = NotebookManifest.currentVersion
    var id: UUID = UUID()
    var title: String
    var kind: NotebookKind = .notebook
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var paperSize: PaperSize = .a4
    var paperColor: PaperColor = .white
    var isLandscape: Bool = false
    var defaultTemplate: PaperTemplate = .blank
    var pages: [PageInfo] = []
    var recordings: [RecordingInfo] = []

    var pageSize: CGSize { paperSize.size(landscape: isLandscape) }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func encoded() throws -> Data { try Self.encoder.encode(self) }

    static func decode(_ data: Data) throws -> NotebookManifest {
        try decoder.decode(NotebookManifest.self, from: data)
    }
}

/// 패키지 내부 경로 상수.
enum NotebookPackage {
    static let fileExtension = "gnote"
    static let contentType = "com.gimgyeonghun.note.gnote"
    static let manifestName = "manifest.json"
    static let backgroundName = "background.pdf"
    static let pagesDirectory = "pages"
    static let audioDirectory = "audio"
    static let thumbnailName = "thumbnail.png"
    static let drawingExtension = "drawing"
}
