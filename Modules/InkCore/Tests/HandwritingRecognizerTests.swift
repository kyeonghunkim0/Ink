import Testing
import UIKit
@testable import InkCore

struct HandwritingRecognizerTests {
    @Test func recognizesRenderedText() async throws {
        let size = CGSize(width: 600, height: 200)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            ("Hello Ink 2026" as NSString).draw(at: CGPoint(x: 40, y: 60), withAttributes: [
                .font: UIFont.systemFont(ofSize: 64, weight: .medium), .foregroundColor: UIColor.black])
        }
        let text = try await HandwritingRecognizer.recognize(try #require(image.cgImage))
        #expect(text.localizedCaseInsensitiveContains("Hello"))
        #expect(text.contains("2026"))
    }
}
