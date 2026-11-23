import SwiftUI

/// Draws waveform columns coloured by frequency, the way club DJ software does: red for the
/// bass, green for the mids, blue for the highs, mixed by how strong each is in that column
/// (bass and mids give yellow, everything gives white). Height still shows loudness.
///
/// Columns are grouped by colour (six steps per channel) so a frame draws a few hundred
/// fills, not one per column.
struct SpectrumPainter {
    private var paths: [Int: Path] = [:]
    private static let steps = 6

    mutating func add(_ rect: CGRect, low: Float, mid: Float, high: Float) {
        // Each band's level is scaled to its own peak, so in a full mix all three are high and
        // everything would turn white. Squaring adds contrast, and the weights let the kick
        // read red, as in club software.
        let l = low * low * 1.0, m = mid * mid * 0.75, h = high * high * 0.6
        let top = max(l, m, h, 1e-4)
        func q(_ v: Float) -> Int { min(Self.steps - 1, Int((v / top) * Float(Self.steps - 1) + 0.5)) }
        let key = (q(l) * Self.steps + q(m)) * Self.steps + q(h)
        paths[key, default: Path()].addRect(rect)
    }

    func fill(_ ctx: GraphicsContext, opacity: Double) {
        let n = Double(Self.steps - 1)
        for (key, path) in paths {
            let r = Double(key / (Self.steps * Self.steps)), g = Double((key / Self.steps) % Self.steps), b = Double(key % Self.steps)
            // Lift dark mixes a little so quiet colours still read on the dark lane.
            let c = Color(red: 0.12 + 0.88 * r / n, green: 0.12 + 0.88 * g / n, blue: 0.12 + 0.88 * b / n)
            ctx.fill(path, with: .color(c.opacity(opacity)))
        }
    }
}
