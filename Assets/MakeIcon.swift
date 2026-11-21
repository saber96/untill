import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

func render(_ pixels: Int, name: String) throws {
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CocoaError(.fileWriteUnknown) }
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    let tile = CGPath(roundedRect: CGRect(x: 92, y: 92, width: 840, height: 840),
                      cornerWidth: 193, cornerHeight: 193, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -17), blur: 35, color: color(0.05, 0.12, 0.22, 0.44))
    context.setFillColor(color(0.09, 0.13, 0.27))
    context.addPath(tile)
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(tile)
    context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [
        color(0.13, 0.28, 0.54), color(0.08, 0.12, 0.25), color(0.10, 0.08, 0.20)
    ] as CFArray, locations: [0, 0.68, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 155, y: 885),
                               end: CGPoint(x: 840, y: 124), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
    context.setStrokeColor(color(0.7, 0.82, 1.0, 0.31))
    context.setLineWidth(8)
    context.addPath(tile)
    context.strokePath()

    context.setStrokeColor(color(0.50, 0.72, 1, 0.27))
    context.setLineWidth(8)
    context.strokeEllipse(in: CGRect(x: 251, y: 251, width: 522, height: 522))

    for index in 0..<8 {
        let angle = CGFloat(index) * .pi / 4
        let x = 512 + sin(angle) * 261
        let y = 512 + cos(angle) * 261
        let radius: CGFloat = index == 1 ? 63 : 47
        context.setFillColor(index == 1 ? color(0.49, 1, 0.81) : color(0.72, 0.84, 1, 0.93))
        context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

    let pointer = CGMutablePath()
    pointer.move(to: CGPoint(x: 429, y: 600))
    pointer.addLine(to: CGPoint(x: 628, y: 495))
    pointer.addLine(to: CGPoint(x: 544, y: 474))
    pointer.addLine(to: CGPoint(x: 584, y: 397))
    pointer.addLine(to: CGPoint(x: 535, y: 372))
    pointer.addLine(to: CGPoint(x: 495, y: 449))
    pointer.addLine(to: CGPoint(x: 452, y: 374))
    pointer.closeSubpath()
    context.setFillColor(color(0.96, 0.98, 1))
    context.setStrokeColor(color(0.96, 0.98, 1))
    context.setLineWidth(12)
    context.setLineJoin(.round)
    context.addPath(pointer)
    context.drawPath(using: .fillStroke)
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL,
                                                            UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

for size in [16, 32, 128, 256, 512] {
    try render(size, name: "icon_\(size)x\(size).png")
    try render(size * 2, name: "icon_\(size)x\(size)@2x.png")
}
