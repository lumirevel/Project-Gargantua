//
//  main.swift
//  Blackhole
//
//  Created by 김령교 on 2/20/26.
//

import Foundation
import Metal

struct Params {
    var width: UInt32
    var height: UInt32
    var fullWidth: UInt32
    var fullHeight: UInt32
    var offsetX: UInt32
    var offsetY: UInt32

    var camPos: SIMD3<Float>
    var planeX: SIMD3<Float>
    var planeY: SIMD3<Float>
    var z: SIMD3<Float>
    var d: Float

    var rs: Float
    var re: Float
    var he: Float

    var M: Float
    var G: Float
    var c: Float
    var k: Float

    var h: Float
    var maxSteps: Int32

    var eps: Float
    var metric: Int32
    var spin: Float
    var kerrSubsteps: Int32
    var kerrTol: Float
    var kerrEscapeMult: Float
    var kerrRadialScale: Float
    var kerrAzimuthScale: Float
    var kerrImpactScale: Float
    var diskFlowTime: Float
    var diskOrbitalBoost: Float
    var diskRadialDrift: Float
    var diskTurbulence: Float
    var diskOrbitalBoostInner: Float
    var diskOrbitalBoostOuter: Float
    var diskRadialDriftInner: Float
    var diskRadialDriftOuter: Float
    var diskTurbulenceInner: Float
    var diskTurbulenceOuter: Float
    var diskFlowStep: Float
    var diskFlowSteps: Float
    var diskAtlasMode: UInt32
    var diskAtlasWidth: UInt32
    var diskAtlasHeight: UInt32
    var diskAtlasWrapPhi: UInt32
    var diskAtlasTempScale: Float
    var diskAtlasDensityBlend: Float
    var diskAtlasVrScale: Float
    var diskAtlasVphiScale: Float
    var diskAtlasRNormMin: Float
    var diskAtlasRNormMax: Float
    var diskAtlasRNormWarp: Float
    var diskNoiseModel: UInt32
    var diskMdotEdd: Float
    var diskRadiativeEfficiency: Float
    var diskPhysicsMode: UInt32
    var diskPlungeFloor: Float
    var diskThickScale: Float
    var diskColorFactor: Float
    var diskReturningRad: Float
    var diskPrecisionTexture: Float
    var diskCloudCoverage: Float
    var diskCloudOpticalDepth: Float
    var diskCloudPorosity: Float
    var diskCloudShadowStrength: Float
    var diskReturnBounces: UInt32
    var diskRTSteps: UInt32
    var diskScatteringAlbedo: Float
    var diskRTPad: Float
}

struct CollisionInfo {
    var hit: UInt32
    var ct: Float
    var T: Float
    var _pad0: Float
    var v_disk: SIMD4<Float>
    var direct_world: SIMD4<Float>
    var noise: Float
    var emit_r_norm: Float
    var emit_phi: Float
    var emit_z_norm: Float
}

struct ExposureSample {
    var T: Float
    var vDisk: SIMD3<Float>
    var direct: SIMD3<Float>
    var noise: Float
}

struct ComposeParams {
    var tileWidth: UInt32
    var tileHeight: UInt32
    var downsample: UInt32
    var outTileWidth: UInt32
    var outTileHeight: UInt32
    var srcOffsetX: UInt32
    var srcOffsetY: UInt32
    var outOffsetX: UInt32
    var outOffsetY: UInt32
    var fullInputWidth: UInt32
    var fullInputHeight: UInt32
    var exposure: Float
    var dither: Float
    var innerEdgeMult: Float
    var spectralStep: Float
    var cloudQ10: Float
    var cloudInvSpan: Float
    var look: UInt32
    var spectralEncoding: UInt32
    var precisionMode: UInt32
    var analysisMode: UInt32
    var cloudBins: UInt32
    var lumBins: UInt32
    var lumLogMin: Float
    var lumLogMax: Float
}

struct RenderMeta: Codable {
    var version: String
    var spectralEncoding: String
    var diskModel: String
    var bridgeCoordinateFrame: String
    var bridgeFields: [String]
    var width: Int
    var height: Int
    var preset: String
    var rcp: Double
    var h: Double
    var maxSteps: Int
    var camX: Double
    var camY: Double
    var camZ: Double
    var fov: Double
    var roll: Double
    var diskH: Double
    var metric: String
    var spin: Double
    var kerrTol: Double
    var kerrEscapeMult: Double
    var kerrSubsteps: Int
    var kerrRadialScale: Double
    var kerrAzimuthScale: Double
    var kerrImpactScale: Double
    var diskFlowTime: Double
    var diskOrbitalBoost: Double
    var diskRadialDrift: Double
    var diskTurbulence: Double
    var diskOrbitalBoostInner: Double
    var diskOrbitalBoostOuter: Double
    var diskRadialDriftInner: Double
    var diskRadialDriftOuter: Double
    var diskTurbulenceInner: Double
    var diskTurbulenceOuter: Double
    var diskFlowStep: Double
    var diskFlowSteps: Int
    var diskMdotEdd: Double
    var diskRadiativeEfficiency: Double
    var diskPhysicsMode: String
    var diskPlungeFloor: Double
    var diskThickScale: Double
    var diskColorFactor: Double
    var diskReturningRad: Double
    var diskPrecisionTexture: Double
    var diskPrecisionClouds: Bool
    var diskCloudCoverage: Double
    var diskCloudOpticalDepth: Double
    var diskCloudPorosity: Double
    var diskCloudShadowStrength: Double
    var diskReturnBounces: Int
    var diskRTSteps: Int
    var diskScatteringAlbedo: Double
    var diskAtlasEnabled: Bool
    var diskAtlasPath: String
    var diskAtlasWidth: Int
    var diskAtlasHeight: Int
    var diskAtlasTempScale: Double
    var diskAtlasDensityBlend: Double
    var diskAtlasVrScale: Double
    var diskAtlasVphiScale: Double
    var diskAtlasRNormMin: Double
    var diskAtlasRNormMax: Double
    var diskAtlasRNormWarp: Double
    var tileSize: Int
    var composeGPU: Bool
    var downsample: Int
    var outputWidth: Int
    var outputHeight: Int
    var exposure: Double
    var look: String
    var collisionStride: Int
}

struct DiskAtlasMeta: Codable {
    var width: Int
    var height: Int
    var format: String?
    var channels: [String]?
    var rNormMin: Double?
    var rNormMax: Double?
    var rNormWarp: Double?
}

func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    return v / len
}

func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

@inline(__always)
func diskKerrISCOM(_ a: Double) -> Double {
    let aSafe = min(max(a, -0.999), 0.999)
    let a2 = aSafe * aSafe
    let z1 = 1.0 + pow(max(1.0 - a2, 0.0), 1.0 / 3.0) * (pow(1.0 + aSafe, 1.0 / 3.0) + pow(1.0 - aSafe, 1.0 / 3.0))
    let z2 = sqrt(max(3.0 * a2 + z1 * z1, 0.0))
    let sgn = (aSafe >= 0.0) ? 1.0 : -1.0
    return 3.0 + z2 - sgn * sqrt(max((3.0 - z1) * (3.0 + z1 + 2.0 * z2), 0.0))
}

@inline(__always)
func diskInnerRadiusM(metric: Int32, spin: Double, rs: Double) -> Double {
    if metric == 0 {
        return 3.0 * rs
    }
    let massLen = 0.5 * rs
    let rI = diskKerrISCOM(spin) * massLen
    let rH = diskHorizonRadiusM(metric: metric, spin: spin, rs: rs)
    return max(rI, rH * (1.0 + 16.0e-5))
}

@inline(__always)
func diskHorizonRadiusM(metric: Int32, spin: Double, rs: Double) -> Double {
    if metric == 0 { return rs }
    let a = min(max(abs(spin), 0.0), 0.999)
    let massLen = 0.5 * rs
    let rPlusM = 1.0 + sqrt(max(1.0 - a * a, 0.0))
    return max(rPlusM * massLen, 0.25 * rs)
}

func intArg(_ name: String, default defaultValue: Int) -> Int {
    guard let idx = CommandLine.arguments.firstIndex(of: name), idx + 1 < CommandLine.arguments.count else {
        return defaultValue
    }
    return Int(CommandLine.arguments[idx + 1]) ?? defaultValue
}

func doubleArg(_ name: String, default defaultValue: Double) -> Double {
    guard let idx = CommandLine.arguments.firstIndex(of: name), idx + 1 < CommandLine.arguments.count else {
        return defaultValue
    }
    return Double(CommandLine.arguments[idx + 1]) ?? defaultValue
}

@inline(__always)
func emitETAProgress(_ done: Int, _ total: Int, _ phase: String, _ extra: String = "") {
    let safeTotal = max(total, 1)
    let suffix = extra.isEmpty ? "" : " " + extra
    let line = "ETA_PROGRESS \(done) \(safeTotal) \(phase)\(suffix)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

func stringArg(_ name: String, default defaultValue: String) -> String {
    guard let idx = CommandLine.arguments.firstIndex(of: name), idx + 1 < CommandLine.arguments.count else {
        return defaultValue
    }
    return CommandLine.arguments[idx + 1]
}

func parseDiskMode(_ raw: String) -> (id: UInt32, canonical: String)? {
    switch raw.lowercased() {
    case "thin", "nt", "strict":
        return (0, "thin")
    case "thick", "plasma", "riaf":
        return (1, "thick")
    case "precision", "analysis", "pt":
        return (2, "precision")
    default:
        return nil
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

func copyCollisionTileRows(sourceBase: UnsafeRawPointer,
                           fullWidth: Int,
                           stride: Int,
                           srcX: Int,
                           srcY: Int,
                           tileWidth: Int,
                           tileHeight: Int,
                           destinationBase: UnsafeMutableRawPointer) {
    if srcX == 0 && tileWidth == fullWidth {
        let byteCount = tileWidth * tileHeight * stride
        let srcOffset = srcY * fullWidth * stride
        memcpy(destinationBase, sourceBase.advanced(by: srcOffset), byteCount)
        return
    }
    let rowBytes = tileWidth * stride
    var dst = destinationBase
    for row in 0..<tileHeight {
        let srcOffset = ((srcY + row) * fullWidth + srcX) * stride
        memcpy(dst, sourceBase.advanced(by: srcOffset), rowBytes)
        dst = dst.advanced(by: rowBytes)
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

func percentileSorted(_ sorted: [Float], _ q: Float) -> Float {
    if sorted.isEmpty { return 0.0 }
    let qq = min(max(q, 0.0), 1.0)
    if sorted.count == 1 { return sorted[0] }
    let pos = Float(sorted.count - 1) * qq
    let lo = Int(floor(pos))
    let hi = min(lo + 1, sorted.count - 1)
    let t = pos - Float(lo)
    return sorted[lo] * (1.0 - t) + sorted[hi] * t
}

func histogramQuantileBin(_ hist: UnsafeBufferPointer<UInt32>, _ q: Float) -> Int {
    if hist.isEmpty { return 0 }
    var total: UInt64 = 0
    for c in hist { total += UInt64(c) }
    if total == 0 { return 0 }
    let qq = min(max(q, 0.0), 1.0)
    let target = UInt64(Double(max(total - 1, 0)) * Double(qq))
    var cum: UInt64 = 0
    for i in 0..<hist.count {
        cum += UInt64(hist[i])
        if cum > target { return i }
    }
    return hist.count - 1
}

func quantileFromUniformHistogram(_ hist: UnsafeBufferPointer<UInt32>, _ q: Float, _ minVal: Float, _ maxVal: Float) -> Float {
    if hist.isEmpty { return minVal }
    let idx = histogramQuantileBin(hist, q)
    if hist.count == 1 { return minVal }
    let t = Float(idx) / Float(hist.count - 1)
    return minVal + (maxVal - minVal) * t
}

func cieXYZBar(_ wavelengthNm: Double) -> (Double, Double, Double) {
    let lam = wavelengthNm
    let t1x = (lam - 442.0) * (lam < 442.0 ? 0.0624 : 0.0374)
    let t2x = (lam - 599.8) * (lam < 599.8 ? 0.0264 : 0.0323)
    let t3x = (lam - 501.1) * (lam < 501.1 ? 0.0490 : 0.0382)
    let x = 0.362 * exp(-0.5 * t1x * t1x) + 1.056 * exp(-0.5 * t2x * t2x) - 0.065 * exp(-0.5 * t3x * t3x)

    let t1y = (lam - 568.8) * (lam < 568.8 ? 0.0213 : 0.0247)
    let t2y = (lam - 530.9) * (lam < 530.9 ? 0.0613 : 0.0322)
    let y = 0.821 * exp(-0.5 * t1y * t1y) + 0.286 * exp(-0.5 * t2y * t2y)

    let t1z = (lam - 437.0) * (lam < 437.0 ? 0.0845 : 0.0278)
    let t2z = (lam - 459.0) * (lam < 459.0 ? 0.0385 : 0.0725)
    let z = 1.217 * exp(-0.5 * t1z * t1z) + 0.681 * exp(-0.5 * t2z * t2z)
    return (max(x, 0.0), max(y, 0.0), max(z, 0.0))
}

func planckLambda(_ lambdaMeters: Double, _ temp: Double) -> Double {
    let c1 = 2.0 * 6.62607015e-34 * 299_792_458.0 * 299_792_458.0
    let c2 = 6.62607015e-34 * 299_792_458.0 / 1.380649e-23
    let x = min(max(c2 / max(lambdaMeters * temp, 1e-30), 1e-8), 700.0)
    return c1 / (pow(lambdaMeters, 5.0) * expm1(x))
}

func fail(_ message: String, code: Int32 = 3) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(code)
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

if CommandLine.arguments.contains("--kerr-use-u") {
    FileHandle.standardError.write(Data("error: --kerr-use-u has been removed after validation tests showed no practical gain.\n".utf8))
    exit(2)
}
if CommandLine.arguments.contains("--sample") {
    FileHandle.standardError.write(Data("error: --sample has been removed. Use --ssaa (1, 2, 4) in run_pipeline.sh.\n".utf8))
    exit(2)
}

guard let device = MTLCreateSystemDefaultDevice() else {
    fail("no Metal device available (check permissions/runtime context)")
}
guard let queue = device.makeCommandQueue() else {
    fail("failed to create Metal command queue")
}
guard let library = device.makeDefaultLibrary() else {
    fail("failed to load default Metal library")
}
guard let fn = library.makeFunction(name: "renderBH") else {
    fail("Metal function renderBH not found in default library")
}
let pipeline = try device.makeComputePipelineState(function: fn)
guard let composeFn = library.makeFunction(name: "composeBH") else {
    fail("Metal function composeBH not found in default library")
}
let composePipeline = try device.makeComputePipelineState(function: composeFn)
guard let composeLinearFn = library.makeFunction(name: "composeLinearRGB") else {
    fail("Metal function composeLinearRGB not found in default library")
}
let composeLinearPipeline = try device.makeComputePipelineState(function: composeLinearFn)
guard let composeLinearTileFn = library.makeFunction(name: "composeLinearRGBTile") else {
    fail("Metal function composeLinearRGBTile not found in default library")
}
let composeLinearTilePipeline = try device.makeComputePipelineState(function: composeLinearTileFn)
guard let composeBHLinearFn = library.makeFunction(name: "composeBHLinear") else {
    fail("Metal function composeBHLinear not found in default library")
}
let composeBHLinearPipeline = try device.makeComputePipelineState(function: composeBHLinearFn)
guard let composeBHLinearTileFn = library.makeFunction(name: "composeBHLinearTile") else {
    fail("Metal function composeBHLinearTile not found in default library")
}
let composeBHLinearTilePipeline = try device.makeComputePipelineState(function: composeBHLinearTileFn)
guard let cloudHistFn = library.makeFunction(name: "composeCloudHist") else {
    fail("Metal function composeCloudHist not found in default library")
}
let cloudHistPipeline = try device.makeComputePipelineState(function: cloudHistFn)
guard let lumHistFn = library.makeFunction(name: "composeLumHist") else {
    fail("Metal function composeLumHist not found in default library")
}
let lumHistPipeline = try device.makeComputePipelineState(function: lumHistFn)
guard let lumHistLinearFn = library.makeFunction(name: "composeLumHistLinear") else {
    fail("Metal function composeLumHistLinear not found in default library")
}
let lumHistLinearPipeline = try device.makeComputePipelineState(function: lumHistLinearFn)
guard let lumHistLinearTileCloudFn = library.makeFunction(name: "composeLumHistLinearTileCloud") else {
    fail("Metal function composeLumHistLinearTileCloud not found in default library")
}
let lumHistLinearTileCloudPipeline = try device.makeComputePipelineState(function: lumHistLinearTileCloudFn)

let width = intArg("--width", default: 1200)
let height = intArg("--height", default: 1200)
let preset = stringArg("--preset", default: "balanced").lowercased()

let baseCamX: Double
let baseCamY: Double
let baseCamZ: Double
let baseFov: Double
let baseRoll: Double
let baseRcp: Double
let baseDiskH: Double
let baseMaxSteps: Int

switch preset {
case "interstellar":
    baseCamX = 4.8
    baseCamY = 0.0
    baseCamZ = 0.55
    baseFov = 58.0
    baseRoll = -18.0
    baseRcp = 9.0
    baseDiskH = 0.08
    baseMaxSteps = 1600
case "eht":
    baseCamX = 8.4
    baseCamY = 0.0
    baseCamZ = 0.10
    baseFov = 30.0
    baseRoll = 0.0
    baseRcp = 4.4
    baseDiskH = 0.20
    baseMaxSteps = 2000
default:
    baseCamX = 22.0
    baseCamY = 0.0
    baseCamZ = 0.9
    baseFov = 58.0
    baseRoll = -18.0
    baseRcp = 9.0
    baseDiskH = 0.01
    baseMaxSteps = 1600
}

let camXFactor = doubleArg("--camX", default: baseCamX)
let camYFactor = doubleArg("--camY", default: baseCamY)
let camZFactor = doubleArg("--camZ", default: baseCamZ)
let fovDeg = doubleArg("--fov", default: baseFov)
let rollDeg = doubleArg("--roll", default: baseRoll)
let rcp = doubleArg("--rcp", default: baseRcp)
let diskHFactor = doubleArg("--diskH", default: baseDiskH)
let maxStepsArg = intArg("--maxSteps", default: baseMaxSteps)
let outPath = stringArg("--output", default: "collisions.bin")
let composeGPU = CommandLine.arguments.contains("--compose-gpu")
let gpuFullCompose = CommandLine.arguments.contains("--gpu-full-compose")
let discardCollisionOutput = CommandLine.arguments.contains("--discard-collisions")
let linear32Intermediate = CommandLine.arguments.contains("--linear32-intermediate")
let linear32OutPath = stringArg("--linear32-out", default: outPath + ".linear32f32")
let imageOutPath = stringArg("--image-out", default: "")
let downsampleArg = max(1, intArg("--downsample", default: 1))
if !(downsampleArg == 1 || downsampleArg == 2 || downsampleArg == 4) {
    FileHandle.standardError.write(Data("error: --downsample must be one of 1, 2, 4\n".utf8))
    exit(2)
}
let metricName = stringArg("--metric", default: "schwarzschild").lowercased()
let metricArg: Int32 = (metricName == "kerr") ? 1 : 0
let spectralEncoding = "gfactor_v1"
let defaultH = 0.01
let hArg = max(1e-6, doubleArg("--h", default: defaultH))
let spinArg = max(-0.999, min(0.999, doubleArg("--spin", default: 0.0)))
let defaultKerrSubsteps = 4
let defaultKerrRadialScale = 1.0
let defaultKerrAzimuthScale = 1.0
let defaultKerrImpactScale = 1.0
let kerrSubstepsArg = max(1, min(8, intArg("--kerr-substeps", default: defaultKerrSubsteps)))
let kerrTolArg = max(1e-6, doubleArg("--kerr-tol", default: 1e-5))
let kerrEscapeMultArg = max(1.0, doubleArg("--kerr-escape-mult", default: 3.0))
let kerrRadialScaleArg = max(0.01, doubleArg("--kerr-radial-scale", default: defaultKerrRadialScale))
let kerrAzimuthScaleArg = max(0.01, doubleArg("--kerr-azimuth-scale", default: defaultKerrAzimuthScale))
let kerrImpactScaleArg = max(0.1, doubleArg("--kerr-impact-scale", default: defaultKerrImpactScale))
if abs(kerrImpactScaleArg - 1.0) > 1e-6 {
    FileHandle.standardError.write(Data("warn: --kerr-impact-scale is deprecated in physics mode and is ignored\n".utf8))
}
let diskFlowTimeArg = doubleArg("--disk-time", default: 0.0)
let diskOrbitalBoostArg = max(0.05, doubleArg("--disk-orbital-boost", default: 1.0))
let diskRadialDriftArg = max(0.0, doubleArg("--disk-radial-drift", default: 0.02))
let diskTurbulenceArg = max(0.0, doubleArg("--disk-turbulence", default: 0.30))
let diskOrbitalBoostInnerArg = max(0.05, doubleArg("--disk-orbital-boost-inner", default: diskOrbitalBoostArg))
let diskOrbitalBoostOuterArg = max(0.05, doubleArg("--disk-orbital-boost-outer", default: diskOrbitalBoostArg))
let diskRadialDriftInnerArg = max(0.0, doubleArg("--disk-radial-drift-inner", default: diskRadialDriftArg))
let diskRadialDriftOuterArg = max(0.0, doubleArg("--disk-radial-drift-outer", default: diskRadialDriftArg))
let diskTurbulenceInnerArg = max(0.0, doubleArg("--disk-turbulence-inner", default: diskTurbulenceArg))
let diskTurbulenceOuterArg = max(0.0, doubleArg("--disk-turbulence-outer", default: diskTurbulenceArg))
let diskFlowStepArg = max(0.03, doubleArg("--disk-flow-step", default: 0.22))
let diskFlowStepsArg = max(2, min(24, intArg("--disk-flow-steps", default: 8)))
let diskMdotEddArg = max(1e-5, doubleArg("--disk-mdot-edd", default: 0.1))
let diskRadiativeEfficiencyArg = min(max(doubleArg("--disk-radiative-efficiency", default: 0.1), 0.01), 0.42)
let diskModeRaw = stringArg("--disk-mode", default: "").lowercased()
let diskPhysicsLegacyRaw = stringArg("--disk-physics-mode", default: "").lowercased()
if !diskModeRaw.isEmpty && !diskPhysicsLegacyRaw.isEmpty {
    guard let modeA = parseDiskMode(diskModeRaw) else {
        fail("invalid --disk-mode \(diskModeRaw). use one of: thin, thick, precision")
    }
    guard let modeB = parseDiskMode(diskPhysicsLegacyRaw) else {
        fail("invalid --disk-physics-mode \(diskPhysicsLegacyRaw). use one of: thin, thick, precision")
    }
    if modeA.id != modeB.id {
        fail("conflicting disk mode: --disk-mode \(diskModeRaw) vs --disk-physics-mode \(diskPhysicsLegacyRaw)")
    }
    FileHandle.standardError.write(Data("warn: --disk-physics-mode is deprecated; prefer --disk-mode\n".utf8))
}
let diskModeResolvedRaw: String = {
    if !diskModeRaw.isEmpty { return diskModeRaw }
    if !diskPhysicsLegacyRaw.isEmpty {
        FileHandle.standardError.write(Data("warn: --disk-physics-mode is deprecated; prefer --disk-mode\n".utf8))
    }
    if !diskPhysicsLegacyRaw.isEmpty { return diskPhysicsLegacyRaw }
    return "thin"
}()
guard let diskModeParsed = parseDiskMode(diskModeResolvedRaw) else {
    if !diskModeRaw.isEmpty {
        fail("invalid --disk-mode \(diskModeRaw). use one of: thin, thick, precision")
    }
    fail("invalid --disk-physics-mode \(diskPhysicsLegacyRaw). use one of: thin, thick, precision")
}
let diskPhysicsModeID: UInt32 = diskModeParsed.id
let diskPhysicsModeArg: String = diskModeParsed.canonical
let diskPlungeFloorArg = max(0.0, doubleArg("--disk-plunge-floor", default: (diskPhysicsModeID == 1 ? 0.02 : 0.0)))
let diskThickScaleArg = max(1.0, doubleArg("--disk-thick-scale", default: 1.3))
let diskColorFactorArg = max(1.0, doubleArg("--disk-color-factor", default: (diskPhysicsModeID == 2 ? 1.7 : 1.0)))
let diskReturningRadRawArg = max(0.0, min(1.0, doubleArg("--disk-returning-rad", default: (diskPhysicsModeID == 2 ? 0.35 : 0.0))))
let diskPrecisionTextureRawArg = max(0.0, min(1.0, doubleArg("--disk-precision-texture", default: (diskPhysicsModeID == 2 ? 0.58 : 0.0))))
let diskPrecisionCloudsName = stringArg("--disk-precision-clouds", default: (diskPhysicsModeID == 2 ? "on" : "off")).lowercased()
let diskPrecisionCloudsEnabled: Bool
switch diskPrecisionCloudsName {
case "on", "true", "1", "yes":
    diskPrecisionCloudsEnabled = true
case "off", "false", "0", "no":
    diskPrecisionCloudsEnabled = false
default:
    fail("invalid --disk-precision-clouds \(diskPrecisionCloudsName). use on|off")
}
let diskCloudCoverageRawArg = max(0.0, min(1.0, doubleArg("--disk-cloud-coverage", default: (diskPhysicsModeID == 2 ? 0.88 : 0.0))))
let diskCloudOpticalDepthRawArg = max(0.0, min(12.0, doubleArg("--disk-cloud-optical-depth", default: (diskPhysicsModeID == 2 ? 2.0 : 0.0))))
let diskCloudPorosityRawArg = max(0.0, min(1.0, doubleArg("--disk-cloud-porosity", default: (diskPhysicsModeID == 2 ? 0.18 : 0.0))))
let diskCloudShadowStrengthRawArg = max(0.0, min(1.0, doubleArg("--disk-cloud-shadow-strength", default: (diskPhysicsModeID == 2 ? 0.90 : 0.0))))
let diskReturnBouncesRawArg = max(1, min(4, intArg("--disk-return-bounces", default: (diskPhysicsModeID == 2 ? 2 : 1))))
let diskRTStepsRawArg = max(0, min(32, intArg("--disk-rt-steps", default: 0)))
let diskScatteringAlbedoRawArg = max(0.0, min(1.0, doubleArg("--disk-scattering-albedo", default: (diskPhysicsModeID == 2 ? 0.62 : 0.0))))
let diskReturningRadArg = (diskPhysicsModeID == 2) ? diskReturningRadRawArg : 0.0
let diskPrecisionTextureArg = (diskPhysicsModeID == 2) ? diskPrecisionTextureRawArg : 0.0
let diskCloudCoverageArg = (diskPhysicsModeID == 2 && diskPrecisionCloudsEnabled) ? diskCloudCoverageRawArg : 0.0
let diskCloudOpticalDepthArg = (diskPhysicsModeID == 2 && diskPrecisionCloudsEnabled) ? diskCloudOpticalDepthRawArg : 0.0
let diskCloudPorosityArg = (diskPhysicsModeID == 2 && diskPrecisionCloudsEnabled) ? diskCloudPorosityRawArg : 0.0
let diskCloudShadowStrengthArg = (diskPhysicsModeID == 2 && diskPrecisionCloudsEnabled) ? diskCloudShadowStrengthRawArg : 0.0
let diskReturnBouncesArg = (diskPhysicsModeID == 2) ? diskReturnBouncesRawArg : 1
let diskRTStepsArg = (diskPhysicsModeID == 2) ? diskRTStepsRawArg : 0
let diskScatteringAlbedoArg = (diskPhysicsModeID == 2) ? diskScatteringAlbedoRawArg : 0.0
if diskPhysicsModeID != 2 && (diskReturningRadRawArg > 1e-8 || diskPrecisionTextureRawArg > 1e-8) {
    FileHandle.standardError.write(Data("warn: --disk-returning-rad and --disk-precision-texture are only active in precision mode\n".utf8))
}
if diskPhysicsModeID != 2 && (diskCloudCoverageRawArg > 1e-8 || diskCloudOpticalDepthRawArg > 1e-8 || diskCloudPorosityRawArg > 1e-8 || diskCloudShadowStrengthRawArg > 1e-8) {
    FileHandle.standardError.write(Data("warn: precision cloud args are only active in precision mode\n".utf8))
}
if diskPhysicsModeID != 2 && (diskReturnBouncesRawArg != 1 || diskRTStepsRawArg > 0 || diskScatteringAlbedoRawArg > 1e-8) {
    FileHandle.standardError.write(Data("warn: --disk-return-bounces, --disk-rt-steps and --disk-scattering-albedo are only active in precision mode\n".utf8))
}
let diskModelArg = stringArg("--disk-model", default: "auto").lowercased()
let diskAtlasPathArg = stringArg("--disk-atlas", default: "")
let diskAtlasWidthArg = max(0, intArg("--disk-atlas-width", default: 0))
let diskAtlasHeightArg = max(0, intArg("--disk-atlas-height", default: 0))
let diskAtlasTempScaleArg = max(0.0, doubleArg("--disk-atlas-temp-scale", default: 1.0))
let diskAtlasDensityBlendDefault = (diskPhysicsModeID == 1) ? 0.55 : 0.70
let diskAtlasDensityBlendArg = max(0.0, min(1.0, doubleArg("--disk-atlas-density-blend", default: diskAtlasDensityBlendDefault)))
let diskAtlasVrScaleArg = max(0.0, doubleArg("--disk-atlas-vr-scale", default: 0.35))
let diskAtlasVphiScaleArg = max(0.0, doubleArg("--disk-atlas-vphi-scale", default: 1.0))
let diskAtlasRMinArg = doubleArg("--disk-atlas-r-min", default: -1.0)
let diskAtlasRMaxArg = doubleArg("--disk-atlas-r-max", default: -1.0)
let diskAtlasRWarpArg = doubleArg("--disk-atlas-r-warp", default: -1.0)
let tileSizeArg = max(0, intArg("--tile-size", default: 0))
let autoTile = width * height > 8_000_000
let tileSize = (tileSizeArg > 0) ? tileSizeArg : (autoTile ? 1024 : max(width, height))
let hasLookArg = CommandLine.arguments.contains("--look")
let defaultLookName = (diskPhysicsModeID == 2 && !hasLookArg) ? "balanced" : preset
let composeLook = stringArg("--look", default: defaultLookName).lowercased()
let composeLookID: UInt32
switch composeLook {
case "interstellar": composeLookID = 1
case "eht": composeLookID = 2
default: composeLookID = 0
}
let composeDitherDefault = (diskPhysicsModeID == 2) ? 0.0 : 0.75
let composeDitherArg = Float(doubleArg("--dither", default: composeDitherDefault))
let composeInnerEdgeArg = Float(max(1.0, doubleArg("--inner-edge-mult", default: 1.4)))
let composeSpectralStepArg = Float(max(0.25, doubleArg("--spectral-step", default: 5.0)))
let composeChunkArg = max(1, intArg("--chunk", default: 160000))
let exposureSamplesArg = max(0, intArg("--exposure-samples", default: 200000))
let exposureArg = Float(doubleArg("--exposure", default: -1.0))
let composePrecisionName = stringArg("--compose-precision", default: "precise").lowercased()
let composePrecisionID: UInt32 = (composePrecisionName == "fast") ? 0 : 1
let composeAnalysisMode: UInt32 = (diskPhysicsModeID == 2) ? (diskPrecisionCloudsEnabled ? 2 : 1) : 0
let composeExposureBase: Float = {
    if exposureArg > 0 { return exposureArg }
    switch composeLookID {
    case 1: return 7.0e-18   // interstellar default
    case 2: return 5.2e-18   // eht default
    default: return 6.8e-18  // balanced default
    }
}()
let spectralEncodingID: UInt32 = (spectralEncoding == "gfactor_v1") ? 1 : 0
var composeExposure = composeExposureBase
let useLinear32Intermediate = composeGPU && !gpuFullCompose && linear32Intermediate
var diskModelResolved: String
switch diskModelArg {
case "flow", "procedural", "legacy", "noise":
    diskModelResolved = "flow"
case "perlin":
    diskModelResolved = "perlin"
case "atlas":
    diskModelResolved = "atlas"
case "auto":
    diskModelResolved = diskAtlasPathArg.isEmpty ? "flow" : "atlas"
default:
    fail("invalid --disk-model \(diskModelArg). use one of: flow, perlin, atlas, auto (alias: procedural)")
}
if diskPhysicsModeID == 2 && diskModelResolved != "flow" {
    FileHandle.standardError.write(Data("warn: precision mode renders with flow disk model; requested --disk-model \(diskModelResolved) is treated as flow\n".utf8))
    diskModelResolved = "flow"
}
if diskModelResolved == "atlas" && diskAtlasPathArg.isEmpty {
    fail("--disk-model atlas requires --disk-atlas <path>")
}
if diskModelResolved != "atlas" && !diskAtlasPathArg.isEmpty {
    FileHandle.standardError.write(Data("warn: --disk-model \(diskModelResolved) ignores --disk-atlas and atlas tuning args at render time\n".utf8))
}
let diskAtlasEnabled = (diskModelResolved == "atlas")
let diskNoiseModel: UInt32 = (diskModelResolved == "perlin") ? 1 : 0
let diskAtlasWrapPhi: UInt32 = 1

let diskAtlasData: Data
let diskAtlasWidth: Int
let diskAtlasHeight: Int
var diskAtlasMetaRMin: Double? = nil
var diskAtlasMetaRMax: Double? = nil
var diskAtlasMetaRWarp: Double? = nil
if diskAtlasEnabled {
    do {
        let loaded = try loadDiskAtlas(path: diskAtlasPathArg, widthOverride: diskAtlasWidthArg, heightOverride: diskAtlasHeightArg)
        diskAtlasData = loaded.data
        diskAtlasWidth = loaded.width
        diskAtlasHeight = loaded.height
        diskAtlasMetaRMin = loaded.rNormMin
        diskAtlasMetaRMax = loaded.rNormMax
        diskAtlasMetaRWarp = loaded.rNormWarp
    } catch {
        fail("failed to load --disk-atlas: \(error.localizedDescription)")
    }
} else {
    var fallback = SIMD4<Float>(1.0, 0.0, 0.0, 1.0)
    diskAtlasData = withUnsafeBytes(of: &fallback) { Data($0) }
    diskAtlasWidth = 1
    diskAtlasHeight = 1
}
let diskAtlasRMinDefault = 1.0
let diskAtlasRMaxDefault = max(diskAtlasRMinDefault + 1e-6, rcp)
let diskAtlasRMin = max(0.0, (diskAtlasRMinArg >= 0.0) ? diskAtlasRMinArg : (diskAtlasMetaRMin ?? diskAtlasRMinDefault))
let diskAtlasRMaxCandidate = (diskAtlasRMaxArg >= 0.0) ? diskAtlasRMaxArg : (diskAtlasMetaRMax ?? diskAtlasRMaxDefault)
let diskAtlasRMax = max(diskAtlasRMin + 1e-6, diskAtlasRMaxCandidate)
let diskAtlasRWarpCandidate = (diskAtlasRWarpArg >= 0.0) ? diskAtlasRWarpArg : (diskAtlasMetaRWarp ?? 1.0)
let diskAtlasRWarp = max(1e-3, diskAtlasRWarpCandidate)

if composeGPU {
    if imageOutPath.isEmpty {
        FileHandle.standardError.write(Data("error: --compose-gpu requires --image-out <path>\n".utf8))
        exit(2)
    }
    if (width % downsampleArg) != 0 || (height % downsampleArg) != 0 {
        FileHandle.standardError.write(Data("error: width/height must be divisible by --downsample\n".utf8))
        exit(2)
    }
}

print("render config preset=\(preset) \(width)x\(height), cam=(\(camXFactor),\(camYFactor),\(camZFactor))rs, fov=\(fovDeg), roll=\(rollDeg), rcp=\(rcp), diskH=\(diskHFactor)rs, maxSteps=\(maxStepsArg), metric=\(metricName), spin=\(spinArg), kerrSubsteps=\(kerrSubstepsArg), kerrTol=\(kerrTolArg), kerrEscape=\(kerrEscapeMultArg), kerrScale=(\(kerrRadialScaleArg),\(kerrAzimuthScaleArg),\(kerrImpactScaleArg)), diskModel=\(diskModelResolved), diskFlow=(t=\(diskFlowTimeArg),omega=\(diskOrbitalBoostArg),vr=\(diskRadialDriftArg),turb=\(diskTurbulenceArg),omegaIn=\(diskOrbitalBoostInnerArg),omegaOut=\(diskOrbitalBoostOuterArg),vrIn=\(diskRadialDriftInnerArg),vrOut=\(diskRadialDriftOuterArg),turbIn=\(diskTurbulenceInnerArg),turbOut=\(diskTurbulenceOuterArg),dt=\(diskFlowStepArg),steps=\(diskFlowStepsArg)), diskPhysics=(mode=\(diskPhysicsModeArg),mdotEdd=\(diskMdotEddArg),eta=\(diskRadiativeEfficiencyArg),plunge=\(diskPlungeFloorArg),thickScale=\(diskThickScaleArg),fcol=\(diskColorFactorArg),ret=\(diskReturningRadArg),retBounces=\(diskReturnBouncesArg),rtSteps=\(diskRTStepsArg),albedo=\(diskScatteringAlbedoArg),texture=\(diskPrecisionTextureArg),precisionClouds=\(diskPrecisionCloudsEnabled),cloudCoverage=\(diskCloudCoverageArg),cloudTau=\(diskCloudOpticalDepthArg),cloudPorosity=\(diskCloudPorosityArg),cloudShadow=\(diskCloudShadowStrengthArg)), diskAtlas=(enabled=\(diskAtlasEnabled),size=\(diskAtlasWidth)x\(diskAtlasHeight),temp=\(diskAtlasTempScaleArg),density=\(diskAtlasDensityBlendArg),vr=\(diskAtlasVrScaleArg),vphi=\(diskAtlasVphiScaleArg),rMin=\(diskAtlasRMin),rMax=\(diskAtlasRMax),rWarp=\(diskAtlasRWarp)), tileSize=\(tileSize), composeGPU=\(composeGPU), downsample=\(downsampleArg), linear32Intermediate=\(useLinear32Intermediate), analysisMode=\(composeAnalysisMode)")

let c: Double = 299_792_458
let G: Double = 6.67430e-11
let k: Double = 1.380649e-23
let M: Double = 1e35

let rsD = 2.0 * G * M / (c * c)
let reD = rsD * rcp
let heD = rsD * diskHFactor
let diskInnerRadiusCompose = diskInnerRadiusM(metric: metricArg, spin: spinArg, rs: rsD)
let diskHorizonRadiusCompose = diskHorizonRadiusM(metric: metricArg, spin: spinArg, rs: rsD) * (1.0 + 2.0e-5)

let camPos = SIMD3<Float>(Float(rsD * camXFactor), Float(rsD * camYFactor), Float(rsD * camZFactor))
let z = normalize(camPos)

let vup = SIMD3<Float>(0, 0, 1)
let planeX0 = normalize(cross(vup, z))
let planeY0 = normalize(cross(z, planeX0))
let roll = Float(rollDeg * Double.pi / 180.0)
let planeX = cos(roll) * planeX0 + sin(roll) * planeY0
let planeY = normalize(cross(z, planeX))

let d = Float(Double(width) / (2.0 * tan(fovDeg * Double.pi / 360.0)))

var params = Params(
    width: UInt32(width),
    height: UInt32(height),
    fullWidth: UInt32(width),
    fullHeight: UInt32(height),
    offsetX: 0,
    offsetY: 0,
    camPos: camPos,
    planeX: planeX,
    planeY: planeY,
    z: z,
    d: d,
    rs: Float(rsD),
    re: Float(reD),
    he: Float(heD),
    M: Float(M),
    G: Float(G),
    c: Float(c),
    k: Float(k),
    h: Float(hArg),
    maxSteps: Int32(maxStepsArg),
    eps: 1e-5,
    metric: metricArg,
    spin: Float(spinArg),
    kerrSubsteps: Int32(kerrSubstepsArg),
    kerrTol: Float(kerrTolArg),
    kerrEscapeMult: Float(kerrEscapeMultArg),
    kerrRadialScale: Float(kerrRadialScaleArg),
    kerrAzimuthScale: Float(kerrAzimuthScaleArg),
    kerrImpactScale: Float(kerrImpactScaleArg),
    diskFlowTime: Float(diskFlowTimeArg),
    diskOrbitalBoost: Float(diskOrbitalBoostArg),
    diskRadialDrift: Float(diskRadialDriftArg),
    diskTurbulence: Float(diskTurbulenceArg),
    diskOrbitalBoostInner: Float(diskOrbitalBoostInnerArg),
    diskOrbitalBoostOuter: Float(diskOrbitalBoostOuterArg),
    diskRadialDriftInner: Float(diskRadialDriftInnerArg),
    diskRadialDriftOuter: Float(diskRadialDriftOuterArg),
    diskTurbulenceInner: Float(diskTurbulenceInnerArg),
    diskTurbulenceOuter: Float(diskTurbulenceOuterArg),
    diskFlowStep: Float(diskFlowStepArg),
    diskFlowSteps: Float(diskFlowStepsArg),
    diskAtlasMode: diskAtlasEnabled ? 1 : 0,
    diskAtlasWidth: UInt32(diskAtlasWidth),
    diskAtlasHeight: UInt32(diskAtlasHeight),
    diskAtlasWrapPhi: diskAtlasWrapPhi,
    diskAtlasTempScale: Float(diskAtlasTempScaleArg),
    diskAtlasDensityBlend: Float(diskAtlasDensityBlendArg),
    diskAtlasVrScale: Float(diskAtlasVrScaleArg),
    diskAtlasVphiScale: Float(diskAtlasVphiScaleArg),
    diskAtlasRNormMin: Float(diskAtlasRMin),
    diskAtlasRNormMax: Float(diskAtlasRMax),
    diskAtlasRNormWarp: Float(diskAtlasRWarp),
    diskNoiseModel: diskNoiseModel,
    diskMdotEdd: Float(diskMdotEddArg),
    diskRadiativeEfficiency: Float(diskRadiativeEfficiencyArg),
    diskPhysicsMode: diskPhysicsModeID,
    diskPlungeFloor: Float(diskPlungeFloorArg),
    diskThickScale: Float(diskThickScaleArg),
    diskColorFactor: Float(diskColorFactorArg),
    diskReturningRad: Float(diskReturningRadArg),
    diskPrecisionTexture: Float(diskPrecisionTextureArg),
    diskCloudCoverage: Float(diskCloudCoverageArg),
    diskCloudOpticalDepth: Float(diskCloudOpticalDepthArg),
    diskCloudPorosity: Float(diskCloudPorosityArg),
    diskCloudShadowStrength: Float(diskCloudShadowStrengthArg),
    diskReturnBounces: UInt32(diskReturnBouncesArg),
    diskRTSteps: UInt32(diskRTStepsArg),
    diskScatteringAlbedo: Float(diskScatteringAlbedoArg),
    diskRTPad: 0
)

let count = width * height
let stride = MemoryLayout<CollisionInfo>.stride
let outSize = count * stride
let url = URL(fileURLWithPath: outPath)
let linearStride = MemoryLayout<SIMD4<Float>>.stride
let linearOutSize = count * linearStride
let linearURL = URL(fileURLWithPath: linear32OutPath)
let useInMemoryCollisions = composeGPU && gpuFullCompose
if discardCollisionOutput && !(useInMemoryCollisions || useLinear32Intermediate) {
    fail("--discard-collisions is only supported with --gpu-full-compose or --linear32-intermediate")
}
let collisionBuffer: MTLBuffer? = useInMemoryCollisions ? device.makeBuffer(length: outSize, options: .storageModeShared) : nil
if useInMemoryCollisions, collisionBuffer == nil {
    fail("failed to allocate in-memory collision buffer (\(outSize) bytes)")
}
let collisionBase = collisionBuffer?.contents()
var linearOutHandle: FileHandle? = nil
if useLinear32Intermediate {
    _ = FileManager.default.createFile(atPath: linearURL.path, contents: nil)
    linearOutHandle = try FileHandle(forWritingTo: linearURL)
}
var outHandle: FileHandle? = nil
if !useInMemoryCollisions && !discardCollisionOutput && !useLinear32Intermediate {
    _ = FileManager.default.createFile(atPath: url.path, contents: nil)
    outHandle = try FileHandle(forWritingTo: url)
    try outHandle?.truncate(atOffset: UInt64(outSize))
}
defer {
    try? outHandle?.close()
    try? linearOutHandle?.close()
}

let tg = MTLSize(width: 16, height: 16, depth: 1)
let dsForTile = composeGPU ? downsampleArg : 1
let baseTile = max(1, tileSize)
let alignedTile = max(dsForTile, (baseTile / dsForTile) * dsForTile)
let effectiveTile = alignedTile
if effectiveTile < max(width, height) {
    print("tile rendering enabled: \(effectiveTile)x\(effectiveTile)")
}
guard let traceParamBuf = device.makeBuffer(length: MemoryLayout<Params>.stride, options: .storageModeShared) else {
    fail("failed to allocate trace param buffer")
}
let maxTraceTilePixels = effectiveTile * effectiveTile
guard let traceTileBuf = device.makeBuffer(length: maxTraceTilePixels * stride, options: .storageModeShared) else {
    fail("failed to allocate trace tile buffer")
}
guard let diskAtlasBuf = device.makeBuffer(length: diskAtlasData.count, options: .storageModeShared) else {
    fail("failed to allocate disk atlas buffer")
}
_ = diskAtlasData.withUnsafeBytes { raw in
    guard let base = raw.baseAddress else { return }
    memcpy(diskAtlasBuf.contents(), base, diskAtlasData.count)
}
let composeLinearTileBuf: MTLBuffer? = useLinear32Intermediate
    ? device.makeBuffer(length: maxTraceTilePixels * linearStride, options: .storageModeShared)
    : nil
if useLinear32Intermediate, composeLinearTileBuf == nil {
    fail("failed to allocate linear32 tile buffer")
}
let composeLinearParamBuf: MTLBuffer? = useLinear32Intermediate
    ? device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared)
    : nil
if useLinear32Intermediate, composeLinearParamBuf == nil {
    fail("failed to allocate linear32 compose param buffer")
}
var composeParamsBase = params
let composeBaseBufForLinear: MTLBuffer? = useLinear32Intermediate
    ? device.makeBuffer(bytes: &composeParamsBase, length: MemoryLayout<Params>.stride, options: [])
    : nil
if useLinear32Intermediate, composeBaseBufForLinear == nil {
    fail("failed to allocate linear32 base param buffer")
}
let tgLinearTile1D = MTLSize(width: max(1, min(256, composeLinearTilePipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)
let linearCloudBins = 2048
var linearCloudHistGlobal = [UInt32](repeating: 0, count: linearCloudBins)
var linearCloudSampleCount: UInt64 = 0
var linearGlobalCloudQ10: Float = 0.0
var linearGlobalCloudQ90: Float = 1.0
var linearGlobalCloudInvSpan: Float = 1.0
let linearLumBins = 4096
let linearLumLogMin: Float = 8.0
let linearLumLogMax: Float = 20.0

var hitCount = 0
var donePixels = 0
let totalPixels = count
let outWidth = width / downsampleArg
let outHeight = height / downsampleArg
let composePrepassOpsTarget: Int
if composeGPU && gpuFullCompose && exposureArg <= 0 {
    composePrepassOpsTarget = 3 * count
} else if composeGPU && useLinear32Intermediate && exposureArg <= 0 {
    composePrepassOpsTarget = count
} else {
    composePrepassOpsTarget = 0
}
let composeOps = composeGPU ? (composePrepassOpsTarget + outWidth * outHeight) : 0
let totalOps = totalPixels + composeOps
let progressStep = max(1, totalOps / 256)
var nextProgressMark = progressStep
var lastProgressPrint = Date().timeIntervalSince1970
let traceTilesX = max(1, (width + effectiveTile - 1) / effectiveTile)
let traceTilesY = max(1, (height + effectiveTile - 1) / effectiveTile)
let traceTileTotal = max(1, traceTilesX * traceTilesY)
var traceTileIndex = 0
emitETAProgress(0, totalOps, "swift_trace", "task=trace tile=0/\(traceTileTotal)")
var ty = 0
while ty < height {
    let tileH = min(effectiveTile, height - ty)
    var tx = 0
    while tx < width {
        let tileW = min(effectiveTile, width - tx)

        var tileParams = params
        tileParams.width = UInt32(tileW)
        tileParams.height = UInt32(tileH)
        tileParams.fullWidth = UInt32(width)
        tileParams.fullHeight = UInt32(height)
        tileParams.offsetX = UInt32(tx)
        tileParams.offsetY = UInt32(ty)

        updateBuffer(traceParamBuf, with: &tileParams)
        let tileCount = tileW * tileH

        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeComputeCommandEncoder()!
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(traceParamBuf, offset: 0, index: 0)
        enc.setBuffer(traceTileBuf, offset: 0, index: 1)
        enc.setBuffer(diskAtlasBuf, offset: 0, index: 2)

        let grid = MTLSize(width: tileW, height: tileH, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        let ptr = traceTileBuf.contents().bindMemory(to: CollisionInfo.self, capacity: tileCount)
        for i in 0..<tileCount where ptr[i].hit != 0 { hitCount += 1 }

        if useLinear32Intermediate {
            guard let composeBaseBufForLinear, let composeLinearParamBuf, let composeLinearTileBuf, let linearOutHandle else {
                fail("linear32 intermediate buffers are not available")
            }

            var linearTileParams = ComposeParams(
                tileWidth: UInt32(tileW),
                tileHeight: UInt32(tileH),
                downsample: 1,
                outTileWidth: 0,
                outTileHeight: 0,
                srcOffsetX: UInt32(tx),
                srcOffsetY: UInt32(ty),
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
                cloudBins: UInt32(linearCloudBins),
                lumBins: UInt32(linearLumBins),
                lumLogMin: linearLumLogMin,
                lumLogMax: linearLumLogMax
            )
            updateBuffer(composeLinearParamBuf, with: &linearTileParams)

            let linearCmd = queue.makeCommandBuffer()!
            let linearEnc = linearCmd.makeComputeCommandEncoder()!
            linearEnc.setComputePipelineState(composeLinearTilePipeline)
            linearEnc.setBuffer(composeBaseBufForLinear, offset: 0, index: 0)
            linearEnc.setBuffer(composeLinearParamBuf, offset: 0, index: 1)
            linearEnc.setBuffer(traceTileBuf, offset: 0, index: 2)
            linearEnc.setBuffer(composeLinearTileBuf, offset: 0, index: 3)
            linearEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgLinearTile1D)
            linearEnc.endEncoding()
            linearCmd.commit()
            linearCmd.waitUntilCompleted()

            let linearPtr = composeLinearTileBuf.contents().bindMemory(to: SIMD4<Float>.self, capacity: tileCount)
            for i in 0..<tileCount {
                let w = linearPtr[i].w
                if w < 0 { continue }
                let cloud = min(max(Double(w), 0.0), 1.0)
                let bin = min(max(Int(floor(cloud * Double(linearCloudBins - 1) + 0.5)), 0), linearCloudBins - 1)
                linearCloudHistGlobal[bin] = linearCloudHistGlobal[bin] &+ 1
                linearCloudSampleCount += 1
            }

            for row in 0..<tileH {
                let rowBytes = tileW * linearStride
                let src = composeLinearTileBuf.contents().advanced(by: row * rowBytes)
                let dstOffset = ((ty + row) * width + tx) * linearStride
                try linearOutHandle.seek(toOffset: UInt64(dstOffset))
                try linearOutHandle.write(contentsOf: Data(bytes: src, count: rowBytes))
            }
        } else {
            for row in 0..<tileH {
                let rowBytes = tileW * stride
                let src = traceTileBuf.contents().advanced(by: row * rowBytes)
                let dstOffset = ((ty + row) * width + tx) * stride
                if let collisionBase {
                    memcpy(collisionBase.advanced(by: dstOffset), src, rowBytes)
                } else if let outHandle {
                    try outHandle.seek(toOffset: UInt64(dstOffset))
                    try outHandle.write(contentsOf: Data(bytes: src, count: rowBytes))
                } else if discardCollisionOutput {
                    // intentionally skip collision writes when output is marked disposable
                } else {
                    fail("no collision output sink available")
                }
            }
        }
        donePixels += tileCount
        traceTileIndex += 1
        let now = Date().timeIntervalSince1970
        if donePixels >= totalPixels || donePixels >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
            emitETAProgress(donePixels, totalOps, "swift_trace", "task=trace tile=\(traceTileIndex)/\(traceTileTotal)")
            lastProgressPrint = now
            while nextProgressMark <= donePixels {
                nextProgressMark += progressStep
            }
        }
        tx += tileW
    }
    ty += tileH
}

if composeGPU {
    if !useInMemoryCollisions && !useLinear32Intermediate {
        try outHandle?.synchronize()
    }
    if useLinear32Intermediate {
        try linearOutHandle?.synchronize()

        if linearCloudSampleCount > 0 {
            linearGlobalCloudQ10 = linearCloudHistGlobal.withUnsafeBufferPointer {
                quantileFromUniformHistogram($0, 0.08, 0.0, 1.0)
            }
            linearGlobalCloudQ90 = linearCloudHistGlobal.withUnsafeBufferPointer {
                quantileFromUniformHistogram($0, 0.92, 0.0, 1.0)
            }
            linearGlobalCloudInvSpan = 1.0 / max(linearGlobalCloudQ90 - linearGlobalCloudQ10, 1e-6)
        }
        print("compose cloud normalization q10=\(linearGlobalCloudQ10) q90=\(linearGlobalCloudQ90) (linear32)")

        if exposureArg <= 0 {
            let rawComposeRows = max(1, composeChunkArg / max(width, 1))
            var composeRows = max(downsampleArg, (rawComposeRows / downsampleArg) * downsampleArg)
            if composeRows <= 0 { composeRows = downsampleArg }
            if composeRows > height { composeRows = height }

            let maxComposeTileCount = width * composeRows
            let lumHistBytes = linearLumBins * MemoryLayout<UInt32>.stride
            let tgLumTile1D = MTLSize(
                width: max(1, min(256, lumHistLinearTileCloudPipeline.maxTotalThreadsPerThreadgroup)),
                height: 1,
                depth: 1
            )
            guard let linearTileInBuf = device.makeBuffer(length: maxComposeTileCount * linearStride, options: .storageModeShared) else {
                fail("failed to allocate linear32 exposure prepass input tile buffer")
            }
            guard let lumParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
                fail("failed to allocate linear32 exposure prepass param buffer")
            }
            guard let lumHistBuf = device.makeBuffer(length: lumHistBytes, options: .storageModeShared) else {
                fail("failed to allocate linear32 exposure prepass histogram buffer")
            }

            var lumHistGlobal = [UInt32](repeating: 0, count: linearLumBins)
            var lumSampleCount: UInt64 = 0
            let readHandle = try FileHandle(forReadingFrom: linearURL)
            defer { try? readHandle.close() }

            var pty = 0
            var prepassDone = 0
            let prepassTileTotal = max(1, (height + composeRows - 1) / composeRows)
            var prepassTileIndex = 0
            while pty < height {
                let tileH = min(composeRows, height - pty)
                let tileW = width
                let tileCount = tileW * tileH
                let rowBytes = tileW * linearStride
                for row in 0..<tileH {
                    let offset = ((pty + row) * width) * linearStride
                    try readHandle.seek(toOffset: UInt64(offset))
                    let rowData = try readHandle.read(upToCount: rowBytes) ?? Data()
                    if rowData.count != rowBytes {
                        throw NSError(domain: "Blackhole", code: 2, userInfo: [NSLocalizedDescriptionKey: "short read while linear32 exposure prepass"])
                    }
                    _ = rowData.withUnsafeBytes { raw in
                        memcpy(linearTileInBuf.contents().advanced(by: row * rowBytes), raw.baseAddress!, rowBytes)
                    }
                }

                var lumParams = ComposeParams(
                    tileWidth: UInt32(tileW),
                    tileHeight: UInt32(tileH),
                    downsample: 1,
                    outTileWidth: 0,
                    outTileHeight: 0,
                    srcOffsetX: 0,
                    srcOffsetY: UInt32(pty),
                    outOffsetX: 0,
                    outOffsetY: 0,
                    fullInputWidth: UInt32(width),
                    fullInputHeight: UInt32(height),
                    exposure: composeExposure,
                    dither: composeDitherArg,
                    innerEdgeMult: composeInnerEdgeArg,
                    spectralStep: composeSpectralStepArg,
                    cloudQ10: linearGlobalCloudQ10,
                    cloudInvSpan: linearGlobalCloudInvSpan,
                    look: composeLookID,
                    spectralEncoding: spectralEncodingID,
                    precisionMode: composePrecisionID,
                    analysisMode: composeAnalysisMode,
                    cloudBins: UInt32(linearCloudBins),
                    lumBins: UInt32(linearLumBins),
                    lumLogMin: linearLumLogMin,
                    lumLogMax: linearLumLogMax
                )
                updateBuffer(lumParamBuf, with: &lumParams)
                memset(lumHistBuf.contents(), 0, lumHistBytes)

                let lumCmd = queue.makeCommandBuffer()!
                let lumEnc = lumCmd.makeComputeCommandEncoder()!
                lumEnc.setComputePipelineState(lumHistLinearTileCloudPipeline)
                lumEnc.setBuffer(lumParamBuf, offset: 0, index: 0)
                lumEnc.setBuffer(linearTileInBuf, offset: 0, index: 1)
                lumEnc.setBuffer(lumHistBuf, offset: 0, index: 2)
                lumEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgLumTile1D)
                lumEnc.endEncoding()
                lumCmd.commit()
                lumCmd.waitUntilCompleted()

                let lumPtr = lumHistBuf.contents().bindMemory(to: UInt32.self, capacity: linearLumBins)
                for i in 0..<linearLumBins {
                    let c = lumPtr[i]
                    lumHistGlobal[i] = lumHistGlobal[i] &+ c
                    lumSampleCount += UInt64(c)
                }

                prepassDone += tileCount
                prepassTileIndex += 1
                let doneAll = totalPixels + prepassDone
                let now = Date().timeIntervalSince1970
                if doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                    emitETAProgress(min(doneAll, totalOps), totalOps, "swift_prepass", "task=linear32_lumhist tile=\(prepassTileIndex)/\(prepassTileTotal)")
                    lastProgressPrint = now
                    while nextProgressMark <= doneAll {
                        nextProgressMark += progressStep
                    }
                }

                pty += tileH
            }

            if lumSampleCount == 0 {
                composeExposure = 1.0
            } else {
                let p50Log = lumHistGlobal.withUnsafeBufferPointer {
                    quantileFromUniformHistogram($0, 0.50, linearLumLogMin, linearLumLogMax)
                }
                let p995Log = lumHistGlobal.withUnsafeBufferPointer {
                    quantileFromUniformHistogram($0, 0.995, linearLumLogMin, linearLumLogMax)
                }
                let p50 = pow(10.0, Double(p50Log))
                let p995 = pow(10.0, Double(p995Log))
                var targetWhite: Float = 0.8
                if composeLookID == 1 { targetWhite = 0.9 }
                else if composeLookID == 2 { targetWhite = 0.6 }
                composeExposure = targetWhite / max(Float(p995), 1e-12)
                print("lum(linear32) p50=\(p50), p99.5=\(p995), samples=\(lumSampleCount)")
            }
        }
    }

    composeParamsBase = params
    if gpuFullCompose {
        guard let collisionBase else {
            fail("gpu-full-compose requires in-memory collision buffer")
        }
        let cloudBins = 8192
        let lumBins = 4096
        let lumLogMin: Float = 8.0
        let lumLogMax: Float = 20.0
        let cloudHistBytes = cloudBins * MemoryLayout<UInt32>.stride
        let lumHistBytes = lumBins * MemoryLayout<UInt32>.stride
        let tgCloud1D = MTLSize(width: max(1, min(256, cloudHistPipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)
        let tgLinear1D = MTLSize(width: max(1, min(256, composeLinearPipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)
        let tgLum1D = MTLSize(width: max(1, min(256, lumHistLinearPipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)

        var globalCloudQ10: Float = 0.0
        var globalCloudQ90: Float = 1.0
        var globalCloudInvSpan = 1.0 / max(globalCloudQ90 - globalCloudQ10, 1e-6)
        let composeBaseBuf = device.makeBuffer(bytes: &composeParamsBase, length: MemoryLayout<Params>.stride, options: [])!
        var composePrepassOps = 0

        var composeParamsTemplate = ComposeParams(
            tileWidth: 0,
            tileHeight: 0,
            downsample: UInt32(downsampleArg),
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
            cloudQ10: globalCloudQ10,
            cloudInvSpan: globalCloudInvSpan,
            look: composeLookID,
            spectralEncoding: spectralEncodingID,
            precisionMode: composePrecisionID,
            analysisMode: composeAnalysisMode,
            cloudBins: UInt32(cloudBins),
            lumBins: UInt32(lumBins),
            lumLogMin: lumLogMin,
            lumLogMax: lumLogMax
        )

        let rawComposeRows = max(1, composeChunkArg / max(width, 1))
        var composeRows = max(downsampleArg, (rawComposeRows / downsampleArg) * downsampleArg)
        if composeRows <= 0 { composeRows = downsampleArg }
        if composeRows > height { composeRows = height }
        let composeTileTotal = max(1, (height + composeRows - 1) / composeRows)
        let maxComposeTileCount = width * composeRows
        let maxComposeOutTileCount = (width / downsampleArg) * (composeRows / downsampleArg)
        guard let composeTileInBuf = device.makeBuffer(length: maxComposeTileCount * stride, options: .storageModeShared) else {
            fail("failed to allocate compose input tile buffer")
        }
        guard let composeParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
            fail("failed to allocate compose param buffer")
        }
        guard let cloudParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
            fail("failed to allocate cloud hist param buffer")
        }
        guard let lumParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
            fail("failed to allocate luminance hist param buffer")
        }
        guard let cloudHistBuf = device.makeBuffer(length: cloudHistBytes, options: .storageModeShared) else {
            fail("failed to allocate cloud histogram buffer")
        }
        guard let lumHistBuf = device.makeBuffer(length: lumHistBytes, options: .storageModeShared) else {
            fail("failed to allocate luminance histogram buffer")
        }
        guard let composeOutBuf = device.makeBuffer(length: maxComposeOutTileCount * 4, options: .storageModeShared) else {
            fail("failed to allocate compose output tile buffer")
        }
        let composeLinearFullBuf: MTLBuffer? = (exposureArg <= 0)
            ? device.makeBuffer(length: count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)
            : nil
        if exposureArg <= 0, composeLinearFullBuf == nil {
            fail("failed to allocate full-frame linear RGB buffer")
        }

        if exposureArg <= 0 {
            guard let composeLinearFullBuf else {
                fail("full-frame linear RGB buffer missing in auto-exposure path")
            }
            var cloudHistGlobal = [UInt32](repeating: 0, count: cloudBins)
            var cloudSampleCount: UInt64 = 0
            var lumHistGlobal = [UInt32](repeating: 0, count: lumBins)
            var lumSampleCount: UInt64 = 0

            // Pass A: compute cloud histogram per tile and global cloud stats.
            var pty = 0
            var cloudHistTileIndex = 0
            while pty < height {
                let tileH = min(composeRows, height - pty)
                let tileW = width
                let tileCount = tileW * tileH
                copyCollisionTileRows(
                    sourceBase: UnsafeRawPointer(collisionBase),
                    fullWidth: width,
                    stride: stride,
                    srcX: 0,
                    srcY: pty,
                    tileWidth: tileW,
                    tileHeight: tileH,
                    destinationBase: composeTileInBuf.contents()
                )

                composeParamsTemplate.tileWidth = UInt32(tileW)
                composeParamsTemplate.tileHeight = UInt32(tileH)
                composeParamsTemplate.srcOffsetY = UInt32(pty)
                composeParamsTemplate.outTileWidth = UInt32(tileW / downsampleArg)
                composeParamsTemplate.outTileHeight = UInt32(tileH / downsampleArg)
                composeParamsTemplate.outOffsetY = UInt32((height - pty - tileH) / downsampleArg)

                memset(cloudHistBuf.contents(), 0, cloudHistBytes)
                var cloudHistParams = composeParamsTemplate
                updateBuffer(cloudParamBuf, with: &cloudHistParams)
                let cloudCmd = queue.makeCommandBuffer()!
                let cloudEnc = cloudCmd.makeComputeCommandEncoder()!
                cloudEnc.setComputePipelineState(cloudHistPipeline)
                cloudEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                cloudEnc.setBuffer(cloudParamBuf, offset: 0, index: 1)
                cloudEnc.setBuffer(composeTileInBuf, offset: 0, index: 2)
                cloudEnc.setBuffer(cloudHistBuf, offset: 0, index: 3)
                cloudEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgCloud1D)
                cloudEnc.endEncoding()
                cloudCmd.commit()
                cloudCmd.waitUntilCompleted()

                let cloudPtr = cloudHistBuf.contents().bindMemory(to: UInt32.self, capacity: cloudBins)
                for i in 0..<cloudBins {
                    let c = cloudPtr[i]
                    cloudHistGlobal[i] = cloudHistGlobal[i] &+ c
                    cloudSampleCount += UInt64(c)
                }

                composePrepassOps += tileCount
                cloudHistTileIndex += 1
                let doneAll = totalPixels + composePrepassOps
                let now = Date().timeIntervalSince1970
                if doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                    emitETAProgress(min(doneAll, totalOps), totalOps, "swift_prepass", "task=cloud_hist tile=\(cloudHistTileIndex)/\(composeTileTotal)")
                    lastProgressPrint = now
                    while nextProgressMark <= doneAll {
                        nextProgressMark += progressStep
                    }
                }

                pty += tileH
            }

            if cloudSampleCount > 0 {
                globalCloudQ10 = cloudHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.08, 0.0, 1.0) }
                globalCloudQ90 = cloudHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.92, 0.0, 1.0) }
                globalCloudInvSpan = 1.0 / max(globalCloudQ90 - globalCloudQ10, 1e-6)
            }

            // Pass B: compute linear RGB once and reuse it for luminance histogram.
            pty = 0
            var prepassTileIndex = 0
            while pty < height {
                let tileH = min(composeRows, height - pty)
                let tileW = width
                let tileCount = tileW * tileH
                copyCollisionTileRows(
                    sourceBase: UnsafeRawPointer(collisionBase),
                    fullWidth: width,
                    stride: stride,
                    srcX: 0,
                    srcY: pty,
                    tileWidth: tileW,
                    tileHeight: tileH,
                    destinationBase: composeTileInBuf.contents()
                )

                composeParamsTemplate.tileWidth = UInt32(tileW)
                composeParamsTemplate.tileHeight = UInt32(tileH)
                composeParamsTemplate.srcOffsetX = 0
                composeParamsTemplate.srcOffsetY = UInt32(pty)
                composeParamsTemplate.outTileWidth = UInt32(tileW / downsampleArg)
                composeParamsTemplate.outTileHeight = UInt32(tileH / downsampleArg)
                composeParamsTemplate.outOffsetX = 0
                composeParamsTemplate.outOffsetY = UInt32((height - pty - tileH) / downsampleArg)
                // Use global cloud normalization to avoid tile-boundary banding artifacts.
                composeParamsTemplate.cloudQ10 = globalCloudQ10
                composeParamsTemplate.cloudInvSpan = globalCloudInvSpan

                var linearParams = composeParamsTemplate
                updateBuffer(lumParamBuf, with: &linearParams)
                let linearCmd = queue.makeCommandBuffer()!
                let linearEnc = linearCmd.makeComputeCommandEncoder()!
                linearEnc.setComputePipelineState(composeLinearPipeline)
                linearEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                linearEnc.setBuffer(lumParamBuf, offset: 0, index: 1)
                linearEnc.setBuffer(composeTileInBuf, offset: 0, index: 2)
                linearEnc.setBuffer(composeLinearFullBuf, offset: 0, index: 3)
                linearEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgLinear1D)
                linearEnc.endEncoding()
                linearCmd.commit()
                linearCmd.waitUntilCompleted()

                memset(lumHistBuf.contents(), 0, lumHistBytes)
                var lumHistParams = composeParamsTemplate
                updateBuffer(lumParamBuf, with: &lumHistParams)
                let lumCmd = queue.makeCommandBuffer()!
                let lumEnc = lumCmd.makeComputeCommandEncoder()!
                lumEnc.setComputePipelineState(lumHistLinearPipeline)
                lumEnc.setBuffer(lumParamBuf, offset: 0, index: 0)
                lumEnc.setBuffer(composeLinearFullBuf, offset: 0, index: 1)
                lumEnc.setBuffer(lumHistBuf, offset: 0, index: 2)
                lumEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgLum1D)
                lumEnc.endEncoding()
                lumCmd.commit()
                lumCmd.waitUntilCompleted()

                let lumPtr = lumHistBuf.contents().bindMemory(to: UInt32.self, capacity: lumBins)
                for i in 0..<lumBins {
                    let c = lumPtr[i]
                    lumHistGlobal[i] = lumHistGlobal[i] &+ c
                    lumSampleCount += UInt64(c)
                }

                composePrepassOps += tileCount * 2
                let doneAll = totalPixels + composePrepassOps
                let now = Date().timeIntervalSince1970
                if doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                    let tileNow = prepassTileIndex + 1
                    emitETAProgress(min(doneAll, totalOps), totalOps, "swift_prepass", "task=linear_lumhist tile=\(tileNow)/\(composeTileTotal)")
                    lastProgressPrint = now
                    while nextProgressMark <= doneAll {
                        nextProgressMark += progressStep
                    }
                }

                pty += tileH
                prepassTileIndex += 1
            }

            if lumSampleCount == 0 {
                composeExposure = 1.0
            } else {
                let p50Log = lumHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.50, lumLogMin, lumLogMax) }
                let p995Log = lumHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.995, lumLogMin, lumLogMax) }
                let p50 = pow(10.0, Double(p50Log))
                let p995 = pow(10.0, Double(p995Log))
                var targetWhite: Float = 0.8
                if composeLookID == 1 { targetWhite = 0.9 }
                else if composeLookID == 2 { targetWhite = 0.6 }
                composeExposure = targetWhite / max(Float(p995), 1e-12)
                print("lum(hist) p50=\(p50), p99.5=\(p995), samples=\(lumSampleCount)")
            }
        }

        composeParamsTemplate.exposure = composeExposure
        composeParamsTemplate.cloudQ10 = globalCloudQ10
        composeParamsTemplate.cloudInvSpan = globalCloudInvSpan
        print("compose cloud normalization q10=\(globalCloudQ10) q90=\(globalCloudQ90)")
        print("exposure=\(composeExposure) (auto=\(exposureArg <= 0), gpuFullCompose=true)")

        var rgb = [UInt8](repeating: 0, count: outWidth * outHeight * 3)
        let composePixelOps = outWidth * outHeight

        var composed = 0
        var cty = 0
        var composeTileIndex = 0
        if exposureArg <= 0 {
            guard let composeLinearFullBuf else {
                fail("linear RGB buffer missing before compose stage")
            }
            while cty < height {
                let tileH = min(composeRows, height - cty)
                let tileW = width
                let outTileW = tileW / downsampleArg
                let outTileH = tileH / downsampleArg
                let outTileCount = outTileW * outTileH
                let outOffsetY = (height - cty - tileH) / downsampleArg

                composeParamsTemplate.tileWidth = UInt32(tileW)
                composeParamsTemplate.tileHeight = UInt32(tileH)
                composeParamsTemplate.outTileWidth = UInt32(outTileW)
                composeParamsTemplate.outTileHeight = UInt32(outTileH)
                composeParamsTemplate.srcOffsetX = 0
                composeParamsTemplate.srcOffsetY = UInt32(cty)
                composeParamsTemplate.outOffsetX = 0
                composeParamsTemplate.outOffsetY = UInt32(outOffsetY)
                updateBuffer(composeParamBuf, with: &composeParamsTemplate)

                let cmd = queue.makeCommandBuffer()!
                let enc = cmd.makeComputeCommandEncoder()!
                enc.setComputePipelineState(composeBHLinearPipeline)
                enc.setBuffer(composeParamBuf, offset: 0, index: 0)
                enc.setBuffer(composeLinearFullBuf, offset: 0, index: 1)
                enc.setBuffer(composeOutBuf, offset: 0, index: 2)
                enc.dispatchThreads(MTLSize(width: outTileW, height: outTileH, depth: 1), threadsPerThreadgroup: tg)
                enc.endEncoding()
                cmd.commit()
                cmd.waitUntilCompleted()

                let outPtr = composeOutBuf.contents().bindMemory(to: UInt8.self, capacity: outTileCount * 4)
                for row in 0..<outTileH {
                    var dst = ((outOffsetY + row) * outWidth) * 3
                    let srcBase = row * outTileW * 4
                    for col in 0..<outTileW {
                        let s = srcBase + col * 4
                        rgb[dst + 0] = outPtr[s + 0]
                        rgb[dst + 1] = outPtr[s + 1]
                        rgb[dst + 2] = outPtr[s + 2]
                        dst += 3
                    }
                }

                composed += outTileCount
                composeTileIndex += 1
                let doneAll = totalPixels + composePrepassOps + composed
                let now = Date().timeIntervalSince1970
                if composed >= composePixelOps || doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                    emitETAProgress(min(doneAll, totalOps), totalOps, "swift_compose", "task=compose_linear tile=\(composeTileIndex)/\(composeTileTotal)")
                    lastProgressPrint = now
                    while nextProgressMark <= doneAll {
                        nextProgressMark += progressStep
                    }
                }
                cty += tileH
            }
        } else {
            while cty < height {
                let tileH = min(composeRows, height - cty)
                let tileW = width

                copyCollisionTileRows(
                    sourceBase: UnsafeRawPointer(collisionBase),
                    fullWidth: width,
                    stride: stride,
                    srcX: 0,
                    srcY: cty,
                    tileWidth: tileW,
                    tileHeight: tileH,
                    destinationBase: composeTileInBuf.contents()
                )

                let outTileW = tileW / downsampleArg
                let outTileH = tileH / downsampleArg
                let outTileCount = outTileW * outTileH
                let outOffsetY = (height - cty - tileH) / downsampleArg

                composeParamsTemplate.tileWidth = UInt32(tileW)
                composeParamsTemplate.tileHeight = UInt32(tileH)
                composeParamsTemplate.outTileWidth = UInt32(outTileW)
                composeParamsTemplate.outTileHeight = UInt32(outTileH)
                composeParamsTemplate.srcOffsetX = 0
                composeParamsTemplate.srcOffsetY = UInt32(cty)
                composeParamsTemplate.outOffsetX = 0
                composeParamsTemplate.outOffsetY = UInt32(outOffsetY)
                // Keep cloud normalization global to avoid horizontal/vertical seams.
                composeParamsTemplate.cloudQ10 = globalCloudQ10
                composeParamsTemplate.cloudInvSpan = globalCloudInvSpan
                updateBuffer(composeParamBuf, with: &composeParamsTemplate)

                let cmd = queue.makeCommandBuffer()!
                let enc = cmd.makeComputeCommandEncoder()!
                enc.setComputePipelineState(composePipeline)
                enc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                enc.setBuffer(composeParamBuf, offset: 0, index: 1)
                enc.setBuffer(composeTileInBuf, offset: 0, index: 2)
                enc.setBuffer(composeOutBuf, offset: 0, index: 3)
                enc.dispatchThreads(MTLSize(width: outTileW, height: outTileH, depth: 1), threadsPerThreadgroup: tg)
                enc.endEncoding()
                cmd.commit()
                cmd.waitUntilCompleted()

                let outPtr = composeOutBuf.contents().bindMemory(to: UInt8.self, capacity: outTileCount * 4)
                for row in 0..<outTileH {
                    var dst = ((outOffsetY + row) * outWidth) * 3
                    let srcBase = row * outTileW * 4
                    for col in 0..<outTileW {
                        let s = srcBase + col * 4
                        rgb[dst + 0] = outPtr[s + 0]
                        rgb[dst + 1] = outPtr[s + 1]
                        rgb[dst + 2] = outPtr[s + 2]
                        dst += 3
                    }
                }

                composed += outTileCount
                composeTileIndex += 1
                let doneAll = totalPixels + composePrepassOps + composed
                let now = Date().timeIntervalSince1970
                if composed >= composePixelOps || doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                    emitETAProgress(min(doneAll, totalOps), totalOps, "swift_compose", "task=compose_collision tile=\(composeTileIndex)/\(composeTileTotal)")
                    lastProgressPrint = now
                    while nextProgressMark <= doneAll {
                        nextProgressMark += progressStep
                    }
                }
                cty += tileH
            }
        }

        let ext = URL(fileURLWithPath: imageOutPath).pathExtension.lowercased()
        if ext == "ppm" {
            try writePPM(path: imageOutPath, width: outWidth, height: outHeight, rgb: rgb)
        } else {
            let tmpPPM = imageOutPath + ".tmp.ppm"
            try writePPM(path: tmpPPM, width: outWidth, height: outHeight, rgb: rgb)
            let pyConverter = FileManager.default.currentDirectoryPath + "/scripts/ppm_to_png.py"
            var rc: Int32 = -1
            if FileManager.default.fileExists(atPath: pyConverter) {
                rc = runProcess("/usr/bin/python3", [pyConverter, "--input", tmpPPM, "--output", imageOutPath])
            }
            if rc != 0 {
                rc = runProcess("/usr/bin/sips", ["-s", "format", "png", tmpPPM, "--out", imageOutPath])
            }
            try? FileManager.default.removeItem(atPath: tmpPPM)
            if rc != 0 {
                throw NSError(domain: "Blackhole", code: 3, userInfo: [NSLocalizedDescriptionKey: "sips conversion failed"])
            }
        }
        print("Saved image at: \(imageOutPath)")
    } else if useLinear32Intermediate {
    print("linear32 source=\(linearURL.path)")
    print("exposure=\(composeExposure) (auto=\(exposureArg <= 0), linear32=true)")

    var composeParamsTemplate = ComposeParams(
        tileWidth: 0,
        tileHeight: 0,
        downsample: UInt32(downsampleArg),
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
        cloudQ10: linearGlobalCloudQ10,
        cloudInvSpan: linearGlobalCloudInvSpan,
        look: composeLookID,
        spectralEncoding: spectralEncodingID,
        precisionMode: composePrecisionID,
        analysisMode: composeAnalysisMode,
        cloudBins: 2048,
        lumBins: UInt32(linearLumBins),
        lumLogMin: linearLumLogMin,
        lumLogMax: linearLumLogMax
    )
    let rawComposeRows = max(1, composeChunkArg / max(width, 1))
    var composeRows = max(downsampleArg, (rawComposeRows / downsampleArg) * downsampleArg)
    if composeRows <= 0 { composeRows = downsampleArg }
    if composeRows > height { composeRows = height }
    let composeTileTotal = max(1, (height + composeRows - 1) / composeRows)

    let maxComposeTileCount = width * composeRows
    let maxComposeOutTileCount = (width / downsampleArg) * (composeRows / downsampleArg)
    guard let linearTileInBuf = device.makeBuffer(length: maxComposeTileCount * linearStride, options: .storageModeShared) else {
        fail("failed to allocate linear32 compose input tile buffer")
    }
    guard let composeParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
        fail("failed to allocate linear32 compose param buffer")
    }
    guard let outBuf = device.makeBuffer(length: maxComposeOutTileCount * 4, options: .storageModeShared) else {
        fail("failed to allocate linear32 compose output tile buffer")
    }

    var rgb = [UInt8](repeating: 0, count: outWidth * outHeight * 3)
    let readHandle = try FileHandle(forReadingFrom: linearURL)
    defer { try? readHandle.close() }

    var composed = 0
    var cty = 0
    var composeTileIndex = 0
    while cty < height {
        let tileH = min(composeRows, height - cty)
        let tileW = width
        let rowBytes = tileW * linearStride
        for row in 0..<tileH {
            let offset = ((cty + row) * width) * linearStride
            try readHandle.seek(toOffset: UInt64(offset))
            let rowData = try readHandle.read(upToCount: rowBytes) ?? Data()
            if rowData.count != rowBytes {
                throw NSError(domain: "Blackhole", code: 2, userInfo: [NSLocalizedDescriptionKey: "short read while composing from linear32"])
            }
            _ = rowData.withUnsafeBytes { raw in
                memcpy(linearTileInBuf.contents().advanced(by: row * rowBytes), raw.baseAddress!, rowBytes)
            }
        }

        let outTileW = tileW / downsampleArg
        let outTileH = tileH / downsampleArg
        let outTileCount = outTileW * outTileH
        let outOffsetY = (height - cty - tileH) / downsampleArg

        composeParamsTemplate.tileWidth = UInt32(tileW)
        composeParamsTemplate.tileHeight = UInt32(tileH)
        composeParamsTemplate.outTileWidth = UInt32(outTileW)
        composeParamsTemplate.outTileHeight = UInt32(outTileH)
        composeParamsTemplate.srcOffsetX = 0
        composeParamsTemplate.srcOffsetY = UInt32(cty)
        composeParamsTemplate.outOffsetX = 0
        composeParamsTemplate.outOffsetY = UInt32(outOffsetY)
        updateBuffer(composeParamBuf, with: &composeParamsTemplate)

        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeComputeCommandEncoder()!
        enc.setComputePipelineState(composeBHLinearTilePipeline)
        enc.setBuffer(composeParamBuf, offset: 0, index: 0)
        enc.setBuffer(linearTileInBuf, offset: 0, index: 1)
        enc.setBuffer(outBuf, offset: 0, index: 2)
        enc.dispatchThreads(MTLSize(width: outTileW, height: outTileH, depth: 1), threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        let outPtr = outBuf.contents().bindMemory(to: UInt8.self, capacity: outTileCount * 4)
        for row in 0..<outTileH {
            var dst = ((outOffsetY + row) * outWidth) * 3
            let srcBase = row * outTileW * 4
            for col in 0..<outTileW {
                let s = srcBase + col * 4
                rgb[dst + 0] = outPtr[s + 0]
                rgb[dst + 1] = outPtr[s + 1]
                rgb[dst + 2] = outPtr[s + 2]
                dst += 3
            }
        }

        composed += outTileCount
        composeTileIndex += 1
        let doneAll = totalPixels + composePrepassOpsTarget + composed
        let now = Date().timeIntervalSince1970
        if composed >= composeOps || doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
            emitETAProgress(min(doneAll, totalOps), totalOps, "swift_compose", "task=linear32_compose tile=\(composeTileIndex)/\(composeTileTotal)")
            lastProgressPrint = now
            while nextProgressMark <= doneAll {
                nextProgressMark += progressStep
            }
        }

        cty += tileH
    }

    let ext = URL(fileURLWithPath: imageOutPath).pathExtension.lowercased()
    if ext == "ppm" {
        try writePPM(path: imageOutPath, width: outWidth, height: outHeight, rgb: rgb)
    } else {
        let tmpPPM = imageOutPath + ".tmp.ppm"
        try writePPM(path: tmpPPM, width: outWidth, height: outHeight, rgb: rgb)
        let pyConverter = FileManager.default.currentDirectoryPath + "/scripts/ppm_to_png.py"
        var rc: Int32 = -1
        if FileManager.default.fileExists(atPath: pyConverter) {
            rc = runProcess("/usr/bin/python3", [pyConverter, "--input", tmpPPM, "--output", imageOutPath])
        }
        if rc != 0 {
            rc = runProcess("/usr/bin/sips", ["-s", "format", "png", tmpPPM, "--out", imageOutPath])
        }
        try? FileManager.default.removeItem(atPath: tmpPPM)
        if rc != 0 {
            throw NSError(domain: "Blackhole", code: 3, userInfo: [NSLocalizedDescriptionKey: "sips conversion failed"])
        }
    }
    print("Saved image at: \(imageOutPath)")
    } else {
    let hitOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.hit) ?? 0
    let tOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.T) ?? 8
    let vDiskOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.v_disk) ?? 16
    let directOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.direct_world) ?? 32
    let noiseOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.noise) ?? 48
    let cloudQ10: Float = 0.0
    let cloudQ90: Float = 1.0
    let cloudInvSpan = 1.0 / max(cloudQ90 - cloudQ10, 1e-6)
    var cpuP995ForCompose: Float = 0.0
    var sampledHits = 0

    if exposureArg <= 0 {
        var lumSamples: [Float] = []
        let sampleStride = (exposureSamplesArg > 0) ? max(1, count / max(exposureSamplesArg, 1)) : 1
        let stepNm = Double(max(composeSpectralStepArg, 0.25))
        let luma = SIMD3<Double>(0.2126, 0.7152, 0.0722)
        let rs = Double(params.rs)
        let ghM = 1.0e35
        let gg = 6.67430e-11
        let cc = 299_792_458.0
        let xyzRow0 = SIMD3<Double>(3.2406, -1.5372, -0.4986)
        let xyzRow1 = SIMD3<Double>(-0.9689, 1.8758, 0.0415)
        let xyzRow2 = SIMD3<Double>(0.0557, -0.2040, 1.0570)
        let sampleHandle = try FileHandle(forReadingFrom: url)
        defer { try? sampleHandle.close() }
        let scanRecords = max(1, composeChunkArg)
        let scanBytes = scanRecords * stride
        var globalStart = 0
        while true {
            let data = try sampleHandle.read(upToCount: scanBytes) ?? Data()
            if data.isEmpty { break }

            let recCount = data.count / stride
            var chunkT: [Double] = []
            var chunkV: [SIMD3<Double>] = []
            var chunkD: [SIMD3<Double>] = []
            var chunkN: [Double] = []
            chunkT.reserveCapacity(min(recCount, 8192))
            chunkV.reserveCapacity(min(recCount, 8192))
            chunkD.reserveCapacity(min(recCount, 8192))
            chunkN.reserveCapacity(min(recCount, 8192))

            data.withUnsafeBytes { raw in
                guard let basePtr = raw.baseAddress else { return }
                for i in 0..<recCount {
                    let absIdx = globalStart + i
                    if exposureSamplesArg > 0 && ((absIdx % sampleStride) != 0) {
                        continue
                    }
                    let base = i * stride
                    var hit: UInt32 = 0
                    withUnsafeMutableBytes(of: &hit) { dst in
                        dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + hitOffset), count: MemoryLayout<UInt32>.size))
                    }
                    if hit == 0 { continue }

                    var t: Float = 0
                    withUnsafeMutableBytes(of: &t) { dst in
                        dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + tOffset), count: MemoryLayout<Float>.size))
                    }
                    var v4 = SIMD4<Float>(repeating: 0)
                    withUnsafeMutableBytes(of: &v4) { dst in
                        dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + vDiskOffset), count: MemoryLayout<SIMD4<Float>>.size))
                    }
                    var d4 = SIMD4<Float>(repeating: 0)
                    withUnsafeMutableBytes(of: &d4) { dst in
                        dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + directOffset), count: MemoryLayout<SIMD4<Float>>.size))
                    }
                    var n: Float = 0
                    withUnsafeMutableBytes(of: &n) { dst in
                        dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + noiseOffset), count: MemoryLayout<Float>.size))
                    }

                    chunkT.append(max(Double(t), 1.0))
                    chunkV.append(SIMD3<Double>(Double(v4.x), Double(v4.y), Double(v4.z)))
                    chunkD.append(SIMD3<Double>(Double(d4.x), Double(d4.y), Double(d4.z)))
                    chunkN.append(Double(n))
                }
            }

            if !chunkT.isEmpty {
                var procNoise = chunkN
                if composeAnalysisMode == 0 && spectralEncodingID == 0 {
                    var maxAbsN = 0.0
                    for n in procNoise { maxAbsN = max(maxAbsN, abs(n)) }
                    if maxAbsN < 1e-6 {
                        let re = max(rcp, 1.2) * rs
                        for i in 0..<procNoise.count {
                            let vx = chunkV[i].x
                            let vy = chunkV[i].y
                            let speed = max(hypot(vx, vy), 1e-30)
                            let r = gg * ghM / max(speed * speed, 1e-30)
                            let u = min(max((r - rs) / max(re - rs, 1e-12), 0.0), 1.0)
                            let phi = atan2(-vx, vy)
                            let theta = phi + 1.9 * log(max(r / rs, 1.0))
                            procNoise[i] = min(max(0.65 * sin(18.0 * u + 3.0 * cos(theta)) + 0.35 * cos(11.0 * theta), -1.0), 1.0)
                        }
                    }
                }

                var cloudVals = [Float](repeating: 0, count: procNoise.count)
                if composeAnalysisMode == 0 {
                    for i in 0..<procNoise.count {
                        let n = min(max(procNoise[i], -1.0), 1.0)
                        let c = (n < -1e-6) ? min(max(0.5 + 0.5 * n, 0.0), 1.0) : min(max(n, 0.0), 1.0)
                        cloudVals[i] = Float(c)
                    }
                } else {
                    for i in 0..<cloudVals.count { cloudVals[i] = 0.5 }
                }
                var sortedCloud = cloudVals
                sortedCloud.sort()
                let q10 = percentileSorted(sortedCloud, 0.08)
                let q90 = percentileSorted(sortedCloud, 0.92)
                let invSpan = 1.0 / max(q90 - q10, 1e-6)

                var chunkLum: [Float] = []
                chunkLum.reserveCapacity(chunkT.count)
                for i in 0..<chunkT.count {
                    let v = chunkV[i]
                    let d = chunkD[i]
                    let colorDilution: Double = (diskPhysicsModeID == 2) ? (1.0 / pow(max(diskColorFactorArg, 1.0), 4.0)) : 1.0
                    let gTotal: Double
                    if spectralEncodingID == 1 {
                        gTotal = min(max(v.x, 1e-4), 1e4)
                    } else {
                        let vNorm = max(sqrt(v.x * v.x + v.y * v.y + v.z * v.z), 1e-30)
                        let dNorm = max(sqrt(d.x * d.x + d.y * d.y + d.z * d.z), 1e-30)
                        let beta = min(max(vNorm / cc, 0.0), 0.999999)
                        let gamma = 1.0 / sqrt(max(1.0 - beta * beta, 1e-18))
                        let vd = v.x * d.x + v.y * d.y + v.z * d.z
                        let cosTheta = min(max(vd / (vNorm * dNorm), -1.0), 1.0)
                        let delta = 1.0 / max(gamma * (1.0 + beta * cosTheta), 1e-9)
                        let rEmitLegacy = max(gg * ghM / max(vNorm * vNorm, 1e-30), rs * 1.0001)
                        let gGr = sqrt(min(max(1.0 - rs / rEmitLegacy, 1e-8), 1.0))
                        gTotal = min(max(delta * gGr, 1e-4), 1e4)
                    }

                    let tObs = max(chunkT[i] * gTotal, 1.0)
                    var X = 0.0
                    var Y = 0.0
                    var Z = 0.0
                    var lam = 380.0
                    while lam <= 750.001 {
                        let (xb, yb, zb) = cieXYZBar(lam)
                        let lamM = lam * 1e-9
                        let b = planckLambda(lamM, tObs) * colorDilution
                        X += b * xb
                        Y += b * yb
                        Z += b * zb
                        lam += stepNm
                    }
                    var rgb = SIMD3<Double>(
                        xyzRow0.x * X + xyzRow0.y * Y + xyzRow0.z * Z,
                        xyzRow1.x * X + xyzRow1.y * Y + xyzRow1.z * Z,
                        xyzRow2.x * X + xyzRow2.y * Y + xyzRow2.z * Z
                    )
                    rgb.x = max(rgb.x, 0.0)
                    rgb.y = max(rgb.y, 0.0)
                    rgb.z = max(rgb.z, 0.0)

                    let mu = abs(d.z) / max(sqrt(d.x * d.x + d.y * d.y + d.z * d.z), 1e-30)
                    let limb: Double
                    if diskPhysicsModeID == 2 {
                        limb = (3.0 / 7.0) * (1.0 + 2.0 * min(max(mu, 0.0), 1.0))
                    } else {
                        limb = 0.4 + 0.6 * min(max(mu, 0.0), 1.0)
                    }
                    rgb *= limb
                    if spectralEncodingID == 1 && diskPhysicsModeID == 1 {
                        let rEmit = max(v.y, rs * 1.0001)
                        let xDen = max(diskInnerRadiusCompose - diskHorizonRadiusCompose, 1e-9)
                        let x = min(max((rEmit - diskHorizonRadiusCompose) / xDen, 0.0), 1.0)
                        let xSoft = x * x * (3.0 - 2.0 * x)
                        let floor = 0.35 * min(max(diskPlungeFloorArg, 0.0), 1.0)
                        let gate = floor + (1.0 - floor) * pow(max(xSoft, 1e-4), 2.2)
                        rgb *= gate
                    }

                    if composeAnalysisMode == 0 {
                        var cloud = min(max((Double(cloudVals[i]) - Double(q10)) * Double(invSpan), 0.0), 1.0)
                        cloud = 0.18 + 0.82 * cloud
                        let core = pow(cloud, 1.15)
                        let clump = pow(core, 2.2)
                        let vvoid = pow(1.0 - cloud, 1.8)
                        let density = 0.62 + 1.28 * core
                        rgb *= density
                        rgb *= (1.0 + 0.34 * clump)
                        rgb *= (1.0 - 0.14 * vvoid)
                        rgb.x *= (1.0 + 0.12 * clump)
                        rgb.z *= (1.0 - 0.08 * clump)
                    }
                    chunkLum.append(Float(rgb.x * luma.x + rgb.y * luma.y + rgb.z * luma.z))
                }

                if !chunkLum.isEmpty {
                    let lumStride = max(1, chunkLum.count / 8192)
                    var j = 0
                    while j < chunkLum.count {
                        lumSamples.append(chunkLum[j])
                        sampledHits += 1
                        j += lumStride
                    }
                }
            }

            globalStart += recCount
        }

        if lumSamples.isEmpty {
            composeExposure = 1.0
        } else {
            lumSamples.sort()
            let p50 = percentileSorted(lumSamples, 0.50)
            let p995 = percentileSorted(lumSamples, 0.995)
            var targetWhite: Float = 0.8
            if composeLookID == 1 { targetWhite = 0.9 }
            else if composeLookID == 2 { targetWhite = 0.6 }
            composeExposure = targetWhite / max(p995, 1e-12)
            cpuP995ForCompose = p995
            print("lum p50=\(p50), p99.5=\(p995), exposureSamples=\(sampledHits)")
        }
    }
    print("compose cloud normalization q10=\(cloudQ10) q90=\(cloudQ90)")
    print("exposure=\(composeExposure) (auto=\(exposureArg <= 0))")

    var composeParamsTemplate = ComposeParams(
        tileWidth: 0,
        tileHeight: 0,
        downsample: UInt32(downsampleArg),
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
        cloudQ10: cloudQ10,
        cloudInvSpan: cloudInvSpan,
        look: composeLookID,
        spectralEncoding: spectralEncodingID,
        precisionMode: composePrecisionID,
        analysisMode: composeAnalysisMode,
        cloudBins: 2048,
        lumBins: 4096,
        lumLogMin: 8.0,
        lumLogMax: 20.0
    )
    let composeBaseBuf = device.makeBuffer(bytes: &composeParamsBase, length: MemoryLayout<Params>.stride, options: [])!

    let rawComposeRows = max(1, composeChunkArg / max(width, 1))
    var composeRows = max(downsampleArg, (rawComposeRows / downsampleArg) * downsampleArg)
    if composeRows <= 0 { composeRows = downsampleArg }
    if composeRows > height { composeRows = height }
    let composeTileTotal = max(1, (height + composeRows - 1) / composeRows)

    if cpuP995ForCompose > 0 {
        var lumHistGlobal = [UInt32](repeating: 0, count: 4096)
        let lumTg = MTLSize(width: max(1, min(256, lumHistPipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)
        let corrHandle = try FileHandle(forReadingFrom: url)
        defer { try? corrHandle.close() }
        var pty = 0
        while pty < height {
            let tileH = min(composeRows, height - pty)
            let tileW = width
            let tileCount = tileW * tileH
            let rowBytes = tileW * stride
            let tileInBuf = device.makeBuffer(length: tileCount * stride, options: .storageModeShared)!
            for row in 0..<tileH {
                let offset = ((pty + row) * width) * stride
                try corrHandle.seek(toOffset: UInt64(offset))
                let rowData = try corrHandle.read(upToCount: rowBytes) ?? Data()
                if rowData.count != rowBytes {
                    throw NSError(domain: "Blackhole", code: 2, userInfo: [NSLocalizedDescriptionKey: "short read while compose exposure correction"])
                }
                _ = rowData.withUnsafeBytes { raw in
                    memcpy(tileInBuf.contents().advanced(by: row * rowBytes), raw.baseAddress!, rowBytes)
                }
            }

            var lumParams = composeParamsTemplate
            lumParams.tileWidth = UInt32(tileW)
            lumParams.tileHeight = UInt32(tileH)
            lumParams.srcOffsetX = 0
            lumParams.srcOffsetY = UInt32(pty)
            lumParams.cloudQ10 = cloudQ10
            lumParams.cloudInvSpan = cloudInvSpan
            let lumParamBuf = device.makeBuffer(bytes: &lumParams, length: MemoryLayout<ComposeParams>.stride, options: [])!
            let lumHistBuf = device.makeBuffer(length: 4096 * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
            memset(lumHistBuf.contents(), 0, 4096 * MemoryLayout<UInt32>.stride)

            let lumCmd = queue.makeCommandBuffer()!
            let lumEnc = lumCmd.makeComputeCommandEncoder()!
            lumEnc.setComputePipelineState(lumHistPipeline)
            lumEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
            lumEnc.setBuffer(lumParamBuf, offset: 0, index: 1)
            lumEnc.setBuffer(tileInBuf, offset: 0, index: 2)
            lumEnc.setBuffer(lumHistBuf, offset: 0, index: 3)
            lumEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: lumTg)
            lumEnc.endEncoding()
            lumCmd.commit()
            lumCmd.waitUntilCompleted()

            let lp = lumHistBuf.contents().bindMemory(to: UInt32.self, capacity: 4096)
            for i in 0..<4096 {
                lumHistGlobal[i] = lumHistGlobal[i] &+ lp[i]
            }
            pty += tileH
        }

        let p995Log = lumHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.995, 8.0, 20.0) }
        let gpuP995 = Float(pow(10.0, Double(p995Log)))
        if gpuP995 > 0 {
            let corr = cpuP995ForCompose / max(gpuP995, 1e-12)
            composeExposure *= corr
            print("compose exposure correction cpu_p99.5=\(cpuP995ForCompose), gpu_p99.5=\(gpuP995), gain=\(corr)")
        }
    }
    composeParamsTemplate.exposure = composeExposure

    var rgb = [UInt8](repeating: 0, count: outWidth * outHeight * 3)
    let readHandle = try FileHandle(forReadingFrom: url)
    defer { try? readHandle.close() }

    var composed = 0
    var cty = 0
    var composeTileIndex = 0
    while cty < height {
        let tileH = min(composeRows, height - cty)
        let ctx = 0
        let tileW = width
        let tileCount = tileW * tileH
        let rowBytes = tileW * stride

        let tileInBuf = device.makeBuffer(length: tileCount * stride, options: .storageModeShared)!
        for row in 0..<tileH {
            let offset = ((cty + row) * width + ctx) * stride
            try readHandle.seek(toOffset: UInt64(offset))
            let rowData = try readHandle.read(upToCount: rowBytes) ?? Data()
            if rowData.count != rowBytes {
                throw NSError(domain: "Blackhole", code: 2, userInfo: [NSLocalizedDescriptionKey: "short read while composing"])
            }
            _ = rowData.withUnsafeBytes { raw in
                memcpy(tileInBuf.contents().advanced(by: row * rowBytes), raw.baseAddress!, rowBytes)
            }
        }

        let outTileW = tileW / downsampleArg
        let outTileH = tileH / downsampleArg
        let outTileCount = outTileW * outTileH
        let outOffsetX = ctx / downsampleArg
        let outOffsetY = (height - cty - tileH) / downsampleArg

        composeParamsTemplate.tileWidth = UInt32(tileW)
        composeParamsTemplate.tileHeight = UInt32(tileH)
        composeParamsTemplate.outTileWidth = UInt32(outTileW)
        composeParamsTemplate.outTileHeight = UInt32(outTileH)
        composeParamsTemplate.srcOffsetX = UInt32(ctx)
        composeParamsTemplate.srcOffsetY = UInt32(cty)
        composeParamsTemplate.outOffsetX = UInt32(outOffsetX)
        composeParamsTemplate.outOffsetY = UInt32(outOffsetY)
        composeParamsTemplate.cloudQ10 = cloudQ10
        composeParamsTemplate.cloudInvSpan = cloudInvSpan

        let composeParamBuf = device.makeBuffer(bytes: &composeParamsTemplate, length: MemoryLayout<ComposeParams>.stride, options: [])!
        let outBuf = device.makeBuffer(length: outTileCount * 4, options: .storageModeShared)!

        let cmd = queue.makeCommandBuffer()!
        let enc = cmd.makeComputeCommandEncoder()!
        enc.setComputePipelineState(composePipeline)
        enc.setBuffer(composeBaseBuf, offset: 0, index: 0)
        enc.setBuffer(composeParamBuf, offset: 0, index: 1)
        enc.setBuffer(tileInBuf, offset: 0, index: 2)
        enc.setBuffer(outBuf, offset: 0, index: 3)
        let grid = MTLSize(width: outTileW, height: outTileH, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        let outPtr = outBuf.contents().bindMemory(to: UInt8.self, capacity: outTileCount * 4)
        for row in 0..<outTileH {
            var dst = ((outOffsetY + row) * outWidth + outOffsetX) * 3
            let srcBase = row * outTileW * 4
            for col in 0..<outTileW {
                let s = srcBase + col * 4
                rgb[dst + 0] = outPtr[s + 0]
                rgb[dst + 1] = outPtr[s + 1]
                rgb[dst + 2] = outPtr[s + 2]
                dst += 3
            }
        }

        composed += outTileCount
        composeTileIndex += 1
        let doneAll = totalPixels + composed
        let now = Date().timeIntervalSince1970
        if composed >= composeOps || doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
            emitETAProgress(min(doneAll, totalOps), totalOps, "swift_compose", "task=cpu_compose tile=\(composeTileIndex)/\(composeTileTotal)")
            lastProgressPrint = now
            while nextProgressMark <= doneAll {
                nextProgressMark += progressStep
            }
        }
        cty += tileH
    }

    let ext = URL(fileURLWithPath: imageOutPath).pathExtension.lowercased()
    if ext == "ppm" {
        try writePPM(path: imageOutPath, width: outWidth, height: outHeight, rgb: rgb)
    } else {
        let tmpPPM = imageOutPath + ".tmp.ppm"
        try writePPM(path: tmpPPM, width: outWidth, height: outHeight, rgb: rgb)
        let pyConverter = FileManager.default.currentDirectoryPath + "/scripts/ppm_to_png.py"
        var rc: Int32 = -1
        if FileManager.default.fileExists(atPath: pyConverter) {
            rc = runProcess("/usr/bin/python3", [pyConverter, "--input", tmpPPM, "--output", imageOutPath])
        }
        if rc != 0 {
            rc = runProcess("/usr/bin/sips", ["-s", "format", "png", tmpPPM, "--out", imageOutPath])
        }
        try? FileManager.default.removeItem(atPath: tmpPPM)
        if rc != 0 {
            throw NSError(domain: "Blackhole", code: 3, userInfo: [NSLocalizedDescriptionKey: "sips conversion failed"])
        }
    }
    print("Saved image at: \(imageOutPath)")
    }
}

if useInMemoryCollisions && !discardCollisionOutput {
    guard let collisionBase else {
        fail("in-memory collision buffer unexpectedly missing at flush")
    }
    try writeRawBuffer(to: url, sourceBase: UnsafeRawPointer(collisionBase), byteCount: outSize)
}

let meta = RenderMeta(
    version: "dense_pruned_v10",
    spectralEncoding: spectralEncoding,
    diskModel: diskAtlasEnabled ? "stage3_atlas_v1" : (diskModelResolved == "perlin" ? "perlin_texture_v1" : "streamline_particles_v1"),
    bridgeCoordinateFrame: "camera_world_xy_disk, r_norm=r/rs, z_norm=z/rs, phi=atan2(y,x)",
    bridgeFields: ["emit_r_norm", "emit_phi", "emit_z_norm", "ct", "T", "v_disk", "direct_world", "noise"],
    width: width,
    height: height,
    preset: preset,
    rcp: rcp,
    h: hArg,
    maxSteps: maxStepsArg,
    camX: camXFactor,
    camY: camYFactor,
    camZ: camZFactor,
    fov: fovDeg,
    roll: rollDeg,
    diskH: diskHFactor,
    metric: metricName,
    spin: spinArg,
    kerrTol: kerrTolArg,
    kerrEscapeMult: kerrEscapeMultArg,
    kerrSubsteps: kerrSubstepsArg,
    kerrRadialScale: kerrRadialScaleArg,
    kerrAzimuthScale: kerrAzimuthScaleArg,
    kerrImpactScale: kerrImpactScaleArg,
    diskFlowTime: diskFlowTimeArg,
    diskOrbitalBoost: diskOrbitalBoostArg,
    diskRadialDrift: diskRadialDriftArg,
    diskTurbulence: diskTurbulenceArg,
    diskOrbitalBoostInner: diskOrbitalBoostInnerArg,
    diskOrbitalBoostOuter: diskOrbitalBoostOuterArg,
    diskRadialDriftInner: diskRadialDriftInnerArg,
    diskRadialDriftOuter: diskRadialDriftOuterArg,
    diskTurbulenceInner: diskTurbulenceInnerArg,
    diskTurbulenceOuter: diskTurbulenceOuterArg,
    diskFlowStep: diskFlowStepArg,
    diskFlowSteps: diskFlowStepsArg,
    diskMdotEdd: diskMdotEddArg,
    diskRadiativeEfficiency: diskRadiativeEfficiencyArg,
    diskPhysicsMode: diskPhysicsModeArg,
    diskPlungeFloor: diskPlungeFloorArg,
    diskThickScale: diskThickScaleArg,
    diskColorFactor: diskColorFactorArg,
    diskReturningRad: diskReturningRadArg,
    diskPrecisionTexture: diskPrecisionTextureArg,
    diskPrecisionClouds: diskPrecisionCloudsEnabled,
    diskCloudCoverage: diskCloudCoverageArg,
    diskCloudOpticalDepth: diskCloudOpticalDepthArg,
    diskCloudPorosity: diskCloudPorosityArg,
    diskCloudShadowStrength: diskCloudShadowStrengthArg,
    diskReturnBounces: diskReturnBouncesArg,
    diskRTSteps: diskRTStepsArg,
    diskScatteringAlbedo: diskScatteringAlbedoArg,
    diskAtlasEnabled: diskAtlasEnabled,
    diskAtlasPath: diskAtlasEnabled ? diskAtlasPathArg : "",
    diskAtlasWidth: diskAtlasWidth,
    diskAtlasHeight: diskAtlasHeight,
    diskAtlasTempScale: diskAtlasTempScaleArg,
    diskAtlasDensityBlend: diskAtlasDensityBlendArg,
    diskAtlasVrScale: diskAtlasVrScaleArg,
    diskAtlasVphiScale: diskAtlasVphiScaleArg,
    diskAtlasRNormMin: diskAtlasRMin,
    diskAtlasRNormMax: diskAtlasRMax,
    diskAtlasRNormWarp: diskAtlasRWarp,
    tileSize: effectiveTile,
    composeGPU: composeGPU,
    downsample: downsampleArg,
    outputWidth: outWidth,
    outputHeight: outHeight,
    exposure: Double(composeExposure),
    look: composeLook,
    collisionStride: MemoryLayout<CollisionInfo>.stride
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
if useLinear32Intermediate {
    let metaData = try encoder.encode(meta)
    let metaURL = URL(fileURLWithPath: linear32OutPath + ".json")
    try metaData.write(to: metaURL)
    print("Saved linear32 at:", linearURL.path)
    print("Saved linear32 (\(linearOutSize) bytes, hits=\(hitCount))")
    print("Saved meta at:", metaURL.path)
} else if !discardCollisionOutput {
    let metaData = try encoder.encode(meta)
    let metaURL = URL(fileURLWithPath: outPath + ".json")
    try metaData.write(to: metaURL)
    print("Saved at:", url.path)
    print("Saved collisions.bin (\(outSize) bytes, hits=\(hitCount))")
    print("Saved meta at:", metaURL.path)
} else {
    print("Collision output skipped (discard mode), hits=\(hitCount)")
}
