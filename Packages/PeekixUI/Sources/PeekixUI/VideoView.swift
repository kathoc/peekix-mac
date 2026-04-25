import AppKit
import Metal
import QuartzCore

public final class VideoView: NSView {
    private var _metalLayer: CAMetalLayer!

    public var metalLayer: CAMetalLayer { _metalLayer }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.backgroundColor = NSColor.black.cgColor
        self._metalLayer = layer
        self.layer = layer
    }

    public override var isFlipped: Bool { true }
}
