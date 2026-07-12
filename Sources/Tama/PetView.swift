import SwiftUI
import TamaCore

/// Tama — warm-yellow 8-bit cat mascot.
/// Two-frame side-view walk traced from the cat/meow1.svg (contact) and
/// cat/meow2.svg (passing) designs. Head stays level-ish; tail and legs animate.
struct PetView: View {
    let mood: Mood

    /// Walk speed / liveliness. Working & greeting walk; resting & napping are still.
    private var energy: Int {
        switch mood {
        case .working(let intensity): return max(1, intensity)
        case .greeting: return 2
        case .resting, .napping: return 0
        }
    }
    private var isNapping: Bool { if case .napping = mood { return true } else { return false } }
    /// Dev-only (README snapshots): freeze the animation clock to this value so the rendered
    /// frame is deterministic and "meow~" is visible. `nil` (the default) = live wall clock.
    var snapshotTime: Double? = nil

    private nonisolated static let px: CGFloat = 2.0

    // Pixel legend:  Y = warm yellow body   E = dark eyes / nose   . = empty
    // 24 cols x 15 rows. Frames are bottom-right anchored so the head and eyes
    // line up; the body bobs 1px between frames for a natural step.

    // Frame 1 — contact pose: tail low, legs gathered (meow1.svg)
    private static let frame1 = [
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

    // Frame 2 — passing pose: tail raised, legs mid-stride, front foot kicked (meow2.svg)
    private static let frame2 = [
        "...........YY.....YY....",
        "..........YYYY...YYYY...",
        "..........YYYYYYYYYYY...",
        ".........YYYYYYYYYYYYY..",
        ".........YYYYYYYYYYYYY..",
        "YY.......YYYYEYYYYYEYY..",
        "YYY...YYYYYYYEYYYYYEYY..",
        ".YYYYYYYYYYYYEYYEYYEYY..",
        "..YYYYYYYYYYYYYYYYYYYY..",
        ".....YYYYYYYYYYYYYYYYY..",
        ".....YYYYYYYYYYYYYYYY...",
        ".....YYYYYYYYYYYYYY.....",
        "....YYYYYYYYYYYYYY......",
        "...YYYYY....YY...YY.....",
        "...YYY.YY...YY..........",
    ]

    private static let walk = [frame1, frame2]

    // Nap pose: frame 1 body with eyes closed to gentle dashes.
    private static let nap = [
        "........................",
        "...........YY.....YY....",
        "..........YYYY...YYYY...",
        "..........YYYYYYYYYYY...",
        ".........YYYYYYYYYYYYY..",
        ".........YYYYYYYYYYYYY..",
        "..YY.....YYYYYYYYYYYYY..",
        "..YYY...YYYYEEEYYYEEEY..",
        "...YYYYYYYYYYYYYYYYYYY..",
        "....YYYYYYYYYYYYYYYYYY..",
        "......YYYYYYYYYYYYYYYY..",
        "......YYYYYYYYYYYYYYY...",
        "......YYYYYYYYYYYYYY....",
        "......YYYYYYYYYYYYYY....",
        "......YY..YYY.YY..Y.....",
    ]

    private static let cols = 24
    private static let rows = 15
    private static let walkPaths = walk.map(makeFrame)
    private static let napPath = makeFrame(nap)

    private struct SpriteFrame {
        let yellow: Path
        let dark: Path
    }

    // Traced straight from the SVG fills.
    private let yellow = Color(red: 0.953, green: 0.741, blue: 0.310) // #F3BD4F
    private let dark = Color(red: 0.106, green: 0.102, blue: 0.094)   // #1B1A18
    private let ground = Color(red: 0.30, green: 0.27, blue: 0.24)

    var body: some View {
        let spriteW = CGFloat(Self.cols) * Self.px
        let spriteH = CGFloat(Self.rows) * Self.px

        // Fill the available width so the walk range follows the (resizable) pinned
        // window — the cat paces across whatever width the widget currently is.
        GeometryReader { geo in
            let w = max(spriteW + 12, geo.size.width)
            TimelineView(.periodic(from: .now, by: energy > 0 ? 0.2 : 0.5)) { timeline in
                let t = snapshotTime ?? timeline.date.timeIntervalSinceReferenceDate
                let m = motion(t: t, spriteW: spriteW, width: w)

                ZStack(alignment: .bottomLeading) {
                    groundLine

                    ZStack(alignment: .bottomLeading) {
                        Canvas { ctx, _ in
                            draw(ctx, frame: m.frame)
                        }
                        .frame(width: spriteW, height: spriteH)
                        .scaleEffect(x: m.facingLeft ? -1 : 1, y: 1)

                        if energy > 0 && meowVisible(t) {
                            Text("meow~")
                                .font(.system(size: scaled(7), weight: .bold, design: .monospaced))
                                .foregroundStyle(yellow.opacity(0.85))
                                .fixedSize()
                                .offset(x: spriteW + 2, y: -spriteH / 2 - 4)
                        }
                        if isNapping {
                            sleepZ(t: t, spriteW: spriteW, spriteH: spriteH)
                        }
                    }
                    .offset(x: m.x, y: m.bob - 2)
                }
                .frame(width: w, height: geo.size.height, alignment: .bottomLeading)
            }
        }
        .frame(height: spriteH + 4)
        .accessibilityHidden(true)
    }

    /// Sleeping "z"s drifting up from the napping cat's head, looping every 3s.
    private func sleepZ(t: Double, spriteW: CGFloat, spriteH: CGFloat) -> some View {
        let loop = t.truncatingRemainder(dividingBy: 3.0) / 3.0
        return ZStack(alignment: .bottomLeading) {
            ForEach(0..<3, id: \.self) { i in
                let p = (loop + Double(i) / 3.0).truncatingRemainder(dividingBy: 1.0)
                Text("z")
                    .font(.system(size: scaled(6) + CGFloat(i) * 2, weight: .heavy, design: .rounded))
                    .foregroundStyle(yellow.opacity(0.85 * (1.0 - p)))
                    .fixedSize()
                    .offset(x: spriteW * 0.62 + CGFloat(p) * 7,
                            y: -spriteH * 0.55 - CGFloat(p) * 16)
            }
        }
    }

    private var groundLine: some View {
        Rectangle()
            .fill(ground)
            .frame(height: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private nonisolated static func makeFrame(_ frame: [String]) -> SpriteFrame {
        var yellow = Path()
        var dark = Path()
        for (r, row) in frame.enumerated() {
            for (c, ch) in row.enumerated() {
                let rect = CGRect(
                    x: CGFloat(c) * px,
                    y: CGFloat(r) * px,
                    width: px + 0.35,
                    height: px + 0.35
                )
                switch ch {
                case "Y": yellow.addRect(rect)
                case "E": dark.addRect(rect)
                default: continue
                }
            }
        }
        return SpriteFrame(yellow: yellow, dark: dark)
    }

    private func draw(_ ctx: GraphicsContext, frame: SpriteFrame) {
        ctx.fill(frame.yellow, with: .color(yellow))
        ctx.fill(frame.dark, with: .color(dark))
    }

    private func meowVisible(_ t: Double) -> Bool {
        energy > 0 && t.truncatingRemainder(dividingBy: 7.0) < 1.0
    }

    private func motion(
        t: Double,
        spriteW: CGFloat,
        width: CGFloat
    ) -> (x: CGFloat, facingLeft: Bool, frame: SpriteFrame, bob: CGFloat) {
        let margin: CGFloat = 6
        let range = Double(max(10, width - spriteW - margin * 2))

        guard energy > 0 else {
            // Napping → curled nap pose with z's; resting → awake but still (frame 1).
            return (
                x: margin + CGFloat(range / 2),
                facingLeft: false,
                frame: isNapping ? Self.napPath : Self.walkPaths[0],
                bob: 0
            )
        }

        // Slower than before so it feels cuter, not frantic.
        let speed = 28.0 + Double(min(energy, 8)) * 10.0

        let phase = (t * speed / range).truncatingRemainder(dividingBy: 2)
        let p = phase < 0 ? phase + 2 : phase

        let x = p < 1 ? p * range : (2 - p) * range
        let facingLeft = p >= 1

        // Two-frame walk cycle; the frames already encode the body bob.
        let stepHz = 3.2 + Double(min(energy, 6)) * 0.4
        let frameIndex = Int(t * stepHz) % Self.walkPaths.count
        let frame = Self.walkPaths[frameIndex]

        return (
            x: margin + CGFloat(x),
            facingLeft: facingLeft,
            frame: frame,
            bob: 0
        )
    }
}
