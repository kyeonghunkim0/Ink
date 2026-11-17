import Foundation

extension URL {
    /// 끝의 '/'와 `.`/`..`를 제거한 파일 URL. 같은 경로를 가리키는 URL끼리 `==`가 성립하도록 맞춘다.
    public var normalizedFileURL: URL {
        URL(fileURLWithPath: standardizedFileURL.path, isDirectory: false)
    }
}
