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
    ParamsBuilderAssets.validateRemovedFlags(cliArguments: cliArguments)

    let width = intArg("--width", default: 1200)
    let height = intArg("--height", default: 1200)
    let preset = stringArg("--preset", default: "balanced").lowercased()
    let presetDefaults = ParamsBuilderRuntime.resolvePresetDefaults(preset: preset)
    let camXFactor = doubleArg("--camX", default: presetDefaults.camX)
    let camYFactor = doubleArg("--camY", default: presetDefaults.camY)
    let camZFactor = doubleArg("--camZ", default: presetDefaults.camZ)
    let fovDeg = doubleArg("--fov", default: presetDefaults.fov)
    let rollDeg = doubleArg("--roll", default: presetDefaults.roll)
    let rcp = doubleArg("--rcp", default: presetDefaults.rcp)
    let diskHFactor = doubleArg("--diskH", default: presetDefaults.diskH)
    let maxStepsArg = intArg("--maxSteps", default: presetDefaults.maxSteps)
    let rawOutputPath = stringArg("--output", default: "blackhole_gpu.png")
    let explicitImageOutPath = stringArg("--image-out", default: "")
    let runtimeIO = ParamsBuilderAssets.resolveRuntimeIO(
        cliArguments: cliArguments,
        rawOutputPath: rawOutputPath,
        explicitImageOutPath: explicitImageOutPath
    )
    let composeGPU = runtimeIO.composeGPU
    let gpuFullCompose = runtimeIO.gpuFullCompose
    let discardCollisionOutput = runtimeIO.discardCollisionOutput
    let linear32Intermediate = runtimeIO.linear32Intermediate
    let linear32OutPath = runtimeIO.linear32OutPath
    let outPath = runtimeIO.outPath
    let imageOutPath = runtimeIO.imageOutPath
    let traceHDRDirectMode = runtimeIO.traceHDRDirectMode
    let downsampleArg = max(1, intArg("--downsample", default: 1))
    ParamsBuilderRuntime.validateDownsample(downsampleArg)
    let metricSettings = ParamsBuilderRuntime.resolveMetricSettings()
    let metricName = metricSettings.metricName
    let metricArg = metricSettings.metricArg
    let spectralEncoding = "gfactor_v1"
    let hArg = metricSettings.hArg
    let spinArg = metricSettings.spinArg
    let kerrSubstepsArg = metricSettings.kerrSubstepsArg
    let kerrTolArg = metricSettings.kerrTolArg
    let kerrEscapeMultArg = metricSettings.kerrEscapeMultArg
    let kerrRadialScaleArg = metricSettings.kerrRadialScaleArg
    let kerrAzimuthScaleArg = metricSettings.kerrAzimuthScaleArg
    let kerrImpactScaleArg = metricSettings.kerrImpactScaleArg
    ParamsBuilderDiagnostics.emitDeprecatedWarnings(kerrImpactScaleArg: kerrImpactScaleArg)
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
    let diskPhysicsSelection = ParamsBuilderPolicy.resolveDiskPhysicsSelection(
        cliArguments: cliArguments,
        diskModeRaw: diskModeRaw,
        diskPhysicsProfileRaw: diskPhysicsProfileRaw,
        diskPhysicsLegacyRaw: diskPhysicsLegacyRaw
    )
    let diskPhysicsModeID = diskPhysicsSelection.diskPhysicsModeID
    let diskPhysicsModeArg = diskPhysicsSelection.diskPhysicsModeArg
    let diskPhysicsThinProfile = diskPhysicsSelection.diskPhysicsThinProfile
    let diskMdotEddArg = max(1e-5, doubleArgAny(["--mdot-edd", "--disk-mdot-edd"], default: 0.1))
    let diskRadiativeEfficiencyArg = min(max(doubleArgAny(["--eta", "--disk-radiative-efficiency"], default: 0.1), 0.01), 0.42)
    let hasDiskVolumeArg = diskPhysicsSelection.hasDiskVolumeArg
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
    ParamsBuilderDiagnostics.emit(lines: diskPolicy.infos)
    ParamsBuilderDiagnostics.emit(lines: diskPolicy.warnings)
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
    let diskPolarizedRTName = stringArg("--disk-polarized-rt", default: "off").lowercased()
    let diskPolarizationFracArg = min(max(doubleArg("--disk-pol-frac", default: 0.25), 0.0), 0.95)
    let diskFaradayRotScaleArg = doubleArg("--disk-faraday-rot", default: 0.0)
    let diskFaradayConvScaleArg = doubleArg("--disk-faraday-conv", default: 0.0)
    let grmhdPolicy = ParamsBuilderPolicy.resolveGRMHDPolicy(
        diskPhysicsModeID: diskPhysicsModeID,
        diskGrmhdDebugName: diskGrmhdDebugName,
        diskPolarizedRTName: diskPolarizedRTName,
        diskFaradayRotScaleArg: diskFaradayRotScaleArg,
        diskFaradayConvScaleArg: diskFaradayConvScaleArg
    )
    let diskGrmhdDebugID = grmhdPolicy.diskGrmhdDebugID
    let diskPolarizedRTEnabled = grmhdPolicy.diskPolarizedRTEnabled
    let visibleSettings = ParamsBuilderVisible.resolveVisibleSettings(
        cliArguments: cliArguments,
        diskPhysicsModeID: diskPhysicsModeID,
        diskPhysicsModeArg: diskPhysicsModeArg,
        diskGrmhdDebugID: diskGrmhdDebugID,
        diskPrecisionTextureRawArg: diskPrecisionTextureRawArg
    )
    let visibleSamplesArg = visibleSettings.visibleSamplesArg
    let visibleTeffModelName = visibleSettings.visibleTeffModelName
    let visibleTeffT0Arg = visibleSettings.visibleTeffT0Arg
    let visibleTeffR0RsArg = visibleSettings.visibleTeffR0RsArg
    let visibleTeffPArg = visibleSettings.visibleTeffPArg
    let visibleBhMassArg = visibleSettings.visibleBhMassArg
    let visibleMdotArg = visibleSettings.visibleMdotArg
    let visibleRInRsArg = visibleSettings.visibleRInRsArg
    let photosphereRhoThresholdArg = visibleSettings.photosphereRhoThresholdArg
    let visiblePolicyName = visibleSettings.visiblePolicyName
    let visibleEmissionModelName = visibleSettings.visibleEmissionModelName
    let visibleKappaArg = visibleSettings.visibleKappaArg
    let coolDustToGasArg = visibleSettings.coolDustToGasArg
    let coolDustKappaVArg = visibleSettings.coolDustKappaVArg
    let coolDustBetaArg = visibleSettings.coolDustBetaArg
    let coolDustTSubArg = visibleSettings.coolDustTSubArg
    let coolDustTWidthArg = visibleSettings.coolDustTWidthArg
    let coolGasKappa0Arg = visibleSettings.coolGasKappa0Arg
    let coolGasNuSlopeArg = visibleSettings.coolGasNuSlopeArg
    let coolClumpStrengthArg = visibleSettings.coolClumpStrengthArg
    let visibleModeEnabled = visibleSettings.visibleModeEnabled
    let visibleTeffModelID = visibleSettings.visibleTeffModelID
    let visibleExpressiveMode = visibleSettings.visibleExpressiveMode
    let visibleEmissionModelID = visibleSettings.visibleEmissionModelID
    let visibleSynchAlphaArg = visibleSettings.visibleSynchAlphaArg
    let coolAbsorptionEnabled = visibleSettings.coolAbsorptionEnabled
    diskPrecisionTextureArg = visibleSettings.effectiveDiskPrecisionTextureArg
    let rayBundleName = stringArg("--ray-bundle", default: "off").lowercased()
    let rayBundleJacobianName = stringArg(
        "--ray-bundle-jacobian",
        default: (rayBundleName == "jacobian" || rayBundleName == "jac" || rayBundleName == "bundle+jacobian") ? "on" : "off"
    ).lowercased()
    let rayBundleJacobianStrengthArg = max(0.0, doubleArg("--ray-bundle-jacobian-strength", default: 1.0))
    let rayBundleFootprintClampArg = min(max(doubleArg("--ray-bundle-footprint-clamp", default: 6.0), 0.0), 20.0)
    let rayBundlePolicy = ParamsBuilderPolicy.resolveRayBundlePolicy(
        cliArguments: cliArguments,
        diskPhysicsModeID: diskPhysicsModeID,
        visibleModeEnabled: visibleModeEnabled,
        diskGrmhdDebugID: diskGrmhdDebugID,
        rayBundleName: rayBundleName,
        rayBundleJacobianName: rayBundleJacobianName
    )
    let rayBundleEnabled = rayBundlePolicy.rayBundleEnabled
    let rayBundleActive = rayBundlePolicy.rayBundleActive
    let rayBundleJacobianActive = rayBundlePolicy.rayBundleJacobianActive
    let tileSizeArg = max(0, intArg("--tile-size", default: 0))
    let traceInFlightOverrideArg = max(0, intArg("--trace-inflight", default: 0))
    let tileSize = ParamsBuilderRuntime.resolveTileSize(
        width: width,
        height: height,
        metricArg: metricArg,
        explicitTileSize: tileSizeArg
    )
    let composeLookSettings = ParamsBuilderRuntime.resolveComposeLookID(
        cliArguments: cliArguments,
        preset: preset,
        diskPhysicsModeID: diskPhysicsModeID
    )
    let composeLook = composeLookSettings.composeLook
    let composeLookID = composeLookSettings.composeLookID
    let visualSettings = ParamsBuilderVisual.resolveVisualSettings(
        diskModelArg: diskModelArg,
        diskPhysicsModeID: diskPhysicsModeID,
        diskPrecisionCloudsEnabled: diskPrecisionCloudsEnabled,
        diskGrmhdDebugID: diskGrmhdDebugID,
        composeLookID: composeLookID,
        composeGPU: composeGPU,
        gpuFullCompose: gpuFullCompose,
        linear32Intermediate: linear32Intermediate
    )
    let composeDitherArg = visualSettings.composeDitherArg
    let cameraModelName = visualSettings.cameraModelName
    let cameraModelID = visualSettings.cameraModelID
    let cameraPsfSigmaArg = visualSettings.cameraPsfSigmaArg
    let cameraReadNoiseArg = visualSettings.cameraReadNoiseArg
    let cameraShotNoiseArg = visualSettings.cameraShotNoiseArg
    let cameraFlareStrengthArg = visualSettings.cameraFlareStrengthArg
    let backgroundModeName = visualSettings.backgroundModeName
    let backgroundModeID = visualSettings.backgroundModeID
    let backgroundStarDensityArg = visualSettings.backgroundStarDensityArg
    let backgroundStarStrengthArg = visualSettings.backgroundStarStrengthArg
    let backgroundNebulaStrengthArg = visualSettings.backgroundNebulaStrengthArg
    let composeInnerEdgeArg = visualSettings.composeInnerEdgeArg
    let composeSpectralStepArg = visualSettings.composeSpectralStepArg
    let composeChunkArg = visualSettings.composeChunkArg
    let exposureSamplesArg = visualSettings.exposureSamplesArg
    let exposureArg = visualSettings.exposureArg
    let exposureModeName = visualSettings.exposureModeName
    let exposureModeID = visualSettings.exposureModeID
    let exposureEVArg = visualSettings.exposureEVArg
    let composePrecisionName = visualSettings.composePrecisionName
    let composePrecisionID = visualSettings.composePrecisionID
    let composeAnalysisMode = visualSettings.composeAnalysisMode
    let composeCameraModelID = visualSettings.composeCameraModelID
    let composeCameraPsfSigmaArg = visualSettings.composeCameraPsfSigmaArg
    let composeCameraReadNoiseArg = visualSettings.composeCameraReadNoiseArg
    let composeCameraShotNoiseArg = visualSettings.composeCameraShotNoiseArg
    let composeCameraFlareStrengthArg = visualSettings.composeCameraFlareStrengthArg
    let autoExposureEnabled = visualSettings.autoExposureEnabled
    let composeExposureBase = visualSettings.composeExposureBase
    let spectralEncodingID = visualSettings.spectralEncodingID
    let composeExposure = visualSettings.composeExposure
    let preserveHighlightColor: UInt32 = (diskPhysicsModeID == 3 && visibleModeEnabled && composeAnalysisMode == 0) ? 1 : 0
    let useLinear32Intermediate = visualSettings.useLinear32Intermediate
    let diskModelResolution = ParamsBuilderPolicy.resolveDiskModel(
        diskModelArg: diskModelArg,
        diskPhysicsModeID: diskPhysicsModeID,
        diskAtlasPathArg: diskAtlasPathArg
    )
    let diskModelResolved = diskModelResolution.diskModelResolved
    let diskAtlasEnabled = diskModelResolution.diskAtlasEnabled
    let diskNoiseModel = diskModelResolution.diskNoiseModel
    let diskAtlasWrapPhi: UInt32 = 1

    let diskAtlasResource = ParamsBuilderAssets.loadDiskAtlasResource(
        enabled: diskAtlasEnabled,
        path: diskAtlasPathArg,
        widthOverride: diskAtlasWidthArg,
        heightOverride: diskAtlasHeightArg
    )
    let diskAtlasData = diskAtlasResource.data
    let diskAtlasWidth = diskAtlasResource.width
    let diskAtlasHeight = diskAtlasResource.height
    let diskAtlasMetaRMin = diskAtlasResource.rNormMin
    let diskAtlasMetaRMax = diskAtlasResource.rNormMax
    let diskAtlasMetaRWarp = diskAtlasResource.rNormWarp
    let diskAtlasRMinDefault = 1.0
    let diskAtlasRMaxDefault = max(diskAtlasRMinDefault + 1e-6, rcp)
    let diskAtlasRMin = max(0.0, (diskAtlasRMinArg >= 0.0) ? diskAtlasRMinArg : (diskAtlasMetaRMin ?? diskAtlasRMinDefault))
    let diskAtlasRMaxCandidate = (diskAtlasRMaxArg >= 0.0) ? diskAtlasRMaxArg : (diskAtlasMetaRMax ?? diskAtlasRMaxDefault)
    let diskAtlasRMax = max(diskAtlasRMin + 1e-6, diskAtlasRMaxCandidate)
    let diskAtlasRWarpCandidate = (diskAtlasRWarpArg >= 0.0) ? diskAtlasRWarpArg : (diskAtlasMetaRWarp ?? 1.0)
    let diskAtlasRWarp = max(1e-3, diskAtlasRWarpCandidate)
    let diskVolumeAssembly = ParamsBuilderDiskVolume.resolve(
        diskPhysicsModeID: diskPhysicsModeID,
        thickCloudExplicit: thickCloudExplicit,
        diskVolumePathArg: diskVolumePathArg,
        diskVol0PathArg: diskVol0PathArg,
        diskVol1PathArg: diskVol1PathArg,
        diskMetaPathArg: diskMetaPathArg,
        diskVolumeTauScaleRawArg: diskVolumeTauScaleRawArg,
        diskVolumeROverrideArg: diskVolumeROverrideArg,
        diskVolumePhiOverrideArg: diskVolumePhiOverrideArg,
        diskVolumeZOverrideArg: diskVolumeZOverrideArg,
        rcp: rcp,
        visibleModeEnabled: visibleModeEnabled,
        photosphereRhoThresholdArg: photosphereRhoThresholdArg
    )
    let diskVolumeTauScaleArg = diskVolumeAssembly.diskVolumeTauScaleArg
    let diskVolumeFormatArg = diskVolumeAssembly.diskVolumeFormatArg
    let diskVolumeLegacyEnabled = diskVolumeAssembly.diskVolumeLegacyEnabled
    let diskVolumeGRMHDEnabled = diskVolumeAssembly.diskVolumeGRMHDEnabled
    let diskVolumeThickEnabled = diskVolumeAssembly.diskVolumeThickEnabled
    let diskVolumeEnabled = diskVolumeAssembly.diskVolumeEnabled
    let diskVolume0Data = diskVolumeAssembly.diskVolume0Data
    let diskVolume1Data = diskVolumeAssembly.diskVolume1Data
    let diskVolumeR = diskVolumeAssembly.diskVolumeR
    let diskVolumePhi = diskVolumeAssembly.diskVolumePhi
    let diskVolumeZ = diskVolumeAssembly.diskVolumeZ
    let diskVol0PathResolved = diskVolumeAssembly.diskVol0PathResolved
    let diskVol1PathResolved = diskVolumeAssembly.diskVol1PathResolved
    let diskVolumeRMin = diskVolumeAssembly.diskVolumeRMin
    let diskVolumeRMax = diskVolumeAssembly.diskVolumeRMax
    let diskVolumeZMax = diskVolumeAssembly.diskVolumeZMax
    let photosphereRhoThresholdResolved = diskVolumeAssembly.photosphereRhoThresholdResolved

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
        config.diskGrmhdDensityScaleArg = diskGrmhdDensityScaleArg
        config.diskGrmhdBScaleArg = diskGrmhdBScaleArg
        config.diskGrmhdEmissionScaleArg = diskGrmhdEmissionScaleArg
        config.diskGrmhdAbsorptionScaleArg = diskGrmhdAbsorptionScaleArg
        config.diskGrmhdVelScaleArg = diskGrmhdVelScaleArg
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
        config.renderConfigLine = ParamsBuilderSummary.renderConfigLine(
            preset: preset,
            width: width,
            height: height,
            camXFactor: camXFactor,
            camYFactor: camYFactor,
            camZFactor: camZFactor,
            fovDeg: fovDeg,
            rollDeg: rollDeg,
            rcp: rcp,
            diskHFactor: diskHFactor,
            maxStepsArg: maxStepsArg,
            metricName: metricName,
            spinArg: spinArg,
            kerrSubstepsArg: kerrSubstepsArg,
            kerrTolArg: kerrTolArg,
            kerrEscapeMultArg: kerrEscapeMultArg,
            kerrRadialScaleArg: kerrRadialScaleArg,
            kerrAzimuthScaleArg: kerrAzimuthScaleArg,
            kerrImpactScaleArg: kerrImpactScaleArg,
            diskModelResolved: diskModelResolved,
            diskFlowTimeArg: diskFlowTimeArg,
            diskOrbitalBoostArg: diskOrbitalBoostArg,
            diskRadialDriftArg: diskRadialDriftArg,
            diskTurbulenceArg: diskTurbulenceArg,
            diskOrbitalBoostInnerArg: diskOrbitalBoostInnerArg,
            diskOrbitalBoostOuterArg: diskOrbitalBoostOuterArg,
            diskRadialDriftInnerArg: diskRadialDriftInnerArg,
            diskRadialDriftOuterArg: diskRadialDriftOuterArg,
            diskTurbulenceInnerArg: diskTurbulenceInnerArg,
            diskTurbulenceOuterArg: diskTurbulenceOuterArg,
            diskFlowStepArg: diskFlowStepArg,
            diskFlowStepsArg: diskFlowStepsArg,
            diskPhysicsModeArg: diskPhysicsModeArg,
            diskMdotEddArg: diskMdotEddArg,
            diskRadiativeEfficiencyArg: diskRadiativeEfficiencyArg,
            diskPlungeFloorArg: diskPlungeFloorArg,
            diskThickScaleArg: diskThickScaleArg,
            diskColorFactorArg: diskColorFactorArg,
            diskReturningRadArg: diskReturningRadArg,
            diskReturnBouncesArg: diskReturnBouncesArg,
            diskRTStepsArg: diskRTStepsArg,
            diskScatteringAlbedoArg: diskScatteringAlbedoArg,
            diskPrecisionTextureArg: diskPrecisionTextureArg,
            diskPrecisionCloudsEnabled: diskPrecisionCloudsEnabled,
            diskCloudCoverageArg: diskCloudCoverageArg,
            diskCloudOpticalDepthArg: diskCloudOpticalDepthArg,
            diskCloudPorosityArg: diskCloudPorosityArg,
            diskCloudShadowStrengthArg: diskCloudShadowStrengthArg,
            diskAtlasEnabled: diskAtlasEnabled,
            diskAtlasWidth: diskAtlasWidth,
            diskAtlasHeight: diskAtlasHeight,
            diskAtlasTempScaleArg: diskAtlasTempScaleArg,
            diskAtlasDensityBlendArg: diskAtlasDensityBlendArg,
            diskAtlasVrScaleArg: diskAtlasVrScaleArg,
            diskAtlasVphiScaleArg: diskAtlasVphiScaleArg,
            diskAtlasRMin: diskAtlasRMin,
            diskAtlasRMax: diskAtlasRMax,
            diskAtlasRWarp: diskAtlasRWarp,
            diskVolumeEnabled: diskVolumeEnabled,
            diskVolumeR: diskVolumeR,
            diskVolumePhi: diskVolumePhi,
            diskVolumeZ: diskVolumeZ,
            diskVolumeRMin: diskVolumeRMin,
            diskVolumeRMax: diskVolumeRMax,
            diskVolumeZMax: diskVolumeZMax,
            diskVolumeTauScaleArg: diskVolumeTauScaleArg,
            rayBundleEnabled: rayBundleEnabled,
            rayBundleActive: rayBundleActive,
            rayBundleJacobianActive: rayBundleJacobianActive,
            rayBundleJacobianStrengthArg: rayBundleJacobianStrengthArg,
            rayBundleFootprintClampArg: rayBundleFootprintClampArg,
            cameraModelName: cameraModelName,
            cameraPsfSigmaArg: cameraPsfSigmaArg,
            cameraReadNoiseArg: cameraReadNoiseArg,
            cameraShotNoiseArg: cameraShotNoiseArg,
            cameraFlareStrengthArg: cameraFlareStrengthArg,
            backgroundModeName: backgroundModeName,
            backgroundStarDensityArg: backgroundStarDensityArg,
            backgroundStarStrengthArg: backgroundStarStrengthArg,
            backgroundNebulaStrengthArg: backgroundNebulaStrengthArg,
            tileSize: tileSize,
            composeGPU: composeGPU,
            gpuFullCompose: gpuFullCompose,
            discardCollisionOutput: discardCollisionOutput,
            useLinear32Intermediate: useLinear32Intermediate,
            traceHDRDirectMode: traceHDRDirectMode,
            downsampleArg: downsampleArg,
            composeAnalysisMode: composeAnalysisMode
        )
        if diskPhysicsModeID == 3 {
            config.grmhdConfigLine = ParamsBuilderSummary.grmhdConfigLine(
                diskVol0PathResolved: diskVol0PathResolved,
                diskVol1PathResolved: diskVol1PathResolved,
                diskNuObsHzArg: diskNuObsHzArg,
                diskGrmhdDensityScaleArg: diskGrmhdDensityScaleArg,
                diskGrmhdBScaleArg: diskGrmhdBScaleArg,
                diskGrmhdEmissionScaleArg: diskGrmhdEmissionScaleArg,
                diskGrmhdAbsorptionScaleArg: diskGrmhdAbsorptionScaleArg,
                diskGrmhdVelScaleArg: diskGrmhdVelScaleArg,
                diskPolarizedRTEnabled: diskPolarizedRTEnabled,
                diskPolarizationFracArg: diskPolarizationFracArg,
                diskFaradayRotScaleArg: diskFaradayRotScaleArg,
                diskFaradayConvScaleArg: diskFaradayConvScaleArg,
                diskGrmhdDebugName: diskGrmhdDebugName
            )
            config.visibleConfigLine = ParamsBuilderSummary.visibleConfigLine(
                visibleModeEnabled: visibleModeEnabled,
                visiblePolicyName: visiblePolicyName,
                visibleSamplesArg: visibleSamplesArg,
                visibleTeffModelName: visibleTeffModelName,
                visibleTeffT0Arg: visibleTeffT0Arg,
                visibleTeffR0RsArg: visibleTeffR0RsArg,
                visibleTeffPArg: visibleTeffPArg,
                visibleBhMassArg: visibleBhMassArg,
                visibleMdotArg: visibleMdotArg,
                visibleRInRsArg: visibleRInRsArg,
                photosphereRhoThresholdResolved: photosphereRhoThresholdResolved,
                visibleEmissionModelName: visibleEmissionModelName,
                visibleSynchAlphaArg: visibleSynchAlphaArg,
                visibleKappaArg: visibleKappaArg,
                coolAbsorptionEnabled: coolAbsorptionEnabled,
                coolDustToGasArg: coolDustToGasArg,
                coolDustKappaVArg: coolDustKappaVArg,
                coolDustBetaArg: coolDustBetaArg,
                coolDustTSubArg: coolDustTSubArg,
                coolDustTWidthArg: coolDustTWidthArg,
                coolGasKappa0Arg: coolGasKappa0Arg,
                coolGasNuSlopeArg: coolGasNuSlopeArg,
                coolClumpStrengthArg: coolClumpStrengthArg,
                exposureModeName: exposureModeName,
                exposureEVArg: exposureEVArg,
                rayBundleEnabled: rayBundleEnabled,
                rayBundleActive: rayBundleActive,
                rayBundleJacobianActive: rayBundleJacobianActive,
                rayBundleJacobianStrengthArg: rayBundleJacobianStrengthArg,
                rayBundleFootprintClampArg: rayBundleFootprintClampArg
            )
        }

        var params = ParamsBuilder.buildPackedParams(from: config)
        accretionModel.buildPackedFields(into: &params, from: diskPolicy)

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
}
