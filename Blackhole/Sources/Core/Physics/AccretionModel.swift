import Foundation

struct DiskPolicyInput {
    let diskHFactor: Double
    let hasDiskVolumeArg: Bool
    let precisionThinProfile: Bool
    let plungeFloorRawArg: Double
    let plungeFloorExplicit: Bool
    let thickScaleRawArg: Double
    let thickScaleExplicit: Bool
    let colorFactorRawArg: Double
    let colorFactorExplicit: Bool
    let returningRadRawArg: Double
    let returningRadExplicit: Bool
    let precisionTextureRawArg: Double
    let precisionTextureExplicit: Bool
    let precisionCloudsEnabled: Bool
    let cloudCoverageRawArg: Double
    let cloudCoverageExplicit: Bool
    let cloudOpticalDepthRawArg: Double
    let cloudOpticalDepthExplicit: Bool
    let cloudPorosityRawArg: Double
    let cloudPorosityExplicit: Bool
    let cloudShadowStrengthRawArg: Double
    let cloudShadowStrengthExplicit: Bool
    let returnBouncesRawArg: Int
    let returnBouncesExplicit: Bool
    let rtStepsRawArg: Int
    let rtStepsExplicit: Bool
    let scatteringAlbedoRawArg: Double
    let scatteringAlbedoExplicit: Bool
}

struct DiskPolicyOutput {
    let plungeFloor: Double
    let thickScale: Double
    let colorFactor: Double
    let returningRad: Double
    let precisionTexture: Double
    let cloudCoverage: Double
    let cloudOpticalDepth: Double
    let cloudPorosity: Double
    let cloudShadowStrength: Double
    let returnBounces: Int
    let rtSteps: Int
    let scatteringAlbedo: Double
    let thickCloudExplicit: Bool
    let precisionCloudsEnabled: Bool
    let warnings: [String]
    let infos: [String]
}

protocol AccretionModel {
    var id: UInt32 { get }
    var name: String { get }
    func applyDefaults(input: DiskPolicyInput) -> DiskPolicyOutput
    func validate(output: DiskPolicyOutput) throws
    func buildPackedFields(into packed: inout PackedParams, from output: DiskPolicyOutput)
}

extension AccretionModel {
    func validate(output _: DiskPolicyOutput) throws {}

    func buildPackedFields(into packed: inout PackedParams, from output: DiskPolicyOutput) {
        packed.diskPlungeFloor = Float(output.plungeFloor)
        packed.diskThickScale = Float(output.thickScale)
        packed.diskColorFactor = Float(output.colorFactor)
        packed.diskReturningRad = Float(output.returningRad)
        packed.diskPrecisionTexture = Float(output.precisionTexture)
        packed.diskCloudCoverage = Float(output.cloudCoverage)
        packed.diskCloudOpticalDepth = Float(output.cloudOpticalDepth)
        packed.diskCloudPorosity = Float(output.cloudPorosity)
        packed.diskCloudShadowStrength = Float(output.cloudShadowStrength)
        packed.diskReturnBounces = UInt32(output.returnBounces)
        packed.diskRTSteps = UInt32(output.rtSteps)
        packed.diskScatteringAlbedo = Float(output.scatteringAlbedo)
    }
}

private func precisionDefaults(for input: DiskPolicyInput) -> (plungeFloor: Double, thickScale: Double, cloudCoverage: Double, cloudTau: Double, cloudPorosity: Double, cloudShadow: Double, scatteringAlbedo: Double, returningRad: Double, precisionTexture: Double, returnBounces: Int) {
    let adaptive = precisionAdaptiveDefaults(diskH: input.diskHFactor)
    let hasVolume = input.hasDiskVolumeArg
    return (
        plungeFloor: adaptive.plungeFloor,
        thickScale: adaptive.thickScale,
        cloudCoverage: hasVolume ? 0.58 : 0.88,
        cloudTau: hasVolume ? 1.10 : 2.0,
        cloudPorosity: hasVolume ? 0.42 : 0.18,
        cloudShadow: hasVolume ? 0.62 : 0.90,
        scatteringAlbedo: hasVolume ? 0.52 : 0.62,
        returningRad: 0.35,
        precisionTexture: 0.58,
        returnBounces: 2
    )
}

struct LegacyAccretionModel: AccretionModel {
    let id: UInt32 = 0
    let name: String = "legacy"

    func applyDefaults(input: DiskPolicyInput) -> DiskPolicyOutput {
        var warnings: [String] = []
        if input.returningRadRawArg > 1e-8 {
            warnings.append("warn: --disk-returning-rad is only active in precision mode")
        }
        if input.cloudCoverageRawArg > 1e-8 || input.cloudOpticalDepthRawArg > 1e-8 || input.cloudPorosityRawArg > 1e-8 || input.cloudShadowStrengthRawArg > 1e-8 {
            warnings.append("warn: cloud args are active in precision mode, or thick mode when --cloud-tau is set")
        }
        if input.returnBouncesRawArg != 1 || input.rtStepsRawArg > 0 || input.scatteringAlbedoRawArg > 1e-8 {
            warnings.append("warn: --disk-return-bounces is precision-only; --rt-steps/--disk-scattering-albedo are active in precision or thick-with-cloud-tau")
        }
        return DiskPolicyOutput(
            plungeFloor: 0.0,
            thickScale: 1.0,
            colorFactor: input.colorFactorExplicit ? input.colorFactorRawArg : 1.0,
            returningRad: 0.0,
            precisionTexture: 0.0,
            cloudCoverage: 0.0,
            cloudOpticalDepth: 0.0,
            cloudPorosity: 0.0,
            cloudShadowStrength: 0.0,
            returnBounces: 1,
            rtSteps: 0,
            scatteringAlbedo: 0.0,
            thickCloudExplicit: false,
            precisionCloudsEnabled: false,
            warnings: warnings,
            infos: []
        )
    }
}

struct ThickAccretionModel: AccretionModel {
    let id: UInt32 = 1
    let name: String = "thick"

    func applyDefaults(input: DiskPolicyInput) -> DiskPolicyOutput {
        let thickCloudExplicit = input.cloudOpticalDepthExplicit
        var warnings: [String] = []
        if input.returningRadRawArg > 1e-8 {
            warnings.append("warn: --disk-returning-rad is only active in precision mode")
        }
        if !thickCloudExplicit && (input.cloudCoverageRawArg > 1e-8 || input.cloudOpticalDepthRawArg > 1e-8 || input.cloudPorosityRawArg > 1e-8 || input.cloudShadowStrengthRawArg > 1e-8) {
            warnings.append("warn: cloud args are active in precision mode, or thick mode when --cloud-tau is set")
        }
        return DiskPolicyOutput(
            plungeFloor: input.plungeFloorExplicit ? input.plungeFloorRawArg : 0.02,
            thickScale: input.thickScaleExplicit ? input.thickScaleRawArg : 1.3,
            colorFactor: input.colorFactorExplicit ? input.colorFactorRawArg : 1.0,
            returningRad: 0.0,
            precisionTexture: 0.0,
            cloudCoverage: thickCloudExplicit ? max(input.cloudCoverageRawArg, 0.55) : 0.0,
            cloudOpticalDepth: thickCloudExplicit ? input.cloudOpticalDepthRawArg : 0.0,
            cloudPorosity: thickCloudExplicit ? max(input.cloudPorosityRawArg, 0.20) : 0.0,
            cloudShadowStrength: thickCloudExplicit ? max(input.cloudShadowStrengthRawArg, 0.55) : 0.0,
            returnBounces: 1,
            rtSteps: input.rtStepsRawArg,
            scatteringAlbedo: thickCloudExplicit ? input.scatteringAlbedoRawArg : 0.0,
            thickCloudExplicit: thickCloudExplicit,
            precisionCloudsEnabled: false,
            warnings: warnings,
            infos: []
        )
    }
}

struct ThinPrecisionAccretionModel: AccretionModel {
    let id: UInt32 = 2
    let name: String = "thin"

    func applyDefaults(input: DiskPolicyInput) -> DiskPolicyOutput {
        let defaults = precisionDefaults(for: input)
        return DiskPolicyOutput(
            plungeFloor: input.plungeFloorExplicit ? input.plungeFloorRawArg : (input.precisionThinProfile ? 0.0 : defaults.plungeFloor),
            thickScale: input.thickScaleExplicit ? input.thickScaleRawArg : (input.precisionThinProfile ? 1.0 : defaults.thickScale),
            colorFactor: input.colorFactorExplicit ? input.colorFactorRawArg : 1.7,
            returningRad: input.returningRadExplicit ? input.returningRadRawArg : (input.precisionThinProfile ? 0.0 : defaults.returningRad),
            precisionTexture: input.precisionTextureExplicit ? input.precisionTextureRawArg : (input.precisionThinProfile ? 0.0 : defaults.precisionTexture),
            cloudCoverage: input.precisionCloudsEnabled ? (input.cloudCoverageExplicit ? input.cloudCoverageRawArg : defaults.cloudCoverage) : 0.0,
            cloudOpticalDepth: input.precisionCloudsEnabled ? (input.cloudOpticalDepthExplicit ? input.cloudOpticalDepthRawArg : defaults.cloudTau) : 0.0,
            cloudPorosity: input.precisionCloudsEnabled ? (input.cloudPorosityExplicit ? input.cloudPorosityRawArg : defaults.cloudPorosity) : 0.0,
            cloudShadowStrength: input.precisionCloudsEnabled ? (input.cloudShadowStrengthExplicit ? input.cloudShadowStrengthRawArg : defaults.cloudShadow) : 0.0,
            returnBounces: input.returnBouncesExplicit ? input.returnBouncesRawArg : (input.precisionThinProfile ? 1 : defaults.returnBounces),
            rtSteps: input.rtStepsRawArg,
            scatteringAlbedo: input.scatteringAlbedoExplicit ? input.scatteringAlbedoRawArg : defaults.scatteringAlbedo,
            thickCloudExplicit: false,
            precisionCloudsEnabled: input.precisionCloudsEnabled,
            warnings: [],
            infos: []
        )
    }
}

struct EHTAccretionModel: AccretionModel {
    let id: UInt32 = 3
    let name: String = "eht"

    func applyDefaults(input: DiskPolicyInput) -> DiskPolicyOutput {
        var warnings: [String] = []
        if input.returningRadRawArg > 1e-8 {
            warnings.append("warn: --disk-returning-rad is only active in precision mode")
        }
        if input.cloudCoverageRawArg > 1e-8 || input.cloudOpticalDepthRawArg > 1e-8 || input.cloudPorosityRawArg > 1e-8 || input.cloudShadowStrengthRawArg > 1e-8 {
            warnings.append("warn: cloud args are active in precision mode, or thick mode when --cloud-tau is set")
        }
        return DiskPolicyOutput(
            plungeFloor: input.plungeFloorExplicit ? input.plungeFloorRawArg : 0.0,
            thickScale: input.thickScaleExplicit ? input.thickScaleRawArg : 1.0,
            colorFactor: input.colorFactorExplicit ? input.colorFactorRawArg : 1.0,
            returningRad: 0.0,
            precisionTexture: 0.0,
            cloudCoverage: 0.0,
            cloudOpticalDepth: 0.0,
            cloudPorosity: 0.0,
            cloudShadowStrength: 0.0,
            returnBounces: 1,
            rtSteps: input.rtStepsRawArg,
            scatteringAlbedo: 0.0,
            thickCloudExplicit: false,
            precisionCloudsEnabled: false,
            warnings: warnings,
            infos: [],
        )
    }
}

enum AccretionModels {
    static let legacy: any AccretionModel = LegacyAccretionModel()
    static let thick: any AccretionModel = ThickAccretionModel()
    static let thin: any AccretionModel = ThinPrecisionAccretionModel()
    static let eht: any AccretionModel = EHTAccretionModel()

    static func model(for physicsModeID: UInt32) -> any AccretionModel {
        switch physicsModeID {
        case 1: return thick
        case 2: return thin
        case 3: return eht
        default: return legacy
        }
    }
}
