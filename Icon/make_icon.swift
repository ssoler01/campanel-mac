import Cocoa

// Genera AppIcon.icns: squircle azul con una lente de cámara.
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: body, xRadius: 190, yRadius: 190)
ctx.saveGState()
path.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.61, blue: 1.0, alpha: 1),
                    NSColor(srgbRed: 0.15, green: 0.34, blue: 0.84, alpha: 1)])!
    .draw(in: body, angle: -60)
ctx.restoreGState()

func circle(_ r: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: 512 - r, y: 512 - r, width: 2 * r, height: 2 * r)).fill()
}
circle(250, NSColor(white: 1, alpha: 0.95))
circle(200, NSColor(srgbRed: 0.07, green: 0.10, blue: 0.2, alpha: 1))
circle(135, NSColor(srgbRed: 0.16, green: 0.30, blue: 0.62, alpha: 1))
circle(60, NSColor(srgbRed: 0.07, green: 0.10, blue: 0.2, alpha: 1))
NSColor(white: 1, alpha: 0.55).setFill()
NSBezierPath(ovalIn: NSRect(x: 440, y: 560, width: 60, height: 60)).fill()
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
