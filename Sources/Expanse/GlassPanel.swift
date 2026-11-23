import AppKit

/// A Liquid Glass panel for an overlay drawn in layers (the minimap, the Spaces strip), over
/// whatever the canvas shows behind it: system glass from macOS 26, the HUD material before.
/// Clicks go through to the canvas, which hit-tests the layers itself.
final class GlassPanel: NSView {
    static let radius: CGFloat = 22

    private let host = Host()
    private var effect: NSView?

    /// `appearanceChanged` gets the appearance the glass gives its content (light or dark text),
    /// at once and whenever it changes.
    init(content: CALayer, appearanceChanged: @escaping (NSAppearance) -> Void) {
        super.init(frame: .zero)
        host.wantsLayer = true
        host.layer?.addSublayer(content)
        host.content = content
        host.appearanceChanged = appearanceChanged
        let effect: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.radius
            glass.contentView = host
            effect = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .hudWindow
            material.blendingMode = .withinWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = Self.radius
            material.layer?.cornerCurve = .continuous
            material.layer?.masksToBounds = true
            host.autoresizingMask = [.width, .height]
            material.addSubview(host)
            effect = material
        }
        effect.autoresizingMask = [.width, .height]
        self.effect = effect
        addSubview(effect)
    }

    /// The panel's corner radius: the full one by default, a smaller one for a compact panel
    /// (see CanvasView.placePanels).
    func setRadius(_ radius: CGFloat) {
        if #available(macOS 26, *), let glass = effect as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            effect?.layer?.cornerRadius = radius
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private final class Host: NSView {
        var content: CALayer?
        var appearanceChanged: ((NSAppearance) -> Void)?

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            content?.frame = bounds
            CATransaction.commit()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            appearanceChanged?(effectiveAppearance)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            appearanceChanged?(effectiveAppearance)
        }
    }
}
