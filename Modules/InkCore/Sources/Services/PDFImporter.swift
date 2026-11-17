import Foundation
import PDFKit

public enum ImportError: LocalizedError {
    case unreadable
    case unsupportedType
    case conversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable: "파일을 읽을 수 없습니다."
        case .unsupportedType: "지원하지 않는 파일 형식입니다."
        case .conversionFailed(let reason): "변환에 실패했습니다: \(reason)"
        }
    }
}

/// PDF 데이터를 노트북 매니페스트 + PDFDocument로 변환한다.
public enum PDFImporter {
    public static func makeNotebook(title: String, pdfData: Data) throws -> (NotebookManifest, PDFDocument) {
        guard let pdf = PDFDocument(data: pdfData), pdf.pageCount > 0 else {
            throw ImportError.unreadable
        }
        var manifest = NotebookManifest(title: title)
        if let first = pdf.page(at: 0) {
            let bounds = first.bounds(for: .mediaBox)
            manifest.isLandscape = bounds.width > bounds.height
        }
        manifest.pages = (0..<pdf.pageCount).map { _ in PageInfo(template: nil) }
        return (manifest, pdf)
    }

    /// 보안 범위 URL에서 데이터를 읽는다. 문서 선택기 결과에 사용한다.
    public static func readData(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var coordinatorError: NSError?
        var result: Data?
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            do { result = try Data(contentsOf: coordinatedURL) } catch { readError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let readError { throw readError }
        guard let result else { throw ImportError.unreadable }
        return result
    }
}
