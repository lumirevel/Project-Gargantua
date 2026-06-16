import AppKit
import MetalKit
import SwiftUI

/// MTKView subclass that forwards mouse / trackpad input as orbit-camera
/// gestures. Left drag orbits (theta/phi), wheel and pinch zoom (radius).
final class PreviewMTKView: MTKView {
    var onOrbit: ((Float, Float) -> Void)?
    var onZoom: ((Float) -> Void)?
    var onInteractionTick: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onInteractionTick?()
    }

    override func mouseDragged(with event: NSEvent) {
        onOrbit?(Float(event.deltaX), Float(event.deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        onInteractionTick?()
    }

    override func rightMouseDragged(with event: NSEvent) {
        // Secondary drag also orbits, matching common 3D-viewport conventions.
        onOrbit?(Float(event.deltaX), Float(event.deltaY))
    }

    override func scrollWheel(with event: NSEvent) {
        // Positive scrollingDeltaY -> zoom in.
        let precise = event.hasPreciseScrollingDeltas
        let delta = Float(event.scrollingDeltaY) * (precise ? 1.0 : 6.0)
        onZoom?(delta)
    }

    override func magnify(with event: NSEvent) {
        // Pinch: magnification is a small signed fraction per event.
        onZoom?(Float(event.magnification) * 320.0)
    }
}

/// SwiftUI wrapper that hosts the Metal preview view and wires gestures to the
/// shared orbit camera controller + renderer.
struct InteractivePreviewViewport: NSViewRepresentable {
    @ObservedObject var model: LauncherModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSView {
        guard let renderer = context.coordinator.renderer else {
            // No Metal device / shader failure: return a black placeholder.
            let fallback = NSView()
            fallback.wantsLayer = true
            fallback.layer?.backgroundColor = NSColor.black.cgColor
            return fallback
        }

        let view = PreviewMTKView(frame: .zero, device: renderer.metalDevice)
        renderer.configure(view: view)
        view.onOrbit = { [weak coordinator = context.coordinator] dx, dy in
            coordinator?.handleOrbit(dx: dx, dy: dy)
        }
        view.onZoom = { [weak coordinator = context.coordinator] delta in
            coordinator?.handleZoom(delta)
        }
        view.onInteractionTick = { [weak coordinator = context.coordinator] in
            coordinator?.beginInteraction()
        }
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Push the latest GUI-derived settings; renderer diffs + resets as needed.
        context.coordinator.renderer?.updateSettings(model.previewRenderSettings)
    }

    @MainActor
    final class Coordinator {
        let model: LauncherModel
        let renderer: BlackHolePreviewRenderer?
        weak var view: PreviewMTKView?

        private var interactionEnd: DispatchWorkItem?
        private var isInteracting = false

        init(model: LauncherModel) {
            self.model = model
            self.renderer = BlackHolePreviewRenderer(
                camera: model.camera,
                stats: model.previewStats,
                settings: model.previewRenderSettings
            )
        }

        func handleOrbit(dx: Float, dy: Float) {
            model.camera.orbit(deltaX: dx, deltaY: dy)
            beginInteraction()
        }

        func handleZoom(_ delta: Float) {
            model.camera.zoom(delta: delta)
            beginInteraction()
        }

        /// Enter the low-quality interactive mode and debounce a return to full
        /// quality once the user stops manipulating the camera.
        func beginInteraction() {
            if !isInteracting {
                isInteracting = true
                renderer?.setInteracting(true)
            }
            renderer?.kick()

            interactionEnd?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.isInteracting = false
                self.renderer?.setInteracting(false)
                // Sync sliders + final-render camera to the new pose.
                self.model.previewCameraDidCommit()
            }
            interactionEnd = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
    }
}

extension BlackHolePreviewRenderer {
    /// Device exposed for view construction.
    var metalDevice: MTLDevice { metalDeviceInternal }

    /// Configure a host MTKView created by the SwiftUI representable.
    func configure(view: MTKView) {
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.autoResizeDrawable = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        attach(view: view)
    }
}
