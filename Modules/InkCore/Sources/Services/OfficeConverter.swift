import UIKit
import WebKit
import UniformTypeIdentifiers

/// Word/PowerPoint/Excel 파일을 WKWebView로 렌더링한 뒤 UIPrintPageRenderer로 페이지 단위 PDF를 만든다.
@MainActor
public final class OfficeConverter: NSObject, WKNavigationDelegate {
    public static let supportedTypes: [UTType] = [
        .pdf,
        UTType("org.openxmlformats.wordprocessingml.document"),
        UTType("org.openxmlformats.presentationml.presentation"),
        UTType("org.openxmlformats.spreadsheetml.sheet"),
        UTType("com.microsoft.word.doc"),
        UTType("com.microsoft.powerpoint.ppt"),
        UTType("com.microsoft.excel.xls"),
        .rtf,
    ].compactMap { $0 }

    public static let officeExtensions: Set<String> = ["doc", "docx", "ppt", "pptx", "xls", "xlsx", "rtf"]

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, any Error>?

    public override init() { super.init() }

    /// 파일을 PDF 데이터로 변환한다. `fileURL`은 앱이 읽을 수 있는 임시 복사본이어야 한다.
    public func convertToPDF(fileURL: URL) async throws -> Data {
        let ext = fileURL.pathExtension.lowercased()
        let paper = ext == "pptx" || ext == "ppt"
            ? CGSize(width: 960, height: 540)
            : PaperSize.a4.portraitSize

        let web = WKWebView(frame: CGRect(origin: .zero, size: paper))
        web.navigationDelegate = self
        web.isHidden = true
        hostWindow?.addSubview(web)
        webView = web
        defer {
            web.removeFromSuperview()
            webView = nil
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            continuation = cont
            web.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        }
        // 레이아웃이 안정될 때까지 잠시 대기.
        try await Task.sleep(for: .milliseconds(600))

        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        let paperRect = CGRect(origin: .zero, size: paper)
        let inset: CGFloat = ext == "pptx" || ext == "ppt" ? 0 : 24
        renderer.setValue(paperRect, forKey: "paperRect")
        renderer.setValue(paperRect.insetBy(dx: inset, dy: inset), forKey: "printableRect")

        let pageCount = renderer.numberOfPages
        guard pageCount > 0 else { throw ImportError.conversionFailed("렌더링된 페이지가 없습니다.") }

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paperRect, nil)
        for i in 0..<pageCount {
            UIGraphicsBeginPDFPageWithInfo(paperRect, nil)
            renderer.drawPage(at: i, in: paperRect)
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    private var hostWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first
    }

    public nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            continuation?.resume()
            continuation = nil
        }
    }

    public nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    public nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
