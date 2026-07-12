import SwiftUI
import TamaCore

/// A 7×24 weekday×hour token grid (Mon…Sun rows, 0…23 cols). Cell shade = tokens, log-scaled
/// so a few heavy hours don't wash out the rest. Fed by `AppState.hourlyActivity` (168 ints,
/// Calendar weekday 1=Sun). Claude-only, last ~30 days, user's local time.
struct UsageHeatmap: View {
    let grid: [Int]                 // 168; index (weekday-1)*24 + hour

    private static let rowLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Calendar weekday (1=Sun…7=Sat) → Mon-first row (Mon→0 … Sun→6).
    private func cell(row: Int, hour: Int) -> Int {
        // row 0=Mon → weekday 2; row 6=Sun → weekday 1. weekday = (row+1)%7 + 1.
        let weekday = (row + 1) % 7 + 1
        return (weekday - 1) * 24 + hour
    }

    private var maxCell: Int { grid.max() ?? 0 }

    private func intensity(_ tokens: Int) -> Double {
        guard maxCell > 0, tokens > 0 else { return 0 }
        return log1p(Double(tokens)) / log1p(Double(maxCell))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: 1) {
                    Text(Self.rowLabels[row])
                        .font(.system(size: scaled(7), design: .monospaced))
                        .foregroundStyle(Palette.dim).frame(width: 22, alignment: .leading)
                    ForEach(0..<24, id: \.self) { hour in
                        let tok = grid.indices.contains(cell(row: row, hour: hour)) ? grid[cell(row: row, hour: hour)] : 0
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Palette.yellow.opacity(0.12 + 0.88 * intensity(tok)))
                            .frame(maxWidth: .infinity)
                            .frame(height: 7)
                            .help("\(Self.rowLabels[row]) \(String(format: "%02d", hour)):00 · \(formatTokens(tok)) tok")
                    }
                }
            }
            HStack(spacing: 1) {
                Spacer().frame(width: 22)
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    Text("\(h)").font(.system(size: scaled(6), design: .monospaced))
                        .foregroundStyle(Palette.dim.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Claude only · last 30 days · your local time")
                .font(.system(size: scaled(7.5))).foregroundStyle(Palette.dim.opacity(0.7))
        }
    }
}
