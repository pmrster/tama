import AppKit

// Renders the Tama cat app icon to a 1024×1024 PNG (Packaging/icon-1024.png).
// Run: swift Packaging/make-icon.swift

let size = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// Rounded background with a warm dark gradient.
let canvas = NSRect(x: 40, y: 40, width: size - 80, height: size - 80)
let bgPath = NSBezierPath(roundedRect: canvas, xRadius: 220, yRadius: 220)
let grad = NSGradient(colors: [
    NSColor(red: 0.16, green: 0.14, blue: 0.11, alpha: 1),
    NSColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 1),
])
grad?.draw(in: bgPath, angle: -90)

// Soft glow behind the cat.
let glow = NSBezierPath(ovalIn: NSRect(x: 300, y: 300, width: 424, height: 424))
NSColor(red: 0.97, green: 0.80, blue: 0.24, alpha: 0.10).setFill()
glow.fill()

// Side-view cat, traced from cat/meow1.svg (same sprite the menu-bar pet uses).
let grid = [
    "........................",
    "...........YY.....YY....",
    "..........YYYY...YYYY...",
    "..........YYYYYYYYYYY...",
    ".........YYYYYYYYYYYYY..",
    ".........YYYYYYYYYYYYY..",
    "..YY.....YYYYEYYYYYEYY..",
    "..YYY...YYYYYEYYYYYEYY..",
    "...YYYYYYYYYYEYYEYYEYY..",
    "....YYYYYYYYYYYYYYYYYY..",
    "......YYYYYYYYYYYYYYYY..",
    "......YYYYYYYYYYYYYYY...",
    "......YYYYYYYYYYYYYY....",
    "......YYYYYYYYYYYYYY....",
    "......YY..YYY.YY..Y.....",
]
let cols = 24, rows = grid.count
let pxSize: CGFloat = 36
let gridW = CGFloat(cols) * pxSize
let gridH = CGFloat(rows) * pxSize
let ox = (CGFloat(size) - gridW) / 2
let oy = (CGFloat(size) - gridH) / 2 + 20

func color(_ ch: Character) -> NSColor? {
    switch ch {
    case "Y": return NSColor(red: 0.953, green: 0.741, blue: 0.310, alpha: 1) // #F3BD4F
    case "E": return NSColor(red: 0.106, green: 0.102, blue: 0.094, alpha: 1) // #1B1A18
    case "N": return NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
    default: return nil
    }
}

for (r, row) in grid.enumerated() {
    for (c, ch) in row.enumerated() {
        guard let col = color(ch) else { continue }
        col.setFill()
        // Flip row index: AppKit origin is bottom-left.
        let rect = NSRect(x: ox + CGFloat(c) * pxSize,
                          y: oy + CGFloat(rows - 1 - r) * pxSize,
                          width: pxSize + 1.5, height: pxSize + 1.5)
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
    }
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr); exit(1)
}
let out = URL(fileURLWithPath: "Packaging/icon-1024.png")
try! png.write(to: out)
print("wrote \(out.path)")
