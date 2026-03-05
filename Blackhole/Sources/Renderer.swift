import Foundation
import Metal

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
    var diskVolumeEnabled: Bool
    var diskVolumeFormat: String
    var diskVolumePath: String
    var diskVol0Path: String
    var diskVol1Path: String
    var diskVolumeR: Int
    var diskVolumePhi: Int
    var diskVolumeZ: Int
    var diskVolumeRNormMin: Double
    var diskVolumeRNormMax: Double
    var diskVolumeZNormMax: Double
    var diskVolumeTauScale: Double
    var diskNuObsHz: Double
    var diskGrmhdDensityScale: Double
    var diskGrmhdBScale: Double
    var diskGrmhdEmissionScale: Double
    var diskGrmhdAbsorptionScale: Double
    var diskGrmhdVelScale: Double
    var diskGrmhdDebug: String
    var visibleMode: Bool
    var visibleSamples: Int
    var visibleTeffModel: String
    var visibleTeffT0: Double
    var visibleTeffR0Rs: Double
    var visibleTeffP: Double
    var visibleBhMass: Double
    var visibleMdot: Double
    var visibleRInRs: Double
    var visiblePhotosphereRhoThreshold: Double
    var visibleEmissionModel: String
    var visibleSynchAlpha: Double
    var exposureMode: String
    var exposureEV: Double
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
    var cameraModel: String
    var cameraPsfSigmaPx: Double
    var cameraReadNoise: Double
    var cameraShotNoise: Double
    var cameraFlareStrength: Double
    var backgroundMode: String
    var backgroundStarDensity: Double
    var backgroundStarStrength: Double
    var backgroundNebulaStrength: Double
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

@inline(__always)
func emitETAProgress(_ done: Int, _ total: Int, _ phase: String, _ extra: String = "") {
    let safeTotal = max(total, 1)
    let suffix = extra.isEmpty ? "" : " " + extra
    let line = "ETA_PROGRESS \(done) \(safeTotal) \(phase)\(suffix)\n"
    FileHandle.standardError.write(Data(line.utf8))
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

func composeTargetWhite(_ lookID: UInt32) -> Float {
    if lookID == 1 { return 0.9 }   // interstellar
    if lookID == 2 { return 0.6 }   // eht
    if lookID == 3 { return 1.25 }  // agx/filmic: avoid chronic underexposure vs ACES-tuned default
    if lookID == 5 { return 1.40 }  // hdr: keep richer highlight headroom before display rolloff
    return 0.8
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

func planckNu(_ nuHz: Double, _ temp: Double) -> Double {
    let h = 6.62607015e-34
    let c = 299_792_458.0
    let k = 1.380649e-23
    let x = min(max((h * nuHz) / max(k * temp, 1e-30), 1e-8), 700.0)
    let num = 2.0 * h * nuHz * nuHz * nuHz / (c * c)
    return num / max(expm1(x), 1e-30)
}

func visibleINuEmit(_ nuHz: Double, _ temp: Double, _ emissionModel: UInt32, _ alpha: Double) -> Double {
    if emissionModel == 1 {
        // Synchrotron-like power-law shape anchored to thermal scale at a pivot frequency.
        let nuPivot = 5.0e14
        let ratio = max(nuHz / nuPivot, 1e-8)
        let slope = min(max(alpha, 0.0), 4.0)
        let pivot = planckNu(nuPivot, temp)
        return pivot * pow(ratio, -slope)
    }
    return planckNu(nuHz, temp)
}

func estimateGRMHDRhoMax(vol0Data: Data) -> Double {
    let floatCount = vol0Data.count / MemoryLayout<Float>.stride
    if floatCount < 4 { return 0.0 }
    let sampleCount = floatCount / 4
    var rhoMax = 0.0
    vol0Data.withUnsafeBytes { raw in
        guard let base = raw.bindMemory(to: Float.self).baseAddress else { return }
        var idx = 0
        for _ in 0..<sampleCount {
            let logRho = Double(base[idx])
            let rho = exp(min(max(logRho, -40.0), 40.0))
            if rho > rhoMax { rhoMax = rho }
            idx += 4
        }
    }
    return rhoMax
}

func fail(_ message: String, code: Int32 = 3) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(code)
}

enum Renderer {
    static func render(arguments: [String]) throws {
        setCLIArguments(arguments)
        let dumpPackedParamsPath = stringArg("--dump-packed-params", default: "")
    if cliArguments.contains("--kerr-use-u") {
        FileHandle.standardError.write(Data("error: --kerr-use-u has been removed after validation tests showed no practical gain.\n".utf8))
        exit(2)
    }
    if cliArguments.contains("--sample") {
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
    let composeGPU = cliArguments.contains("--compose-gpu")
    let gpuFullCompose = cliArguments.contains("--gpu-full-compose")
    let discardCollisionOutput = cliArguments.contains("--discard-collisions")
    let linear32Intermediate = cliArguments.contains("--linear32-intermediate")
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
    let diskModeRaw = stringArg("--disk-mode", default: "").lowercased()
    let diskPhysicsProfileRaw = stringArg("--disk-physics", default: "").lowercased()
    let diskPhysicsLegacyRaw = stringArg("--disk-physics-mode", default: "").lowercased()
    if !diskModeRaw.isEmpty && !diskPhysicsLegacyRaw.isEmpty {
        guard let modeA = parseDiskMode(diskModeRaw) else {
            fail("invalid --disk-mode \(diskModeRaw). use one of: thin, thick, precision, grmhd, auto")
        }
        guard let modeB = parseDiskMode(diskPhysicsLegacyRaw) else {
            fail("invalid --disk-physics-mode \(diskPhysicsLegacyRaw). use one of: thin, thick, precision, grmhd, auto")
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
            fail("invalid --disk-mode \(diskModeRaw). use one of: thin, thick, precision, grmhd, auto")
        }
        fail("invalid --disk-physics-mode \(diskPhysicsLegacyRaw). use one of: thin, thick, precision, grmhd, auto")
    }
    let accretionModel = AccretionModels.default
    let resolvedMode = accretionModel.resolvePhysicsMode(
        parsedModeID: diskModeParsed.id,
        parsedModeName: diskModeParsed.canonical,
        rawMode: diskModeResolvedRaw
    )
    var diskPhysicsModeID: UInt32 = resolvedMode.id
    var diskPhysicsModeArg: String = resolvedMode.name
    if !diskPhysicsProfileRaw.isEmpty {
        guard let profile = parseDiskPhysicsProfile(diskPhysicsProfileRaw) else {
            fail("invalid --disk-physics \(diskPhysicsProfileRaw). use one of: legacy, thin, thick, eht")
        }
        if profile.id != diskPhysicsModeID {
            FileHandle.standardError.write(
                Data("info: --disk-physics \(profile.canonical) overrides --disk-mode \(diskModeResolvedRaw)\n".utf8)
            )
        }
        diskPhysicsModeID = profile.id
        diskPhysicsModeArg = profile.canonical
    }
    let diskPhysicsThinProfile = (!diskPhysicsProfileRaw.isEmpty && diskPhysicsModeArg == "thin")
    let diskMdotEddArg = max(1e-5, doubleArgAny(["--mdot-edd", "--disk-mdot-edd"], default: 0.1))
    let diskRadiativeEfficiencyArg = min(max(doubleArgAny(["--eta", "--disk-radiative-efficiency"], default: 0.1), 0.01), 0.42)
    let hasDiskVolumeArg = cliArguments.contains("--disk-volume")
        || cliArguments.contains("--disk-vol0")
        || cliArguments.contains("--disk-vol1")
    let diskModeUsesAutoAlias = ["auto", "unified", "adaptive", "smart"].contains(diskModeResolvedRaw)
    let precisionAdaptive = precisionAdaptiveDefaults(diskH: diskHFactor)
    let diskPlungeFloorDefault: Double = {
        if diskPhysicsModeID == 1 { return 0.02 }
        if diskPhysicsModeID == 2 { return precisionAdaptive.plungeFloor }
        return 0.0
    }()
    let diskThickScaleDefault: Double = {
        if diskPhysicsModeID == 1 { return 1.3 }
        if diskPhysicsModeID == 2 { return precisionAdaptive.thickScale }
        return 1.0
    }()
    if diskModeUsesAutoAlias {
        FileHandle.standardError.write(
            Data("info: --disk-mode auto resolves to precision with diskH-adaptive thin/thick defaults\n".utf8)
        )
    }
    let diskPlungeFloorArg = min(1.0, max(0.0, doubleArg("--disk-plunge-floor", default: diskPlungeFloorDefault)))
    let diskThickScaleArg = max(1.0, doubleArgAny(["--thick-scale", "--disk-thick-scale"], default: diskThickScaleDefault))
    let diskColorFactorArg = max(1.0, doubleArgAny(["--fcol", "--disk-color-factor"], default: (diskPhysicsModeID == 2 ? 1.7 : 1.0)))
    let precisionDefaultsEnabled = (diskPhysicsModeID == 2 && !diskPhysicsThinProfile)
    let diskReturningRadRawArg = max(0.0, min(1.0, doubleArg("--disk-returning-rad", default: (precisionDefaultsEnabled ? 0.35 : 0.0))))
    let diskPrecisionTextureRawArg = max(0.0, min(1.0, doubleArg("--disk-precision-texture", default: (precisionDefaultsEnabled ? 0.58 : 0.0))))
    let diskPrecisionCloudsName = stringArg("--disk-precision-clouds", default: (precisionDefaultsEnabled ? "on" : "off")).lowercased()
    let diskPrecisionCloudsEnabled: Bool
    switch diskPrecisionCloudsName {
    case "on", "true", "1", "yes":
        diskPrecisionCloudsEnabled = true
    case "off", "false", "0", "no":
        diskPrecisionCloudsEnabled = false
    default:
        fail("invalid --disk-precision-clouds \(diskPrecisionCloudsName). use on|off")
    }
    let diskCloudCoverageRawArg = max(0.0, min(1.0, doubleArg("--disk-cloud-coverage", default: (precisionDefaultsEnabled ? (hasDiskVolumeArg ? 0.58 : 0.88) : 0.0))))
    let diskCloudOpticalDepthRawArg = max(0.0, min(12.0, doubleArgAny(["--cloud-tau", "--disk-cloud-optical-depth"], default: (precisionDefaultsEnabled ? (hasDiskVolumeArg ? 1.10 : 2.0) : 0.0))))
    let diskCloudPorosityRawArg = max(0.0, min(1.0, doubleArg("--disk-cloud-porosity", default: (precisionDefaultsEnabled ? (hasDiskVolumeArg ? 0.42 : 0.18) : 0.0))))
    let diskCloudShadowStrengthRawArg = max(0.0, min(1.0, doubleArg("--disk-cloud-shadow-strength", default: (precisionDefaultsEnabled ? (hasDiskVolumeArg ? 0.62 : 0.90) : 0.0))))
    let diskReturnBouncesRawArg = max(1, min(4, intArg("--disk-return-bounces", default: (precisionDefaultsEnabled ? 2 : 1))))
    let diskRTStepsRawArg = max(0, min(32, intArgAny(["--rt-steps", "--disk-rt-steps"], default: 0)))
    let diskScatteringAlbedoRawArg = max(0.0, min(1.0, doubleArg("--disk-scattering-albedo", default: (precisionDefaultsEnabled ? (hasDiskVolumeArg ? 0.52 : 0.62) : 0.0))))
    let diskReturningRadArg = (diskPhysicsModeID == 2) ? diskReturningRadRawArg : 0.0
    var diskPrecisionTextureArg = (diskPhysicsModeID == 2) ? diskPrecisionTextureRawArg : 0.0
    let thickCloudExplicit = (diskPhysicsModeID == 1) &&
        (cliArguments.contains("--cloud-tau") || cliArguments.contains("--disk-cloud-optical-depth"))
    let diskCloudCoverageArg = (diskPhysicsModeID == 2 && diskPrecisionCloudsEnabled)
        ? diskCloudCoverageRawArg
        : (thickCloudExplicit ? max(diskCloudCoverageRawArg, 0.55) : 0.0)
    let diskCloudOpticalDepthArg = (diskPhysicsModeID == 2 && diskPrecisionCloudsEnabled)
        ? diskCloudOpticalDepthRawArg
        : (thickCloudExplicit ? diskCloudOpticalDepthRawArg : 0.0)
    let diskCloudPorosityArg = (diskPhysicsModeID == 2 && diskPrecisionCloudsEnabled)
        ? diskCloudPorosityRawArg
        : (thickCloudExplicit ? max(diskCloudPorosityRawArg, 0.20) : 0.0)
    let diskCloudShadowStrengthArg = (diskPhysicsModeID == 2 && diskPrecisionCloudsEnabled)
        ? diskCloudShadowStrengthRawArg
        : (thickCloudExplicit ? max(diskCloudShadowStrengthRawArg, 0.55) : 0.0)
    let diskReturnBouncesArg = (diskPhysicsModeID == 2) ? diskReturnBouncesRawArg : 1
    let diskRTStepsArg = (diskPhysicsModeID == 2 || diskPhysicsModeID == 3) ? diskRTStepsRawArg : 0
    let diskScatteringAlbedoArg = (diskPhysicsModeID == 2) ? diskScatteringAlbedoRawArg : 0.0
    if diskPhysicsModeID != 2 && diskReturningRadRawArg > 1e-8 {
        FileHandle.standardError.write(Data("warn: --disk-returning-rad is only active in precision mode\n".utf8))
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
    let diskVolumePathArg = stringArg("--disk-volume", default: "")
    let diskVol0PathArg = stringArg("--disk-vol0", default: "")
    let diskVol1PathArg = stringArg("--disk-vol1", default: "")
    let diskMetaPathArg = stringArg("--disk-meta", default: "")
    let diskVolumeROverrideArg = max(0, intArg("--disk-volume-r", default: 0))
    let diskVolumePhiOverrideArg = max(0, intArg("--disk-volume-phi", default: 0))
    let diskVolumeZOverrideArg = max(0, intArg("--disk-volume-z", default: 0))
    let diskVolumeTauScaleRawArg = max(0.0, doubleArg("--disk-volume-tau-scale", default: hasDiskVolumeArg ? 0.85 : 1.0))
    let diskNuObsHzArg = max(1e6, doubleArgAny(["--nu-obs-hz", "--disk-nu-obs-hz"], default: 230.0e9))
    let diskGrmhdDensityScaleArg = max(0.0, doubleArg("--disk-grmhd-density-scale", default: 1.0))
    let diskGrmhdBScaleArg = max(0.0, doubleArg("--disk-grmhd-b-scale", default: 1.0))
    let diskGrmhdEmissionScaleArg = max(0.0, doubleArg("--disk-grmhd-emission-scale", default: 1.0))
    let diskGrmhdAbsorptionScaleArg = max(0.0, doubleArg("--disk-grmhd-absorption-scale", default: 1.0))
    let diskGrmhdVelScaleArg = max(0.0, doubleArg("--disk-grmhd-vel-scale", default: 1.0))
    let diskGrmhdDebugName = stringArg("--disk-grmhd-debug", default: "off").lowercased()
    let diskGrmhdDebugID: UInt32
    switch diskGrmhdDebugName {
    case "off", "none":
        diskGrmhdDebugID = 0
    case "rho", "max-rho":
        diskGrmhdDebugID = 1
    case "b2", "bsq", "max-b2":
        diskGrmhdDebugID = 2
    case "j", "jnu", "max-jnu":
        diskGrmhdDebugID = 3
    case "i", "inu", "intensity", "max-inu":
        diskGrmhdDebugID = 4
    case "teff", "temperature":
        diskGrmhdDebugID = 5
    case "g", "gfactor", "redshift":
        diskGrmhdDebugID = 6
    case "y", "luma", "luminance":
        diskGrmhdDebugID = 7
    case "peak", "peak-lambda", "lambda-peak":
        diskGrmhdDebugID = 8
    case "pol", "polarization", "polfrac":
        diskGrmhdDebugID = 9
    default:
        fail("invalid --disk-grmhd-debug \(diskGrmhdDebugName). use one of: off, rho, b2, jnu, inu, teff, g, y, peak, pol")
    }
    if diskPhysicsModeID != 3 && diskGrmhdDebugID != 0 {
        FileHandle.standardError.write(Data("warn: --disk-grmhd-debug is only active in grmhd mode\n".utf8))
    }
    let diskPolarizedRTName = stringArg("--disk-polarized-rt", default: "off").lowercased()
    let diskPolarizedRTEnabled: Bool
    switch diskPolarizedRTName {
    case "on", "true", "1", "yes":
        diskPolarizedRTEnabled = true
    case "off", "false", "0", "no":
        diskPolarizedRTEnabled = false
    default:
        fail("invalid --disk-polarized-rt \(diskPolarizedRTName). use on|off")
    }
    let diskPolarizationFracArg = min(max(doubleArg("--disk-pol-frac", default: 0.25), 0.0), 0.95)
    let diskFaradayRotScaleArg = doubleArg("--disk-faraday-rot", default: 0.0)
    let diskFaradayConvScaleArg = doubleArg("--disk-faraday-conv", default: 0.0)
    if diskPhysicsModeID != 3 && (diskPolarizedRTEnabled || abs(diskFaradayRotScaleArg) > 1e-30 || abs(diskFaradayConvScaleArg) > 1e-30) {
        FileHandle.standardError.write(Data("warn: polarized GRRT options are only active in grmhd mode\n".utf8))
    }
    let visibleModeName = stringArg("--visible-mode", default: "off").lowercased()
    let visibleModeEnabled: Bool
    switch visibleModeName {
    case "on", "true", "1", "yes":
        visibleModeEnabled = true
    case "off", "false", "0", "no":
        visibleModeEnabled = false
    default:
        fail("invalid --visible-mode \(visibleModeName). use on|off")
    }
    if diskPhysicsModeID != 3 && visibleModeEnabled {
        FileHandle.standardError.write(Data("warn: --visible-mode currently applies to grmhd mode; requested mode \(diskPhysicsModeArg) will ignore it\n".utf8))
    }
    let visibleSamplesArg = max(8, min(128, intArg("--visible-samples", default: 48)))
    let visibleTeffModelName = stringArg("--teff-model", default: "parametric").lowercased()
    let visibleTeffModelID: UInt32
    switch visibleTeffModelName {
    case "parametric", "a1":
        visibleTeffModelID = 0
    case "thin-disk", "thin", "a2":
        visibleTeffModelID = 1
    case "nt", "novikov-thorne", "novikov_thorne", "a3":
        visibleTeffModelID = 2
    default:
        fail("invalid --teff-model \(visibleTeffModelName). use one of: parametric, thin-disk, nt")
    }
    let visibleTeffT0Arg = max(100.0, doubleArg("--teff-T0", default: 12000.0))
    let visibleTeffR0RsArg = max(1e-3, doubleArg("--teff-r0", default: 5.0))
    let visibleTeffPArg = min(max(doubleArg("--teff-p", default: 0.75), 0.05), 3.0)
    let visibleBhMassArg = max(1e20, doubleArg("--bh-mass", default: 1.0e35))
    let visibleMdotArg = max(0.0, doubleArg("--mdot", default: 1.0e15))
    let visibleRInRsArg = max(0.0, doubleArg("--r-in", default: 0.0))
    let photosphereRhoThresholdArg = max(0.0, doubleArg("--photosphere-rho-threshold", default: 0.0))
    let visibleEmissionModelName = stringArg("--visible-emission-model", default: "blackbody").lowercased()
    let visibleEmissionModelID: UInt32
    switch visibleEmissionModelName {
    case "blackbody", "thermal":
        visibleEmissionModelID = 0
    case "synchrotron", "powerlaw", "power-law":
        visibleEmissionModelID = 1
    default:
        fail("invalid --visible-emission-model \(visibleEmissionModelName). use one of: blackbody, synchrotron")
    }
    let visibleSynchAlphaArg = min(max(doubleArg("--visible-synch-alpha", default: 0.85), 0.0), 4.0)
    let visibleKappaArg = max(0.0, doubleArg("--visible-kappa", default: 0.0))
    let coolAbsorptionName = stringArg("--disk-cool-absorption", default: ((diskPhysicsModeID == 3 && visibleModeEnabled) ? "on" : "off")).lowercased()
    let coolAbsorptionEnabled: Bool
    switch coolAbsorptionName {
    case "on", "true", "1", "yes":
        coolAbsorptionEnabled = true
    case "off", "false", "0", "no":
        coolAbsorptionEnabled = false
    default:
        fail("invalid --disk-cool-absorption \(coolAbsorptionName). use on|off")
    }
    let coolDustToGasArg = max(0.0, min(0.2, doubleArg("--disk-cool-dust-to-gas", default: 0.01)))
    let coolDustKappaVArg = max(0.0, doubleArg("--disk-cool-dust-kappa-v", default: 1800.0))
    let coolDustBetaArg = max(0.0, min(4.0, doubleArg("--disk-cool-dust-beta", default: 1.7)))
    let coolDustTSubArg = max(300.0, doubleArg("--disk-cool-dust-tsub", default: 1500.0))
    let coolDustTWidthArg = max(10.0, doubleArg("--disk-cool-dust-twidth", default: 180.0))
    let coolGasKappa0Arg = max(0.0, doubleArg("--disk-cool-gas-kappa0", default: 4.0e-3))
    let coolGasNuSlopeArg = max(0.0, min(6.0, doubleArg("--disk-cool-gas-nu-slope", default: 2.0)))
    let coolClumpStrengthArg = max(0.0, min(2.0, doubleArg("--disk-cool-clump-strength", default: 0.7)))
    let coolAbsorptionArgsExplicit =
        cliArguments.contains("--disk-cool-absorption") ||
        cliArguments.contains("--disk-cool-dust-to-gas") ||
        cliArguments.contains("--disk-cool-dust-kappa-v") ||
        cliArguments.contains("--disk-cool-dust-beta") ||
        cliArguments.contains("--disk-cool-dust-tsub") ||
        cliArguments.contains("--disk-cool-dust-twidth") ||
        cliArguments.contains("--disk-cool-gas-kappa0") ||
        cliArguments.contains("--disk-cool-gas-nu-slope") ||
        cliArguments.contains("--disk-cool-clump-strength")
    if !(diskPhysicsModeID == 3 && visibleModeEnabled) &&
        (coolAbsorptionEnabled || coolAbsorptionArgsExplicit) {
        FileHandle.standardError.write(Data("warn: cool gas/dust absorption args are active only in grmhd visible mode\n".utf8))
    }
    if diskPhysicsModeID == 3 && visibleModeEnabled {
        // GRMHD visible mode benefits from mild unresolved-photosphere texture contrast.
        // Keep user override if explicitly provided.
        let hasTextureArg = cliArguments.contains("--disk-precision-texture")
        if hasTextureArg {
            diskPrecisionTextureArg = diskPrecisionTextureRawArg
        } else {
            diskPrecisionTextureArg = 0.58
        }
    } else if diskPhysicsModeID != 2 && diskPrecisionTextureRawArg > 1e-8 {
        FileHandle.standardError.write(Data("warn: --disk-precision-texture is active in precision mode and grmhd visible mode only\n".utf8))
    }
    let rayBundleName = stringArg("--ray-bundle", default: "off").lowercased()
    let rayBundleEnabled: Bool
    switch rayBundleName {
    case "on", "true", "1", "yes":
        rayBundleEnabled = true
    case "off", "false", "0", "no":
        rayBundleEnabled = false
    default:
        fail("invalid --ray-bundle \(rayBundleName). use on|off")
    }
    let rayBundleJacobianName = stringArg("--ray-bundle-jacobian", default: "off").lowercased()
    let rayBundleJacobianEnabled: Bool
    switch rayBundleJacobianName {
    case "on", "true", "1", "yes":
        rayBundleJacobianEnabled = true
    case "off", "false", "0", "no":
        rayBundleJacobianEnabled = false
    default:
        fail("invalid --ray-bundle-jacobian \(rayBundleJacobianName). use on|off")
    }
    let rayBundleJacobianStrengthArg = max(0.0, doubleArg("--ray-bundle-jacobian-strength", default: 1.0))
    let rayBundleFootprintClampArg = min(max(doubleArg("--ray-bundle-footprint-clamp", default: 6.0), 0.0), 20.0)
    let rayBundleEligible = (diskPhysicsModeID == 3 && visibleModeEnabled && diskGrmhdDebugID == 0)
    let rayBundleActive = rayBundleEnabled && rayBundleEligible
    let rayBundleJacobianActive = rayBundleActive && rayBundleJacobianEnabled
    if rayBundleEnabled && !rayBundleEligible {
        FileHandle.standardError.write(
            Data("warn: --ray-bundle is currently applied only for grmhd visible mode (--disk-mode grmhd --visible-mode on --disk-grmhd-debug off); falling back to single-ray path\n".utf8)
        )
    }
    let tileSizeArg = max(0, intArg("--tile-size", default: 0))
    let traceInFlightOverrideArg = max(0, intArg("--trace-inflight", default: 0))
    let pixelCount = width * height
    // Kerr high-resolution full-frame dispatch (e.g. 2000x2000 in SSAA path)
    // can intermittently miss disk hits; force tiled tracing earlier for stability.
    let autoTile = pixelCount > 8_000_000 || (metricArg == 1 && pixelCount >= 4_000_000)
    let tileSize = (tileSizeArg > 0) ? tileSizeArg : (autoTile ? 1024 : max(width, height))
    let hasLookArg = cliArguments.contains("--look")
    let defaultLookName = ((diskPhysicsModeID == 2 || diskPhysicsModeID == 3) && !hasLookArg) ? "balanced" : preset
    let composeLook = stringArg("--look", default: defaultLookName).lowercased()
    let composeLookID: UInt32
    switch composeLook {
    case "interstellar": composeLookID = 1
    case "eht": composeLookID = 2
    case "agx", "filmic": composeLookID = 3
    case "none", "linear": composeLookID = 4
    case "hdr", "hdr-rich", "hdrrich": composeLookID = 5
    default: composeLookID = 0
    }
    let composeDitherDefault: Double = {
        switch diskModelArg {
        case "perlin", "perlin-ec7", "perlin-legacy", "perlin-classic", "perlin-f552":
            return 0.0
        default:
            break
        }
        return (diskPhysicsModeID == 2 || diskPhysicsModeID == 3) ? 0.0 : 0.75
    }()
    let composeDitherArg = Float(doubleArg("--dither", default: composeDitherDefault))
    let cameraModelName = stringArg("--camera-model", default: ((diskPhysicsModeID == 2 || diskPhysicsModeID == 3) ? "scientific" : "legacy")).lowercased()
    let cameraModelID: UInt32
    switch cameraModelName {
    case "legacy", "none":
        cameraModelID = 0
    case "scientific", "science":
        cameraModelID = 1
    case "cinematic", "cinema":
        cameraModelID = 2
    default:
        fail("invalid --camera-model \(cameraModelName). use one of: legacy, scientific, cinematic")
    }
    let cameraPsfSigmaArg = Float(max(0.0, doubleArg("--camera-psf-sigma", default: {
        switch cameraModelID {
        case 1: return 0.55
        case 2: return 0.35
        default: return 0.0
        }
    }())))
    let cameraReadNoiseArg = Float(max(0.0, doubleArg("--camera-read-noise", default: {
        switch cameraModelID {
        case 1: return 0.0025
        case 2: return 0.0012
        default: return 0.0
        }
    }())))
    let cameraShotNoiseArg = Float(max(0.0, doubleArg("--camera-shot-noise", default: {
        switch cameraModelID {
        case 1: return 0.010
        case 2: return 0.006
        default: return 0.0
        }
    }())))
    let cameraFlareStrengthArg = Float(max(0.0, min(1.0, doubleArg("--camera-flare", default: (cameraModelID == 2 ? 0.20 : 0.0)))))
    if cameraModelID != 2 && cameraFlareStrengthArg > 1e-6 {
        FileHandle.standardError.write(Data("warn: --camera-flare is only active in --camera-model cinematic\n".utf8))
    }
    let backgroundRawArg = stringArg("--background", default: "").lowercased()
    let backgroundStarsRawArg = stringArg("--bg-stars", default: "").lowercased()
    let backgroundModeName: String = {
        if !backgroundRawArg.isEmpty { return backgroundRawArg }
        if !backgroundStarsRawArg.isEmpty {
            switch backgroundStarsRawArg {
            case "on", "true", "1", "yes":
                return "stars"
            case "off", "false", "0", "no":
                return "off"
            default:
                fail("invalid --bg-stars \(backgroundStarsRawArg). use on|off")
            }
        }
        return (cameraModelID == 2) ? "stars" : "off"
    }()
    let backgroundModeID: UInt32
    switch backgroundModeName {
    case "off", "none", "black":
        backgroundModeID = 0
    case "stars", "starfield", "sky":
        backgroundModeID = 1
    default:
        fail("invalid --background \(backgroundModeName). use one of: off, stars")
    }
    let backgroundStarDensityArg = Float(max(0.0, min(4.0, doubleArg("--bg-star-density", default: (backgroundModeID == 1 ? 1.0 : 0.0)))))
    let backgroundStarStrengthArg = Float(max(0.0, min(4.0, doubleArg("--bg-star-strength", default: (backgroundModeID == 1 ? 1.0 : 0.0)))))
    let backgroundNebulaStrengthArg = Float(max(0.0, min(2.0, doubleArg("--bg-nebula-strength", default: (backgroundModeID == 1 ? 0.45 : 0.0)))))
    if backgroundModeID == 0 && (backgroundStarDensityArg > 1e-6 || backgroundStarStrengthArg > 1e-6 || backgroundNebulaStrengthArg > 1e-6) {
        FileHandle.standardError.write(Data("warn: background intensity args are ignored when --background off\n".utf8))
    }
    let composeInnerEdgeArg = Float(max(1.0, doubleArg("--inner-edge-mult", default: 1.4)))
    let composeSpectralStepArg = Float(max(0.25, doubleArg("--spectral-step", default: 5.0)))
    let composeChunkArg = max(1, intArg("--chunk", default: 160000))
    let exposureSamplesArg = max(0, intArg("--exposure-samples", default: 200000))
    let exposureArg = Float(doubleArg("--exposure", default: -1.0))
    let exposureModeName = stringArg("--exposure-mode", default: "auto").lowercased()
    let exposureModeID: UInt32
    switch exposureModeName {
    case "auto":
        exposureModeID = 0
    case "fixed":
        exposureModeID = 1
    default:
        fail("invalid --exposure-mode \(exposureModeName). use one of: auto, fixed")
    }
    let exposureEVArg = doubleArg("--exposure-ev", default: 0.0)
    let composePrecisionName = stringArg("--compose-precision", default: "precise").lowercased()
    let composePrecisionID: UInt32 = (composePrecisionName == "fast") ? 0 : 1
    let composeAnalysisMode: UInt32 = {
        if diskPhysicsModeID == 2 { return diskPrecisionCloudsEnabled ? 2 : 1 }
        if diskPhysicsModeID == 3 && diskGrmhdDebugID != 0 { return 10 + diskGrmhdDebugID }
        return 0
    }()
    let composeCameraModelID: UInt32 = (composeAnalysisMode == 0) ? cameraModelID : 0
    let composeCameraPsfSigmaArg: Float = (composeAnalysisMode == 0) ? cameraPsfSigmaArg : 0.0
    let composeCameraReadNoiseArg: Float = (composeAnalysisMode == 0) ? cameraReadNoiseArg : 0.0
    let composeCameraShotNoiseArg: Float = (composeAnalysisMode == 0) ? cameraShotNoiseArg : 0.0
    let composeCameraFlareStrengthArg: Float = (composeAnalysisMode == 0) ? cameraFlareStrengthArg : 0.0
    let autoExposureEnabled: Bool = {
        if exposureArg > 0 { return false }
        if exposureModeID == 1 { return false }
        return true
    }()
    let composeExposureBase: Float = {
        if exposureArg > 0 { return exposureArg }
        if exposureModeID == 1 { return Float(pow(2.0, exposureEVArg)) }
        switch composeLookID {
        case 1: return 7.0e-18   // interstellar default
        case 2: return 5.2e-18   // eht default
        default: return 6.8e-18  // balanced default
        }
    }()
    let spectralEncodingID: UInt32 = (spectralEncoding == "gfactor_v1") ? 1 : 0
    var composeExposure = composeExposureBase
    let preserveHighlightColor: UInt32 = (diskPhysicsModeID == 3 && visibleModeEnabled && composeAnalysisMode == 0) ? 1 : 0
    let useLinear32Intermediate = composeGPU && !gpuFullCompose && linear32Intermediate
    var diskModelResolved: String
    switch diskModelArg {
    case "flow", "procedural", "legacy", "noise":
        diskModelResolved = "flow"
    case "perlin":
        diskModelResolved = "perlin"
    case "perlin-ec7", "perlin-legacy":
        diskModelResolved = "perlin-ec7"
    case "perlin-classic", "perlin-f552":
        diskModelResolved = "perlin-classic"
    case "atlas":
        diskModelResolved = "atlas"
    case "auto":
        diskModelResolved = diskAtlasPathArg.isEmpty ? "flow" : "atlas"
    default:
        fail("invalid --disk-model \(diskModelArg). use one of: flow, perlin, perlin-classic, perlin-ec7, atlas, auto (alias: procedural)")
    }
    if (diskPhysicsModeID == 2 || diskPhysicsModeID == 3) && diskModelResolved != "flow" {
        let modeLabel = (diskPhysicsModeID == 3) ? "grmhd" : "precision"
        FileHandle.standardError.write(Data("warn: \(modeLabel) mode renders with flow disk model; requested --disk-model \(diskModelResolved) is treated as flow\n".utf8))
        diskModelResolved = "flow"
    }
    if diskModelResolved == "atlas" && diskAtlasPathArg.isEmpty {
        fail("--disk-model atlas requires --disk-atlas <path>")
    }
    if diskModelResolved != "atlas" && !diskAtlasPathArg.isEmpty {
        FileHandle.standardError.write(Data("warn: --disk-model \(diskModelResolved) ignores --disk-atlas and atlas tuning args at render time\n".utf8))
    }
    let diskAtlasEnabled = (diskModelResolved == "atlas")
    let diskNoiseModel: UInt32 = {
        switch diskModelResolved {
        case "perlin": return 1
        case "perlin-ec7": return 2
        case "perlin-classic": return 3
        default: return 0
        }
    }()
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
    if diskPhysicsModeID != 2 && !diskVolumePathArg.isEmpty {
        FileHandle.standardError.write(Data("warn: --disk-volume is only active in precision mode\n".utf8))
    }
    if diskPhysicsModeID != 3 && (!diskVol0PathArg.isEmpty || !diskVol1PathArg.isEmpty) {
        FileHandle.standardError.write(Data("warn: --disk-vol0/--disk-vol1 are only active in grmhd mode\n".utf8))
    }
    let diskVolumeTauScaleArg = (diskPhysicsModeID == 2 || diskPhysicsModeID == 3) ? diskVolumeTauScaleRawArg : 0.0
    let diskVolumeFormatArg: UInt32 = (diskPhysicsModeID == 3) ? 1 : 0
    let diskVolumeLegacyEnabled = (diskPhysicsModeID == 2) && !diskVolumePathArg.isEmpty
    let diskVolumeGRMHDEnabled = (diskPhysicsModeID == 3)
    if diskVolumeGRMHDEnabled && (diskVol0PathArg.isEmpty || diskVol1PathArg.isEmpty) {
        fail("grmhd mode requires --disk-vol0 <path> and --disk-vol1 <path>")
    }
    let diskVolumeEnabled = diskVolumeLegacyEnabled || diskVolumeGRMHDEnabled

    let diskVolume0Data: Data
    let diskVolume1Data: Data
    let diskVolumeR: Int
    let diskVolumePhi: Int
    let diskVolumeZ: Int
    var diskVolumeMetaRMin: Double? = nil
    var diskVolumeMetaRMax: Double? = nil
    var diskVolumeMetaZMax: Double? = nil
    let diskVol0PathResolved: String
    let diskVol1PathResolved: String
    if diskVolumeLegacyEnabled {
        do {
            let loaded = try loadDiskVolume(
                path: diskVolumePathArg,
                metaPath: diskMetaPathArg,
                rOverride: diskVolumeROverrideArg,
                phiOverride: diskVolumePhiOverrideArg,
                zOverride: diskVolumeZOverrideArg
            )
            diskVolume0Data = loaded.data
            diskVolumeR = loaded.r
            diskVolumePhi = loaded.phi
            diskVolumeZ = loaded.z
            diskVolumeMetaRMin = loaded.rNormMin
            diskVolumeMetaRMax = loaded.rNormMax
            diskVolumeMetaZMax = loaded.zNormMax
            var empty = SIMD4<Float>(repeating: 0.0)
            diskVolume1Data = withUnsafeBytes(of: &empty) { Data($0) }
            diskVol0PathResolved = diskVolumePathArg
            diskVol1PathResolved = ""
        } catch {
            fail("failed to load --disk-volume: \(error.localizedDescription)")
        }
    } else if diskVolumeGRMHDEnabled {
        do {
            let loaded0 = try loadDiskVolume(
                path: diskVol0PathArg,
                metaPath: diskMetaPathArg,
                rOverride: diskVolumeROverrideArg,
                phiOverride: diskVolumePhiOverrideArg,
                zOverride: diskVolumeZOverrideArg
            )
            let loaded1 = try loadDiskVolume(
                path: diskVol1PathArg,
                metaPath: diskMetaPathArg,
                rOverride: diskVolumeROverrideArg,
                phiOverride: diskVolumePhiOverrideArg,
                zOverride: diskVolumeZOverrideArg
            )
            if loaded0.r != loaded1.r || loaded0.phi != loaded1.phi || loaded0.z != loaded1.z {
                fail("grmhd volume dimensions mismatch: vol0=\(loaded0.r)x\(loaded0.phi)x\(loaded0.z), vol1=\(loaded1.r)x\(loaded1.phi)x\(loaded1.z)")
            }
            diskVolume0Data = loaded0.data
            diskVolume1Data = loaded1.data
            diskVolumeR = loaded0.r
            diskVolumePhi = loaded0.phi
            diskVolumeZ = loaded0.z
            diskVolumeMetaRMin = loaded0.rNormMin ?? loaded1.rNormMin
            diskVolumeMetaRMax = loaded0.rNormMax ?? loaded1.rNormMax
            diskVolumeMetaZMax = loaded0.zNormMax ?? loaded1.zNormMax
            diskVol0PathResolved = diskVol0PathArg
            diskVol1PathResolved = diskVol1PathArg
        } catch {
            fail("failed to load --disk-vol0/--disk-vol1: \(error.localizedDescription)")
        }
    } else {
        var empty = SIMD4<Float>(repeating: 0.0)
        let emptyData = withUnsafeBytes(of: &empty) { Data($0) }
        diskVolume0Data = emptyData
        diskVolume1Data = emptyData
        diskVolumeR = 1
        diskVolumePhi = 1
        diskVolumeZ = 1
        diskVol0PathResolved = ""
        diskVol1PathResolved = ""
    }
    let diskVolumeRMin = max(0.0, diskVolumeMetaRMin ?? 1.0)
    let diskVolumeRMax = max(diskVolumeRMin + 1e-6, diskVolumeMetaRMax ?? max(rcp, diskVolumeRMin + 0.1))
    let diskVolumeZMax = max(1e-4, diskVolumeMetaZMax ?? 0.35)
    var photosphereRhoThresholdResolved = photosphereRhoThresholdArg
    if diskPhysicsModeID == 3 && visibleModeEnabled && photosphereRhoThresholdResolved > 0.0 && diskVolumeFormatArg == 1 {
        let rhoMax = estimateGRMHDRhoMax(vol0Data: diskVolume0Data)
        if rhoMax > 0.0 && photosphereRhoThresholdResolved > rhoMax {
            let clamped = max(rhoMax * 0.25, rhoMax * 1e-3)
            FileHandle.standardError.write(
                Data(
                    String(
                        format: "warn: --photosphere-rho-threshold %.6e exceeds volume rho max %.6e; clamping to %.6e\n",
                        photosphereRhoThresholdResolved,
                        rhoMax,
                        clamped
                    ).utf8
                )
            )
            photosphereRhoThresholdResolved = clamped
        }
    }

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

    print(
        "render config preset=\(preset) \(width)x\(height), cam=(\(camXFactor),\(camYFactor),\(camZFactor))rs, fov=\(fovDeg), roll=\(rollDeg), rcp=\(rcp), diskH=\(diskHFactor)rs, maxSteps=\(maxStepsArg), metric=\(metricName), spin=\(spinArg), kerrSubsteps=\(kerrSubstepsArg), kerrTol=\(kerrTolArg), kerrEscape=\(kerrEscapeMultArg), kerrScale=(\(kerrRadialScaleArg),\(kerrAzimuthScaleArg),\(kerrImpactScaleArg)), diskModel=\(diskModelResolved), diskFlow=(t=\(diskFlowTimeArg),omega=\(diskOrbitalBoostArg),vr=\(diskRadialDriftArg),turb=\(diskTurbulenceArg),omegaIn=\(diskOrbitalBoostInnerArg),omegaOut=\(diskOrbitalBoostOuterArg),vrIn=\(diskRadialDriftInnerArg),vrOut=\(diskRadialDriftOuterArg),turbIn=\(diskTurbulenceInnerArg),turbOut=\(diskTurbulenceOuterArg),dt=\(diskFlowStepArg),steps=\(diskFlowStepsArg)), diskPhysics=(mode=\(diskPhysicsModeArg),mdotEdd=\(diskMdotEddArg),eta=\(diskRadiativeEfficiencyArg),plunge=\(diskPlungeFloorArg),thickScale=\(diskThickScaleArg),fcol=\(diskColorFactorArg),ret=\(diskReturningRadArg),retBounces=\(diskReturnBouncesArg),rtSteps=\(diskRTStepsArg),albedo=\(diskScatteringAlbedoArg),texture=\(diskPrecisionTextureArg),precisionClouds=\(diskPrecisionCloudsEnabled),cloudCoverage=\(diskCloudCoverageArg),cloudTau=\(diskCloudOpticalDepthArg),cloudPorosity=\(diskCloudPorosityArg),cloudShadow=\(diskCloudShadowStrengthArg)), diskAtlas=(enabled=\(diskAtlasEnabled),size=\(diskAtlasWidth)x\(diskAtlasHeight),temp=\(diskAtlasTempScaleArg),density=\(diskAtlasDensityBlendArg),vr=\(diskAtlasVrScaleArg),vphi=\(diskAtlasVphiScaleArg),rMin=\(diskAtlasRMin),rMax=\(diskAtlasRMax),rWarp=\(diskAtlasRWarp)), diskVolume=(enabled=\(diskVolumeEnabled),size=\(diskVolumeR)x\(diskVolumePhi)x\(diskVolumeZ),rMin=\(diskVolumeRMin),rMax=\(diskVolumeRMax),zMax=\(diskVolumeZMax),tauScale=\(diskVolumeTauScaleArg)), rayBundle=(requested=\(rayBundleEnabled),active=\(rayBundleActive),jacobian=\(rayBundleJacobianActive),jacStrength=\(rayBundleJacobianStrengthArg),clamp=\(rayBundleFootprintClampArg)), cameraModel=(name=\(cameraModelName),psf=\(cameraPsfSigmaArg),readNoise=\(cameraReadNoiseArg),shotNoise=\(cameraShotNoiseArg),flare=\(cameraFlareStrengthArg)), background=(mode=\(backgroundModeName),density=\(backgroundStarDensityArg),strength=\(backgroundStarStrengthArg),nebula=\(backgroundNebulaStrengthArg)), tileSize=\(tileSize), composeGPU=\(composeGPU), downsample=\(downsampleArg), linear32Intermediate=\(useLinear32Intermediate), analysisMode=\(composeAnalysisMode)"
    )
    if diskPhysicsModeID == 3 {
        print(
            "grmhd config vol0=\(diskVol0PathResolved.isEmpty ? "none" : diskVol0PathResolved), vol1=\(diskVol1PathResolved.isEmpty ? "none" : diskVol1PathResolved), nuObsHz=\(diskNuObsHzArg), rhoScale=\(diskGrmhdDensityScaleArg), bScale=\(diskGrmhdBScaleArg), jScale=\(diskGrmhdEmissionScaleArg), alphaScale=\(diskGrmhdAbsorptionScaleArg), velScale=\(diskGrmhdVelScaleArg), polarized=\(diskPolarizedRTEnabled), polFrac=\(diskPolarizationFracArg), faradayRot=\(diskFaradayRotScaleArg), faradayConv=\(diskFaradayConvScaleArg), debug=\(diskGrmhdDebugName)"
        )
        print(
            "visible config enabled=\(visibleModeEnabled), samples=\(visibleSamplesArg), teffModel=\(visibleTeffModelName), teff=(T0=\(visibleTeffT0Arg),r0Rs=\(visibleTeffR0RsArg),p=\(visibleTeffPArg)), thinDisk=(M=\(visibleBhMassArg),mdot=\(visibleMdotArg),rInRs=\(visibleRInRsArg)), photosphereRho=\(photosphereRhoThresholdResolved), emissionModel=\(visibleEmissionModelName), synchAlpha=\(visibleSynchAlphaArg), visibleKappa=\(visibleKappaArg), coolAbsorption=(enabled=\(coolAbsorptionEnabled),dustToGas=\(coolDustToGasArg),dustKappaV=\(coolDustKappaVArg),dustBeta=\(coolDustBetaArg),dustTsub=\(coolDustTSubArg),dustTwidth=\(coolDustTWidthArg),gasKappa0=\(coolGasKappa0Arg),gasNuSlope=\(coolGasNuSlopeArg),clump=\(coolClumpStrengthArg)), exposureMode=\(exposureModeName), exposureEV=\(exposureEVArg), rayBundle=(requested=\(rayBundleEnabled),active=\(rayBundleActive),jacobian=\(rayBundleJacobianActive),jacStrength=\(rayBundleJacobianStrengthArg),clamp=\(rayBundleFootprintClampArg))"
        )
    }

    let c: Double = 299_792_458
    let G: Double = 6.67430e-11
    let k: Double = 1.380649e-23
    let M: Double = 1e35

    let rsD = 2.0 * G * M / (c * c)
    let reD = rsD * rcp
    let heD = rsD * diskHFactor
    let visibleTeffR0Meters = visibleTeffR0RsArg * rsD
    let visibleRInMeters = visibleRInRsArg * rsD
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

var params = PackedParams(
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
        diskRTPad: 0,
        diskVolumeMode: diskVolumeEnabled ? 1 : 0,
        diskVolumeR: UInt32(diskVolumeR),
        diskVolumePhi: UInt32(diskVolumePhi),
        diskVolumeZ: UInt32(diskVolumeZ),
        diskVolumeRNormMin: Float(diskVolumeRMin),
        diskVolumeRNormMax: Float(diskVolumeRMax),
        diskVolumeZNormMax: Float(diskVolumeZMax),
        diskVolumeTauScale: Float(diskVolumeTauScaleArg),
        diskVolumeFormat: diskVolumeFormatArg,
        diskVolumeR0: UInt32(diskVolumeR),
        diskVolumePhi0: UInt32(diskVolumePhi),
        diskVolumeZ0: UInt32(diskVolumeZ),
        diskVolumeR1: UInt32(diskVolumeR),
        diskVolumePhi1: UInt32(diskVolumePhi),
        diskVolumeZ1: UInt32(diskVolumeZ),
        diskNuObsHz: Float(diskNuObsHzArg),
        diskGrmhdDensityScale: Float(diskGrmhdDensityScaleArg),
        diskGrmhdBScale: Float(diskGrmhdBScaleArg),
        diskGrmhdEmissionScale: Float(diskGrmhdEmissionScaleArg),
        diskGrmhdAbsorptionScale: Float(diskGrmhdAbsorptionScaleArg),
        diskGrmhdVelScale: Float(diskGrmhdVelScaleArg),
        diskGrmhdDebugView: diskGrmhdDebugID,
        diskPolarizedRT: (diskPhysicsModeID == 3 && diskPolarizedRTEnabled) ? 1 : 0,
        diskPolarizationFrac: Float(diskPolarizationFracArg),
        diskFaradayRotScale: Float(diskFaradayRotScaleArg),
        diskFaradayConvScale: Float(diskFaradayConvScaleArg),
        visibleMode: (diskPhysicsModeID == 3 && visibleModeEnabled) ? 1 : 0,
        visibleSamples: UInt32(visibleSamplesArg),
        visibleTeffModel: visibleTeffModelID,
        visiblePad0: 0,
        visibleTeffT0: Float(visibleTeffT0Arg),
        visibleTeffR0: Float(visibleTeffR0Meters),
        visibleTeffP: Float(visibleTeffPArg),
        visiblePhotosphereRhoThreshold: Float(photosphereRhoThresholdResolved),
        visibleBhMass: Float(visibleBhMassArg),
        visibleMdot: Float(visibleMdotArg),
        visibleRIn: Float(visibleRInMeters),
        visibleKappa: Float(visibleKappaArg),
        visibleEmissionModel: visibleEmissionModelID,
        visibleEmissionAlpha: Float(visibleSynchAlphaArg),
        rayBundleSSAA: rayBundleActive ? 1 : 0,
        rayBundleJacobian: rayBundleJacobianActive ? 1 : 0,
        rayBundleJacobianStrength: Float(rayBundleJacobianStrengthArg),
        rayBundleFootprintClamp: Float(rayBundleFootprintClampArg),
        coolAbsorptionMode: (diskPhysicsModeID == 3 && visibleModeEnabled && coolAbsorptionEnabled) ? 1 : 0,
        coolDustToGas: Float(coolDustToGasArg),
        coolDustKappaV: Float(coolDustKappaVArg),
        coolDustBeta: Float(coolDustBetaArg),
        coolDustTSub: Float(coolDustTSubArg),
        coolDustTWidth: Float(coolDustTWidthArg),
        coolGasKappa0: Float(coolGasKappa0Arg),
        coolGasNuSlope: Float(coolGasNuSlopeArg),
    coolClumpStrength: Float(coolClumpStrengthArg),
    coolAbsorptionPad: 0
)
if !dumpPackedParamsPath.isEmpty {
    try dumpPackedParams(&params, to: dumpPackedParamsPath)
    print("dumped packed params to: \(dumpPackedParamsPath)")
}

    let count = width * height
    let stride = MemoryLayout<CollisionInfo>.stride
    let useInMemoryCollisions = composeGPU && gpuFullCompose
    let collisionLite32Enabled =
        useLinear32Intermediate &&
        !useInMemoryCollisions &&
        !rayBundleActive &&
        diskPhysicsModeID <= 1 &&
        !visibleModeEnabled &&
        composeAnalysisMode == 0 &&
        diskGrmhdDebugID == 0
    let traceStride = collisionLite32Enabled ? MemoryLayout<CollisionLite32>.stride : stride
    let outSize = count * stride
    let url = URL(fileURLWithPath: outPath)
    let linearStride = MemoryLayout<SIMD4<Float>>.stride
    let linearOutSize = count * linearStride
    let linearURL = URL(fileURLWithPath: linear32OutPath)
    if discardCollisionOutput && !(useInMemoryCollisions || useLinear32Intermediate) {
        fail("--discard-collisions is only supported with --gpu-full-compose or --linear32-intermediate")
    }
    let collisionBuffer: MTLBuffer? = useInMemoryCollisions ? device.makeBuffer(length: outSize, options: .storageModeShared) : nil
    if useInMemoryCollisions, collisionBuffer == nil {
        fail("failed to allocate in-memory collision buffer (\(outSize) bytes)")
    }
    let collisionBase = collisionBuffer?.contents()
    if collisionLite32Enabled {
        print("collision layout=lite32 (2xfloat4) for linear32 trace tiles")
    }
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
    let maxTraceTilePixels = effectiveTile * effectiveTile
    let traceTilesX = max(1, (width + effectiveTile - 1) / effectiveTile)
    let traceTilesY = max(1, (height + effectiveTile - 1) / effectiveTile)
    let traceTileTotal = max(1, traceTilesX * traceTilesY)

    let diskAtlasTex = makeFloat4Texture2D(
        device: device,
        width: Int(max(params.diskAtlasWidth, 1)),
        height: Int(max(params.diskAtlasHeight, 1)),
        data: diskAtlasData,
        label: "diskAtlas"
    )
    let diskVol0Tex = makeFloat4Texture3D(
        device: device,
        width: Int(max(params.diskVolumeR0, 1)),
        height: Int(max(params.diskVolumePhi0, 1)),
        depth: Int(max(params.diskVolumeZ0, 1)),
        data: diskVolume0Data,
        label: "diskVol0"
    )
    let diskVol1Tex = makeFloat4Texture3D(
        device: device,
        width: Int(max(params.diskVolumeR1, 1)),
        height: Int(max(params.diskVolumePhi1, 1)),
        depth: Int(max(params.diskVolumeZ1, 1)),
        data: diskVolume1Data,
        label: "diskVol1"
    )

    let traceKernelBase: String
    if collisionLite32Enabled {
        traceKernelBase = "renderBHClassicLite"
    } else {
        traceKernelBase = rayBundleActive ? "renderBHBundle" : "renderBHClassic"
    }
    let traceKernelName = useInMemoryCollisions ? "\(traceKernelBase)Global" : traceKernelBase
    let composeLinearTileKernelName = collisionLite32Enabled ? "composeLinearRGBTileLite" : "composeLinearRGBTile"
    let pipelines = try MetalPipelines.makeRenderPipelines(
        device: device,
        library: library,
        traceKernelName: traceKernelName,
        composeLinearTileKernelName: composeLinearTileKernelName,
        metric: Int32(metricArg),
        physicsMode: UInt32(diskPhysicsModeID),
        visibleMode: UInt32((diskPhysicsModeID == 3 && visibleModeEnabled) ? 1 : 0),
        traceDebugOff: UInt32(diskGrmhdDebugID == 0 ? 1 : 0)
    )
    let tracePipeline = pipelines.tracePipeline
    let composePipeline = pipelines.composePipeline
    let composeLinearPipeline = pipelines.composeLinearPipeline
    let composeLinearTilePipeline = pipelines.composeLinearTilePipeline
    let composeBHLinearPipeline = pipelines.composeBHLinearPipeline
    let composeBHLinearTilePipeline = pipelines.composeBHLinearTilePipeline
    let cloudHistPipeline = pipelines.cloudHistPipeline
    let lumHistPipeline = pipelines.lumHistPipeline
    let lumHistLinearPipeline = pipelines.lumHistLinearPipeline
    let lumHistLinearTileCloudPipeline = pipelines.lumHistLinearTileCloudPipeline

    struct InFlightSlot {
        let traceParamBuf: MTLBuffer
        let traceTileBuf: MTLBuffer?
        let linearParamBuf: MTLBuffer?
        let linearTileBuf: MTLBuffer?
    }

    let slotTraceParamBytes = MemoryLayout<PackedParams>.stride
    let slotTraceTileBytes = maxTraceTilePixels * traceStride
    let slotLinearParamBytes = useLinear32Intermediate ? MemoryLayout<ComposeParams>.stride : 0
    let slotLinearTileBytes = useLinear32Intermediate ? (maxTraceTilePixels * linearStride) : 0
    let slotBytes = slotTraceParamBytes
        + ((useInMemoryCollisions && !useLinear32Intermediate) ? 0 : slotTraceTileBytes)
        + slotLinearParamBytes
        + slotLinearTileBytes
    let workingSetCap = Int(min(device.recommendedMaxWorkingSetSize, UInt64(Int.max)))
    let inFlightBudget = max(64 * 1024 * 1024, min(workingSetCap / 8, 768 * 1024 * 1024))
    var maxInFlight = 2
    if slotBytes > 0 && slotBytes * 3 <= inFlightBudget {
        maxInFlight = 3
    }
    if traceInFlightOverrideArg > 0 {
        maxInFlight = traceInFlightOverrideArg
    }
    maxInFlight = min(maxInFlight, traceTileTotal)
    maxInFlight = max(1, maxInFlight)
    print("trace in-flight=\(maxInFlight), slotBytes=\(slotBytes), tiles=\(traceTileTotal)")

    var traceSlots: [InFlightSlot] = []
    traceSlots.reserveCapacity(maxInFlight)
    for _ in 0..<maxInFlight {
        guard let traceParamBuf = device.makeBuffer(length: slotTraceParamBytes, options: .storageModeShared) else {
            fail("failed to allocate trace param buffer slot")
        }
        let needsTraceTile = !(useInMemoryCollisions && !useLinear32Intermediate)
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
            guard let lt = device.makeBuffer(length: maxTraceTilePixels * linearStride, options: .storageModeShared) else {
                fail("failed to allocate linear32 tile buffer slot")
            }
            linearParamBuf = lp
            linearTileBuf = lt
        } else {
            linearParamBuf = nil
            linearTileBuf = nil
        }
        traceSlots.append(InFlightSlot(traceParamBuf: traceParamBuf, traceTileBuf: traceTileBuf, linearParamBuf: linearParamBuf, linearTileBuf: linearTileBuf))
    }

    var composeParamsBase = params
    let composeBaseBufForLinear: MTLBuffer? = useLinear32Intermediate
        ? device.makeBuffer(bytes: &composeParamsBase, length: MemoryLayout<PackedParams>.stride, options: [])
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
    let composeLumLogMin: Float = (diskPhysicsModeID == 3) ? -36.0 : 8.0
    let composeLumLogMax: Float = (diskPhysicsModeID == 3) ? 4.0 : 20.0
    let linearLumLogMin: Float = composeLumLogMin
    let linearLumLogMax: Float = composeLumLogMax

    var hitCount = 0
    var donePixels = 0
    let totalPixels = count
    let outWidth = width / downsampleArg
    let outHeight = height / downsampleArg
    let composePrepassOpsTarget: Int
    if composeGPU && gpuFullCompose && autoExposureEnabled {
        composePrepassOpsTarget = 3 * count
    } else if composeGPU && useLinear32Intermediate && autoExposureEnabled {
        composePrepassOpsTarget = count
    } else {
        composePrepassOpsTarget = 0
    }
    let composeOps = composeGPU ? (composePrepassOpsTarget + outWidth * outHeight) : 0
    let totalOps = totalPixels + composeOps
    let progressStep = max(1, totalOps / 256)
    var nextProgressMark = progressStep
    var lastProgressPrint = Date().timeIntervalSince1970
    var traceTileIndex = 0
    emitETAProgress(0, totalOps, "swift_trace", "task=trace tile=0/\(traceTileTotal)")
    let inFlightSemaphore = DispatchSemaphore(value: maxInFlight)
    let traceDispatchGroup = DispatchGroup()
    let ioQueue = DispatchQueue(label: "blackhole.trace.io")
    var traceIOError: Error? = nil
    let traceIOErrorLock = NSLock()
    func traceGetError() -> Error? {
        traceIOErrorLock.lock()
        defer { traceIOErrorLock.unlock() }
        return traceIOError
    }
    func traceSetErrorIfNil(_ error: Error) {
        traceIOErrorLock.lock()
        if traceIOError == nil {
            traceIOError = error
        }
        traceIOErrorLock.unlock()
    }
    var traceDispatchIndex = 0
    var ty = 0
    while ty < height {
        let tileH = min(effectiveTile, height - ty)
        var tx = 0
        while tx < width {
            let tileW = min(effectiveTile, width - tx)
            let tileCount = tileW * tileH
            let tileOriginX = tx
            let tileOriginY = ty
            let tileOrdinal = traceTileIndex + 1
            traceTileIndex += 1

            inFlightSemaphore.wait()
            if let e = traceGetError() {
                inFlightSemaphore.signal()
                throw e
            }
            let slot = traceSlots[traceDispatchIndex % maxInFlight]
            traceDispatchIndex += 1

            var tileParams = params
            tileParams.width = UInt32(tileW)
            tileParams.height = UInt32(tileH)
            tileParams.fullWidth = UInt32(width)
            tileParams.fullHeight = UInt32(height)
            tileParams.offsetX = UInt32(tileOriginX)
            tileParams.offsetY = UInt32(tileOriginY)
            updateBuffer(slot.traceParamBuf, with: &tileParams)

            if useLinear32Intermediate {
                guard let linearParamBuf = slot.linearParamBuf else {
                    fail("linear32 slot param buffer missing")
                }
                var linearTileParams = ComposeParams(
                    tileWidth: UInt32(tileW),
                    tileHeight: UInt32(tileH),
                    downsample: 1,
                    outTileWidth: 0,
                    outTileHeight: 0,
                    srcOffsetX: UInt32(tileOriginX),
                    srcOffsetY: UInt32(tileOriginY),
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
                    lumLogMax: linearLumLogMax,
                    cameraModel: composeCameraModelID,
                    cameraPsfSigmaPx: composeCameraPsfSigmaArg,
                    cameraReadNoise: composeCameraReadNoiseArg,
                    cameraShotNoise: composeCameraShotNoiseArg,
                    cameraFlareStrength: composeCameraFlareStrengthArg,
                    backgroundMode: backgroundModeID,
                    backgroundStarDensity: backgroundStarDensityArg,
                    backgroundStarStrength: backgroundStarStrengthArg,
                    backgroundNebulaStrength: backgroundNebulaStrengthArg,
                    preserveHighlightColor: preserveHighlightColor
                )
                updateBuffer(linearParamBuf, with: &linearTileParams)
            }

            traceDispatchGroup.enter()
            let cmd = queue.makeCommandBuffer()!
            let enc = cmd.makeComputeCommandEncoder()!
            enc.setComputePipelineState(tracePipeline)
            enc.setBuffer(slot.traceParamBuf, offset: 0, index: 0)
            if useInMemoryCollisions {
                guard let collisionBuffer else {
                    fail("in-memory collision buffer missing for global trace path")
                }
                enc.setBuffer(collisionBuffer, offset: 0, index: 1)
            } else {
                guard let traceTileBuf = slot.traceTileBuf else {
                    fail("trace tile buffer missing for local trace path")
                }
                enc.setBuffer(traceTileBuf, offset: 0, index: 1)
            }
            enc.setTexture(diskAtlasTex, index: 0)
            enc.setTexture(diskVol0Tex, index: 1)
            enc.setTexture(diskVol1Tex, index: 2)
            enc.dispatchThreads(MTLSize(width: tileW, height: tileH, depth: 1), threadsPerThreadgroup: tg)
            enc.endEncoding()

            if useLinear32Intermediate {
                guard let composeBaseBufForLinear,
                      let linearParamBuf = slot.linearParamBuf,
                      let traceTileBuf = slot.traceTileBuf,
                      let linearTileBuf = slot.linearTileBuf else {
                    fail("linear32 slot buffers are not available")
                }
                let linearEnc = cmd.makeComputeCommandEncoder()!
                linearEnc.setComputePipelineState(composeLinearTilePipeline)
                linearEnc.setBuffer(composeBaseBufForLinear, offset: 0, index: 0)
                linearEnc.setBuffer(linearParamBuf, offset: 0, index: 1)
                linearEnc.setBuffer(traceTileBuf, offset: 0, index: 2)
                linearEnc.setBuffer(linearTileBuf, offset: 0, index: 3)
                linearEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgLinearTile1D)
                linearEnc.endEncoding()
            }

            cmd.addCompletedHandler { cmdBuf in
                ioQueue.async {
                    defer {
                        inFlightSemaphore.signal()
                        traceDispatchGroup.leave()
                    }
                    if traceGetError() != nil { return }
                    if cmdBuf.status != .completed {
                        traceSetErrorIfNil(cmdBuf.error ?? NSError(domain: "Blackhole", code: 70, userInfo: [NSLocalizedDescriptionKey: "trace command buffer failed"]))
                        return
                    }
                    do {
                        if useInMemoryCollisions {
                            if let collisionBase {
                                let fullPtr = collisionBase.bindMemory(to: CollisionInfo.self, capacity: count)
                                var localHits = 0
                                for row in 0..<tileH {
                                    let rowBase = (tileOriginY + row) * width + tileOriginX
                                    for col in 0..<tileW {
                                        if fullPtr[rowBase + col].hit != 0 { localHits += 1 }
                                    }
                                }
                                hitCount += localHits
                            }
                        } else if let traceTileBuf = slot.traceTileBuf {
                            var localHits = 0
                            if collisionLite32Enabled {
                                let ptr = traceTileBuf.contents().bindMemory(to: CollisionLite32.self, capacity: tileCount)
                                for i in 0..<tileCount where ptr[i].noise_dirOct_hit.w > 0.5 { localHits += 1 }
                            } else {
                                let ptr = traceTileBuf.contents().bindMemory(to: CollisionInfo.self, capacity: tileCount)
                                for i in 0..<tileCount where ptr[i].hit != 0 { localHits += 1 }
                            }
                            hitCount += localHits
                        }

                        if useLinear32Intermediate {
                            guard let linearOutHandle, let linearTileBuf = slot.linearTileBuf else {
                                throw NSError(domain: "Blackhole", code: 71, userInfo: [NSLocalizedDescriptionKey: "linear32 output buffers missing"])
                            }
                            let linearPtr = linearTileBuf.contents().bindMemory(to: SIMD4<Float>.self, capacity: tileCount)
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
                                let src = linearTileBuf.contents().advanced(by: row * rowBytes)
                                let dstOffset = ((tileOriginY + row) * width + tileOriginX) * linearStride
                                try linearOutHandle.seek(toOffset: UInt64(dstOffset))
                                try linearOutHandle.write(contentsOf: Data(bytes: src, count: rowBytes))
                            }
                        } else if !useInMemoryCollisions {
                            if let traceTileBuf = slot.traceTileBuf {
                                for row in 0..<tileH {
                                    let rowBytes = tileW * traceStride
                                    let src = traceTileBuf.contents().advanced(by: row * rowBytes)
                                    let dstOffset = ((tileOriginY + row) * width + tileOriginX) * traceStride
                                    if let outHandle {
                                        try outHandle.seek(toOffset: UInt64(dstOffset))
                                        try outHandle.write(contentsOf: Data(bytes: src, count: rowBytes))
                                    } else if discardCollisionOutput {
                                        // intentionally skip collision writes when output is marked disposable
                                    } else {
                                        throw NSError(domain: "Blackhole", code: 72, userInfo: [NSLocalizedDescriptionKey: "no collision output sink available"])
                                    }
                                }
                            }
                        }
                    } catch {
                        traceSetErrorIfNil(error)
                        return
                    }

                    donePixels += tileCount
                    let now = Date().timeIntervalSince1970
                    if donePixels >= totalPixels || donePixels >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                        emitETAProgress(donePixels, totalOps, "swift_trace", "task=trace tile=\(tileOrdinal)/\(traceTileTotal)")
                        lastProgressPrint = now
                        while nextProgressMark <= donePixels {
                            nextProgressMark += progressStep
                        }
                    }
                }
            }
            cmd.commit()
            tx += tileW
        }
        ty += tileH
    }

    traceDispatchGroup.wait()
    if let e = traceGetError() {
        throw e
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

            if autoExposureEnabled {
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
                        lumLogMax: linearLumLogMax,
                        cameraModel: composeCameraModelID,
                        cameraPsfSigmaPx: composeCameraPsfSigmaArg,
                        cameraReadNoise: composeCameraReadNoiseArg,
                        cameraShotNoise: composeCameraShotNoiseArg,
                        cameraFlareStrength: composeCameraFlareStrengthArg,
                        backgroundMode: backgroundModeID,
                        backgroundStarDensity: backgroundStarDensityArg,
                        backgroundStarStrength: backgroundStarStrengthArg,
                        backgroundNebulaStrength: backgroundNebulaStrengthArg,
                        preserveHighlightColor: preserveHighlightColor
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
                    let targetWhite: Float = composeTargetWhite(composeLookID)
                    let pFloor: Float = (diskPhysicsModeID == 3) ? 1e-30 : 1e-12
                    composeExposure = targetWhite / max(Float(p995), pFloor)
                    print("lum(linear32) p50=\(p50), p99.5=\(p995), samples=\(lumSampleCount)")
                }
            }
        }

        composeParamsBase = params
        if gpuFullCompose {
            guard let collisionBuffer else {
                fail("gpu-full-compose requires in-memory collision buffer")
            }
            let cloudBins = 8192
            let lumBins = 4096
            let lumLogMin: Float = composeLumLogMin
            let lumLogMax: Float = composeLumLogMax
            let cloudHistBytes = cloudBins * MemoryLayout<UInt32>.stride
            let lumHistBytes = lumBins * MemoryLayout<UInt32>.stride
            let tgCloud1D = MTLSize(width: max(1, min(256, cloudHistPipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)
            let tgLinear1D = MTLSize(width: max(1, min(256, composeLinearPipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)
            let tgLum1D = MTLSize(width: max(1, min(256, lumHistLinearPipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)

            var globalCloudQ10: Float = 0.0
            var globalCloudQ90: Float = 1.0
            var globalCloudInvSpan = 1.0 / max(globalCloudQ90 - globalCloudQ10, 1e-6)
            let composeBaseBuf = device.makeBuffer(bytes: &composeParamsBase, length: MemoryLayout<PackedParams>.stride, options: [])!
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
                lumLogMax: lumLogMax,
                cameraModel: composeCameraModelID,
                cameraPsfSigmaPx: composeCameraPsfSigmaArg,
                cameraReadNoise: composeCameraReadNoiseArg,
                cameraShotNoise: composeCameraShotNoiseArg,
                cameraFlareStrength: composeCameraFlareStrengthArg,
                backgroundMode: backgroundModeID,
                backgroundStarDensity: backgroundStarDensityArg,
                backgroundStarStrength: backgroundStarStrengthArg,
                backgroundNebulaStrength: backgroundNebulaStrengthArg,
                preserveHighlightColor: preserveHighlightColor
            )

            let rawComposeRows = max(1, composeChunkArg / max(width, 1))
            var composeRows = max(downsampleArg, (rawComposeRows / downsampleArg) * downsampleArg)
            if composeRows <= 0 { composeRows = downsampleArg }
            if composeRows > height { composeRows = height }
            let composeTileTotal = max(1, (height + composeRows - 1) / composeRows)
            let maxComposeOutTileCount = (width / downsampleArg) * (composeRows / downsampleArg)
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
            let composeLinearFullBuf: MTLBuffer? = autoExposureEnabled
                ? device.makeBuffer(length: count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)
                : nil
            if autoExposureEnabled, composeLinearFullBuf == nil {
                fail("failed to allocate full-frame linear RGB buffer")
            }

            if autoExposureEnabled {
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
                    let srcOffsetBytes = pty * width * stride

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
                    cloudEnc.setBuffer(collisionBuffer, offset: srcOffsetBytes, index: 2)
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
                    let srcOffsetBytes = pty * width * stride

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
                    linearEnc.setBuffer(collisionBuffer, offset: srcOffsetBytes, index: 2)
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
                    var targetWhite: Float = composeTargetWhite(composeLookID)
                    if diskVolumeEnabled && diskPhysicsModeID != 3 { targetWhite *= 2.2 }
                    let pFloor: Float = (diskPhysicsModeID == 3) ? 1e-30 : 1e-12
                    composeExposure = targetWhite / max(Float(p995), pFloor)
                    print("lum(hist) p50=\(p50), p99.5=\(p995), samples=\(lumSampleCount)")
                }
            }

            composeParamsTemplate.exposure = composeExposure
            composeParamsTemplate.cloudQ10 = globalCloudQ10
            composeParamsTemplate.cloudInvSpan = globalCloudInvSpan
            print("compose cloud normalization q10=\(globalCloudQ10) q90=\(globalCloudQ90)")
            print("exposure=\(composeExposure) (auto=\(autoExposureEnabled), gpuFullCompose=true)")

            var rgb = [UInt8](repeating: 0, count: outWidth * outHeight * 3)
            let composePixelOps = outWidth * outHeight

            var composed = 0
            var cty = 0
            var composeTileIndex = 0
            if autoExposureEnabled {
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
                    let srcOffsetBytes = cty * width * stride

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
                    enc.setBuffer(collisionBuffer, offset: srcOffsetBytes, index: 2)
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
                let pyConverter = FileManager.default.currentDirectoryPath + "/Blackhole/scripts/ppm_to_png.py"
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
        print("exposure=\(composeExposure) (auto=\(autoExposureEnabled), linear32=true)")

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
            lumLogMax: linearLumLogMax,
            cameraModel: composeCameraModelID,
            cameraPsfSigmaPx: composeCameraPsfSigmaArg,
            cameraReadNoise: composeCameraReadNoiseArg,
            cameraShotNoise: composeCameraShotNoiseArg,
            cameraFlareStrength: composeCameraFlareStrengthArg,
            backgroundMode: backgroundModeID,
            backgroundStarDensity: backgroundStarDensityArg,
            backgroundStarStrength: backgroundStarStrengthArg,
            backgroundNebulaStrength: backgroundNebulaStrengthArg,
            preserveHighlightColor: preserveHighlightColor
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
            let pyConverter = FileManager.default.currentDirectoryPath + "/Blackhole/scripts/ppm_to_png.py"
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
        let emitROffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.emit_r_norm) ?? 52
        let emitPhiOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.emit_phi) ?? 56
        let emitZOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.emit_z_norm) ?? 60
        let cloudQ10: Float = 0.0
        let cloudQ90: Float = 1.0
        let cloudInvSpan = 1.0 / max(cloudQ90 - cloudQ10, 1e-6)
        var cpuP995ForCompose: Float = 0.0
        var sampledHits = 0

        if autoExposureEnabled {
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
            let camX = Double(params.camPos.x)
            let camY = Double(params.camPos.y)
            let camZ = Double(params.camPos.z)
            let rObs = max(sqrt(camX * camX + camY * camY + camZ * camZ), rs * 1.0001)
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
                var chunkI: [Double] = []
                var chunkEmitR: [Double] = []
                var chunkEmitPhi: [Double] = []
                var chunkEmitZ: [Double] = []
                chunkT.reserveCapacity(min(recCount, 8192))
                chunkV.reserveCapacity(min(recCount, 8192))
                chunkD.reserveCapacity(min(recCount, 8192))
                chunkN.reserveCapacity(min(recCount, 8192))
                chunkI.reserveCapacity(min(recCount, 8192))
                chunkEmitR.reserveCapacity(min(recCount, 8192))
                chunkEmitPhi.reserveCapacity(min(recCount, 8192))
                chunkEmitZ.reserveCapacity(min(recCount, 8192))

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
                        var emitR: Float = 0
                        withUnsafeMutableBytes(of: &emitR) { dst in
                            dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + emitROffset), count: MemoryLayout<Float>.size))
                        }
                        var emitPhi: Float = 0
                        withUnsafeMutableBytes(of: &emitPhi) { dst in
                            dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + emitPhiOffset), count: MemoryLayout<Float>.size))
                        }
                        var emitZ: Float = 0
                        withUnsafeMutableBytes(of: &emitZ) { dst in
                            dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + emitZOffset), count: MemoryLayout<Float>.size))
                        }

                        chunkT.append(max(Double(t), 1.0))
                        chunkV.append(SIMD3<Double>(Double(v4.x), Double(v4.y), Double(v4.z)))
                        chunkD.append(SIMD3<Double>(Double(d4.x), Double(d4.y), Double(d4.z)))
                        chunkN.append(Double(n))
                        chunkI.append(max(Double(v4.w), 0.0))
                        chunkEmitR.append(Double(emitR))
                        chunkEmitPhi.append(Double(emitPhi))
                        chunkEmitZ.append(Double(emitZ))
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
                        if diskPhysicsModeID == 3 {
                            let rgb: SIMD3<Double>
                            if composeAnalysisMode >= 11 && composeAnalysisMode <= 14 {
                                var raw = 0.0
                                var lo = -30.0
                                var hi = 2.0
                                if composeAnalysisMode == 11 {
                                    raw = max(chunkEmitR[i], 0.0) // max_rho
                                    lo = -16.0
                                } else if composeAnalysisMode == 12 {
                                    raw = max(chunkEmitPhi[i], 0.0) // max_b2
                                    lo = -20.0
                                    hi = 4.0
                                } else if composeAnalysisMode == 13 {
                                    raw = max(chunkEmitZ[i], 0.0) // max_jnu
                                    lo = -40.0
                                    hi = -20.0
                                } else {
                                    raw = max(chunkN[i], 0.0) // max_inu
                                    lo = -40.0
                                    hi = -20.0
                                }
                                let lv = log10(max(raw, 1e-38))
                                let t = min(max((lv - lo) / max(hi - lo, 1e-9), 0.0), 1.0)
                                rgb = SIMD3<Double>(repeating: t)
                            } else if composeAnalysisMode == 15 {
                                let teff = max(chunkT[i], 1.0)
                                let lv = log10(teff)
                                let t = min(max((lv - 2.0) / max(7.0 - 2.0, 1e-9), 0.0), 1.0)
                                rgb = SIMD3<Double>(repeating: t)
                            } else if composeAnalysisMode == 16 {
                                let g = min(max(chunkV[i].x, 1e-6), 1e6)
                                let lv = log10(g)
                                let t = min(max((lv - (-2.0)) / max(2.0 - (-2.0), 1e-9), 0.0), 1.0)
                                rgb = SIMD3<Double>(repeating: t)
                            } else if visibleModeEnabled {
                                let g = min(max(chunkV[i].x, 1e-4), 1e4)
                                let tEmit = max(chunkT[i], 1.0)
                                let scalarI = max(chunkI[i], 0.0)
                                let fCol = (visibleTeffModelID == 2) ? max(diskColorFactorArg, 1.0) : 1.0
                                let tSpec = tEmit * fCol
                                let colorDilution = 1.0 / pow(fCol, 4.0)
                                let usePackedVisibleAnchors =
                                    (diskPhysicsModeID == 3 &&
                                     photosphereRhoThresholdResolved <= 0.0 &&
                                     chunkEmitR[i] > 0.0 &&
                                     chunkEmitPhi[i] > 0.0 &&
                                     chunkEmitZ[i] > 0.0)
                                let nLam = max(8, visibleSamplesArg)
                                let lamMin = 380.0
                                let lamMax = 780.0
                                let dLamNm = (lamMax - lamMin) / Double(max(nLam - 1, 1))
                                let dLamM = dLamNm * 1e-9
                                let g3 = g * g * g

                                var X = 0.0
                                var Y = 0.0
                                var Z = 0.0
                                var peakLamNm = lamMin
                                var peakIlam = 0.0

                                if usePackedVisibleAnchors {
                                    // GRMHD visible volumetric path already integrated three I_nu anchors
                                    // in Metal: {650nm, 550nm, 450nm}. Reconstruct a smooth spectrum here
                                    // instead of re-imposing a blackbody from T/g, which over-whitens output.
                                    let lamRnm = 650.0
                                    let lamGnm = 550.0
                                    let lamBnm = 450.0
                                    let lamRm = lamRnm * 1e-9
                                    let lamGm = lamGnm * 1e-9
                                    let lamBm = lamBnm * 1e-9

                                    let iNuR = max(chunkEmitR[i], 1e-38)
                                    let iNuG = max(chunkEmitPhi[i], 1e-38)
                                    let iNuB = max(chunkEmitZ[i], 1e-38)
                                    let iLamR = iNuR * cc / max(lamRm * lamRm, 1e-30)
                                    let iLamG = iNuG * cc / max(lamGm * lamGm, 1e-30)
                                    let iLamB = iNuB * cc / max(lamBm * lamBm, 1e-30)

                                    let xR = log(lamRnm)
                                    let xG = log(lamGnm)
                                    let xB = log(lamBnm)
                                    let yR = log(max(iLamR, 1e-38))
                                    let yG = log(max(iLamG, 1e-38))
                                    let yB = log(max(iLamB, 1e-38))
                                    let slopeBG = (yG - yB) / max(xG - xB, 1e-12)
                                    let slopeGR = (yR - yG) / max(xR - xG, 1e-12)

                                    for j in 0..<nLam {
                                        let lamNm = lamMin + dLamNm * Double(j)
                                        let xLam = log(max(lamNm, 1e-9))
                                        let logILam: Double
                                        if lamNm <= lamGnm {
                                            logILam = yB + slopeBG * (xLam - xB)
                                        } else {
                                            logILam = yG + slopeGR * (xLam - xG)
                                        }
                                        let iLamObs = exp(min(max(logILam, -90.0), 90.0))
                                        let (xb, yb, zb) = cieXYZBar(lamNm)
                                        X += iLamObs * xb * dLamM
                                        Y += iLamObs * yb * dLamM
                                        Z += iLamObs * zb * dLamM
                                        if iLamObs > peakIlam {
                                            peakIlam = iLamObs
                                            peakLamNm = lamNm
                                        }
                                    }

                                    // Keep flux consistency with scalar payload, but avoid massive re-scaling.
                                    let iNuRef = 0.30 * iNuR + 0.40 * iNuG + 0.30 * iNuB
                                    if scalarI > 1e-18 {
                                        let amp = min(max(scalarI / max(iNuRef, 1e-38), 0.1), 10.0)
                                        X *= amp
                                        Y *= amp
                                        Z *= amp
                                    }
                                } else {
                                    for j in 0..<nLam {
                                        let lamNm = lamMin + dLamNm * Double(j)
                                        let lamM = lamNm * 1e-9
                                        let nuObs = cc / max(lamM, 1e-30)
                                        let nuEm = nuObs / max(g, 1e-8)
                                        let iNuEm = visibleINuEmit(nuEm, tSpec, visibleEmissionModelID, visibleSynchAlphaArg)
                                        let iNuObs = g3 * iNuEm
                                        let iLamObs = iNuObs * cc / max(lamM * lamM, 1e-30) * colorDilution
                                        let (xb, yb, zb) = cieXYZBar(lamNm)
                                        X += iLamObs * xb * dLamM
                                        Y += iLamObs * yb * dLamM
                                        Z += iLamObs * zb * dLamM
                                        if iLamObs > peakIlam {
                                            peakIlam = iLamObs
                                            peakLamNm = lamNm
                                        }
                                    }

                                    if scalarI > 1e-18 {
                                        let nuObsRef = max(diskNuObsHzArg, 1e6)
                                        let nuEmRef = nuObsRef / max(g, 1e-8)
                                        let iNuPred = g3 * visibleINuEmit(nuEmRef, tSpec, visibleEmissionModelID, visibleSynchAlphaArg) * colorDilution
                                        let amp = min(max(scalarI / max(iNuPred, 1e-38), 0.0), 1e12)
                                        X *= amp
                                        Y *= amp
                                        Z *= amp
                                    }
                                }

                                if composeAnalysisMode == 17 {
                                    let lv = log10(max(Y, 1e-38))
                                    let t = min(max((lv - (-30.0)) / max(4.0 - (-30.0), 1e-9), 0.0), 1.0)
                                    rgb = SIMD3<Double>(repeating: t)
                                } else if composeAnalysisMode == 18 {
                                    let w = min(max((peakLamNm - 380.0) / (780.0 - 380.0), 0.0), 1.0)
                                    let r = min(max(1.5 - abs(4.0 * w - 3.0), 0.0), 1.0)
                                    let gch = min(max(1.5 - abs(4.0 * w - 2.0), 0.0), 1.0)
                                    let b = min(max(1.5 - abs(4.0 * w - 1.0), 0.0), 1.0)
                                    rgb = SIMD3<Double>(r, gch, b)
                                } else {
                                    var rgbLin = SIMD3<Double>(
                                        xyzRow0.x * X + xyzRow0.y * Y + xyzRow0.z * Z,
                                        xyzRow1.x * X + xyzRow1.y * Y + xyzRow1.z * Z,
                                        xyzRow2.x * X + xyzRow2.y * Y + xyzRow2.z * Z
                                    )
                                    rgbLin.x = max(rgbLin.x, 0.0)
                                    rgbLin.y = max(rgbLin.y, 0.0)
                                    rgbLin.z = max(rgbLin.z, 0.0)
                                    let d = chunkD[i]
                                    let mu = abs(d.z) / max(sqrt(d.x * d.x + d.y * d.y + d.z * d.z), 1e-30)
                                    let limb = 0.4 + 0.6 * min(max(mu, 0.0), 1.0)
                                    rgb = rgbLin * limb
                                }
                            } else {
                                let iNu = max(chunkI[i], 0.0)
                                rgb = SIMD3<Double>(repeating: iNu)
                            }
                            chunkLum.append(Float(rgb.x * luma.x + rgb.y * luma.y + rgb.z * luma.z))
                            continue
                        }

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
                            let delta = 1.0 / max(gamma * (1.0 - beta * cosTheta), 1e-9)
                            let rEmitLegacy = max(gg * ghM / max(vNorm * vNorm, 1e-30), rs * 1.0001)
                            let gravNum = min(max(1.0 - rs / rEmitLegacy, 1e-8), 1.0)
                            let gravDen = min(max(1.0 - rs / rObs, 1e-8), 1.0)
                            let gGr = sqrt(min(max(gravNum / gravDen, 1e-8), 4.0))
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
                var targetWhite: Float = composeTargetWhite(composeLookID)
                if diskVolumeEnabled && diskPhysicsModeID != 3 { targetWhite *= 2.2 }
                let pFloor: Float = (diskPhysicsModeID == 3) ? 1e-30 : 1e-12
                composeExposure = targetWhite / max(p995, pFloor)
                cpuP995ForCompose = p995
                print("lum p50=\(p50), p99.5=\(p995), exposureSamples=\(sampledHits)")
            }
        }
        print("compose cloud normalization q10=\(cloudQ10) q90=\(cloudQ90)")
        print("exposure=\(composeExposure) (auto=\(autoExposureEnabled))")

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
            lumLogMin: composeLumLogMin,
            lumLogMax: composeLumLogMax,
            cameraModel: composeCameraModelID,
            cameraPsfSigmaPx: composeCameraPsfSigmaArg,
            cameraReadNoise: composeCameraReadNoiseArg,
            cameraShotNoise: composeCameraShotNoiseArg,
            cameraFlareStrength: composeCameraFlareStrengthArg,
            backgroundMode: backgroundModeID,
            backgroundStarDensity: backgroundStarDensityArg,
            backgroundStarStrength: backgroundStarStrengthArg,
            backgroundNebulaStrength: backgroundNebulaStrengthArg,
            preserveHighlightColor: preserveHighlightColor
        )
        let composeBaseBuf = device.makeBuffer(bytes: &composeParamsBase, length: MemoryLayout<PackedParams>.stride, options: [])!

        let rawComposeRows = max(1, composeChunkArg / max(width, 1))
        var composeRows = max(downsampleArg, (rawComposeRows / downsampleArg) * downsampleArg)
        if composeRows <= 0 { composeRows = downsampleArg }
        if composeRows > height { composeRows = height }
        let composeTileTotal = max(1, (height + composeRows - 1) / composeRows)

        if cpuP995ForCompose > 0 && diskPhysicsModeID != 3 {
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
            let pyConverter = FileManager.default.currentDirectoryPath + "/Blackhole/scripts/ppm_to_png.py"
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
        diskModel: (diskPhysicsModeID == 3)
            ? "grmhd_scalar_rt_v1"
            : (diskVolumeEnabled ? "volume_rt_v1" : (diskAtlasEnabled ? "stage3_atlas_v1" : ((diskModelResolved == "perlin") ? "perlin_texture_v1" : ((diskModelResolved == "perlin-ec7") ? "perlin_texture_ec7_v1" : ((diskModelResolved == "perlin-classic") ? "perlin_texture_classic_v1" : "streamline_particles_v1"))))),
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
        diskVolumeEnabled: diskVolumeEnabled,
        diskVolumeFormat: (diskVolumeFormatArg == 1) ? "grmhd_dual_float4" : "legacy_float4",
        diskVolumePath: diskVolumeLegacyEnabled ? diskVolumePathArg : "",
        diskVol0Path: diskVol0PathResolved,
        diskVol1Path: diskVol1PathResolved,
        diskVolumeR: diskVolumeR,
        diskVolumePhi: diskVolumePhi,
        diskVolumeZ: diskVolumeZ,
        diskVolumeRNormMin: diskVolumeRMin,
        diskVolumeRNormMax: diskVolumeRMax,
        diskVolumeZNormMax: diskVolumeZMax,
        diskVolumeTauScale: diskVolumeTauScaleArg,
        diskNuObsHz: diskNuObsHzArg,
        diskGrmhdDensityScale: diskGrmhdDensityScaleArg,
        diskGrmhdBScale: diskGrmhdBScaleArg,
        diskGrmhdEmissionScale: diskGrmhdEmissionScaleArg,
        diskGrmhdAbsorptionScale: diskGrmhdAbsorptionScaleArg,
        diskGrmhdVelScale: diskGrmhdVelScaleArg,
        diskGrmhdDebug: diskGrmhdDebugName,
        visibleMode: visibleModeEnabled && diskPhysicsModeID == 3,
        visibleSamples: visibleSamplesArg,
        visibleTeffModel: visibleTeffModelName,
        visibleTeffT0: visibleTeffT0Arg,
        visibleTeffR0Rs: visibleTeffR0RsArg,
        visibleTeffP: visibleTeffPArg,
        visibleBhMass: visibleBhMassArg,
        visibleMdot: visibleMdotArg,
        visibleRInRs: visibleRInRsArg,
        visiblePhotosphereRhoThreshold: photosphereRhoThresholdResolved,
        visibleEmissionModel: visibleEmissionModelName,
        visibleSynchAlpha: visibleSynchAlphaArg,
        exposureMode: exposureModeName,
        exposureEV: exposureEVArg,
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
        cameraModel: cameraModelName,
        cameraPsfSigmaPx: Double(cameraPsfSigmaArg),
        cameraReadNoise: Double(cameraReadNoiseArg),
        cameraShotNoise: Double(cameraShotNoiseArg),
        cameraFlareStrength: Double(cameraFlareStrengthArg),
        backgroundMode: backgroundModeName,
        backgroundStarDensity: Double(backgroundStarDensityArg),
        backgroundStarStrength: Double(backgroundStarStrengthArg),
        backgroundNebulaStrength: Double(backgroundNebulaStrengthArg),
        collisionStride: traceStride
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
    }
}
