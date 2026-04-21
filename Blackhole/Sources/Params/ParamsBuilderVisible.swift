import Foundation

struct VisibleSettings {
    let visibleModeName: String
    let visibleSamplesArg: Int
    let visibleTeffModelName: String
    let visibleTeffT0Arg: Double
    let visibleTeffR0RsArg: Double
    let visibleTeffPArg: Double
    let visibleBhMassArg: Double
    let visibleMdotArg: Double
    let visibleRInRsArg: Double
    let photosphereRhoThresholdArg: Double
    let visiblePolicyName: String
    let visibleEmissionModelName: String
    let visibleSynchAlphaArgRaw: Double
    let visibleKappaArg: Double
    let coolAbsorptionName: String
    let coolDustToGasArg: Double
    let coolDustKappaVArg: Double
    let coolDustBetaArg: Double
    let coolDustTSubArg: Double
    let coolDustTWidthArg: Double
    let coolGasKappa0Arg: Double
    let coolGasNuSlopeArg: Double
    let coolClumpStrengthArg: Double
    let coolAbsorptionArgsExplicit: Bool
    let visibleModeEnabled: Bool
    let visibleTeffModelID: UInt32
    let visibleExpressiveMode: Bool
    let visibleEmissionModelID: UInt32
    let visibleSynchAlphaArg: Double
    let coolAbsorptionEnabled: Bool
    let effectiveDiskPrecisionTextureArg: Double
}

enum ParamsBuilderVisible {
    static func resolveVisibleSettings(
        cliArguments: [String],
        diskPhysicsModeID: UInt32,
        diskPhysicsModeArg: String,
        diskGrmhdDebugID: UInt32,
        diskPrecisionTextureRawArg: Double
    ) -> VisibleSettings {
        let visibleModeName = stringArg("--visible-mode", default: "off").lowercased()
        let visibleSamplesArg = max(8, min(128, intArg("--visible-samples", default: 48)))
        let visibleTeffModelName = stringArg("--teff-model", default: "parametric").lowercased()
        let visibleTeffT0Arg = max(100.0, doubleArg("--teff-T0", default: 12000.0))
        let visibleTeffR0RsArg = max(1e-3, doubleArg("--teff-r0", default: 5.0))
        let visibleTeffPArg = min(max(doubleArg("--teff-p", default: 0.75), 0.05), 3.0)
        let visibleBhMassArg = max(1e20, doubleArg("--bh-mass", default: 1.0e35))
        let visibleMdotArg = max(0.0, doubleArg("--mdot", default: 1.0e15))
        let visibleRInRsArg = max(0.0, doubleArg("--r-in", default: 0.0))
        let photosphereRhoThresholdArg = max(0.0, doubleArg("--photosphere-rho-threshold", default: 0.0))
        let visiblePolicyName = stringArg("--visible-policy", default: "physical").lowercased()
        let visibleEmissionModelName = stringArg("--visible-emission-model", default: "blackbody").lowercased()
        let visibleSynchAlphaArgRaw = min(max(doubleArg("--visible-synch-alpha", default: 0.85), 0.0), 4.0)
        let visibleKappaArg = max(0.0, doubleArg("--visible-kappa", default: 0.0))
        let visibleModeRequested = ["on", "true", "1", "yes"].contains(visibleModeName)
        let coolAbsorptionName = stringArg("--disk-cool-absorption", default: ((diskPhysicsModeID == 3 && visibleModeRequested) ? "on" : "off")).lowercased()
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

        let visiblePolicy = ParamsBuilderPolicy.resolveVisiblePolicy(
            cliArguments: cliArguments,
            diskPhysicsModeID: diskPhysicsModeID,
            diskPhysicsModeArg: diskPhysicsModeArg,
            diskGrmhdDebugID: diskGrmhdDebugID,
            diskPrecisionTextureRawArg: diskPrecisionTextureRawArg,
            visibleModeName: visibleModeName,
            visibleTeffModelName: visibleTeffModelName,
            visiblePolicyName: visiblePolicyName,
            visibleEmissionModelName: visibleEmissionModelName,
            visibleSynchAlphaArg: visibleSynchAlphaArgRaw,
            coolAbsorptionName: coolAbsorptionName,
            coolAbsorptionArgsExplicit: coolAbsorptionArgsExplicit
        )

        return VisibleSettings(
            visibleModeName: visibleModeName,
            visibleSamplesArg: visibleSamplesArg,
            visibleTeffModelName: visibleTeffModelName,
            visibleTeffT0Arg: visibleTeffT0Arg,
            visibleTeffR0RsArg: visibleTeffR0RsArg,
            visibleTeffPArg: visibleTeffPArg,
            visibleBhMassArg: visibleBhMassArg,
            visibleMdotArg: visibleMdotArg,
            visibleRInRsArg: visibleRInRsArg,
            photosphereRhoThresholdArg: photosphereRhoThresholdArg,
            visiblePolicyName: visiblePolicyName,
            visibleEmissionModelName: visibleEmissionModelName,
            visibleSynchAlphaArgRaw: visibleSynchAlphaArgRaw,
            visibleKappaArg: visibleKappaArg,
            coolAbsorptionName: coolAbsorptionName,
            coolDustToGasArg: coolDustToGasArg,
            coolDustKappaVArg: coolDustKappaVArg,
            coolDustBetaArg: coolDustBetaArg,
            coolDustTSubArg: coolDustTSubArg,
            coolDustTWidthArg: coolDustTWidthArg,
            coolGasKappa0Arg: coolGasKappa0Arg,
            coolGasNuSlopeArg: coolGasNuSlopeArg,
            coolClumpStrengthArg: coolClumpStrengthArg,
            coolAbsorptionArgsExplicit: coolAbsorptionArgsExplicit,
            visibleModeEnabled: visiblePolicy.visibleModeEnabled,
            visibleTeffModelID: visiblePolicy.visibleTeffModelID,
            visibleExpressiveMode: visiblePolicy.visibleExpressiveMode,
            visibleEmissionModelID: visiblePolicy.visibleEmissionModelID,
            visibleSynchAlphaArg: visiblePolicy.visibleSynchAlphaArg,
            coolAbsorptionEnabled: visiblePolicy.coolAbsorptionEnabled,
            effectiveDiskPrecisionTextureArg: visiblePolicy.effectiveDiskPrecisionTextureArg
        )
    }
}
