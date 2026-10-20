import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func context(width: Int, height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func drawIcon(_ ctx: CGContext, color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(1.5)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 2.75, y: 8.25, width: 16.5, height: 11),
                       cornerWidth: 1.75, cornerHeight: 1.75, transform: nil))
    ctx.strokePath()
    ctx.saveGState()
    ctx.translateBy(x: 3.1, y: 7.9)
    ctx.rotate(by: -.pi / 20)
    ctx.translateBy(x: -3.1, y: -7.9)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 3.1, y: 4.7, width: 15.8, height: 3.2),
                       cornerWidth: 0.55, cornerHeight: 0.55, transform: nil))
    ctx.strokePath()
    for x in [7.6, 12.7] {
        ctx.move(to: CGPoint(x: x, y: 4.7))
        ctx.addLine(to: CGPoint(x: x + 1.5, y: 7.9))
    }
    ctx.strokePath()
    ctx.restoreGState()
    ctx.strokeEllipse(in: CGRect(x: 7.6, y: 10.7, width: 5.1, height: 5.1))
    ctx.move(to: CGPoint(x: 12, y: 15.1))
    ctx.addLine(to: CGPoint(x: 14.85, y: 17.5))
    ctx.strokePath()
}

func save(_ ctx: CGContext, name: String) {
    let path = output.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    print(path.path)
}

for (size, name) in [(22, "Carfo-menubar.png"), (44, "Carfo-menubar@2x.png"), (512, "Carfo-menubar-master.png")] {
    let ctx = context(width: size, height: size)
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: CGFloat(size) / 22, y: -CGFloat(size) / 22)
    drawIcon(ctx, color: CGColor(gray: 0, alpha: 1))
    save(ctx, name: name)
}

let preview = context(width: 320, height: 112)
preview.setFillColor(CGColor(gray: 0.97, alpha: 1))
preview.fill(CGRect(x: 0, y: 0, width: 160, height: 112))
preview.setFillColor(CGColor(gray: 0.12, alpha: 1))
preview.fill(CGRect(x: 160, y: 0, width: 160, height: 112))
for (x, size, gray) in [(28.0, 22.0, 0.0), (81.0, 44.0, 0.0), (188.0, 22.0, 1.0), (241.0, 44.0, 1.0)] {
    preview.saveGState()
    preview.translateBy(x: x, y: (112 + size) / 2)
    preview.scaleBy(x: size / 22, y: -size / 22)
    drawIcon(preview, color: CGColor(gray: gray, alpha: 1))
    preview.restoreGState()
}
save(preview, name: "Carfo-menubar-preview.png")
