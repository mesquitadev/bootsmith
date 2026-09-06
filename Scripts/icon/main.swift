import AppKit
import CoreGraphics

/// Gera o iconset do Bootsmith. Desenhado por código para que qualquer ajuste seja
/// um diff revisável e as dez resoluções saiam sempre consistentes.
///
/// A forma: uma seta descendo para dentro de um dispositivo — a imagem entrando
/// no pendrive.
func drawIcon(size: CGFloat, context ctx: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.setAllowsAntialiasing(true)

    let inset = size * 0.086
    let plate = rect.insetBy(dx: inset, dy: inset)
    let radius = plate.width * 0.2237
    let shape = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Laranja de forja, escurecendo para baixo.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let colors = [
        NSColor(srgbRed: 0.98, green: 0.62, blue: 0.20, alpha: 1).cgColor,
        NSColor(srgbRed: 0.96, green: 0.42, blue: 0.16, alpha: 1).cgColor,
        NSColor(srgbRed: 0.85, green: 0.24, blue: 0.20, alpha: 1).cgColor,
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: plate.minX, y: plate.maxY),
                           end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
    ctx.setBlendMode(.softLight)
    ctx.setFillColor(NSColor(white: 1, alpha: 0.30).cgColor)
    ctx.move(to: CGPoint(x: plate.minX, y: plate.maxY))
    ctx.addLine(to: CGPoint(x: plate.maxX, y: plate.maxY))
    ctx.addLine(to: CGPoint(x: plate.minX, y: plate.midY))
    ctx.closePath()
    ctx.fillPath()
    ctx.setBlendMode(.normal)
    ctx.restoreGState()

    let center = CGPoint(x: plate.midX, y: plate.midY)
    let white = NSColor.white.cgColor

    // O corpo do pendrive: um retângulo arredondado na metade de baixo, com o
    // conector saindo por cima.
    ctx.saveGState()
    ctx.setFillColor(white)
    let bodyWidth = plate.width * 0.40
    let bodyHeight = plate.height * 0.26
    let body = CGRect(x: center.x - bodyWidth / 2,
                      y: plate.minY + plate.height * 0.16,
                      width: bodyWidth, height: bodyHeight)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: bodyWidth * 0.16,
                       cornerHeight: bodyWidth * 0.16, transform: nil))
    ctx.fillPath()

    let neckWidth = plate.width * 0.17
    let neck = CGRect(x: center.x - neckWidth / 2, y: body.maxY,
                      width: neckWidth, height: plate.height * 0.075)
    ctx.addPath(CGPath(roundedRect: neck, cornerWidth: neckWidth * 0.2,
                       cornerHeight: neckWidth * 0.2, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()

    // A seta que desce até o conector.
    ctx.saveGState()
    ctx.setFillColor(white)
    let stem = plate.width * 0.085
    let arrowTop = plate.maxY - plate.height * 0.14
    let headHeight = plate.height * 0.135
    let headWidth = plate.width * 0.235
    let arrowBottom = neck.maxY + plate.height * 0.055

    let stemRect = CGRect(x: center.x - stem / 2, y: arrowBottom + headHeight - stem * 0.4,
                          width: stem, height: arrowTop - arrowBottom - headHeight + stem * 0.4)
    ctx.addPath(CGPath(roundedRect: stemRect, cornerWidth: stem / 2,
                       cornerHeight: stem / 2, transform: nil))
    ctx.fillPath()

    ctx.setLineJoin(.round)
    ctx.setLineWidth(plate.width * 0.03)
    ctx.setStrokeColor(white)
    ctx.move(to: CGPoint(x: center.x - headWidth / 2, y: arrowBottom + headHeight))
    ctx.addLine(to: CGPoint(x: center.x, y: arrowBottom))
    ctx.addLine(to: CGPoint(x: center.x + headWidth / 2, y: arrowBottom + headHeight))
    ctx.closePath()
    ctx.drawPath(using: .fillStroke)
    ctx.restoreGState()
}

func writePNG(size: Int, to url: URL) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(size: CGFloat(size), context: ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: size, height: size)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (size, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"),
                     (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"),
                     (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"),
                     (1024, "icon_512x512@2x")] {
    writePNG(size: size, to: out.appending(path: "\(name).png"))
}
