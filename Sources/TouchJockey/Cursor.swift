import AppKit
import SwiftUI

/// Cursors that show what you can do with something under the pointer:
/// a pointing hand for anything clickable, resize arrows for sliders.
extension View {
    /// Pointing-hand cursor while hovering: "you can click this".
    func pointingHandCursor() -> some View { cursor(.pointingHand) }

    /// Up/down or left/right arrows while hovering: "you can slide this".
    func slideCursor(_ axis: Axis) -> some View { cursor(axis == .vertical ? .resizeUpDown : .resizeLeftRight) }

    /// Sets `cursor` while the pointer is inside (when `enabled`), and the arrow when it leaves.
    func cursor(_ cursor: NSCursor, enabled: Bool = true) -> some View {
        onHover { inside in
            if inside && enabled { cursor.set() } else { NSCursor.arrow.set() }
        }
    }
}
