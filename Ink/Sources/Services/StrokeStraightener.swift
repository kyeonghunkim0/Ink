import PencilKit
import UIKit

/// 펜을 멈춘 채 들어 올린 스트로크를 직선으로 바꾼다.
enum StrokeStraightener {
    /// 이 시간 이상 펜을 움직이지 않고 떼면 직선으로 간주한다.
    static let holdDuration: TimeInterval = 0.5
    /// 멈춤 판정용 이동 허용치(포인트).
    static let holdTolerance: CGFloat = 4

    /// 스트로크가 직선에 가까우면 양 끝을 잇는 직선 스트로크를 돌려준다.
    /// 호나 도형처럼 크게 휜 경우는 nil.
    static func straightened(_ stroke: PKStroke) -> PKStroke? {
        let points = stroke.path.map { $0 }
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        let a = first.location, b = last.location
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length >= 20 else { return nil }

        // 끝점 근처의 멈춤 구간(펜을 유지한 동안 쌓인 점)을 제외하고 직선성을 판정한다.
        let maxDeviation = points.reduce(CGFloat(0)) { acc, p in
            let q = p.location
            let d = abs(dy * q.x - dx * q.y + b.x * a.y - b.y * a.x) / length
            return max(acc, d)
        }
        guard maxDeviation <= max(10, length * 0.12) else { return nil }

        let avgSize = points.reduce(CGSize.zero) { CGSize(width: $0.width + $1.size.width, height: $0.height + $1.size.height) }
        let size = CGSize(width: avgSize.width / CGFloat(points.count), height: avgSize.height / CGFloat(points.count))
        let opacity = points.reduce(CGFloat(0)) { $0 + $1.opacity } / CGFloat(points.count)
        let duration = max(last.timeOffset, 0.05)
        let steps = max(2, Int(length / 8))
        var controlPoints: [PKStrokePoint] = []
        controlPoints.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            controlPoints.append(PKStrokePoint(
                location: CGPoint(x: a.x + dx * t, y: a.y + dy * t),
                timeOffset: duration * TimeInterval(t),
                size: size, opacity: opacity,
                force: first.force, azimuth: first.azimuth, altitude: first.altitude))
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: stroke.path.creationDate)
        return PKStroke(ink: stroke.ink, path: path, transform: stroke.transform, mask: stroke.mask)
    }
}

/// 캔버스 터치를 관찰만 하는 제스처. 펜을 멈춘 채 들어 올렸는지 알려 준다.
/// 인식 상태로 넘어가지 않으므로 PencilKit의 필기 제스처를 방해하지 않는다.
@MainActor
final class StrokeHoldObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// 터치가 끝났을 때 호출. 인자는 끝나기 직전 멈춰 있던 시간.
    var onTouchEnded: ((TimeInterval) -> Void)?
    private var anchor: CGPoint = .zero
    private var lastMoveAt: TimeInterval = 0

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        anchor = touch.location(in: view)
        lastMoveAt = touch.timestamp
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let p = touch.location(in: view)
        if hypot(p.x - anchor.x, p.y - anchor.y) > StrokeStraightener.holdTolerance {
            anchor = p
            lastMoveAt = touch.timestamp
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { onTouchEnded?(touch.timestamp - lastMoveAt) }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                       shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                       shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }
}
