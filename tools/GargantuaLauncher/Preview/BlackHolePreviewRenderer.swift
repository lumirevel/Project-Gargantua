import Combine
import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

/// Lightweight, throttled stats surfaced to the SwiftUI HUD overlay.
@MainActor
final class PreviewStats: ObservableObject {
    @Published var sampleCount: Int = 0
    @Published var maxSamples: Int = 0
    @Published var width: Int = 0
    @Published var height: Int = 0
    @Published var fps: Double = 0
    @Published var converged: Bool = false
    @Published var interacting: Bool = false
    @Published var failureMessage: String?
}

/// Metal renderer for the interactive progressive preview viewport.
///
/// Owns the accumulation buffers (ping-pong float textures), the geodesic
/// compute pipeline and the tone-mapping present pipeline. Accumulation resets
/// whenever the camera pose, the render settings, the resolution or the
/// interaction state changes — so no stale samples from a previous
/// configuration ever bleed into the current image.
final class BlackHolePreviewRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let accumulatePSO: MTLComputePipelineState
    private let presentPSO: MTLRenderPipelineState

    private let camera: OrbitCameraController
    private let stats: PreviewStats

    private var settings: PreviewRenderSettings
    private var pendingSettings: PreviewRenderSettings

    private var accumA: MTLTexture?
    private var accumB: MTLTexture?
    private var writeToA = true

    private var accumWidth = 0
    private var accumHeight = 0
    private var drawableWidth = 0
    private var drawableHeight = 0

    private var sampleCount: UInt32 = 0
    private var frameSeed: UInt32 = 1
    private var lastCameraGeneration: UInt64 = .max
    private var isInteracting = false
    private var lastInteracting = false

    private weak var view: MTKView?

    // FPS smoothing.
    private var lastFrameTime: CFTimeInterval = 0
    private var smoothedFPS: Double = 0
    private var framesSinceStats = 0
    private var lastConverged = false

    init?(camera: OrbitCameraController, stats: PreviewStats, settings: PreviewRenderSettings) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.queue = queue
        self.camera = camera
        self.stats = stats
        self.settings = settings
        self.pendingSettings = settings

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: PreviewShaderSource.metal, options: nil)
        } catch {
            Task { @MainActor in stats.failureMessage = "Shader compile failed: \(error.localizedDescription)" }
            return nil
        }

        guard let accumulateFn = library.makeFunction(name: "accumulateKernel"),
              let presentVert = library.makeFunction(name: "presentVert"),
              let presentFrag = library.makeFunction(name: "presentFrag") else {
            return nil
        }

        do {
            self.accumulatePSO = try device.makeComputePipelineState(function: accumulateFn)
        } catch {
            Task { @MainActor in stats.failureMessage = "Compute pipeline failed: \(error.localizedDescription)" }
            return nil
        }

        let presentDesc = MTLRenderPipelineDescriptor()
        presentDesc.vertexFunction = presentVert
        presentDesc.fragmentFunction = presentFrag
        presentDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            self.presentPSO = try device.makeRenderPipelineState(descriptor: presentDesc)
        } catch {
            Task { @MainActor in stats.failureMessage = "Present pipeline failed: \(error.localizedDescription)" }
            return nil
        }

        super.init()
    }

    /// Metal device, for the SwiftUI representable to build the host view.
    var metalDeviceInternal: MTLDevice { device }

    /// Store a weak reference to the host view (used to pause/resume drawing).
    func attach(view: MTKView) {
        self.view = view
    }

    // MARK: - External control

    /// Push new GUI-derived settings. Adopted (and accumulation reset) on the
    /// next draw if anything actually changed.
    func updateSettings(_ newValue: PreviewRenderSettings) {
        pendingSettings = newValue
        kick()
    }

    /// Mark whether the user is actively manipulating the camera. Lower quality
    /// while interacting, then re-converge when released.
    func setInteracting(_ value: Bool) {
        isInteracting = value
        kick()
    }

    /// Wake the view so accumulation resumes after a pause.
    func kick() {
        view?.isPaused = false
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        self.view = view
        kick()
    }

    func draw(in view: MTKView) {
        self.view = view
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor else { return }

        let dw = max(Int(view.drawableSize.width), 1)
        let dh = max(Int(view.drawableSize.height), 1)
        guard dw > 1, dh > 1 else { return }

        var needsReset = false

        // Adopt pending settings.
        if pendingSettings != settings {
            settings = pendingSettings
            needsReset = true
        }

        // Camera changes.
        if camera.generation != lastCameraGeneration {
            lastCameraGeneration = camera.generation
            needsReset = true
        }

        // Interaction state changes (resolution / step budget changes).
        if isInteracting != lastInteracting {
            lastInteracting = isInteracting
            needsReset = true
        }

        // Resolve target accumulation size.
        let scale = isInteracting ? settings.quality.interactiveScale : settings.quality.idleScale
        let maxEdge = settings.quality.maxResolution
        var targetW = max(Int((Float(dw) * scale).rounded()), 16)
        var targetH = max(Int((Float(dh) * scale).rounded()), 16)
        let longest = max(targetW, targetH)
        if longest > maxEdge {
            let k = Double(maxEdge) / Double(longest)
            targetW = max(Int((Double(targetW) * k).rounded()), 16)
            targetH = max(Int((Double(targetH) * k).rounded()), 16)
        }

        if targetW != accumWidth || targetH != accumHeight || accumA == nil || accumB == nil {
            allocateAccum(width: targetW, height: targetH)
            needsReset = true
        }
        drawableWidth = dw
        drawableHeight = dh

        if needsReset {
            sampleCount = 0
            view.isPaused = false
        }

        let maxSamples = settings.quality.maxSamples
        let converged = sampleCount >= maxSamples

        guard let readTex = writeToA ? accumB : accumA,
              let writeTex = writeToA ? accumA : accumB,
              let commandBuffer = queue.makeCommandBuffer() else { return }

        let spf = converged ? 0 : max(settings.quality.samplesPerFrame, 1)
        let activeSPF: UInt32 = isInteracting ? 1 : spf

        // 1) Accumulate one (or more) stochastic samples, unless converged.
        if activeSPF > 0 {
            var uniforms = makeUniforms(samplesPerFrame: activeSPF)
            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(accumulatePSO)
                encoder.setTexture(readTex, index: 0)
                encoder.setTexture(writeTex, index: 1)
                encoder.setBytes(&uniforms, length: MemoryLayout<PreviewUniforms>.stride, index: 0)
                let tg = MTLSize(width: 8, height: 8, depth: 1)
                let groups = MTLSize(
                    width: (accumWidth + tg.width - 1) / tg.width,
                    height: (accumHeight + tg.height - 1) / tg.height,
                    depth: 1
                )
                encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
                encoder.endEncoding()
            }
            sampleCount += activeSPF
            frameSeed &+= 1
        }

        // The texture holding the freshest accumulation for presentation.
        let presentTex: MTLTexture = activeSPF > 0 ? writeTex : readTex

        // 2) Present: divide by sample count + tone map to the drawable.
        var present = PreviewPresentParams(
            exposure: settings.exposure,
            gamma: 2.2,
            toneMode: settings.toneMap.rawMode,
            pad: 0
        )
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
            encoder.setRenderPipelineState(presentPSO)
            encoder.setFragmentTexture(presentTex, index: 0)
            encoder.setFragmentBytes(&present, length: MemoryLayout<PreviewPresentParams>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        if activeSPF > 0 {
            writeToA.toggle()
        }

        updateStats(view: view, converged: sampleCount >= maxSamples, maxSamples: maxSamples)

        // Pause when fully converged and not interacting to save power.
        if sampleCount >= maxSamples && !isInteracting {
            view.isPaused = true
        }
    }

    // MARK: - Helpers

    private func allocateAccum(width: Int, height: Int) {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        accumA = device.makeTexture(descriptor: desc)
        accumB = device.makeTexture(descriptor: desc)
        accumWidth = width
        accumHeight = height
        writeToA = true
    }

    private func makeUniforms(samplesPerFrame: UInt32) -> PreviewUniforms {
        let state = camera.state
        let basis = state.basis
        let eye = state.eye

        var u = PreviewUniforms()
        u.camPos = SIMD4<Float>(eye, 0)
        u.camForward = SIMD4<Float>(basis.forward, 0)
        u.camRight = SIMD4<Float>(basis.right, 0)
        u.camUp = SIMD4<Float>(basis.up, 0)

        let aspect = Float(accumWidth) / Float(max(accumHeight, 1))
        let tanHalf = tan((state.fov * .pi / 180.0) * 0.5)
        u.resFov = SIMD4<Float>(Float(accumWidth), Float(accumHeight), tanHalf, aspect)

        let horizon = PreviewPhysics.horizonRadius(metric: settings.metric, spin: settings.spin)
        let escapeR = max(settings.diskOuter * 2.6, 70.0)
        let stepScale: Float = isInteracting ? 1.3 : 1.0

        u.disk0 = SIMD4<Float>(settings.spin, settings.diskInner, settings.diskOuter, settings.diskThickness)
        u.disk1 = SIMD4<Float>(settings.diskBrightness, settings.diskDensity, settings.backgroundStars, stepScale)
        u.disk2 = SIMD4<Float>(escapeR, horizon, 3.0, settings.diskTempScale)
        u.disk3 = SIMD4<Float>(settings.diskTurbulence, settings.diskNoiseScale, settings.diskSpiralArms, settings.diskSpiralStrength)

        let maxSteps = isInteracting ? settings.quality.interactiveMarchSteps : settings.quality.idleMarchSteps
        u.u0 = SIMD4<UInt32>(sampleCount, frameSeed, maxSteps, settings.metric.rawValue)
        u.u1 = SIMD4<UInt32>(samplesPerFrame, 0, 0, 0)
        return u
    }

    private func updateStats(view: MTKView, converged: Bool, maxSamples: UInt32) {
        let now = CACurrentMediaTime()
        if lastFrameTime > 0 {
            let dt = now - lastFrameTime
            if dt > 0 {
                let inst = 1.0 / dt
                smoothedFPS = smoothedFPS == 0 ? inst : smoothedFPS * 0.9 + inst * 0.1
            }
        }
        lastFrameTime = now

        framesSinceStats += 1
        let shouldPush = framesSinceStats >= 6 || converged != lastConverged
        guard shouldPush else { return }
        framesSinceStats = 0
        lastConverged = converged

        let sc = Int(sampleCount)
        let ms = Int(maxSamples)
        let w = accumWidth
        let h = accumHeight
        let fps = smoothedFPS
        let interacting = isInteracting
        Task { @MainActor in
            stats.sampleCount = sc
            stats.maxSamples = ms
            stats.width = w
            stats.height = h
            stats.fps = fps
            stats.converged = converged
            stats.interacting = interacting
        }
    }
}
