// Генератор иконки приложения: swift scripts/make_icon.swift SpeakCheck/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let bg = CGGradient(colorsSpace: space, colors: [rgb(0x15254A).cgColor, rgb(0x0B1426).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
let glow = CGGradient(colorsSpace: space, colors: [rgb(0x2563EB, 0.5).cgColor, rgb(0x2563EB, 0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 480, options: [])

let heights: [Double] = [0.18, 0.34, 0.56, 0.78, 0.56, 0.92, 0.62, 0.40, 0.24]
let barW = 58.0, gap = 30.0
let total = Double(heights.count) * barW + Double(heights.count - 1) * gap
var x = (size - total) / 2
for (i, h) in heights.enumerated() {
    let hh = h * 600
    let t = CGFloat(i) / CGFloat(heights.count - 1)
    NSColor(red: 0.145 + 0.075 * t, green: 0.388 + 0.353 * t, blue: 0.922 + 0.051 * t, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: x, y: (size - hh) / 2, width: barW, height: hh), xRadius: barW / 2, yRadius: barW / 2).fill()
    x += barW + gap
}

rgb(0x34D399).setFill()
NSBezierPath(ovalIn: CGRect(x: 700, y: 140, width: 220, height: 220)).fill()
let check = NSBezierPath()
check.move(to: NSPoint(x: 752, y: 252))
check.line(to: NSPoint(x: 795, y: 207))
check.line(to: NSPoint(x: 868, y: 296))
check.lineWidth = 28
check.lineCapStyle = .round
check.lineJoinStyle = .round
rgb(0x101C32).setStroke()
check.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("ok")
