import Foundation

struct VisiblePolicyResolution {
    let visibleModeEnabled: Bool
    let visibleTeffModelID: UInt32
    let visibleExpressiveMode: Bool
    let visibleEmissionModelID: UInt32
    let visibleSynchAlphaArg: Double
    let coolAbsorptionEnabled: Bool
    let effectiveDiskPrecisionTextureArg: Double
}

struct RayBundlePolicyResolution {
    let rayBundleEnabled: Bool
    let rayBundleJacobianEnabled: Bool
    let rayBundleActive: Bool
    let rayBundleJacobianActive: Bool
}

struct ComposePolicyResolution {
    let composeAnalysisMode: UInt32
    let composeCameraModelID: UInt32
    let composeCameraPsfSigmaArg: Float
    let composeCameraReadNoiseArg: Float
    let composeCameraShotNoiseArg: Float
    let composeCameraFlareStrengthArg: Float
}

struct DiskModelResolution {
    let diskModelResolved: String
    let diskAtlasEnabled: Bool
    let diskNoiseModel: UInt32
}

struct GRMHDPolicyResolution {
    let diskGrmhdDebugID: UInt32
    let diskPolarizedRTEnabled: Bool
}

struct VolumeModeResolution {
    let diskVolumeTauScaleArg: Double
    let diskVolumeFormatArg: UInt32
    let diskVolumeLegacyEnabled: Bool
    let diskVolumeGRMHDEnabled: Bool
    let diskVolumeThickEnabled: Bool
    let diskVolumeEnabled: Bool
}

struct DiskPhysicsSelectionResolution {
    let diskPhysicsModeID: UInt32
    let diskPhysicsModeArg: String
    let diskPhysicsThinProfile: Bool
    let hasDiskVolumeArg: Bool
    let diskModeUsesAutoAlias: Bool
}

enum ParamsBuilderPolicy {
    static func resolveDiskPhysicsSelection(
        cliArguments: [String],
        diskModeRaw: String,
        diskPhysicsProfileRaw: String,
        diskPhysicsLegacyRaw: String
    ) -> DiskPhysicsSelectionResolution {
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
                return diskPhysicsLegacyRaw
            }
            return "thin"
        }()

        guard let diskModeParsed = parseDiskMode(diskModeResolvedRaw) else {
            if !diskModeRaw.isEmpty {
                fail("invalid --disk-mode \(diskModeRaw). use one of: thin, thick, precision, grmhd, auto")
            }
            fail("invalid --disk-physics-mode \(diskPhysicsLegacyRaw). use one of: thin, thick, precision, grmhd, auto")
        }

        var diskPhysicsModeID = diskModeParsed.id
        var diskPhysicsModeArg = diskModeParsed.canonical
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

        let diskModeUsesAutoAlias = ["auto", "unified", "adaptive", "smart"].contains(diskModeResolvedRaw)
        if diskModeUsesAutoAlias {
            FileHandle.standardError.write(
                Data("info: --disk-mode auto resolves to precision with diskH-adaptive thin/thick defaults\n".utf8)
            )
        }

        return DiskPhysicsSelectionResolution(
            diskPhysicsModeID: diskPhysicsModeID,
            diskPhysicsModeArg: diskPhysicsModeArg,
            diskPhysicsThinProfile: (!diskPhysicsProfileRaw.isEmpty && diskPhysicsModeArg == "thin"),
            hasDiskVolumeArg: cliArguments.contains("--disk-volume")
                || cliArguments.contains("--disk-vol0")
                || cliArguments.contains("--disk-vol1"),
            diskModeUsesAutoAlias: diskModeUsesAutoAlias
        )
    }

    static func resolveVisiblePolicy(
        cliArguments: [String],
        diskPhysicsModeID: UInt32,
        diskPhysicsModeArg: String,
        diskGrmhdDebugID: UInt32,
        diskPrecisionTextureRawArg: Double,
        visibleModeName: String,
        visibleTeffModelName: String,
        visiblePolicyName: String,
        visibleEmissionModelName: String,
        visibleSynchAlphaArg initialVisibleSynchAlphaArg: Double,
        coolAbsorptionName: String,
        coolAbsorptionArgsExplicit: Bool
    ) -> VisiblePolicyResolution {
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

        let visibleExpressiveMode: Bool
        switch visiblePolicyName {
        case "physical":
            visibleExpressiveMode = false
        case "expressive", "cinematic":
            visibleExpressiveMode = true
        default:
            fail("invalid --visible-policy \(visiblePolicyName). use one of: physical, expressive")
        }

        var visibleEmissionModelID: UInt32
        switch visibleEmissionModelName {
        case "blackbody", "thermal":
            visibleEmissionModelID = 0
        case "synchrotron", "powerlaw", "power-law":
            visibleEmissionModelID = 1
        default:
            fail("invalid --visible-emission-model \(visibleEmissionModelName). use one of: blackbody, synchrotron")
        }

        var visibleSynchAlphaArg = initialVisibleSynchAlphaArg
        if diskPhysicsModeID == 3 && visibleModeEnabled && visibleExpressiveMode {
            FileHandle.standardError.write(Data("info: --visible-policy expressive maps nu_obs emissivity to visible palette for readability\n".utf8))
            if !cliArguments.contains("--visible-emission-model") {
                visibleEmissionModelID = 1
            }
            if !cliArguments.contains("--visible-synch-alpha") {
                visibleSynchAlphaArg = 0.85
            }
        }

        let coolAbsorptionEnabled: Bool
        switch coolAbsorptionName {
        case "on", "true", "1", "yes":
            coolAbsorptionEnabled = true
        case "off", "false", "0", "no":
            coolAbsorptionEnabled = false
        default:
            fail("invalid --disk-cool-absorption \(coolAbsorptionName). use on|off")
        }
        if !(diskPhysicsModeID == 3 && visibleModeEnabled) && (coolAbsorptionEnabled || coolAbsorptionArgsExplicit) {
            FileHandle.standardError.write(Data("warn: cool gas/dust absorption args are active only in grmhd visible mode\n".utf8))
        }

        let effectiveDiskPrecisionTextureArg: Double
        if diskPhysicsModeID == 3 && visibleModeEnabled {
            if cliArguments.contains("--disk-precision-texture") {
                effectiveDiskPrecisionTextureArg = diskPrecisionTextureRawArg
            } else {
                effectiveDiskPrecisionTextureArg = 0.58
            }
        } else {
            effectiveDiskPrecisionTextureArg = diskPrecisionTextureRawArg
            if diskPhysicsModeID != 2 && diskPrecisionTextureRawArg > 1e-8 {
                FileHandle.standardError.write(Data("warn: --disk-precision-texture is active in precision mode and grmhd visible mode only\n".utf8))
            }
        }

        if diskPhysicsModeID != 3 && diskGrmhdDebugID != 0 {
            FileHandle.standardError.write(Data("warn: --disk-grmhd-debug is only active in grmhd mode\n".utf8))
        }

        return VisiblePolicyResolution(
            visibleModeEnabled: visibleModeEnabled,
            visibleTeffModelID: visibleTeffModelID,
            visibleExpressiveMode: visibleExpressiveMode,
            visibleEmissionModelID: visibleEmissionModelID,
            visibleSynchAlphaArg: visibleSynchAlphaArg,
            coolAbsorptionEnabled: coolAbsorptionEnabled,
            effectiveDiskPrecisionTextureArg: effectiveDiskPrecisionTextureArg
        )
    }

    static func resolveRayBundlePolicy(
        cliArguments: [String],
        diskPhysicsModeID: UInt32,
        visibleModeEnabled: Bool,
        diskGrmhdDebugID: UInt32,
        rayBundleName: String,
        rayBundleJacobianName: String
    ) -> RayBundlePolicyResolution {
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

        let rayBundleJacobianEnabled: Bool
        switch rayBundleJacobianName {
        case "on", "true", "1", "yes":
            rayBundleJacobianEnabled = true
        case "off", "false", "0", "no":
            rayBundleJacobianEnabled = false
        default:
            fail("invalid --ray-bundle-jacobian \(rayBundleJacobianName). use on|off")
        }

        let hasRayBundleJacobianArg = cliArguments.contains("--ray-bundle-jacobian")
        if rayBundleJacobianRequestedByMode && hasRayBundleJacobianArg && !rayBundleJacobianEnabled {
            FileHandle.standardError.write(Data("warn: --ray-bundle jacobian was overridden by explicit --ray-bundle-jacobian off\n".utf8))
        }

        let rayBundleEligible = (diskPhysicsModeID == 3 && visibleModeEnabled && diskGrmhdDebugID == 0)
        let rayBundleActive = rayBundleEnabled && rayBundleEligible
        let rayBundleJacobianActive = rayBundleActive && rayBundleJacobianEnabled
        if rayBundleEnabled && !rayBundleEligible {
            FileHandle.standardError.write(Data("warn: --ray-bundle is currently applied only for grmhd visible mode (--disk-mode grmhd --visible-mode on --disk-grmhd-debug off); falling back to single-ray path\n".utf8))
        }

        return RayBundlePolicyResolution(
            rayBundleEnabled: rayBundleEnabled,
            rayBundleJacobianEnabled: rayBundleJacobianEnabled,
            rayBundleActive: rayBundleActive,
            rayBundleJacobianActive: rayBundleJacobianActive
        )
    }

    static func resolveComposePolicy(
        diskPhysicsModeID: UInt32,
        diskPrecisionCloudsEnabled: Bool,
        diskGrmhdDebugID: UInt32,
        cameraModelID: UInt32,
        cameraPsfSigmaArg: Float,
        cameraReadNoiseArg: Float,
        cameraShotNoiseArg: Float,
        cameraFlareStrengthArg: Float
    ) -> ComposePolicyResolution {
        let composeAnalysisMode: UInt32 = {
            if diskPhysicsModeID == 2 { return diskPrecisionCloudsEnabled ? 2 : 1 }
            if diskPhysicsModeID == 3 && diskGrmhdDebugID != 0 { return 10 + diskGrmhdDebugID }
            return 0
        }()

        return ComposePolicyResolution(
            composeAnalysisMode: composeAnalysisMode,
            composeCameraModelID: (composeAnalysisMode == 0) ? cameraModelID : 0,
            composeCameraPsfSigmaArg: (composeAnalysisMode == 0) ? cameraPsfSigmaArg : 0.0,
            composeCameraReadNoiseArg: (composeAnalysisMode == 0) ? cameraReadNoiseArg : 0.0,
            composeCameraShotNoiseArg: (composeAnalysisMode == 0) ? cameraShotNoiseArg : 0.0,
            composeCameraFlareStrengthArg: (composeAnalysisMode == 0) ? cameraFlareStrengthArg : 0.0
        )
    }

    static func resolveGRMHDPolicy(
        diskPhysicsModeID: UInt32,
        diskGrmhdDebugName: String,
        diskPolarizedRTName: String,
        diskFaradayRotScaleArg: Double,
        diskFaradayConvScaleArg: Double
    ) -> GRMHDPolicyResolution {
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

        let diskPolarizedRTEnabled: Bool
        switch diskPolarizedRTName {
        case "on", "true", "1", "yes":
            diskPolarizedRTEnabled = true
        case "off", "false", "0", "no":
            diskPolarizedRTEnabled = false
        default:
            fail("invalid --disk-polarized-rt \(diskPolarizedRTName). use on|off")
        }
        if diskPhysicsModeID != 3 && (diskPolarizedRTEnabled || abs(diskFaradayRotScaleArg) > 1e-30 || abs(diskFaradayConvScaleArg) > 1e-30) {
            FileHandle.standardError.write(Data("warn: polarized GRRT options are only active in grmhd mode\n".utf8))
        }

        return GRMHDPolicyResolution(
            diskGrmhdDebugID: diskGrmhdDebugID,
            diskPolarizedRTEnabled: diskPolarizedRTEnabled
        )
    }

    static func resolveVolumeMode(
        diskPhysicsModeID: UInt32,
        thickCloudExplicit: Bool,
        diskVolumePathArg: String,
        diskVol0PathArg: String,
        diskVol1PathArg: String,
        diskVolumeTauScaleRawArg: Double
    ) -> VolumeModeResolution {
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
        let diskVolumeEnabled = diskVolumeLegacyEnabled || diskVolumeGRMHDEnabled || diskVolumeThickEnabled

        return VolumeModeResolution(
            diskVolumeTauScaleArg: diskVolumeTauScaleArg,
            diskVolumeFormatArg: diskVolumeFormatArg,
            diskVolumeLegacyEnabled: diskVolumeLegacyEnabled,
            diskVolumeGRMHDEnabled: diskVolumeGRMHDEnabled,
            diskVolumeThickEnabled: diskVolumeThickEnabled,
            diskVolumeEnabled: diskVolumeEnabled
        )
    }

    static func resolveDiskModel(
        diskModelArg: String,
        diskPhysicsModeID: UInt32,
        diskAtlasPathArg: String
    ) -> DiskModelResolution {
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

        let diskNoiseModel: UInt32 = {
            switch diskModelResolved {
            case "perlin": return 1
            case "perlin-ec7": return 2
            case "perlin-classic": return 3
            default: return 0
            }
        }()

        return DiskModelResolution(
            diskModelResolved: diskModelResolved,
            diskAtlasEnabled: (diskModelResolved == "atlas"),
            diskNoiseModel: diskNoiseModel
        )
    }
}
