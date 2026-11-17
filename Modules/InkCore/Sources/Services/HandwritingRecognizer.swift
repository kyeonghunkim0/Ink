import Foundation
import Vision
import CoreGraphics

/// Vision으로 손글씨를 텍스트로 인식한다.
public enum HandwritingRecognizer {
    /// 이미지 전체를 인식해 줄 단위 텍스트를 합쳐 돌려준다.
    public static func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { request, error in
                if let error { cont.resume(throwing: error); return }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ko-KR", "en-US"]
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .utility).async {
                do { try handler.perform([request]) } catch { cont.resume(throwing: error) }
            }
        }
    }
}
