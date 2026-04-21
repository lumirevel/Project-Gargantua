import Foundation
import simd

struct ResolvedRenderConfig {
    var width: Int = 0
    var height: Int = 0
    var preset: String = "balanced"
    var outPath: String = "collisions.bin"
    var linear32OutPath: String = ""
    var imageOutPath: String = ""
    var composeGPU: Bool = false
    var gpuFullCompose: Bool = false
    var discardCollisionOutput: Bool = false
    var linear32IntermediateRequested: Bool = false
    var useLinear32Intermediate: Bool = false
    var traceHDRDirectMode: String = "auto"
    var downsampleArg: Int = 1

    var metricName: String = "schwarzschild"
    var metricArg: Int32 = 0
    var spectralEncoding: String = "gfactor_v1"
    var spectralEncodingID: UInt32 = 1

    var camXFactor: Double = 0.0
    var camYFactor: Double = 0.0
    var camZFactor: Double = 0.0
    var fovDeg: Double = 90.0
    var rollDeg: Double = 0.0
    var rcp: Double = 0.0
    var diskHFactor: Double = 0.0
    var maxStepsArg: Int = 0

    var hArg: Double = 0.0
    var spinArg: Double = 0.0
    var kerrSubstepsArg: Int = 0
    var kerrTolArg: Double = 0.0
    var kerrEscapeMultArg: Double = 0.0
    var kerrRadialScaleArg: Double = 0.0
    var kerrAzimuthScaleArg: Double = 0.0
    var kerrImpactScaleArg: Double = 0.0

    var diskFlowTimeArg: Double = 0.0
    var diskOrbitalBoostArg: Double = 0.0
    var diskRadialDriftArg: Double = 0.0
    var diskTurbulenceArg: Double = 0.0
    var diskOrbitalBoostInnerArg: Double = 0.0
    var diskOrbitalBoostOuterArg: Double = 0.0
    var diskRadialDriftInnerArg: Double = 0.0
    var diskRadialDriftOuterArg: Double = 0.0
    var diskTurbulenceInnerArg: Double = 0.0
    var diskTurbulenceOuterArg: Double = 0.0
    var diskFlowStepArg: Double = 0.0
    var diskFlowStepsArg: Int = 0

    var diskPhysicsModeID: UInt32 = 0
    var diskPhysicsModeArg: String = "thin"
    var diskModelResolved: String = "flow"
    var diskNoiseModel: UInt32 = 0
    var diskMdotEddArg: Double = 0.0
    var diskRadiativeEfficiencyArg: Double = 0.0
    var diskPlungeFloorArg: Double = 0.0
    var diskThickScaleArg: Double = 0.0
    var diskColorFactorArg: Double = 0.0
    var diskReturningRadArg: Double = 0.0
    var diskPrecisionTextureArg: Double = 0.0
    var diskPrecisionCloudsEnabled: Bool = false
    var diskCloudCoverageArg: Double = 0.0
    var diskCloudOpticalDepthArg: Double = 0.0
    var diskCloudPorosityArg: Double = 0.0
    var diskCloudShadowStrengthArg: Double = 0.0
    var diskReturnBouncesArg: Int = 1
    var diskRTStepsArg: Int = 0
    var diskScatteringAlbedoArg: Double = 0.0

    var diskAtlasEnabled: Bool = false
    var diskAtlasPathArg: String = ""
    var diskAtlasWidth: Int = 1
    var diskAtlasHeight: Int = 1
    var diskAtlasWrapPhi: UInt32 = 1
    var diskAtlasTempScaleArg: Double = 1.0
    var diskAtlasDensityBlendArg: Double = 0.0
    var diskAtlasVrScaleArg: Double = 0.0
    var diskAtlasVphiScaleArg: Double = 0.0
    var diskAtlasRMin: Double = 0.0
    var diskAtlasRMax: Double = 0.0
    var diskAtlasRWarp: Double = 1.0
    var diskAtlasData: Data = Data()
    var uploadedDiskAssetBytes: Int = 0

    var diskVolumeEnabled: Bool = false
    var diskVolumeLegacyEnabled: Bool = false
    var diskVolumeGRMHDEnabled: Bool = false
    var diskVolumeThickEnabled: Bool = false
    var diskVolumeFormatArg: UInt32 = 0
    var diskVolumeR: Int = 1
    var diskVolumePhi: Int = 1
    var diskVolumeZ: Int = 1
    var diskVolumeRMin: Double = 1.0
    var diskVolumeRMax: Double = 1.0
    var diskVolumeZMax: Double = 0.35
    var diskVolumeTauScaleArg: Double = 0.0
    var diskVolume0Data: Data = Data()
    var diskVolume1Data: Data = Data()
    var diskVolumePathArg: String = ""
    var diskVol0PathResolved: String = ""
    var diskVol1PathResolved: String = ""

    var diskNuObsHzArg: Double = 0.0
    var diskGrmhdDensityScaleArg: Double = 0.0
    var diskGrmhdBScaleArg: Double = 0.0
    var diskGrmhdEmissionScaleArg: Double = 0.0
    var diskGrmhdAbsorptionScaleArg: Double = 0.0
    var diskGrmhdVelScaleArg: Double = 0.0
    var diskGrmhdDebugName: String = "off"
    var diskGrmhdDebugID: UInt32 = 0
    var diskPolarizedRTEnabled: Bool = false
    var diskPolarizationFracArg: Double = 0.0
    var diskFaradayRotScaleArg: Double = 0.0
    var diskFaradayConvScaleArg: Double = 0.0

    var visibleModeEnabled: Bool = false
    var visibleSamplesArg: Int = 0
    var visibleTeffModelName: String = "parametric"
    var visibleTeffModelID: UInt32 = 0
    var visibleTeffT0Arg: Double = 0.0
    var visibleTeffR0RsArg: Double = 0.0
    var visibleTeffPArg: Double = 0.0
    var visibleBhMassArg: Double = 0.0
    var visibleMdotArg: Double = 0.0
    var visibleRInRsArg: Double = 0.0
    var photosphereRhoThresholdResolved: Double = 0.0
    var visiblePolicyName: String = "physical"
    var visibleExpressiveMode: Bool = false
    var visibleEmissionModelName: String = "blackbody"
    var visibleEmissionModelID: UInt32 = 0
    var visibleSynchAlphaArg: Double = 0.0
    var visibleKappaArg: Double = 0.0

    var coolAbsorptionEnabled: Bool = false
    var coolDustToGasArg: Double = 0.0
    var coolDustKappaVArg: Double = 0.0
    var coolDustBetaArg: Double = 0.0
    var coolDustTSubArg: Double = 0.0
    var coolDustTWidthArg: Double = 0.0
    var coolGasKappa0Arg: Double = 0.0
    var coolGasNuSlopeArg: Double = 0.0
    var coolClumpStrengthArg: Double = 0.0

    var rayBundleEnabled: Bool = false
    var rayBundleActive: Bool = false
    var rayBundleJacobianActive: Bool = false
    var rayBundleJacobianStrengthArg: Double = 1.0
    var rayBundleFootprintClampArg: Double = 6.0

    var tileSize: Int = 0
    var traceInFlightOverrideArg: Int = 0

    var composeLook: String = "balanced"
    var composeLookID: UInt32 = 0
    var composeDitherArg: Float = 0.0
    var composeInnerEdgeArg: Float = 1.4
    var composeSpectralStepArg: Float = 5.0
    var composeChunkArg: Int = 160000
    var exposureSamplesArg: Int = 200000
    var exposureArg: Float = -1.0
    var exposureModeName: String = "auto"
    var exposureModeID: UInt32 = 0
    var exposureEVArg: Double = 0.0
    var composePrecisionName: String = "precise"
    var composePrecisionID: UInt32 = 1
    var composeAnalysisMode: UInt32 = 0
    var autoExposureEnabled: Bool = true
    var composeExposureBase: Float = 0.0
    var composeExposure: Float = 0.0
    var preserveHighlightColor: UInt32 = 0

    var cameraModelName: String = "legacy"
    var cameraModelID: UInt32 = 0
    var composeCameraModelID: UInt32 = 0
    var cameraPsfSigmaArg: Float = 0.0
    var cameraReadNoiseArg: Float = 0.0
    var cameraShotNoiseArg: Float = 0.0
    var cameraFlareStrengthArg: Float = 0.0
    var composeCameraPsfSigmaArg: Float = 0.0
    var composeCameraReadNoiseArg: Float = 0.0
    var composeCameraShotNoiseArg: Float = 0.0
    var composeCameraFlareStrengthArg: Float = 0.0

    var backgroundModeName: String = "off"
    var backgroundModeID: UInt32 = 0
    var backgroundStarDensityArg: Float = 0.0
    var backgroundStarStrengthArg: Float = 0.0
    var backgroundNebulaStrengthArg: Float = 0.0

    var c: Double = 0.0
    var G: Double = 0.0
    var k: Double = 0.0
    var M: Double = 0.0
    var rsD: Double = 0.0
    var reD: Double = 0.0
    var heD: Double = 0.0
    var visibleTeffR0Meters: Double = 0.0
    var visibleRInMeters: Double = 0.0
    var diskInnerRadiusCompose: Double = 0.0
    var diskHorizonRadiusCompose: Double = 0.0
    var camPos: SIMD3<Float> = .zero
    var z: SIMD3<Float> = .zero
    var planeX: SIMD3<Float> = .zero
    var planeY: SIMD3<Float> = .zero
    var d: Float = 0.0

    var renderConfigLine: String = ""
    var grmhdConfigLine: String = ""
    var visibleConfigLine: String = ""
}
