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
    var _padMetric0: Float
    var _padMetric1: Int32
}

struct CollisionInfo {
    var hit: UInt32
    var ct: Float
    var T: Float
    var v_disk: SIMD3<Float>
    var direct_world: SIMD3<Float>
    var noise: Float
}

struct RenderMeta: Codable {
    var version: String
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
    var collisionStride: Int
}

func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    return v / len
}

func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
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

func stringArg(_ name: String, default defaultValue: String) -> String {
    guard let idx = CommandLine.arguments.firstIndex(of: name), idx + 1 < CommandLine.arguments.count else {
        return defaultValue
    }
    return CommandLine.arguments[idx + 1]
}

if CommandLine.arguments.contains("--kerr-use-u") {
    FileHandle.standardError.write(Data("error: --kerr-use-u has been removed after validation tests showed no practical gain.\n".utf8))
    exit(2)
}

let device = MTLCreateSystemDefaultDevice()!
let queue = device.makeCommandQueue()!

let library = device.makeDefaultLibrary()!
let fn = library.makeFunction(name: "renderBH")!
let pipeline = try device.makeComputePipelineState(function: fn)

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
let metricName = stringArg("--metric", default: "schwarzschild").lowercased()
let metricArg: Int32 = (metricName == "kerr") ? 1 : 0
let defaultH = 0.01
let hArg = max(1e-6, doubleArg("--h", default: defaultH))
let spinArg = max(0.0, min(0.999, doubleArg("--spin", default: 0.0)))
let defaultKerrSubsteps = 4
let defaultKerrRadialScale = 0.69
let defaultKerrAzimuthScale = 0.91
let defaultKerrImpactScale = 0.97
let kerrSubstepsArg = max(1, min(8, intArg("--kerr-substeps", default: defaultKerrSubsteps)))
let kerrTolArg = max(1e-6, doubleArg("--kerr-tol", default: 1e-5))
let kerrEscapeMultArg = max(1.0, doubleArg("--kerr-escape-mult", default: 3.0))
let kerrRadialScaleArg = max(0.01, doubleArg("--kerr-radial-scale", default: defaultKerrRadialScale))
let kerrAzimuthScaleArg = max(0.01, doubleArg("--kerr-azimuth-scale", default: defaultKerrAzimuthScale))
let kerrImpactScaleArg = max(0.1, doubleArg("--kerr-impact-scale", default: defaultKerrImpactScale))

print("render config preset=\(preset) \(width)x\(height), cam=(\(camXFactor),\(camYFactor),\(camZFactor))rs, fov=\(fovDeg), roll=\(rollDeg), rcp=\(rcp), diskH=\(diskHFactor)rs, maxSteps=\(maxStepsArg), metric=\(metricName), spin=\(spinArg), kerrSubsteps=\(kerrSubstepsArg), kerrTol=\(kerrTolArg), kerrEscape=\(kerrEscapeMultArg), kerrScale=(\(kerrRadialScaleArg),\(kerrAzimuthScaleArg),\(kerrImpactScaleArg))")

let c: Double = 299_792_458
let G: Double = 6.67430e-11
let k: Double = 1.380649e-23
let M: Double = 1e35

let rsD = 2.0 * G * M / (c * c)
let reD = rsD * rcp
let heD = rsD * diskHFactor

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
    _padMetric0: 0.0,
    _padMetric1: 0
)

let paramBuf = device.makeBuffer(bytes: &params, length: MemoryLayout<Params>.stride, options: [])!

let count = width * height
let outSize = count * MemoryLayout<CollisionInfo>.stride
let outBuf = device.makeBuffer(length: outSize, options: .storageModeShared)!

let cmd = queue.makeCommandBuffer()!
let enc = cmd.makeComputeCommandEncoder()!
enc.setComputePipelineState(pipeline)
enc.setBuffer(paramBuf, offset: 0, index: 0)
enc.setBuffer(outBuf, offset: 0, index: 1)

let tg = MTLSize(width: 16, height: 16, depth: 1)
let grid = MTLSize(width: width, height: height, depth: 1)
enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
enc.endEncoding()

cmd.commit()
cmd.waitUntilCompleted()

let ptr = outBuf.contents().bindMemory(to: CollisionInfo.self, capacity: count)
var hitCount = 0
for i in 0..<count where ptr[i].hit != 0 { hitCount += 1 }

let data = Data(bytesNoCopy: outBuf.contents(), count: outSize, deallocator: .none)
let url = URL(fileURLWithPath: outPath)
try data.write(to: url)

let meta = RenderMeta(
    version: "dense_pruned_v2",
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
    collisionStride: MemoryLayout<CollisionInfo>.stride
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let metaData = try encoder.encode(meta)
let metaURL = URL(fileURLWithPath: outPath + ".json")
try metaData.write(to: metaURL)

print("Saved at:", url.path)
print("Saved collisions.bin (\(outSize) bytes, hits=\(hitCount))")
print("Saved meta at:", metaURL.path)
