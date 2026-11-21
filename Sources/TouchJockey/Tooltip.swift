import AppKit
import SwiftUI

/// App-styled tooltips: large text in a dark bubble with a gold border.
///
/// Tooltips are drawn by one layer over the whole window (not inside the control),
/// so panels that clip their content can't cut them off. A control marks itself with
/// `.tip("…")`; hovering it for half a second shows the bubble just below it.
///
/// A sheet is a separate window, so it has its own layer and coordinate space
/// (see `.tooltipScope(_:)`); each layer only draws tips from its own space.
final class TooltipCenter: ObservableObject {
    static let shared = TooltipCenter()
    @Published private(set) var text: String?
    @Published private(set) var anchor: CGRect = .zero
    /// The coordinate space (and so the layer) the current tip belongs to.
    @Published private(set) var space = tooltipSpace
    private var owner: UUID?

    func show(_ text: String, at anchor: CGRect, in space: String, owner id: UUID) {
        guard !text.isEmpty else { return }
        _ = escMonitor
        self.text = text
        self.anchor = anchor
        self.space = space
        owner = id
    }

    /// Hides whatever tip is showing, for example when a sheet opens over it.
    func hideAll() {
        text = nil
        owner = nil
    }

    func isShowing(owner id: UUID) -> Bool { owner == id && text != nil }

    /// Esc closes whatever help or tooltip is open.
    private lazy var escMonitor: Any? = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
        if e.keyCode == 53, let self, self.text != nil { self.text = nil; self.owner = nil; return nil }
        return e
    }

    func hide(owner id: UUID) {
        guard owner == id else { return }
        text = nil
        owner = nil
    }
}

/// The coordinate space tooltips are positioned in (the window's content).
let tooltipSpace = "tjTooltipSpace"

private struct TooltipSpaceKey: EnvironmentKey { static let defaultValue = tooltipSpace }

extension EnvironmentValues {
    /// Which tooltip layer the tips below this view go to.
    var tooltipSpaceName: String {
        get { self[TooltipSpaceKey.self] }
        set { self[TooltipSpaceKey.self] = newValue }
    }
}

private struct TipModifier: ViewModifier {
    let text: String
    var delay: Double = 0.5
    @State private var id = UUID()
    @State private var frame: CGRect = .zero
    @State private var hovering = false
    @Environment(\.tooltipSpaceName) private var space

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .named(space)) }
                    .onChange(of: g.frame(in: .named(space))) { frame = $0 }
            })
            .onHover { inside in
                hovering = inside
                if inside {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        if hovering { TooltipCenter.shared.show(text, at: frame, in: space, owner: id) }
                    }
                } else {
                    TooltipCenter.shared.hide(owner: id)
                }
            }
            .onDisappear { TooltipCenter.shared.hide(owner: id) }
            .accessibilityHint(text)
    }
}

/// For controls the pointer sits on for a long time (sliders): the tooltip only appears
/// after the pointer has rested, without moving, for `stillFor` seconds. Any movement,
/// or pressing to drag, hides it, and it won't come back until the pointer rests again.
private struct StillTipModifier: ViewModifier {
    let text: String
    let stillFor: Double
    @State private var id = UUID()
    @State private var frame: CGRect = .zero
    @State private var lastMove = Date.distantPast
    @State private var inside = false
    @State private var pressed = false
    @Environment(\.tooltipSpaceName) private var space

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .named(space)) }
                    .onChange(of: g.frame(in: .named(space))) { frame = $0 }
            })
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    inside = true
                    let moved = Date()
                    lastMove = moved
                    TooltipCenter.shared.hide(owner: id)
                    DispatchQueue.main.asyncAfter(deadline: .now() + stillFor) {
                        // Show only if nothing moved since, the pointer is still here, and no drag is on.
                        if inside, !pressed, lastMove == moved {
                            TooltipCenter.shared.show(text, at: frame, in: space, owner: id)
                        }
                    }
                case .ended:
                    inside = false
                    TooltipCenter.shared.hide(owner: id)
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed { pressed = true; TooltipCenter.shared.hide(owner: id) }
                }
                .onEnded { _ in pressed = false; lastMove = Date() })
            .onDisappear { TooltipCenter.shared.hide(owner: id) }
            .accessibilityHint(text)
    }
}

extension View {
    /// Tooltip for sliders and other controls the pointer rests on while using them:
    /// shown only after the pointer stays still over it for `stillFor` seconds (default 1).
    func sliderTip(_ text: String, stillFor: Double = 1.0) -> some View {
        modifier(StillTipModifier(text: text, stillFor: stillFor))
    }

    /// Tooltip for a control: appears only after the pointer has rested on it, without moving,
    /// for 1 second, and hides on any movement or press. Use it only where a beginner wouldn't
    /// understand the control from its label (see AGENTS.md).
    func tip(_ text: String) -> some View { modifier(StillTipModifier(text: text, stillFor: 1.0)) }

    /// Tooltip shown after a fixed delay, even while the pointer moves. Only for things whose
    /// whole purpose is to show help on hover, like the ⓘ help icons.
    func tip(_ text: String, delay: Double) -> some View { modifier(TipModifier(text: text, delay: delay)) }

    /// Gives this view (a window's or sheet's root) its own tooltip layer and coordinate space.
    func tooltipScope(_ name: String) -> some View {
        coordinateSpace(name: name)
            .overlay(TooltipLayer(space: name))
            .environment(\.tooltipSpaceName, name)
    }
}

/// Setting that hides every info icon once a user no longer needs them (View → Show Help Icons).
let infoTipsKey = "showInfoTips"

/// A small ⓘ icon that explains the thing next to it. **Click** to read; it doesn't open on hover.
///
/// Used instead of explainer text in the layout, so beginners get plenty of help
/// without it taking up screen space. Hidden entirely when Show Help Icons is off.
struct InfoTip: View {
    let text: String
    @AppStorage(infoTipsKey) private var showInfoTips = true

    init(_ text: String) { self.text = text }

    var body: some View {
        if showInfoTips {
            Image(systemName: "info.circle")
                .font(.tj(13, weight: .semibold))
                .foregroundColor(TJ.gold)
                .contentShape(Circle())
                .pointingHandCursor()
                .modifier(ClickTipModifier(text: text))
        }
    }
}

/// Help that opens on click and stays open while you read it: clicking the icon again,
/// opening another help icon, or pressing Esc closes it. Used by the ⓘ help icons.
private struct ClickTipModifier: ViewModifier {
    let text: String
    @State private var id = UUID()
    @State private var frame: CGRect = .zero
    @Environment(\.tooltipSpaceName) private var space

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .named(space)) }
                    .onChange(of: g.frame(in: .named(space))) { frame = $0 }
            })
            .onTapGesture {
                if TooltipCenter.shared.isShowing(owner: id) { TooltipCenter.shared.hide(owner: id) }
                else { TooltipCenter.shared.show(text, at: frame, in: space, owner: id) }
            }
            .onDisappear { TooltipCenter.shared.hide(owner: id) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(text)
    }
}

/// Draws the current tooltip if it belongs to `space`. Put it in an overlay on the window's root view,
/// together with `.coordinateSpace(name: space)`, or use `.tooltipScope(_:)` for both.
struct TooltipLayer: View {
    var space = tooltipSpace
    @ObservedObject private var center = TooltipCenter.shared
    private static let fontSize: CGFloat = 13.5
    private let maxTextWidth: CGFloat = 330
    private let padH: CGFloat = 14, padV: CGFloat = 10

    /// Tooltip text is markdown: **bold** for terms, and a blank line between paragraphs.
    static func styled(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    /// Measures the text so the bubble is exactly as wide (up to the maximum) and tall as it needs.
    private func textSize(_ text: String, maxWidth: CGFloat) -> CGSize {
        let font = NSFont.boldSystemFont(ofSize: Self.fontSize * UIScale.current)   // bold: never too narrow
        let plain = String(Self.styled(text).characters)
        let widest = plain.components(separatedBy: "\n")
            .map { NSAttributedString(string: $0, attributes: [.font: font]).size().width }.max() ?? 0
        let attr = NSAttributedString(string: plain, attributes: [.font: font])
        let w = min(maxWidth, ceil(widest) + 2)
        let r = attr.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: w, height: ceil(r.height) + 2)
    }

    var body: some View {
        GeometryReader { g in
            if let text = center.text, center.space == space {
                let a = center.anchor
                let ts = textSize(text, maxWidth: min(maxTextWidth, g.size.width - 16 - padH * 2))
                let w = ts.width + padH * 2, h = ts.height + padV * 2
                // Left-aligned with the control, kept inside the window; below it, or above if no room.
                let x = min(max(8, a.minX), g.size.width - w - 8)
                let below = a.maxY + 8 + h <= g.size.height - 8
                let y = below ? a.maxY + 8 : max(8, a.minY - 8 - h)
                Text(Self.styled(text))
                    .font(.tj(Self.fontSize))
                    .lineSpacing(2)
                    .foregroundColor(.white)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(width: ts.width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)   // height grows with the text
                    .padding(.horizontal, padH).padding(.vertical, padV)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.11, green: 0.12, blue: 0.15)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TJ.gold, lineWidth: 2))
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 5)
                    .offset(x: x, y: y)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .id(text)
            }
        }
        .animation(.easeOut(duration: 0.12), value: center.text)
        .allowsHitTesting(false)
    }
}
