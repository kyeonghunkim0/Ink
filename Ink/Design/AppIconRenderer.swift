import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let variant = CommandLine.arguments[1]   // "4A" or "3B"
let out = CommandLine.arguments[2]

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xff)/255, CGFloat((hex >> 8) & 0xff)/255, CGFloat(hex & 0xff)/255, a])!
}

// 배경
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0x0B1437), rgb(0x1E3A8A), rgb(0x2563EB)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, 0.12), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 300, y: 240), startRadius: 0, endCenter: CGPoint(x: 300, y: 240), endRadius: 720, options: [])

func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// 펜: 중심선 (from→to) 기준으로 몸통, 펜촉(삼각), 꼬리를 그린다.
func drawPen(from a: CGPoint, to b: CGPoint, width w: CGFloat, body: CGColor, tip: CGColor, ring: CGColor?) {
    let dx = b.x - a.x, dy = b.y - a.y
    let len = sqrt(dx*dx + dy*dy)
    let angle = atan2(dy, dx)
    ctx.saveGState()
    ctx.translateBy(x: a.x, y: a.y)
    ctx.rotate(by: angle)
    // 펜촉 길이
    let tipLen = w * 1.6
    let bodyLen = len - tipLen
    // 몸통(둥근 끝)
    ctx.setFillColor(body)
    ctx.addPath(roundedRect(CGRect(x: -w/2 + 0, y: -w/2, width: bodyLen + w/2, height: w), w/2))
    ctx.fillPath()
    // 몸통 끝은 각지게: 펜촉 쪽 사각 덮기
    ctx.fill(CGRect(x: bodyLen - w/2, y: -w/2, width: w/2, height: w))
    // 클립(고리)
    if let ring {
        ctx.setFillColor(ring)
        ctx.fill(CGRect(x: bodyLen - w*0.55, y: -w/2, width: w*0.22, height: w))
    }
    // 펜촉(삼각형)
    ctx.setFillColor(tip)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: bodyLen, y: -w/2))
    p.addLine(to: CGPoint(x: bodyLen + tipLen, y: 0))
    p.addLine(to: CGPoint(x: bodyLen, y: w/2))
    p.closeSubpath()
    ctx.addPath(p); ctx.fillPath()
    // 펜촉 끝 작은 심
    ctx.setFillColor(rgb(0x0B1437))
    let c = CGMutablePath()
    c.move(to: CGPoint(x: bodyLen + tipLen*0.62, y: -w*0.12))
    c.addLine(to: CGPoint(x: bodyLen + tipLen, y: 0))
    c.addLine(to: CGPoint(x: bodyLen + tipLen*0.62, y: w*0.12))
    c.closeSubpath()
    ctx.addPath(c); ctx.fillPath()
    ctx.restoreGState()
}

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x000000, 0.35))

if variant == "4A" {
    // 미니멀: 흰 노트 사각형 + 흰 펜 막대. 노트는 가운데, 펜은 우측 위에서 대각선.
    let note = CGRect(x: 240, y: 232, width: 470, height: 580)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.addPath(roundedRect(note, 56)); ctx.fillPath()
    // 줄 세 개(배경색으로 살짝)
    ctx.setFillColor(rgb(0x1E3A8A, 0.18))
    for i in 0..<3 {
        ctx.addPath(roundedRect(CGRect(x: note.minX + 78, y: note.minY + 150 + CGFloat(i) * 110, width: i == 2 ? 180 : 314, height: 26), 13))
        ctx.fillPath()
    }
    // 펜: 우상단에서 노트 우하단 쪽으로
    drawPen(from: CGPoint(x: 860, y: 230), to: CGPoint(x: 560, y: 770), width: 96,
            body: rgb(0xFFFFFF), tip: rgb(0xFFFFFF), ring: rgb(0x1E3A8A, 0.25))
} else {
    // 3B: 노트 위에 펜촉이 닿아 있고 잉크 획이 나오는 모습. 펜은 하늘색.
    let note = CGRect(x: 200, y: 250, width: 520, height: 600)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.addPath(roundedRect(note, 56)); ctx.fillPath()
    // 노트 줄
    ctx.setFillColor(rgb(0x1E3A8A, 0.16))
    for i in 0..<2 {
        ctx.addPath(roundedRect(CGRect(x: note.minX + 76, y: note.minY + 140 + CGFloat(i) * 100, width: 300, height: 24), 12))
        ctx.fillPath()
    }
    // 잉크 획: 펜촉에서 왼쪽 아래로 흐르는 곡선
    ctx.setStrokeColor(rgb(0x2563EB))
    ctx.setLineWidth(30)
    ctx.setLineCap(.round)
    let ink = CGMutablePath()
    ink.move(to: CGPoint(x: 278, y: 690))
    ink.addCurve(to: CGPoint(x: 552, y: 612), control1: CGPoint(x: 340, y: 760), control2: CGPoint(x: 470, y: 760))
    ctx.addPath(ink); ctx.strokePath()
    // 펜: 우상단에서 획의 끝(552,612)로 내려와 닿음
    drawPen(from: CGPoint(x: 880, y: 210), to: CGPoint(x: 552, y: 612), width: 100,
            body: rgb(0xBFDBFE), tip: rgb(0xFFFFFF), ring: rgb(0xFFFFFF, 0.95))
}
ctx.restoreGState()

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
