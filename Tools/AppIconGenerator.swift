// アプリアイコン（ライト / ダーク / ティント）を生成するスクリプト。
//
// 使い方:
//   cd Otanecho/Resources/Assets.xcassets/AppIcon.appiconset
//   xcrun swift ../../../../Tools/AppIconGenerator.swift
//
// カレントディレクトリに AppIcon.png / AppIcon-Dark.png / AppIcon-Tinted.png を書き出す。
// デザイン: 紙の罫線から芽が出る「お種帳」のモチーフ。

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024

struct P { var x: CGFloat; var y: CGFloat }

/// 葉っぱ形（根元 base から先端 tip へ、左右対称にふくらむレンズ形）
func leafPath(base: P, tip: P, bulge: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let dx = tip.x - base.x, dy = tip.y - base.y
    let mx = base.x + dx / 2, my = base.y + dy / 2
    let px = -dy * bulge, py = dx * bulge
    path.move(to: CGPoint(x: base.x, y: base.y))
    path.addQuadCurve(to: CGPoint(x: tip.x, y: tip.y), control: CGPoint(x: mx + px, y: my + py))
    path.addQuadCurve(to: CGPoint(x: base.x, y: base.y), control: CGPoint(x: mx - px, y: my - py))
    path.closeSubpath()
    return path
}

func render(to url: URL, background: (CGColor, CGColor)?, mark: CGColor, lines: CGColor?) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // CoreGraphics は原点が左下なので、上下を反転して「上が上」の座標で描く
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    if let (top, bottom) = background {
        let gradient = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
    }

    // ノートの罫線（種が紙から芽吹くイメージ）
    if let lines {
        ctx.setStrokeColor(lines)
        ctx.setLineCap(.round)
        ctx.setLineWidth(26)
        for (y, half) in [(CGFloat(661), CGFloat(214)), (CGFloat(745), CGFloat(140))] {
            ctx.move(to: CGPoint(x: 512 - half, y: y))
            ctx.addLine(to: CGPoint(x: 512 + half, y: y))
            ctx.strokePath()
        }
    }

    ctx.setFillColor(mark)
    ctx.setStrokeColor(mark)

    // 茎
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: 510, y: 655))
    stem.addCurve(to: CGPoint(x: 510, y: 395),
                  control1: CGPoint(x: 492, y: 565),
                  control2: CGPoint(x: 528, y: 475))
    ctx.setLineWidth(40)
    ctx.setLineCap(.round)
    ctx.addPath(stem)
    ctx.strokePath()

    // 左の葉（下寄り・大きめ）
    ctx.addPath(leafPath(base: P(x: 505, y: 525), tip: P(x: 225, y: 405), bulge: 0.30))
    ctx.fillPath()
    // 右の葉（上寄り）
    ctx.addPath(leafPath(base: P(x: 510, y: 435), tip: P(x: 800, y: 265), bulge: 0.30))
    ctx.fillPath()

    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let out = URL(fileURLWithPath: ".")
render(to: out.appending(path: "AppIcon.png"),
       background: (rgb(46, 148, 94), rgb(23, 94, 62)),
       mark: rgb(252, 250, 240),
       lines: rgb(255, 255, 255, 0.28))
render(to: out.appending(path: "AppIcon-Dark.png"),
       background: (rgb(20, 62, 43), rgb(9, 33, 23)),
       mark: rgb(150, 216, 176),
       lines: rgb(150, 216, 176, 0.22))
render(to: out.appending(path: "AppIcon-Tinted.png"),
       background: nil,
       mark: rgb(255, 255, 255),
       lines: rgb(255, 255, 255, 0.35))
print("rendered")
