import Foundation
import Metal

struct BuiltParams {
    var rawArguments: [String]
    var runRegression: Bool
    var printPackedLayout: Bool
    var validatePackedABI: Bool
    var dumpPackedParamsPath: String
    var resolvedConfig: ResolvedRenderConfig?
    var packedParams: PackedParams?
}

enum ParamsBuilder {
    @inline(__always)
    static func build(from logical: LogicalParams) -> BuiltParams {
        if logical.runRegression || logical.printPackedLayout || logical.validatePackedABI {
            return BuiltParams(
                rawArguments: logical.rawArguments,
                runRegression: logical.runRegression,
                printPackedLayout: logical.printPackedLayout,
                validatePackedABI: logical.validatePackedABI,
                dumpPackedParamsPath: logical.dumpPackedParamsPath,
                resolvedConfig: nil,
                packedParams: nil
            )
        }

        setCLIArguments(logical.rawArguments)
    if cliArguments.contains("--kerr-use-u") {
        FileHandle.standardError.write(Data("error: --kerr-use-u has been removed after validation tests showed no practical gain.\n".utf8))
        exit(2)
    }
    if cliArguments.contains("--sample") {
        FileHandle.standardError.write(Data("error: --sample has been removed. Use --ssaa (1, 2, 4) in run_pipeline.sh.\n".utf8))
        exit(2)
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
    let rawOutputPath = stringArg("--output", default: "blackhole_gpu.png")
    let explicitImageOutPath = stringArg("--image-out", default: "")
    let outputLooksLikeCollision = rawOutputPath.lowercased().hasSuffix(".bin")
    let composeGPU = true
    let gpuFullCompose = true
    let debugCollisionOutput = flagArgAny(["--debug"])
    let discardCollisionOutput = !debugCollisionOutput
    let linear32Intermediate = false
    let linear32OutPath = stringArgAny(["--linear32-out", "--hdr-out"], default: rawOutputPath + ".linear32f32")
    let outPath: String = {
        if !explicitImageOutPath.isEmpty {
            return rawOutputPath
        }
        if outputLooksLikeCollision {
            return rawOutputPath
        }
        if let dot = rawOutputPath.lastIndex(of: ".") {
            return String(rawOutputPath[..<dot]) + ".collisions.bin"
        }
        return rawOutputPath + ".collisions.bin"
    }()
    let imageOutPath: String = {
        if !explicitImageOutPath.isEmpty {
            return explicitImageOutPath
        }
        if outputLooksLikeCollision {
            let trimmed = String(rawOutputPath.dropLast(4))
            return trimmed.isEmpty ? "blackhole_gpu.png" : trimmed + ".png"
        }
        return rawOutputPath
    }()
    if flagArgAny(["--compose-gpu", "--gpu-compose", "--gpu-full-compose", "--compose-in-memory", "--discard-collisions", "--skip-collision-dump", "--linear32-intermediate", "--hdr-intermediate", "--trace-hdr-direct"]) {
        FileHandle.standardError.write(Data("warn: compose/intermediate runtime flags are deprecated and ignored; GPU full-compose with automatic memory management is now the default.\n".utf8))
    }
    let traceHDRDirectMode = stringArgAny(["--trace-hdr-direct", "--trace-linear-hdr"], default: "auto").lowercased()
    if !["auto", "on", "off"].contains(traceHDRDirectMode) {
        fail("invalid --trace-hdr-direct \(traceHDRDirectMode). use auto|on|off")
    }
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
    var diskPhysicsModeID: UInt32 = diskModeParsed.id
    var diskPhysicsModeArg: String = diskModeParsed.canonical
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
    if diskModeUsesAutoAlias {
        FileHandle.standardError.write(
            Data("info: --disk-mode auto resolves to precision with diskH-adaptive thin/thick defaults\n".utf8)
        )
    }
    let diskPlungeFloorExplicit = cliArguments.contains("--disk-plunge-floor")
    let diskThickScaleExplicit = cliArguments.contains("--thick-scale") || cliArguments.contains("--disk-thick-scale")
    let diskColorFactorExplicit = cliArguments.contains("--fcol") || cliArguments.contains("--disk-color-factor")
    let diskReturningRadExplicit = cliArguments.contains("--disk-returning-rad")
    let diskPrecisionTextureExplicit = cliArguments.contains("--disk-precision-texture")
    let diskCloudCoverageExplicit = cliArguments.contains("--disk-cloud-coverage")
    let diskCloudOpticalDepthExplicit = cliArguments.contains("--cloud-tau") || cliArguments.contains("--disk-cloud-optical-depth")
    let diskCloudPorosityExplicit = cliArguments.contains("--disk-cloud-porosity")
    let diskCloudShadowStrengthExplicit = cliArguments.contains("--disk-cloud-shadow-strength")
    let diskReturnBouncesExplicit = cliArguments.contains("--disk-return-bounces")
    let diskRTStepsExplicit = cliArguments.contains("--rt-steps") || cliArguments.contains("--disk-rt-steps")
    let diskScatteringAlbedoExplicit = cliArguments.contains("--disk-scattering-albedo")
    let diskPlungeFloorRawArg = min(1.0, max(0.0, doubleArg("--disk-plunge-floor", default: 0.0)))
    let diskThickScaleRawArg = max(1.0, doubleArgAny(["--thick-scale", "--disk-thick-scale"], default: 1.0))
    let diskColorFactorRawArg = max(1.0, doubleArgAny(["--fcol", "--disk-color-factor"], default: 1.0))
    let precisionDefaultsEnabled = (diskPhysicsModeID == 2 && !diskPhysicsThinProfile)
    let diskReturningRadRawArg = max(0.0, min(1.0, doubleArg("--disk-returning-rad", default: 0.0)))
    let diskPrecisionTextureRawArg = max(0.0, min(1.0, doubleArg("--disk-precision-texture", default: 0.0)))
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
    let diskCloudCoverageRawArg = max(0.0, min(1.0, doubleArg("--disk-cloud-coverage", default: 0.0)))
    let diskCloudOpticalDepthRawArg = max(0.0, min(12.0, doubleArgAny(["--cloud-tau", "--disk-cloud-optical-depth"], default: 0.0)))
    let diskCloudPorosityRawArg = max(0.0, min(1.0, doubleArg("--disk-cloud-porosity", default: 0.0)))
    let diskCloudShadowStrengthRawArg = max(0.0, min(1.0, doubleArg("--disk-cloud-shadow-strength", default: 0.0)))
    let diskReturnBouncesRawArg = max(1, min(4, intArg("--disk-return-bounces", default: 1)))
    let diskRTStepsRawArg = max(0, min(32, intArgAny(["--rt-steps", "--disk-rt-steps"], default: 0)))
    let diskScatteringAlbedoRawArg = max(0.0, min(1.0, doubleArg("--disk-scattering-albedo", default: 0.0)))
    let diskPolicyInput = DiskPolicyInput(
        diskHFactor: diskHFactor,
        hasDiskVolumeArg: hasDiskVolumeArg,
        precisionThinProfile: diskPhysicsThinProfile,
        plungeFloorRawArg: diskPlungeFloorRawArg,
        plungeFloorExplicit: diskPlungeFloorExplicit,
        thickScaleRawArg: diskThickScaleRawArg,
        thickScaleExplicit: diskThickScaleExplicit,
        colorFactorRawArg: diskColorFactorRawArg,
        colorFactorExplicit: diskColorFactorExplicit,
        returningRadRawArg: diskReturningRadRawArg,
        returningRadExplicit: diskReturningRadExplicit,
        precisionTextureRawArg: diskPrecisionTextureRawArg,
        precisionTextureExplicit: diskPrecisionTextureExplicit,
        precisionCloudsEnabled: diskPrecisionCloudsEnabled,
        cloudCoverageRawArg: diskCloudCoverageRawArg,
        cloudCoverageExplicit: diskCloudCoverageExplicit,
        cloudOpticalDepthRawArg: diskCloudOpticalDepthRawArg,
        cloudOpticalDepthExplicit: diskCloudOpticalDepthExplicit,
        cloudPorosityRawArg: diskCloudPorosityRawArg,
        cloudPorosityExplicit: diskCloudPorosityExplicit,
        cloudShadowStrengthRawArg: diskCloudShadowStrengthRawArg,
        cloudShadowStrengthExplicit: diskCloudShadowStrengthExplicit,
        returnBouncesRawArg: diskReturnBouncesRawArg,
        returnBouncesExplicit: diskReturnBouncesExplicit,
        rtStepsRawArg: diskRTStepsRawArg,
        rtStepsExplicit: diskRTStepsExplicit,
        scatteringAlbedoRawArg: diskScatteringAlbedoRawArg,
        scatteringAlbedoExplicit: diskScatteringAlbedoExplicit
    )
    let accretionModel = AccretionModels.model(for: diskPhysicsModeID)
    let diskPolicy = accretionModel.applyDefaults(input: diskPolicyInput)
    try? accretionModel.validate(output: diskPolicy)
    for info in diskPolicy.infos {
        FileHandle.standardError.write(Data((info + "\n").utf8))
    }
    for warning in diskPolicy.warnings {
        FileHandle.standardError.write(Data((warning + "\n").utf8))
    }
    let diskPlungeFloorArg = diskPolicy.plungeFloor
    let diskThickScaleArg = diskPolicy.thickScale
    let diskColorFactorArg = diskPolicy.colorFactor
    let diskReturningRadArg = diskPolicy.returningRad
    var diskPrecisionTextureArg = diskPolicy.precisionTexture
    let thickCloudExplicit = diskPolicy.thickCloudExplicit
    let diskCloudCoverageArg = diskPolicy.cloudCoverage
    let diskCloudOpticalDepthArg = diskPolicy.cloudOpticalDepth
    let diskCloudPorosityArg = diskPolicy.cloudPorosity
    let diskCloudShadowStrengthArg = diskPolicy.cloudShadowStrength
    let diskReturnBouncesArg = diskPolicy.returnBounces
    let diskRTStepsArg = diskPolicy.rtSteps
    let diskScatteringAlbedoArg = diskPolicy.scatteringAlbedo
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
    let visiblePolicyName = stringArg("--visible-policy", default: "physical").lowercased()
    let visibleExpressiveMode: Bool
    switch visiblePolicyName {
    case "physical":
        visibleExpressiveMode = false
    case "expressive", "cinematic":
        visibleExpressiveMode = true
    default:
        fail("invalid --visible-policy \(visiblePolicyName). use one of: physical, expressive")
    }
    let visibleEmissionModelName = stringArg("--visible-emission-model", default: "blackbody").lowercased()
    var visibleEmissionModelID: UInt32
    switch visibleEmissionModelName {
    case "blackbody", "thermal":
        visibleEmissionModelID = 0
    case "synchrotron", "powerlaw", "power-law":
        visibleEmissionModelID = 1
    default:
        fail("invalid --visible-emission-model \(visibleEmissionModelName). use one of: blackbody, synchrotron")
    }
    var visibleSynchAlphaArg = min(max(doubleArg("--visible-synch-alpha", default: 0.85), 0.0), 4.0)
    if diskPhysicsModeID == 3 && visibleModeEnabled && visibleExpressiveMode {
        FileHandle.standardError.write(Data("info: --visible-policy expressive maps nu_obs emissivity to visible palette for readability\n".utf8))
        if !cliArguments.contains("--visible-emission-model") {
            visibleEmissionModelID = 1 // expressive: map nu_obs-driven intensity to visible palette.
        }
        if !cliArguments.contains("--visible-synch-alpha") {
            visibleSynchAlphaArg = 0.85
        }
    }
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
    let rayBundleJacobianRequestedByMode: Bool
    switch rayBundleName {
    case "on", "true", "1", "yes":
        rayBundleEnabled = true
        rayBundleJacobianRequestedByMode = false
    case "jacobian", "jac", "bundle+jacobian":
        rayBundleEnabled = true
        rayBundleJacobianRequestedByMode = true
    case "off", "false", "0", "no":
        rayBundleEnabled = false
        rayBundleJacobianRequestedByMode = false
    default:
        fail("invalid --ray-bundle \(rayBundleName). use off|on|jacobian")
    }
    let hasRayBundleJacobianArg = cliArguments.contains("--ray-bundle-jacobian")
    let rayBundleJacobianName = stringArg(
        "--ray-bundle-jacobian",
        default: rayBundleJacobianRequestedByMode ? "on" : "off"
    ).lowercased()
    let rayBundleJacobianEnabled: Bool
    switch rayBundleJacobianName {
    case "on", "true", "1", "yes":
        rayBundleJacobianEnabled = true
    case "off", "false", "0", "no":
        rayBundleJacobianEnabled = false
    default:
        fail("invalid --ray-bundle-jacobian \(rayBundleJacobianName). use on|off")
    }
    if rayBundleJacobianRequestedByMode && hasRayBundleJacobianArg && !rayBundleJacobianEnabled {
        FileHandle.standardError.write(
            Data("warn: --ray-bundle jacobian was overridden by explicit --ray-bundle-jacobian off\n".utf8)
        )
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
    let diskVolumeTauScaleArg = ((diskPhysicsModeID == 1 && thickCloudExplicit) || diskPhysicsModeID == 2 || diskPhysicsModeID == 3)
        ? diskVolumeTauScaleRawArg
        : 0.0
    let diskVolumeFormatArg: UInt32 = (diskPhysicsModeID == 3) ? 1 : 0
    let diskVolumeLegacyEnabled = (diskPhysicsModeID == 2) && !diskVolumePathArg.isEmpty
    let diskVolumeGRMHDEnabled = (diskPhysicsModeID == 3)
    let diskVolumeThickEnabled = (diskPhysicsModeID == 1) && thickCloudExplicit
    if diskVolumeGRMHDEnabled && (diskVol0PathArg.isEmpty || diskVol1PathArg.isEmpty) {
        fail("grmhd mode requires --disk-vol0 <path> and --disk-vol1 <path>")
    }
    let diskVolumeEnabled = diskVolumeLegacyEnabled || diskVolumeGRMHDEnabled || diskVolumeThickEnabled

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
        if (width % downsampleArg) != 0 || (height % downsampleArg) != 0 {
            FileHandle.standardError.write(Data("error: width/height must be divisible by --downsample\n".utf8))
            exit(2)
        }
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
        visiblePad0: (diskPhysicsModeID == 3 && visibleModeEnabled && visibleExpressiveMode) ? 1 : 0,
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
        accretionModel.buildPackedFields(into: &params, from: diskPolicy)

        var config = ResolvedRenderConfig()
        config.width = width
        config.height = height
        config.preset = preset
        config.outPath = outPath
        config.linear32OutPath = linear32OutPath
        config.imageOutPath = imageOutPath
        config.composeGPU = composeGPU
        config.gpuFullCompose = gpuFullCompose
        config.discardCollisionOutput = discardCollisionOutput
        config.linear32IntermediateRequested = linear32Intermediate
        config.traceHDRDirectMode = traceHDRDirectMode
        config.downsampleArg = downsampleArg
        config.metricName = metricName
        config.metricArg = metricArg
        config.spectralEncoding = spectralEncoding
        config.spectralEncodingID = spectralEncodingID
        config.diskPhysicsModeID = diskPhysicsModeID
        config.diskPhysicsModeArg = diskPhysicsModeArg
        config.diskModelResolved = diskModelResolved
        config.diskNoiseModel = diskNoiseModel
        config.diskAtlasEnabled = diskAtlasEnabled
        config.diskAtlasPathArg = diskAtlasEnabled ? diskAtlasPathArg : ""
        config.diskAtlasWidth = diskAtlasWidth
        config.diskAtlasHeight = diskAtlasHeight
        config.diskAtlasWrapPhi = diskAtlasWrapPhi
        config.diskAtlasTempScaleArg = diskAtlasTempScaleArg
        config.diskAtlasDensityBlendArg = diskAtlasDensityBlendArg
        config.diskAtlasVrScaleArg = diskAtlasVrScaleArg
        config.diskAtlasVphiScaleArg = diskAtlasVphiScaleArg
        config.diskAtlasRMin = diskAtlasRMin
        config.diskAtlasRMax = diskAtlasRMax
        config.diskAtlasRWarp = diskAtlasRWarp
        config.diskAtlasData = diskAtlasData
        config.diskVolumeEnabled = diskVolumeEnabled
        config.diskVolumeLegacyEnabled = diskVolumeLegacyEnabled
        config.diskVolumeGRMHDEnabled = diskVolumeGRMHDEnabled
        config.diskVolumeThickEnabled = diskVolumeThickEnabled
        config.diskVolumeFormatArg = diskVolumeFormatArg
        config.diskVolumeR = diskVolumeR
        config.diskVolumePhi = diskVolumePhi
        config.diskVolumeZ = diskVolumeZ
        config.diskVolumeRMin = diskVolumeRMin
        config.diskVolumeRMax = diskVolumeRMax
        config.diskVolumeZMax = diskVolumeZMax
        config.diskVolumeTauScaleArg = diskVolumeTauScaleArg
        config.diskVolume0Data = diskVolume0Data
        config.diskVolume1Data = diskVolume1Data
        config.diskVolumePathArg = diskVolumeLegacyEnabled ? diskVolumePathArg : ""
        config.diskVol0PathResolved = diskVol0PathResolved
        config.diskVol1PathResolved = diskVol1PathResolved
        config.visibleModeEnabled = visibleModeEnabled
        config.visibleTeffModelName = visibleTeffModelName
        config.visiblePolicyName = visiblePolicyName
        config.visibleEmissionModelName = visibleEmissionModelName
        config.diskGrmhdDebugName = diskGrmhdDebugName
        config.diskGrmhdDebugID = diskGrmhdDebugID
        config.diskNuObsHzArg = diskNuObsHzArg
        config.useLinear32Intermediate = useLinear32Intermediate
        config.rayBundleEnabled = rayBundleEnabled
        config.rayBundleActive = rayBundleActive
        config.rayBundleJacobianActive = rayBundleJacobianActive
        config.traceInFlightOverrideArg = traceInFlightOverrideArg
        config.tileSize = tileSize
        config.composeLook = composeLook
        config.composeLookID = composeLookID
        config.composeDitherArg = composeDitherArg
        config.composeInnerEdgeArg = composeInnerEdgeArg
        config.composeSpectralStepArg = composeSpectralStepArg
        config.composeChunkArg = composeChunkArg
        config.exposureSamplesArg = exposureSamplesArg
        config.exposureArg = exposureArg
        config.exposureModeName = exposureModeName
        config.exposureModeID = exposureModeID
        config.exposureEVArg = exposureEVArg
        config.composePrecisionName = composePrecisionName
        config.composePrecisionID = composePrecisionID
        config.composeAnalysisMode = composeAnalysisMode
        config.autoExposureEnabled = autoExposureEnabled
        config.composeExposureBase = composeExposureBase
        config.composeExposure = composeExposure
        config.preserveHighlightColor = preserveHighlightColor
        config.cameraModelName = cameraModelName
        config.cameraModelID = cameraModelID
        config.composeCameraModelID = composeCameraModelID
        config.cameraPsfSigmaArg = cameraPsfSigmaArg
        config.cameraReadNoiseArg = cameraReadNoiseArg
        config.cameraShotNoiseArg = cameraShotNoiseArg
        config.cameraFlareStrengthArg = cameraFlareStrengthArg
        config.composeCameraPsfSigmaArg = composeCameraPsfSigmaArg
        config.composeCameraReadNoiseArg = composeCameraReadNoiseArg
        config.composeCameraShotNoiseArg = composeCameraShotNoiseArg
        config.composeCameraFlareStrengthArg = composeCameraFlareStrengthArg
        config.backgroundModeName = backgroundModeName
        config.backgroundModeID = backgroundModeID
        config.backgroundStarDensityArg = backgroundStarDensityArg
        config.backgroundStarStrengthArg = backgroundStarStrengthArg
        config.backgroundNebulaStrengthArg = backgroundNebulaStrengthArg
        config.c = c
        config.G = G
        config.k = k
        config.M = M
        config.rsD = rsD
        config.reD = reD
        config.heD = heD
        config.camXFactor = camXFactor
        config.camYFactor = camYFactor
        config.camZFactor = camZFactor
        config.fovDeg = fovDeg
        config.rollDeg = rollDeg
        config.rcp = rcp
        config.diskHFactor = diskHFactor
        config.maxStepsArg = maxStepsArg
        config.hArg = hArg
        config.spinArg = spinArg
        config.kerrSubstepsArg = kerrSubstepsArg
        config.kerrTolArg = kerrTolArg
        config.kerrEscapeMultArg = kerrEscapeMultArg
        config.kerrRadialScaleArg = kerrRadialScaleArg
        config.kerrAzimuthScaleArg = kerrAzimuthScaleArg
        config.kerrImpactScaleArg = kerrImpactScaleArg
        config.diskFlowTimeArg = diskFlowTimeArg
        config.diskOrbitalBoostArg = diskOrbitalBoostArg
        config.diskRadialDriftArg = diskRadialDriftArg
        config.diskTurbulenceArg = diskTurbulenceArg
        config.diskOrbitalBoostInnerArg = diskOrbitalBoostInnerArg
        config.diskOrbitalBoostOuterArg = diskOrbitalBoostOuterArg
        config.diskRadialDriftInnerArg = diskRadialDriftInnerArg
        config.diskRadialDriftOuterArg = diskRadialDriftOuterArg
        config.diskTurbulenceInnerArg = diskTurbulenceInnerArg
        config.diskTurbulenceOuterArg = diskTurbulenceOuterArg
        config.diskFlowStepArg = diskFlowStepArg
        config.diskFlowStepsArg = diskFlowStepsArg
        config.diskMdotEddArg = diskMdotEddArg
        config.diskRadiativeEfficiencyArg = diskRadiativeEfficiencyArg
        config.diskPlungeFloorArg = diskPlungeFloorArg
        config.diskThickScaleArg = diskThickScaleArg
        config.diskColorFactorArg = diskColorFactorArg
        config.diskReturningRadArg = diskReturningRadArg
        config.diskPrecisionTextureArg = diskPrecisionTextureArg
        config.diskPrecisionCloudsEnabled = diskPrecisionCloudsEnabled
        config.diskCloudCoverageArg = diskCloudCoverageArg
        config.diskCloudOpticalDepthArg = diskCloudOpticalDepthArg
        config.diskCloudPorosityArg = diskCloudPorosityArg
        config.diskCloudShadowStrengthArg = diskCloudShadowStrengthArg
        config.diskReturnBouncesArg = diskReturnBouncesArg
        config.diskRTStepsArg = diskRTStepsArg
        config.diskScatteringAlbedoArg = diskScatteringAlbedoArg
        config.diskPolarizedRTEnabled = diskPolarizedRTEnabled
        config.diskPolarizationFracArg = diskPolarizationFracArg
        config.diskFaradayRotScaleArg = diskFaradayRotScaleArg
        config.diskFaradayConvScaleArg = diskFaradayConvScaleArg
        config.visibleSamplesArg = visibleSamplesArg
        config.visibleTeffModelID = visibleTeffModelID
        config.visibleTeffT0Arg = visibleTeffT0Arg
        config.visibleTeffR0RsArg = visibleTeffR0RsArg
        config.visibleTeffPArg = visibleTeffPArg
        config.visibleBhMassArg = visibleBhMassArg
        config.visibleMdotArg = visibleMdotArg
        config.visibleRInRsArg = visibleRInRsArg
        config.photosphereRhoThresholdResolved = photosphereRhoThresholdResolved
        config.visibleExpressiveMode = visibleExpressiveMode
        config.visibleEmissionModelID = visibleEmissionModelID
        config.visibleSynchAlphaArg = visibleSynchAlphaArg
        config.visibleKappaArg = visibleKappaArg
        config.coolAbsorptionEnabled = coolAbsorptionEnabled
        config.coolDustToGasArg = coolDustToGasArg
        config.coolDustKappaVArg = coolDustKappaVArg
        config.coolDustBetaArg = coolDustBetaArg
        config.coolDustTSubArg = coolDustTSubArg
        config.coolDustTWidthArg = coolDustTWidthArg
        config.coolGasKappa0Arg = coolGasKappa0Arg
        config.coolGasNuSlopeArg = coolGasNuSlopeArg
        config.coolClumpStrengthArg = coolClumpStrengthArg
        config.rayBundleJacobianStrengthArg = rayBundleJacobianStrengthArg
        config.rayBundleFootprintClampArg = rayBundleFootprintClampArg
        config.visibleTeffR0Meters = visibleTeffR0Meters
        config.visibleRInMeters = visibleRInMeters
        config.diskInnerRadiusCompose = diskInnerRadiusCompose
        config.diskHorizonRadiusCompose = diskHorizonRadiusCompose
        config.camPos = camPos
        config.z = z
        config.planeX = planeX
        config.planeY = planeY
        config.d = d
        config.renderConfigLine = "render config preset=\(preset) \(width)x\(height), cam=(\(camXFactor),\(camYFactor),\(camZFactor))rs, fov=\(fovDeg), roll=\(rollDeg), rcp=\(rcp), diskH=\(diskHFactor)rs, maxSteps=\(maxStepsArg), metric=\(metricName), spin=\(spinArg), kerrSubsteps=\(kerrSubstepsArg), kerrTol=\(kerrTolArg), kerrEscape=\(kerrEscapeMultArg), kerrScale=(\(kerrRadialScaleArg),\(kerrAzimuthScaleArg),\(kerrImpactScaleArg)), diskModel=\(diskModelResolved), diskFlow=(t=\(diskFlowTimeArg),omega=\(diskOrbitalBoostArg),vr=\(diskRadialDriftArg),turb=\(diskTurbulenceArg),omegaIn=\(diskOrbitalBoostInnerArg),omegaOut=\(diskOrbitalBoostOuterArg),vrIn=\(diskRadialDriftInnerArg),vrOut=\(diskRadialDriftOuterArg),turbIn=\(diskTurbulenceInnerArg),turbOut=\(diskTurbulenceOuterArg),dt=\(diskFlowStepArg),steps=\(diskFlowStepsArg)), diskPhysics=(mode=\(diskPhysicsModeArg),mdotEdd=\(diskMdotEddArg),eta=\(diskRadiativeEfficiencyArg),plunge=\(diskPlungeFloorArg),thickScale=\(diskThickScaleArg),fcol=\(diskColorFactorArg),ret=\(diskReturningRadArg),retBounces=\(diskReturnBouncesArg),rtSteps=\(diskRTStepsArg),albedo=\(diskScatteringAlbedoArg),texture=\(diskPrecisionTextureArg),precisionClouds=\(diskPrecisionCloudsEnabled),cloudCoverage=\(diskCloudCoverageArg),cloudTau=\(diskCloudOpticalDepthArg),cloudPorosity=\(diskCloudPorosityArg),cloudShadow=\(diskCloudShadowStrengthArg)), diskAtlas=(enabled=\(diskAtlasEnabled),size=\(diskAtlasWidth)x\(diskAtlasHeight),temp=\(diskAtlasTempScaleArg),density=\(diskAtlasDensityBlendArg),vr=\(diskAtlasVrScaleArg),vphi=\(diskAtlasVphiScaleArg),rMin=\(diskAtlasRMin),rMax=\(diskAtlasRMax),rWarp=\(diskAtlasRWarp)), diskVolume=(enabled=\(diskVolumeEnabled),size=\(diskVolumeR)x\(diskVolumePhi)x\(diskVolumeZ),rMin=\(diskVolumeRMin),rMax=\(diskVolumeRMax),zMax=\(diskVolumeZMax),tauScale=\(diskVolumeTauScaleArg)), rayBundle=(requested=\(rayBundleEnabled),active=\(rayBundleActive),jacobian=\(rayBundleJacobianActive),jacStrength=\(rayBundleJacobianStrengthArg),clamp=\(rayBundleFootprintClampArg)), cameraModel=(name=\(cameraModelName),psf=\(cameraPsfSigmaArg),readNoise=\(cameraReadNoiseArg),shotNoise=\(cameraShotNoiseArg),flare=\(cameraFlareStrengthArg)), background=(mode=\(backgroundModeName),density=\(backgroundStarDensityArg),strength=\(backgroundStarStrengthArg),nebula=\(backgroundNebulaStrengthArg)), tileSize=\(tileSize), io=(composeGPU=\(composeGPU),gpuFullCompose=\(gpuFullCompose),discardCollisions=\(discardCollisionOutput),hdrFileIntermediate=\(useLinear32Intermediate),traceHDRPreference=\(traceHDRDirectMode)), downsample=\(downsampleArg), analysisMode=\(composeAnalysisMode)"
        if diskPhysicsModeID == 3 {
            let grmhdVol0Label = diskVol0PathResolved.isEmpty ? "none" : diskVol0PathResolved
            let grmhdVol1Label = diskVol1PathResolved.isEmpty ? "none" : diskVol1PathResolved
            config.grmhdConfigLine = "grmhd config vol0=\(grmhdVol0Label), vol1=\(grmhdVol1Label), nuObsHz=\(diskNuObsHzArg), rhoScale=\(diskGrmhdDensityScaleArg), bScale=\(diskGrmhdBScaleArg), jScale=\(diskGrmhdEmissionScaleArg), alphaScale=\(diskGrmhdAbsorptionScaleArg), velScale=\(diskGrmhdVelScaleArg), polarized=\(diskPolarizedRTEnabled), polFrac=\(diskPolarizationFracArg), faradayRot=\(diskFaradayRotScaleArg), faradayConv=\(diskFaradayConvScaleArg), debug=\(diskGrmhdDebugName)"
            config.visibleConfigLine = "visible config enabled=\(visibleModeEnabled), policy=\(visiblePolicyName), samples=\(visibleSamplesArg), teffModel=\(visibleTeffModelName), teff=(T0=\(visibleTeffT0Arg),r0Rs=\(visibleTeffR0RsArg),p=\(visibleTeffPArg)), thinDisk=(M=\(visibleBhMassArg),mdot=\(visibleMdotArg),rInRs=\(visibleRInRsArg)), photosphereRho=\(photosphereRhoThresholdResolved), emissionModel=\(visibleEmissionModelName), synchAlpha=\(visibleSynchAlphaArg), visibleKappa=\(visibleKappaArg), coolAbsorption=(enabled=\(coolAbsorptionEnabled),dustToGas=\(coolDustToGasArg),dustKappaV=\(coolDustKappaVArg),dustBeta=\(coolDustBetaArg),dustTsub=\(coolDustTSubArg),dustTwidth=\(coolDustTWidthArg),gasKappa0=\(coolGasKappa0Arg),gasNuSlope=\(coolGasNuSlopeArg),clump=\(coolClumpStrengthArg)), exposureMode=\(exposureModeName), exposureEV=\(exposureEVArg), rayBundle=(requested=\(rayBundleEnabled),active=\(rayBundleActive),jacobian=\(rayBundleJacobianActive),jacStrength=\(rayBundleJacobianStrengthArg),clamp=\(rayBundleFootprintClampArg))"
        }

        return BuiltParams(
            rawArguments: logical.rawArguments,
            runRegression: false,
            printPackedLayout: false,
            validatePackedABI: false,
            dumpPackedParamsPath: logical.dumpPackedParamsPath,
            resolvedConfig: config,
            packedParams: params
        )
    }

    static func buildPackedParams(from config: ResolvedRenderConfig) -> PackedParams {
        PackedParams(
            width: UInt32(config.width),
            height: UInt32(config.height),
            fullWidth: UInt32(config.width),
            fullHeight: UInt32(config.height),
            offsetX: 0,
            offsetY: 0,
            camPos: config.camPos,
            planeX: config.planeX,
            planeY: config.planeY,
            z: config.z,
            d: config.d,
            rs: Float(config.rsD),
            re: Float(config.reD),
            he: Float(config.heD),
            M: Float(config.M),
            G: Float(config.G),
            c: Float(config.c),
            k: Float(config.k),
            h: Float(config.hArg),
            maxSteps: Int32(config.maxStepsArg),
            eps: 1e-5,
            metric: config.metricArg,
            spin: Float(config.spinArg),
            kerrSubsteps: Int32(config.kerrSubstepsArg),
            kerrTol: Float(config.kerrTolArg),
            kerrEscapeMult: Float(config.kerrEscapeMultArg),
            kerrRadialScale: Float(config.kerrRadialScaleArg),
            kerrAzimuthScale: Float(config.kerrAzimuthScaleArg),
            kerrImpactScale: Float(config.kerrImpactScaleArg),
            diskFlowTime: Float(config.diskFlowTimeArg),
            diskOrbitalBoost: Float(config.diskOrbitalBoostArg),
            diskRadialDrift: Float(config.diskRadialDriftArg),
            diskTurbulence: Float(config.diskTurbulenceArg),
            diskOrbitalBoostInner: Float(config.diskOrbitalBoostInnerArg),
            diskOrbitalBoostOuter: Float(config.diskOrbitalBoostOuterArg),
            diskRadialDriftInner: Float(config.diskRadialDriftInnerArg),
            diskRadialDriftOuter: Float(config.diskRadialDriftOuterArg),
            diskTurbulenceInner: Float(config.diskTurbulenceInnerArg),
            diskTurbulenceOuter: Float(config.diskTurbulenceOuterArg),
            diskFlowStep: Float(config.diskFlowStepArg),
            diskFlowSteps: Float(config.diskFlowStepsArg),
            diskAtlasMode: config.diskAtlasEnabled ? 1 : 0,
            diskAtlasWidth: UInt32(config.diskAtlasWidth),
            diskAtlasHeight: UInt32(config.diskAtlasHeight),
            diskAtlasWrapPhi: config.diskAtlasWrapPhi,
            diskAtlasTempScale: Float(config.diskAtlasTempScaleArg),
            diskAtlasDensityBlend: Float(config.diskAtlasDensityBlendArg),
            diskAtlasVrScale: Float(config.diskAtlasVrScaleArg),
            diskAtlasVphiScale: Float(config.diskAtlasVphiScaleArg),
            diskAtlasRNormMin: Float(config.diskAtlasRMin),
            diskAtlasRNormMax: Float(config.diskAtlasRMax),
            diskAtlasRNormWarp: Float(config.diskAtlasRWarp),
            diskNoiseModel: config.diskNoiseModel,
            diskMdotEdd: Float(config.diskMdotEddArg),
            diskRadiativeEfficiency: Float(config.diskRadiativeEfficiencyArg),
            diskPhysicsMode: config.diskPhysicsModeID,
            diskPlungeFloor: Float(config.diskPlungeFloorArg),
            diskThickScale: Float(config.diskThickScaleArg),
            diskColorFactor: Float(config.diskColorFactorArg),
            diskReturningRad: Float(config.diskReturningRadArg),
            diskPrecisionTexture: Float(config.diskPrecisionTextureArg),
            diskCloudCoverage: Float(config.diskCloudCoverageArg),
            diskCloudOpticalDepth: Float(config.diskCloudOpticalDepthArg),
            diskCloudPorosity: Float(config.diskCloudPorosityArg),
            diskCloudShadowStrength: Float(config.diskCloudShadowStrengthArg),
            diskReturnBounces: UInt32(config.diskReturnBouncesArg),
            diskRTSteps: UInt32(config.diskRTStepsArg),
            diskScatteringAlbedo: Float(config.diskScatteringAlbedoArg),
            diskRTPad: 0,
            diskVolumeMode: config.diskVolumeEnabled ? 1 : 0,
            diskVolumeR: UInt32(config.diskVolumeR),
            diskVolumePhi: UInt32(config.diskVolumePhi),
            diskVolumeZ: UInt32(config.diskVolumeZ),
            diskVolumeRNormMin: Float(config.diskVolumeRMin),
            diskVolumeRNormMax: Float(config.diskVolumeRMax),
            diskVolumeZNormMax: Float(config.diskVolumeZMax),
            diskVolumeTauScale: Float(config.diskVolumeTauScaleArg),
            diskVolumeFormat: config.diskVolumeFormatArg,
            diskVolumeR0: UInt32(config.diskVolumeR),
            diskVolumePhi0: UInt32(config.diskVolumePhi),
            diskVolumeZ0: UInt32(config.diskVolumeZ),
            diskVolumeR1: UInt32(config.diskVolumeR),
            diskVolumePhi1: UInt32(config.diskVolumePhi),
            diskVolumeZ1: UInt32(config.diskVolumeZ),
            diskNuObsHz: Float(config.diskNuObsHzArg),
            diskGrmhdDensityScale: Float(config.diskGrmhdDensityScaleArg),
            diskGrmhdBScale: Float(config.diskGrmhdBScaleArg),
            diskGrmhdEmissionScale: Float(config.diskGrmhdEmissionScaleArg),
            diskGrmhdAbsorptionScale: Float(config.diskGrmhdAbsorptionScaleArg),
            diskGrmhdVelScale: Float(config.diskGrmhdVelScaleArg),
            diskGrmhdDebugView: config.diskGrmhdDebugID,
            diskPolarizedRT: (config.diskPhysicsModeID == 3 && config.diskPolarizedRTEnabled) ? 1 : 0,
            diskPolarizationFrac: Float(config.diskPolarizationFracArg),
            diskFaradayRotScale: Float(config.diskFaradayRotScaleArg),
            diskFaradayConvScale: Float(config.diskFaradayConvScaleArg),
            visibleMode: (config.diskPhysicsModeID == 3 && config.visibleModeEnabled) ? 1 : 0,
            visibleSamples: UInt32(config.visibleSamplesArg),
            visibleTeffModel: config.visibleTeffModelID,
            visiblePad0: (config.diskPhysicsModeID == 3 && config.visibleModeEnabled && config.visibleExpressiveMode) ? 1 : 0,
            visibleTeffT0: Float(config.visibleTeffT0Arg),
            visibleTeffR0: Float(config.visibleTeffR0Meters),
            visibleTeffP: Float(config.visibleTeffPArg),
            visiblePhotosphereRhoThreshold: Float(config.photosphereRhoThresholdResolved),
            visibleBhMass: Float(config.visibleBhMassArg),
            visibleMdot: Float(config.visibleMdotArg),
            visibleRIn: Float(config.visibleRInMeters),
            visibleKappa: Float(config.visibleKappaArg),
            visibleEmissionModel: config.visibleEmissionModelID,
            visibleEmissionAlpha: Float(config.visibleSynchAlphaArg),
            rayBundleSSAA: config.rayBundleActive ? 1 : 0,
            rayBundleJacobian: config.rayBundleJacobianActive ? 1 : 0,
            rayBundleJacobianStrength: Float(config.rayBundleJacobianStrengthArg),
            rayBundleFootprintClamp: Float(config.rayBundleFootprintClampArg),
            coolAbsorptionMode: (config.diskPhysicsModeID == 3 && config.visibleModeEnabled && config.coolAbsorptionEnabled) ? 1 : 0,
            coolDustToGas: Float(config.coolDustToGasArg),
            coolDustKappaV: Float(config.coolDustKappaVArg),
            coolDustBeta: Float(config.coolDustBetaArg),
            coolDustTSub: Float(config.coolDustTSubArg),
            coolDustTWidth: Float(config.coolDustTWidthArg),
            coolGasKappa0: Float(config.coolGasKappa0Arg),
            coolGasNuSlope: Float(config.coolGasNuSlopeArg),
            coolClumpStrength: Float(config.coolClumpStrengthArg),
            coolAbsorptionPad: 0
        )
    }
}
