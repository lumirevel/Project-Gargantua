import AppKit
import SwiftUI

/// NSView that draws the latest preview render (from the real renderer) and
/// forwards mouse / trackpad input as orbit-camera gestures. Left drag orbits,
/// wheel and pinch zoom.
final class PreviewImageView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var onOrbit: ((Float, Float) -> Void)?
    var onZoom: ((Float) -> Void)?
    var onInteractionBegan: (() -> Void)?
    var onInteractionEnded: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let isz = image.size
        let scale = min(bounds.width / isz.width, bounds.height / isz.height)
        let w = isz.width * scale
        let h = isz.height * scale
        let rect = NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onInteractionBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        onOrbit?(Float(event.deltaX), Float(event.deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        onInteractionEnded?()
    }

    override func rightMouseDragged(with event: NSEvent) {
        onOrbit?(Float(event.deltaX), Float(event.deltaY))
    }

    override func scrollWheel(with event: NSEvent) {
        let precise = event.hasPreciseScrollingDeltas
        onZoom?(Float(event.scrollingDeltaY) * (precise ? 1.0 : 6.0))
    }

    override func magnify(with event: NSEvent) {
        onZoom?(Float(event.magnification) * 320.0)
    }
}

/// SwiftUI wrapper that shows the live preview image and wires gestures to the
/// shared orbit camera, debouncing a real-renderer pass when the camera settles.
struct InteractivePreviewViewport: NSViewRepresentable {
    @ObservedObject var model: LauncherModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> PreviewImageView {
        let view = PreviewImageView()
        view.wantsLayer = true
        view.image = model.previewImage
        view.onOrbit = { [weak coordinator = context.coordinator] dx, dy in
            coordinator?.handleOrbit(dx: dx, dy: dy)
        }
        view.onZoom = { [weak coordinator = context.coordinator] delta in
            coordinator?.handleZoom(delta)
        }
        view.onInteractionBegan = { [weak coordinator = context.coordinator] in
            coordinator?.beginInteraction()
        }
        view.onInteractionEnded = { [weak coordinator = context.coordinator] in
            coordinator?.endInteraction()
        }
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: PreviewImageView, context: Context) {
        nsView.image = model.previewImage
    }

    @MainActor
    final class Coordinator {
        let model: LauncherModel
        weak var view: PreviewImageView?
        private var settle: DispatchWorkItem?

        init(model: LauncherModel) { self.model = model }

        func handleOrbit(dx: Float, dy: Float) {
            model.camera.orbit(deltaX: dx, deltaY: dy)
            model.setPreviewInteracting(true)
            model.streamPreviewCamera() // live low-res frame; renders coalesce
            scheduleRefine()
        }

        func handleZoom(_ delta: Float) {
            model.camera.zoom(delta: delta)
            model.setPreviewInteracting(true)
            model.streamPreviewCamera()
            scheduleRefine()
        }

        func beginInteraction() {
            model.setPreviewInteracting(true)
        }

        func endInteraction() {
            scheduleRefine()
        }

        /// Once the camera stops moving, refresh dependent UI and render a sharper
        /// (higher-resolution) frame.
        private func scheduleRefine() {
            settle?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.model.setPreviewInteracting(false)
                self.model.previewCameraDidCommit()
                self.model.refinePreview()
            }
            settle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
    }
}
