import Foundation
import Metal

struct DiskAtlasMeta: Codable {
    var width: Int
    var height: Int
    var format: String?
    var channels: [String]?
    var rNormMin: Double?
    var rNormMax: Double?
    var rNormWarp: Double?
}

struct DiskVolumeMeta: Codable {
    var r: Int?
    var phi: Int?
    var z: Int?
    var nr: Int?
    var nphi: Int?
    var nz: Int?
    var width: Int?
    var height: Int?
    var depth: Int?
    var format: String?
    var channels: [String]?
    var rNormMin: Double?
    var rNormMax: Double?
    var zNormMax: Double?
}

enum Resources {
    static func ensureParentDirectory(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
}

struct InFlightTraceSlot {
    let traceParamBuf: MTLBuffer
    let traceTileBuf: MTLBuffer?
    let linearParamBuf: MTLBuffer?
    let linearTileBuf: MTLBuffer?
}

struct RenderFrameResources {
    let outputURL: URL
    let linearOutputURL: URL
    let collisionBuffer: MTLBuffer?
    let collisionBase: UnsafeMutableRawPointer?
    let directLinearTraceBuf: MTLBuffer?
    let directLinearHitCountBuf: MTLBuffer?
    let directLinearParamBuf: MTLBuffer?
    let composeBaseBufForLinear: MTLBuffer?
    let traceSlots: [InFlightTraceSlot]
    let traceStride: Int
    let collisionStorageSize: Int
    let maxInFlight: Int
    let slotBytes: Int
}

extension Resources {
    static func makeFrameResources(
        device: MTLDevice,
        config: ResolvedRenderConfig,
        params: PackedParams,
        policy: RenderResourcePolicy,
        useDirectLinear: Bool,
        useInMemoryCollisions: Bool,
        useLinear32Intermediate: Bool,
        width: Int,
        height: Int,
        composeExposure: Float,
        composeLookID: UInt32,
        spectralEncodingID: UInt32,
        composePrecisionID: UInt32,
        composeAnalysisMode: UInt32,
        composeCameraModelID: UInt32,
        composeCameraPsfSigmaArg: Float,
        composeCameraReadNoiseArg: Float,
        composeCameraShotNoiseArg: Float,
        composeCameraFlareStrengthArg: Float,
        backgroundModeID: UInt32,
        backgroundStarDensityArg: Float,
        backgroundStarStrengthArg: Float,
        backgroundNebulaStrengthArg: Float,
        preserveHighlightColor: UInt32,
        downsampleArg: Int,
        composeDitherArg: Float,
        composeInnerEdgeArg: Float,
        composeSpectralStepArg: Float,
        tileSize: Int,
        traceInFlightOverrideArg: Int
    ) -> RenderFrameResources {
        let directLinearTraceBuf: MTLBuffer? =
            useDirectLinear
            ? device.makeBuffer(length: policy.linearOutSize, options: .storageModePrivate)
            : nil
        let directLinearEnabled = directLinearTraceBuf != nil
        if useDirectLinear, directLinearTraceBuf == nil {
            fail("failed to allocate direct HDR trace buffer (\(policy.linearOutSize) bytes)")
        }
        let directLinearHitCountBuf: MTLBuffer? = directLinearEnabled
            ? device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
            : nil
        if directLinearEnabled, directLinearHitCountBuf == nil {
            fail("failed to allocate direct linear hit-count buffer")
        }
        if let directLinearHitCountBuf {
            memset(directLinearHitCountBuf.contents(), 0, MemoryLayout<UInt32>.stride)
        }

        let collisionLite32Enabled = policy.collisionLite32Enabled(
            directLinearEnabled: directLinearEnabled,
            useLinear32Intermediate: useLinear32Intermediate
        )
        let traceStride = policy.traceStride(collisionLite32Enabled: collisionLite32Enabled)
        let collisionStorageSize = policy.collisionStorageSize(collisionLite32Enabled: collisionLite32Enabled)

        let collisionBuffer: MTLBuffer? = (useInMemoryCollisions && !directLinearEnabled)
            ? device.makeBuffer(length: collisionStorageSize, options: .storageModeShared)
            : nil
        if useInMemoryCollisions, collisionBuffer == nil, !directLinearEnabled {
            fail("failed to allocate in-memory collision buffer (\(collisionStorageSize) bytes)")
        }
        let collisionBase = collisionBuffer?.contents()

        let outputURL = URL(fileURLWithPath: config.outPath)
        let linearOutputURL = URL(fileURLWithPath: config.linear32OutPath)

        var composeParamsBase = params
        let composeBaseBufForLinear: MTLBuffer? = useLinear32Intermediate
            ? device.makeBuffer(bytes: &composeParamsBase, length: MemoryLayout<PackedParams>.stride, options: [])
            : nil
        if useLinear32Intermediate, composeBaseBufForLinear == nil {
            fail("failed to allocate linear32 base param buffer")
        }

        let directLinearParamBuf: MTLBuffer?
        if directLinearEnabled {
            var directLinearParams = ComposeParams(
                tileWidth: UInt32(width),
                tileHeight: UInt32(height),
                downsample: 1,
                outTileWidth: 0,
                outTileHeight: 0,
                srcOffsetX: 0,
                srcOffsetY: 0,
                outOffsetX: 0,
                outOffsetY: 0,
                fullInputWidth: UInt32(width),
                fullInputHeight: UInt32(height),
                exposure: composeExposure,
                dither: composeDitherArg,
                innerEdgeMult: composeInnerEdgeArg,
                spectralStep: composeSpectralStepArg,
                cloudQ10: 0.0,
                cloudInvSpan: 1.0,
                look: composeLookID,
                spectralEncoding: spectralEncodingID,
                precisionMode: composePrecisionID,
                analysisMode: composeAnalysisMode,
                cloudBins: 0,
                lumBins: 0,
                lumLogMin: 0.0,
                lumLogMax: 0.0,
                cameraModel: composeCameraModelID,
                cameraPsfSigmaPx: composeCameraPsfSigmaArg,
                cameraReadNoise: composeCameraReadNoiseArg,
                cameraShotNoise: composeCameraShotNoiseArg,
                cameraFlareStrength: composeCameraFlareStrengthArg,
                backgroundMode: backgroundModeID,
                backgroundStarDensity: backgroundStarDensityArg,
                backgroundStarStrength: backgroundStarStrengthArg,
                backgroundNebulaStrength: backgroundNebulaStrengthArg,
                preserveHighlightColor: preserveHighlightColor,
                diskNoiseModel: params.diskNoiseModel,
                _pad0: 0,
                _pad1: 0,
                _pad2: 0
            )
            directLinearParamBuf = device.makeBuffer(bytes: &directLinearParams, length: MemoryLayout<ComposeParams>.stride, options: [])
            if directLinearParamBuf == nil {
                fail("failed to allocate direct linear compose param buffer")
            }
        } else {
            directLinearParamBuf = nil
        }

        let dsForTile = config.composeGPU ? downsampleArg : 1
        let baseTile = max(1, tileSize)
        let alignedTile = max(dsForTile, (baseTile / dsForTile) * dsForTile)
        let effectiveTile = alignedTile
        let maxTraceTilePixels = effectiveTile * effectiveTile
        let traceTileTotal = max(1, ((width + effectiveTile - 1) / effectiveTile) * ((height + effectiveTile - 1) / effectiveTile))

        let slotTraceParamBytes = MemoryLayout<PackedParams>.stride
        let slotTraceTileBytes = maxTraceTilePixels * traceStride
        let slotLinearParamBytes = useLinear32Intermediate ? MemoryLayout<ComposeParams>.stride : 0
        let slotLinearTileBytes = useLinear32Intermediate ? (maxTraceTilePixels * policy.linearStride) : 0
        let needsTraceTile = !(useInMemoryCollisions && !useLinear32Intermediate) && !directLinearEnabled
        let slotBytes = slotTraceParamBytes
            + (needsTraceTile ? slotTraceTileBytes : 0)
            + slotLinearParamBytes
            + slotLinearTileBytes

        let inFlightBudget = policy.inFlightBudget()
        var maxInFlight = 2
        if slotBytes > 0 && slotBytes * 3 <= inFlightBudget {
            maxInFlight = 3
        }
        if traceInFlightOverrideArg > 0 {
            maxInFlight = traceInFlightOverrideArg
        } else if useLinear32Intermediate {
            maxInFlight = min(maxInFlight, 2)
        }
        maxInFlight = min(maxInFlight, traceTileTotal)
        maxInFlight = max(1, maxInFlight)

        var traceSlots: [InFlightTraceSlot] = []
        traceSlots.reserveCapacity(maxInFlight)
        for _ in 0..<maxInFlight {
            guard let traceParamBuf = device.makeBuffer(length: slotTraceParamBytes, options: .storageModeShared) else {
                fail("failed to allocate trace param buffer slot")
            }
            let traceTileBuf: MTLBuffer?
            if needsTraceTile {
                guard let buf = device.makeBuffer(length: slotTraceTileBytes, options: .storageModeShared) else {
                    fail("failed to allocate trace tile buffer slot")
                }
                traceTileBuf = buf
            } else {
                traceTileBuf = nil
            }

            let linearParamBuf: MTLBuffer?
            let linearTileBuf: MTLBuffer?
            if useLinear32Intermediate {
                guard let lp = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
                    fail("failed to allocate linear32 compose param buffer slot")
                }
                guard let lt = device.makeBuffer(length: maxTraceTilePixels * policy.linearStride, options: .storageModeShared) else {
                    fail("failed to allocate linear32 tile buffer slot")
                }
                linearParamBuf = lp
                linearTileBuf = lt
            } else {
                linearParamBuf = nil
                linearTileBuf = nil
            }

            traceSlots.append(
                InFlightTraceSlot(
                    traceParamBuf: traceParamBuf,
                    traceTileBuf: traceTileBuf,
                    linearParamBuf: linearParamBuf,
                    linearTileBuf: linearTileBuf
                )
            )
        }

        return RenderFrameResources(
            outputURL: outputURL,
            linearOutputURL: linearOutputURL,
            collisionBuffer: collisionBuffer,
            collisionBase: collisionBase,
            directLinearTraceBuf: directLinearTraceBuf,
            directLinearHitCountBuf: directLinearHitCountBuf,
            directLinearParamBuf: directLinearParamBuf,
            composeBaseBufForLinear: composeBaseBufForLinear,
            traceSlots: traceSlots,
            traceStride: traceStride,
            collisionStorageSize: collisionStorageSize,
            maxInFlight: maxInFlight,
            slotBytes: slotBytes
        )
    }
}

func writePPM(path: String, width: Int, height: Int, rgb: [UInt8]) throws {
    let header = "P6\n\(width) \(height)\n255\n"
    let url = URL(fileURLWithPath: path)
    var data = Data(header.utf8)
    data.append(contentsOf: rgb)
    try data.write(to: url)
}

@discardableResult
func runProcess(_ launchPath: String, _ args: [String]) -> Int32 {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: launchPath)
    proc.arguments = args
    do {
        try proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    } catch {
        return -1
    }
}

func updateBuffer<T>(_ buffer: MTLBuffer, with value: inout T) {
    withUnsafeBytes(of: &value) { raw in
        guard let base = raw.baseAddress else { return }
        memcpy(buffer.contents(), base, raw.count)
    }
}

func writeRawBuffer(to url: URL, sourceBase: UnsafeRawPointer, byteCount: Int) throws {
    _ = FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.truncate(atOffset: UInt64(byteCount))
    try handle.seek(toOffset: 0)
    let chunkBytes = 4 * 1024 * 1024
    var offset = 0
    while offset < byteCount {
        let count = min(chunkBytes, byteCount - offset)
        let ptr = sourceBase.advanced(by: offset)
        try handle.write(contentsOf: Data(bytes: ptr, count: count))
        offset += count
    }
}

func makeFloat4Texture2D(device: MTLDevice,
                         width: Int,
                         height: Int,
                         data: Data,
                         label: String) -> MTLTexture {
    let w = max(width, 1)
    let h = max(height, 1)
    let expectedBytes = w * h * MemoryLayout<SIMD4<Float>>.stride
    if data.count != expectedBytes {
        fail("\(label) size mismatch: got \(data.count), expected \(expectedBytes) for \(w)x\(h) float4")
    }
    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
    desc.usage = [.shaderRead]
    desc.storageMode = .shared
    guard let tex = device.makeTexture(descriptor: desc) else {
        fail("failed to create texture: \(label)")
    }
    let rowBytes = w * MemoryLayout<SIMD4<Float>>.stride
    data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: rowBytes)
    }
    return tex
}

func makeFloat4Texture3D(device: MTLDevice,
                         width: Int,
                         height: Int,
                         depth: Int,
                         data: Data,
                         label: String) -> MTLTexture {
    let w = max(width, 1)
    let h = max(height, 1)
    let d = max(depth, 1)
    let expectedBytes = w * h * d * MemoryLayout<SIMD4<Float>>.stride
    if data.count != expectedBytes {
        fail("\(label) size mismatch: got \(data.count), expected \(expectedBytes) for \(w)x\(h)x\(d) float4")
    }
    let desc = MTLTextureDescriptor()
    desc.textureType = .type3D
    desc.pixelFormat = .rgba32Float
    desc.width = w
    desc.height = h
    desc.depth = d
    desc.mipmapLevelCount = 1
    desc.usage = [.shaderRead]
    desc.storageMode = .shared
    guard let tex = device.makeTexture(descriptor: desc) else {
        fail("failed to create 3D texture: \(label)")
    }
    let rowBytes = w * MemoryLayout<SIMD4<Float>>.stride
    let imageBytes = rowBytes * h
    data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        tex.replace(region: MTLRegionMake3D(0, 0, 0, w, h, d), mipmapLevel: 0, slice: 0, withBytes: base, bytesPerRow: rowBytes, bytesPerImage: imageBytes)
    }
    return tex
}

func loadDiskAtlas(path: String, widthOverride: Int, heightOverride: Int) throws -> (data: Data, width: Int, height: Int, rNormMin: Double?, rNormMax: Double?, rNormWarp: Double?) {
    let atlasURL = URL(fileURLWithPath: path)
    let atlasData = try Data(contentsOf: atlasURL, options: [.mappedIfSafe])

    var width = widthOverride
    var height = heightOverride
    var rNormMin: Double? = nil
    var rNormMax: Double? = nil
    var rNormWarp: Double? = nil
    if width <= 0 || height <= 0 {
        let metaURL = URL(fileURLWithPath: path + ".json")
        if FileManager.default.fileExists(atPath: metaURL.path) {
            let metaData = try Data(contentsOf: metaURL)
            let meta = try JSONDecoder().decode(DiskAtlasMeta.self, from: metaData)
            width = meta.width
            height = meta.height
            rNormMin = meta.rNormMin
            rNormMax = meta.rNormMax
            rNormWarp = meta.rNormWarp
        }
    } else {
        let metaURL = URL(fileURLWithPath: path + ".json")
        if FileManager.default.fileExists(atPath: metaURL.path) {
            let metaData = try Data(contentsOf: metaURL)
            let meta = try JSONDecoder().decode(DiskAtlasMeta.self, from: metaData)
            rNormMin = meta.rNormMin
            rNormMax = meta.rNormMax
            rNormWarp = meta.rNormWarp
        }
    }

    if width <= 0 || height <= 0 {
        throw NSError(domain: "Blackhole", code: 10, userInfo: [NSLocalizedDescriptionKey: "disk atlas needs width/height (pass --disk-atlas-width/--disk-atlas-height or provide <atlas>.json)"])
    }

    let expectedBytes = width * height * MemoryLayout<SIMD4<Float>>.stride
    if atlasData.count != expectedBytes {
        throw NSError(domain: "Blackhole", code: 11, userInfo: [NSLocalizedDescriptionKey: "disk atlas size mismatch: got \(atlasData.count), expected \(expectedBytes) for \(width)x\(height) float4"])
    }

    return (atlasData, width, height, rNormMin, rNormMax, rNormWarp)
}

func loadDiskVolume(path: String, metaPath: String, rOverride: Int, phiOverride: Int, zOverride: Int) throws -> (data: Data, r: Int, phi: Int, z: Int, rNormMin: Double?, rNormMax: Double?, zNormMax: Double?) {
    let volumeURL = URL(fileURLWithPath: path)
    let volumeData = try Data(contentsOf: volumeURL, options: [.mappedIfSafe])

    var r = rOverride
    var phi = phiOverride
    var z = zOverride
    var rNormMin: Double? = nil
    var rNormMax: Double? = nil
    var zNormMax: Double? = nil

    let metaURL = URL(fileURLWithPath: metaPath.isEmpty ? (path + ".json") : metaPath)
    if FileManager.default.fileExists(atPath: metaURL.path) {
        let metaData = try Data(contentsOf: metaURL)
        let meta = try JSONDecoder().decode(DiskVolumeMeta.self, from: metaData)
        if r <= 0 {
            r = meta.r ?? meta.nr ?? meta.width ?? 0
        }
        if phi <= 0 {
            phi = meta.phi ?? meta.nphi ?? meta.height ?? 0
        }
        if z <= 0 {
            z = meta.z ?? meta.nz ?? meta.depth ?? 0
        }
        rNormMin = meta.rNormMin
        rNormMax = meta.rNormMax
        zNormMax = meta.zNormMax
    }

    if r <= 0 || phi <= 0 || z <= 0 {
        throw NSError(
            domain: "Blackhole",
            code: 12,
            userInfo: [NSLocalizedDescriptionKey: "disk volume needs dimensions (pass --disk-volume-r/--disk-volume-phi/--disk-volume-z or provide <volume>.json)"]
        )
    }

    let expectedBytes = r * phi * z * MemoryLayout<SIMD4<Float>>.stride
    if volumeData.count != expectedBytes {
        throw NSError(
            domain: "Blackhole",
            code: 13,
            userInfo: [NSLocalizedDescriptionKey: "disk volume size mismatch: got \(volumeData.count), expected \(expectedBytes) for \(r)x\(phi)x\(z) float4"]
        )
    }

    return (volumeData, r, phi, z, rNormMin, rNormMax, zNormMax)
}
