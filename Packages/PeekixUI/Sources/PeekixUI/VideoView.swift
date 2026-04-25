import AppKit
import Metal
import QuartzCore

public final class VideoView: NSView {
    private var _metalLayer: CAMetalLayer!

    public var metalLayer: CAMetalLayer { _metalLayer }

    public var onScroll: ((_ deltaY: CGFloat, _ cursor: NSPoint, _ size: NSSize) -> Void)?
    public var onDoubleClick: (() -> Void)?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Primary backing layer is a *plain* CALayer. AppKit's view-region/dirty
        // bookkeeping (e.g. -[NSWindow _adjustNeedsDisplayRegionForNewFrame:])
        // assumes it can walk the primary layer like a normal CALayer; using
        // CAMetalLayer there crashes inside NSRegion math during fullscreen
        // exit (brk 1, __kCGRegionEmptyRegion). The CAMetalLayer is hosted as
        // a sublayer instead — this is the same pattern MTKView uses.
        let host = CALayer()
        host.backgroundColor = NSColor.black.cgColor
        host.isOpaque = true
        host.masksToBounds = true

        let metal = CAMetalLayer()
        metal.device = MTLCreateSystemDefaultDevice()
        metal.pixelFormat = .bgra8Unorm
        metal.framebufferOnly = true
        metal.backgroundColor = NSColor.black.cgColor
        metal.isOpaque = true
        metal.presentsWithTransaction = false
        metal.frame = .zero
        metal.anchorPoint = CGPoint(x: 0, y: 0)
        metal.position = .zero

        host.addSublayer(metal)
        self._metalLayer = metal

        self.layer = host
        self.wantsLayer = true
    }

    // Manage layer contents ourselves; keeps AppKit's display-region traversal
    // out of our subtree during fullscreen transitions.
    public override var wantsUpdateLayer: Bool { true }
    public override var isOpaque: Bool { true }

    public override func updateLayer() {
        // No-op: the CAMetalLayer drives its own contents via nextDrawable().
        // Implementing wantsUpdateLayer requires a non-default updateLayer()
        // override (otherwise AppKit may fall back to the drawRect path).
    }

    public override var isFlipped: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = window?.backingScaleFactor {
            _metalLayer.contentsScale = scale
        }
        updateDrawableSize()
    }

    public override func layout() {
        super.layout()
        updateDrawableSize()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? _metalLayer.contentsScale
        let size = bounds.size
        // Resize the hosted CAMetalLayer to fill the primary host layer.
        // Disable implicit animations so the metal sublayer doesn't lag behind
        // the window during fullscreen transitions (which would briefly leak
        // the host layer's black background into the rendered area).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        _metalLayer.frame = CGRect(origin: .zero, size: size)
        CATransaction.commit()

        let w = max(1, Int((size.width * scale).rounded()))
        let h = max(1, Int((size.height * scale).rounded()))
        let newSize = CGSize(width: w, height: h)
        if _metalLayer.drawableSize != newSize {
            _metalLayer.drawableSize = newSize
        }
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let cb = onDoubleClick {
            cb()
            return
        }
        super.mouseDown(with: event)
    }

    public override func scrollWheel(with event: NSEvent) {
        guard let cb = onScroll else {
            super.scrollWheel(with: event)
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        cb(event.scrollingDeltaY, p, bounds.size)
    }
}
