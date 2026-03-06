import Foundation
import Metal

// Metal constant-buffer ABI mirror for kernel `Params`.
// Keep field order and scalar widths identical to integral.metal.
struct PackedParams {
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
    var diskVolumeMode: UInt32
    var diskVolumeR: UInt32
    var diskVolumePhi: UInt32
    var diskVolumeZ: UInt32
    var diskVolumeRNormMin: Float
    var diskVolumeRNormMax: Float
    var diskVolumeZNormMax: Float
    var diskVolumeTauScale: Float
    var diskVolumeFormat: UInt32
    var diskVolumeR0: UInt32
    var diskVolumePhi0: UInt32
    var diskVolumeZ0: UInt32
    var diskVolumeR1: UInt32
    var diskVolumePhi1: UInt32
    var diskVolumeZ1: UInt32
    var diskNuObsHz: Float
    var diskGrmhdDensityScale: Float
    var diskGrmhdBScale: Float
    var diskGrmhdEmissionScale: Float
    var diskGrmhdAbsorptionScale: Float
    var diskGrmhdVelScale: Float
    var diskGrmhdDebugView: UInt32
    var diskPolarizedRT: UInt32
    var diskPolarizationFrac: Float
    var diskFaradayRotScale: Float
    var diskFaradayConvScale: Float
    var visibleMode: UInt32
    var visibleSamples: UInt32
    var visibleTeffModel: UInt32
    var visiblePad0: UInt32
    var visibleTeffT0: Float
    var visibleTeffR0: Float
    var visibleTeffP: Float
    var visiblePhotosphereRhoThreshold: Float
    var visibleBhMass: Float
    var visibleMdot: Float
    var visibleRIn: Float
    var visibleKappa: Float
    var visibleEmissionModel: UInt32
    var visibleEmissionAlpha: Float
    var rayBundleSSAA: UInt32
    var rayBundleJacobian: UInt32
    var rayBundleJacobianStrength: Float
    var rayBundleFootprintClamp: Float
    var coolAbsorptionMode: UInt32
    var coolDustToGas: Float
    var coolDustKappaV: Float
    var coolDustBeta: Float
    var coolDustTSub: Float
    var coolDustTWidth: Float
    var coolGasKappa0: Float
    var coolGasNuSlope: Float
    var coolClumpStrength: Float
    var coolAbsorptionPad: Float
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

// 2xfloat4 (32-byte) lite collision payload for linear32 path.
struct CollisionLite32 {
    var vDiskXYZ_T: SIMD4<Float>
    var noise_dirOct_hit: SIMD4<Float>
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
    var cameraModel: UInt32
    var cameraPsfSigmaPx: Float
    var cameraReadNoise: Float
    var cameraShotNoise: Float
    var cameraFlareStrength: Float
    var backgroundMode: UInt32
    var backgroundStarDensity: Float
    var backgroundStarStrength: Float
    var backgroundNebulaStrength: Float
    var preserveHighlightColor: UInt32
}

func printPackedParamsLayout() {
    print("PackedParams.layout size=\(MemoryLayout<PackedParams>.size) stride=\(MemoryLayout<PackedParams>.stride) align=\(MemoryLayout<PackedParams>.alignment)")
    print("CollisionInfo.layout size=\(MemoryLayout<CollisionInfo>.size) stride=\(MemoryLayout<CollisionInfo>.stride) align=\(MemoryLayout<CollisionInfo>.alignment)")
    print("CollisionLite32.layout size=\(MemoryLayout<CollisionLite32>.size) stride=\(MemoryLayout<CollisionLite32>.stride) align=\(MemoryLayout<CollisionLite32>.alignment)")
    print("ComposeParams.layout size=\(MemoryLayout<ComposeParams>.size) stride=\(MemoryLayout<ComposeParams>.stride) align=\(MemoryLayout<ComposeParams>.alignment)")
    let offsets = packedParamsCriticalOffsets()
    for key in offsets.keys.sorted() {
        if let value = offsets[key] {
            print("PackedParams.offset \(key)=\(value)")
        }
    }
}

func dumpPackedParams(_ params: inout PackedParams, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let data = withUnsafeBytes(of: &params) { Data($0) }
    try data.write(to: url)
}

func validatePackedParamsABIOrThrow() throws {
    let expectedSize = 548
    let expectedStride = 560
    let expectedAlignment = 16
    let expectedOffsets: [String: Int] = [
        "camPos": 32,
        "rs": 100,
        "metric": 140,
        "diskPhysicsMode": 276,
        "diskVolumeMode": 332,
        "visibleMode": 436,
        "coolAbsorptionMode": 508,
    ]
    guard MemoryLayout<PackedParams>.size == expectedSize else {
        throw NSError(domain: "Blackhole", code: 101, userInfo: [NSLocalizedDescriptionKey: "PackedParams size changed: \(MemoryLayout<PackedParams>.size) != \(expectedSize)"])
    }
    guard MemoryLayout<PackedParams>.stride == expectedStride else {
        throw NSError(domain: "Blackhole", code: 102, userInfo: [NSLocalizedDescriptionKey: "PackedParams stride changed: \(MemoryLayout<PackedParams>.stride) != \(expectedStride)"])
    }
    guard MemoryLayout<PackedParams>.alignment == expectedAlignment else {
        throw NSError(domain: "Blackhole", code: 103, userInfo: [NSLocalizedDescriptionKey: "PackedParams alignment changed: \(MemoryLayout<PackedParams>.alignment) != \(expectedAlignment)"])
    }
    let actualOffsets = packedParamsCriticalOffsets()
    for (name, expected) in expectedOffsets {
        guard actualOffsets[name] == expected else {
            throw NSError(domain: "Blackhole", code: 104, userInfo: [NSLocalizedDescriptionKey: "PackedParams offset \(name) changed: \(String(describing: actualOffsets[name])) != \(expected)"])
        }
    }
    guard MemoryLayout<CollisionInfo>.stride == 64 else {
        throw NSError(domain: "Blackhole", code: 105, userInfo: [NSLocalizedDescriptionKey: "CollisionInfo stride changed: \(MemoryLayout<CollisionInfo>.stride)"])
    }
    guard MemoryLayout<CollisionLite32>.stride == 32 else {
        throw NSError(domain: "Blackhole", code: 106, userInfo: [NSLocalizedDescriptionKey: "CollisionLite32 stride changed: \(MemoryLayout<CollisionLite32>.stride)"])
    }
}

private func packedParamsCriticalOffsets() -> [String: Int] {
    [
        "camPos": MemoryLayout<PackedParams>.offset(of: \PackedParams.camPos) ?? -1,
        "rs": MemoryLayout<PackedParams>.offset(of: \PackedParams.rs) ?? -1,
        "metric": MemoryLayout<PackedParams>.offset(of: \PackedParams.metric) ?? -1,
        "diskPhysicsMode": MemoryLayout<PackedParams>.offset(of: \PackedParams.diskPhysicsMode) ?? -1,
        "diskVolumeMode": MemoryLayout<PackedParams>.offset(of: \PackedParams.diskVolumeMode) ?? -1,
        "visibleMode": MemoryLayout<PackedParams>.offset(of: \PackedParams.visibleMode) ?? -1,
        "coolAbsorptionMode": MemoryLayout<PackedParams>.offset(of: \PackedParams.coolAbsorptionMode) ?? -1,
    ]
}
