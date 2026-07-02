import Foundation

enum Renderer {
    static func render(config: inout ResolvedRenderConfig, params: PackedParams) throws {
        let uploadedDiskAssetBytes =
            config.diskAtlasData.count + config.diskVolume0Data.count + config.diskVolume1Data.count
        let runtime = try RenderSetup.prepare(config: config, params: params)
        config.uploadedDiskAssetBytes = uploadedDiskAssetBytes
        config.diskAtlasData.removeAll(keepingCapacity: false)
        config.diskVolume0Data.removeAll(keepingCapacity: false)
        config.diskVolume1Data.removeAll(keepingCapacity: false)
        try RenderExecution.execute(config: config, params: params, runtime: runtime)
    }

    static func composeHDRInput(config: inout ResolvedRenderConfig, params: PackedParams) throws {
        let uploadedDiskAssetBytes =
            config.diskAtlasData.count + config.diskVolume0Data.count + config.diskVolume1Data.count
        let runtime = try RenderSetup.prepare(config: config, params: params)
        config.uploadedDiskAssetBytes = uploadedDiskAssetBytes
        config.diskAtlasData.removeAll(keepingCapacity: false)
        config.diskVolume0Data.removeAll(keepingCapacity: false)
        config.diskVolume1Data.removeAll(keepingCapacity: false)
        try RenderExecution.composeHDRInput(config: config, params: params, runtime: runtime)
    }

    /// Persistent "warm" render loop. The expensive setup (Metal pipelines, disk
    /// atlas/volume upload) runs once; then each line on stdin supplies a new
    /// camera ("camX camY camZ fov roll [seq]") and re-runs only the trace +
    /// compose, writing the same image-out each time and printing
    /// "SERVE_FRAME <seq>" when the frame is ready. Everything but the camera is
    /// fixed for the session, so changing the source/resolution restarts serve.
    static func serve(config: inout ResolvedRenderConfig, params: PackedParams) throws {
        // Force full-frame compose for every preview frame: the tile-first legacy
        // paths corrupt / GPU-hang when this warm runtime renders at a resolution
        // other than its launch size (the refine ladder resizes each settle).
        config.serveFullFrameCompose = true
        let uploadedDiskAssetBytes =
            config.diskAtlasData.count + config.diskVolume0Data.count + config.diskVolume1Data.count
        let runtime = try RenderSetup.prepare(config: config, params: params)
        config.uploadedDiskAssetBytes = uploadedDiskAssetBytes
        config.diskAtlasData.removeAll(keepingCapacity: false)
        config.diskVolume0Data.removeAll(keepingCapacity: false)
        config.diskVolume1Data.removeAll(keepingCapacity: false)

        var live = params
        var localConfig = config
        let rsD = config.rsD

        // Reuse the resolution-derived render context across frames: only the camera
        // pose changes between most requests, so we rebuild the Metal resources/plan
        // only when width/height actually changes (e.g. a ladder step). quiet=true
        // suppresses the per-frame diagnostic prints on the stdout pipe the GUI reads.
        var frameContext: RenderExecution.RenderFrameContext?
        var ctxWidth = -1
        var ctxHeight = -1
        defer { frameContext?.close() }

        // Last camera/resolution the GUI requested. A `reconfig` (interpreter-only
        // change: exposure / look / eye) re-renders this same view with the new
        // compose settings, so the user sees a Lightroom-style instant adjustment
        // instead of paying a full process relaunch + re-warm.
        var lastCam: (cx: Double, cy: Double, cz: Double, fov: Double, roll: Double, w: Int, h: Int)?

        func renderAndSignal(_ seq: String) {
            do {
                if frameContext == nil || ctxWidth != localConfig.width || ctxHeight != localConfig.height {
                    frameContext?.close()
                    frameContext = try RenderExecution.makeFrameContext(config: localConfig, params: live, runtime: runtime, quiet: true)
                    ctxWidth = localConfig.width
                    ctxHeight = localConfig.height
                }
                guard let context = frameContext else { return }
                try RenderExecution.runFrame(context, config: localConfig, params: live, runtime: runtime, quiet: true)
                print("SERVE_FRAME \(seq)")
            } catch {
                print("SERVE_ERROR \(seq) \(error)")
            }
            fflush(stdout)
        }

        print("SERVE_READY")
        fflush(stdout)
        renderAndSignal("0") // initial frame at the camera/resolution from the launch args

        // Request format: "camX camY camZ fov roll width height [seq]". The disk
        // atlas and pipelines are resolution-independent, so width/height may
        // vary per request — letting the GUI render low-res while orbiting and
        // a sharper frame once it settles, all in one warm session.
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed == "quit" || trimmed == "q" { break }

            // "reconfig <argv-file> [seq]": re-resolve the render config from a new
            // argument list (the GUI emits it for camera/eye interpreter edits),
            // reuse the warm runtime, and re-render the last view. No relaunch, no
            // re-warm. The trace re-runs but the disk atlas / pipelines are reused.
            if trimmed.hasPrefix("reconfig ") {
                let comps = trimmed.split(separator: " ").map(String.init)
                let seq = comps.count >= 3 ? comps[2] : "0"
                do {
                    let path = comps.count >= 2 ? comps[1] : ""
                    let argv = try String(contentsOfFile: path, encoding: .utf8)
                        .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                    guard !argv.isEmpty else {
                        throw NSError(domain: "Blackhole", code: 140, userInfo: [NSLocalizedDescriptionKey: "empty reconfig argv"])
                    }
                    let rebuilt = ParamsBuilder.build(from: CLI.parse(arguments: argv))
                    guard var cfg2 = rebuilt.resolvedConfig, let p2 = rebuilt.packedParams else {
                        throw NSError(domain: "Blackhole", code: 141, userInfo: [NSLocalizedDescriptionKey: "reconfig produced no render config"])
                    }
                    cfg2.serveFullFrameCompose = true
                    cfg2.diskAtlasData.removeAll(keepingCapacity: false)
                    cfg2.diskVolume0Data.removeAll(keepingCapacity: false)
                    cfg2.diskVolume1Data.removeAll(keepingCapacity: false)
                    localConfig = cfg2
                    live = p2
                    if let c = lastCam {
                        applyView(camX: c.cx, camY: c.cy, camZ: c.cz, fovDeg: c.fov, rollDeg: c.roll,
                                  width: c.w, height: c.h, params: &live, config: &localConfig, rsD: rsD)
                    }
                    // The frame context bakes compose settings into Metal buffers at
                    // creation (e.g. exposure/look in the direct-linear ComposeParams),
                    // so a reconfig MUST rebuild it — otherwise interpreter edits are
                    // silently ignored on direct-linear sources. Rebuild costs ~ms and
                    // reconfigs are rare (one per slider settle).
                    frameContext?.close()
                    frameContext = nil
                    renderAndSignal(seq)
                } catch {
                    print("SERVE_ERROR \(seq) reconfig \(error)")
                    fflush(stdout)
                }
                continue
            }

            let parts = trimmed.split(separator: " ").map(String.init)
            guard parts.count >= 7,
                  let cx = Double(parts[0]), let cy = Double(parts[1]), let cz = Double(parts[2]),
                  let fov = Double(parts[3]), let roll = Double(parts[4]),
                  let w = Int(parts[5]), let h = Int(parts[6]) else {
                print("SERVE_ERROR bad-request")
                fflush(stdout)
                continue
            }
            let seq = parts.count >= 8 ? parts[7] : "0"
            lastCam = (cx, cy, cz, fov, roll, w, h)
            applyView(camX: cx, camY: cy, camZ: cz, fovDeg: fov, rollDeg: roll,
                      width: w, height: h, params: &live, config: &localConfig, rsD: rsD)
            renderAndSignal(seq)
        }
    }

    /// Recompute the camera basis exactly as ParamsBuilder does (plus resolution)
    /// and write it into the live params/config; everything else stays fixed.
    private static func applyView(camX: Double, camY: Double, camZ: Double,
                                  fovDeg: Double, rollDeg: Double,
                                  width: Int, height: Int,
                                  params: inout PackedParams, config: inout ResolvedRenderConfig,
                                  rsD: Double) {
        let w = max(16, width)
        let h = max(16, height)
        let camPos = SIMD3<Float>(Float(rsD * camX), Float(rsD * camY), Float(rsD * camZ))
        let z = normalize(camPos)
        let vup = SIMD3<Float>(0, 0, 1)
        let planeX0 = normalize(cross(vup, z))
        let planeY0 = normalize(cross(z, planeX0))
        let roll = Float(rollDeg * Double.pi / 180.0)
        let planeX = cos(roll) * planeX0 + sin(roll) * planeY0
        let planeY = normalize(cross(z, planeX))
        let d = Float(Double(w) / (2.0 * tan(fovDeg * Double.pi / 360.0)))
        params.camPos = camPos
        params.planeX = planeX
        params.planeY = planeY
        params.z = z
        params.d = d
        params.width = UInt32(w)
        params.height = UInt32(h)
        params.fullWidth = UInt32(w)
        params.fullHeight = UInt32(h)
        params.offsetX = 0
        params.offsetY = 0
        config.width = w
        config.height = h
    }
}
