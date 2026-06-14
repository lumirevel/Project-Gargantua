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
    let visibleSynchScaleArg: Double
    let visibleKappaArg: Double
    let grmhdBranchIsolationName: String
    let grmhdBranchIsolationID: UInt32
    let grmhdTransportAlphaScaleArg: Double
    let grmhdSmoothEmissionScaleArg: Double
    let grmhdCloudEmissionScaleArg: Double
    let grmhdSmoothWeightName: String
    let grmhdSmoothWeightModeID: UInt32
    let thinPhotosphereEnabled: Bool
    let thinRadialTaperEnabled: Bool
    let thinHOverRBaseArg: Double
    let thinHOverRInnerArg: Double
    let thinHOverROuterArg: Double
    let thinWeightPowerEmissionArg: Double
    let thinWeightPowerAbsorptionArg: Double
    let coronaLayerEnabled: Bool
    let coronaHOverRArg: Double
    let coronaWeightPowerArg: Double
    let visibleThermalTransferModeID: UInt32
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
    static func calibratedGRMHDHybridT0(
        blackHoleMass: Double,
        mdot: Double,
        r0Meters: Double,
        rInMeters: Double
    ) -> Double? {
        guard blackHoleMass.isFinite,
              mdot.isFinite,
              r0Meters.isFinite,
              rInMeters.isFinite,
              blackHoleMass > 0.0,
              mdot > 0.0,
              r0Meters > rInMeters,
              rInMeters > 0.0 else {
            return nil
        }

        // Newtonian thin-disk Teff normalization used only to calibrate the
        // GRMHD-hybrid color-temperature anchor when the user supplies explicit
        // physical M and Mdot. The shader still applies GRMHD state modulation and
        // relativistic transport; this avoids silently treating T0 as an arbitrary
        // color knob when physical units are available.
        let sigmaSB = 5.670374419e-8
        let gravitationalConstant = 6.67430e-11
        let boundary = max(1.0 - sqrt(rInMeters / r0Meters), 0.0)
        guard boundary > 0.0 else { return nil }

        let t4 = (3.0 * gravitationalConstant * blackHoleMass * mdot * boundary)
            / max(8.0 * Double.pi * sigmaSB * pow(r0Meters, 3.0), 1e-300)
        guard t4.isFinite, t4 > 0.0 else { return nil }
        return min(max(pow(t4, 0.25), 100.0), 5.0e7)
    }

    static func resolveVisibleSettings(
        cliArguments: [String],
        diskPhysicsModeID: UInt32,
        diskPhysicsModeArg: String,
        diskGrmhdDebugID: UInt32,
        diskPrecisionTextureRawArg: Double
    ) -> VisibleSettings {
        let visibleModeName = stringArg("--visible-mode", default: "off").lowercased()
        let visibleSamplesArg = max(8, min(128, intArg("--visible-samples", default: 48)))
        let visibleTeffModelNameRaw = stringArg("--teff-model", default: "parametric").lowercased()
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
        let visibleModeRequested = ["on", "true", "1", "yes"].contains(visibleModeName)
        let visibleSynchScaleDefault = (
            diskPhysicsModeID == 3 &&
            visibleModeRequested &&
            visibleEmissionModelName == "hybrid"
        ) ? 20.0 : 1.0
        let visibleSynchScaleArg = max(0.0, doubleArg("--visible-synch-scale", default: visibleSynchScaleDefault))
        let visibleKappaArg = max(0.0, doubleArg("--visible-kappa", default: 0.0))
        let grmhdBranchIsolationName = stringArg("--grmhd-branch-isolation", default: "off").lowercased()
        let grmhdBranchIsolationID: UInt32
        switch grmhdBranchIsolationName {
        case "off", "none", "baseline", "total":
            grmhdBranchIsolationID = 0
        case "smooth", "smooth-thermal", "continuum":
            grmhdBranchIsolationID = 1
        case "cloud", "cloud-thermal", "structured", "skin":
            grmhdBranchIsolationID = 2
        case "body", "photosphere":
            grmhdBranchIsolationID = 3
        case "skin-thermal", "structured-skin":
            grmhdBranchIsolationID = 4
        case "corona", "thin":
            grmhdBranchIsolationID = 5
        default:
            fail("invalid --grmhd-branch-isolation \(grmhdBranchIsolationName). use off|smooth|cloud|body|skin|corona")
        }
        let grmhdTransportAlphaScaleArg = max(0.0, doubleArg("--grmhd-transport-alpha-scale", default: 1.0))
        let grmhdSmoothEmissionScaleArg = max(0.0, doubleArg("--grmhd-smooth-emission-scale", default: 1.0))
        let grmhdCloudEmissionScaleArg = max(0.0, doubleArg("--grmhd-cloud-emission-scale", default: 1.0))
        let grmhdSmoothWeightDefault = (
            diskPhysicsModeID == 3 &&
            visibleModeRequested &&
            visiblePolicyName == "physical" &&
            visibleEmissionModelName == "blackbody"
        ) ? "state" : "constant"
        let grmhdSmoothWeightName = stringArg("--grmhd-smooth-weight", default: grmhdSmoothWeightDefault).lowercased()
        let grmhdSmoothWeightModeID: UInt32
        switch grmhdSmoothWeightName {
        case "off", "none", "constant", "legacy", "baseline":
            grmhdSmoothWeightModeID = 0
        case "state", "state-dependent", "physical":
            grmhdSmoothWeightModeID = 1
        case "body", "body-source", "photosphere", "layer", "emission-layer":
            grmhdSmoothWeightModeID = 2
        case "state-body", "combined", "state-layer", "state*layer":
            grmhdSmoothWeightModeID = 3
        case "plasma-body", "body-plasma", "state-plasma", "photosphere-skin":
            grmhdSmoothWeightModeID = 4
        case "positive-plasma", "emissive-plasma", "positive-skin", "plasma-positive":
            grmhdSmoothWeightModeID = 5
        case "hot-skin", "synchrotron-skin", "thin-hot-skin":
            grmhdSmoothWeightModeID = 6
        case "hot-skin-b", "hot-skin-strong-b", "synchrotron-skin-b":
            grmhdSmoothWeightModeID = 7
        case "hot-skin-theta", "hot-skin-strong-theta", "synchrotron-skin-theta":
            grmhdSmoothWeightModeID = 8
        case "hot-skin-corona", "synchrotron-skin-corona":
            grmhdSmoothWeightModeID = 9
        case "hybrid-visible-disk", "hybrid-disk", "visible-disk-hybrid":
            grmhdSmoothWeightModeID = 10
        case "hybrid-visible-disk-shallow", "hybrid-disk-shallow":
            grmhdSmoothWeightModeID = 11
        case "hybrid-visible-disk-structured", "hybrid-visible-disk-skin", "hybrid-disk-structured":
            grmhdSmoothWeightModeID = 12
        case "hybrid-visible-disk-corona", "hybrid-disk-corona":
            grmhdSmoothWeightModeID = 13
        case "visible-reference-skin", "reference-skin", "thin-reference-skin", "source-reference-skin":
            grmhdSmoothWeightModeID = 14
        case "visible-reference-skin-corona", "reference-skin-corona", "thin-reference-skin-corona":
            grmhdSmoothWeightModeID = 15
        default:
            fail("invalid --grmhd-smooth-weight \(grmhdSmoothWeightName). use constant|state|body|state-body|plasma-body|positive-plasma|hot-skin|hybrid-visible-disk|visible-reference-skin")
        }
        let thinPhotosphereName = stringArg("--thin-photosphere", default: "auto").lowercased()
        let thinPhotosphereAuto = (
            diskPhysicsModeID == 3 &&
            visibleModeRequested &&
            visiblePolicyName == "physical" &&
            (visibleEmissionModelName == "blackbody" || visibleEmissionModelName == "hybrid")
        )
        let thinPhotosphereEnabled: Bool
        switch thinPhotosphereName {
        case "auto":
            thinPhotosphereEnabled = thinPhotosphereAuto
        case "on", "true", "1", "yes":
            thinPhotosphereEnabled = true
        case "off", "false", "0", "no":
            thinPhotosphereEnabled = false
        default:
            fail("invalid --thin-photosphere \(thinPhotosphereName). use auto|on|off")
        }
        let thinRadialTaperName = stringArg("--thin-radial-taper", default: "on").lowercased()
        let thinRadialTaperEnabled: Bool
        switch thinRadialTaperName {
        case "on", "true", "1", "yes":
            thinRadialTaperEnabled = true
        case "off", "false", "0", "no":
            thinRadialTaperEnabled = false
        default:
            fail("invalid --thin-radial-taper \(thinRadialTaperName). use on|off")
        }
        let thinHOverRBaseArg = min(max(doubleArg("--thin-h-over-r-base", default: 0.03), 0.002), 0.5)
        let thinHOverRInnerArg = min(max(doubleArg("--thin-h-over-r-inner", default: 0.02), 0.002), 0.5)
        let thinHOverROuterArg = min(max(doubleArg("--thin-h-over-r-outer", default: 0.045), 0.002), 0.5)
        let thinWeightPowerEmissionArg = min(max(doubleArg("--thin-weight-power-emission", default: 1.0), 0.0), 8.0)
        let defaultThinAbsorptionPower = (
            diskPhysicsModeID == 3 &&
            visibleModeRequested &&
            visiblePolicyName == "physical" &&
            (visibleEmissionModelName == "blackbody" || visibleEmissionModelName == "hybrid")
        ) ? 2.5 : 1.0
        let thinWeightPowerAbsorptionArg = min(max(doubleArg("--thin-weight-power-absorption", default: defaultThinAbsorptionPower), 0.0), 8.0)
        let coronaLayerName = stringArg("--corona-layer", default: "auto").lowercased()
        let coronaLayerAuto = (
            diskPhysicsModeID == 3 &&
            visibleModeRequested &&
            visiblePolicyName == "physical" &&
            visibleEmissionModelName == "hybrid"
        )
        let coronaLayerEnabled: Bool
        switch coronaLayerName {
        case "auto":
            coronaLayerEnabled = coronaLayerAuto
        case "on", "true", "1", "yes":
            coronaLayerEnabled = true
        case "off", "false", "0", "no":
            coronaLayerEnabled = false
        default:
            fail("invalid --corona-layer \(coronaLayerName). use auto|on|off")
        }
        let coronaHOverRArg = min(max(doubleArg("--corona-h-over-r", default: 0.12), 0.01), 2.0)
        let coronaWeightPowerArg = min(max(doubleArg("--corona-weight-power", default: 1.0), 0.0), 8.0)
        let thermalTransferName = stringArg("--thermal-transfer-mode", default: "auto").lowercased()
        let thermalTransferAuto = (
            diskPhysicsModeID == 3 &&
            visibleModeRequested &&
            visiblePolicyName == "physical" &&
            visibleEmissionModelName == "blackbody"
        )
        let visibleThermalTransferModeID: UInt32
        switch thermalTransferName {
        case "auto":
            visibleThermalTransferModeID = thermalTransferAuto ? 1 : 0
        case "volume", "rt", "volume-rt":
            visibleThermalTransferModeID = 0
        case "tau-surface", "surface", "photosphere", "tau1", "tau-one":
            visibleThermalTransferModeID = 1
        default:
            fail("invalid --thermal-transfer-mode \(thermalTransferName). use auto|volume|tau-surface")
        }
        let visibleTeffModelName = (
            diskPhysicsModeID == 3 &&
            visibleModeRequested &&
            visiblePolicyName == "physical" &&
            (visibleEmissionModelName == "blackbody" || visibleEmissionModelName == "hybrid") &&
            !cliArguments.contains("--teff-model")
        ) ? "grmhd-hybrid" : visibleTeffModelNameRaw
        // Default GRMHD visible thermal rendering should not add a separate
        // cold dust/gas occluder. Dense hot gas must emit through the same
        // thermal RT closure; cool absorption is an explicit experiment only.
        let defaultCoolAbsorption = "off"
        let coolAbsorptionName = stringArg("--disk-cool-absorption", default: defaultCoolAbsorption).lowercased()
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
            visibleSynchScaleArg: visibleSynchScaleArg,
            visibleKappaArg: visibleKappaArg,
            grmhdBranchIsolationName: grmhdBranchIsolationName,
            grmhdBranchIsolationID: grmhdBranchIsolationID,
            grmhdTransportAlphaScaleArg: grmhdTransportAlphaScaleArg,
            grmhdSmoothEmissionScaleArg: grmhdSmoothEmissionScaleArg,
            grmhdCloudEmissionScaleArg: grmhdCloudEmissionScaleArg,
            grmhdSmoothWeightName: grmhdSmoothWeightName,
            grmhdSmoothWeightModeID: grmhdSmoothWeightModeID,
            thinPhotosphereEnabled: thinPhotosphereEnabled,
            thinRadialTaperEnabled: thinRadialTaperEnabled,
            thinHOverRBaseArg: thinHOverRBaseArg,
            thinHOverRInnerArg: thinHOverRInnerArg,
            thinHOverROuterArg: thinHOverROuterArg,
            thinWeightPowerEmissionArg: thinWeightPowerEmissionArg,
            thinWeightPowerAbsorptionArg: thinWeightPowerAbsorptionArg,
            coronaLayerEnabled: coronaLayerEnabled,
            coronaHOverRArg: coronaHOverRArg,
            coronaWeightPowerArg: coronaWeightPowerArg,
            visibleThermalTransferModeID: visibleThermalTransferModeID,
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
