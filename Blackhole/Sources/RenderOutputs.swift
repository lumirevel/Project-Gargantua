import Foundation

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
    var visiblePolicy: String
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

enum RenderOutputs {
    static func writeImage(path: String, width: Int, height: Int, rgb: [UInt8]) throws {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ext == "ppm" {
            try writePPM(path: path, width: width, height: height, rgb: rgb)
            return
        }
        let tmpPPM = path + ".tmp.ppm"
        try writePPM(path: tmpPPM, width: width, height: height, rgb: rgb)
        let pyConverter = FileManager.default.currentDirectoryPath + "/Blackhole/scripts/ppm_to_png.py"
        var rc: Int32 = -1
        if FileManager.default.fileExists(atPath: pyConverter) {
            rc = runProcess("/usr/bin/python3", [pyConverter, "--input", tmpPPM, "--output", path])
        }
        if rc != 0 {
            rc = runProcess("/usr/bin/sips", ["-s", "format", "png", tmpPPM, "--out", path])
        }
        try? FileManager.default.removeItem(atPath: tmpPPM)
        if rc != 0 {
            throw NSError(domain: "Blackhole", code: 3, userInfo: [NSLocalizedDescriptionKey: "sips conversion failed"])
        }
    }

    static func makeMeta(config: ResolvedRenderConfig, composeExposure: Float, effectiveTile: Int, outWidth: Int, outHeight: Int, collisionStride: Int) -> RenderMeta {
        let diskModelLabel: String
        if config.diskPhysicsModeID == 3 {
            diskModelLabel = "grmhd_scalar_rt_v1"
        } else if config.diskVolumeEnabled {
            diskModelLabel = "volume_rt_v1"
        } else if config.diskAtlasEnabled {
            diskModelLabel = "stage3_atlas_v1"
        } else if config.diskModelResolved == "perlin" {
            diskModelLabel = "perlin_texture_v1"
        } else if config.diskModelResolved == "perlin-ec7" {
            diskModelLabel = "perlin_texture_ec7_v1"
        } else if config.diskModelResolved == "perlin-classic" {
            diskModelLabel = "perlin_texture_classic_v1"
        } else {
            diskModelLabel = "streamline_particles_v1"
        }
        return RenderMeta(
            version: "dense_pruned_v10",
            spectralEncoding: config.spectralEncoding,
            diskModel: diskModelLabel,
            bridgeCoordinateFrame: "camera_world_xy_disk, r_norm=r/rs, z_norm=z/rs, phi=atan2(y,x)",
            bridgeFields: ["emit_r_norm", "emit_phi", "emit_z_norm", "ct", "T", "v_disk", "direct_world", "noise"],
            width: config.width,
            height: config.height,
            preset: config.preset,
            rcp: config.rcp,
            h: config.hArg,
            maxSteps: config.maxStepsArg,
            camX: config.camXFactor,
            camY: config.camYFactor,
            camZ: config.camZFactor,
            fov: config.fovDeg,
            roll: config.rollDeg,
            diskH: config.diskHFactor,
            metric: config.metricName,
            spin: config.spinArg,
            kerrTol: config.kerrTolArg,
            kerrEscapeMult: config.kerrEscapeMultArg,
            kerrSubsteps: config.kerrSubstepsArg,
            kerrRadialScale: config.kerrRadialScaleArg,
            kerrAzimuthScale: config.kerrAzimuthScaleArg,
            kerrImpactScale: config.kerrImpactScaleArg,
            diskFlowTime: config.diskFlowTimeArg,
            diskOrbitalBoost: config.diskOrbitalBoostArg,
            diskRadialDrift: config.diskRadialDriftArg,
            diskTurbulence: config.diskTurbulenceArg,
            diskOrbitalBoostInner: config.diskOrbitalBoostInnerArg,
            diskOrbitalBoostOuter: config.diskOrbitalBoostOuterArg,
            diskRadialDriftInner: config.diskRadialDriftInnerArg,
            diskRadialDriftOuter: config.diskRadialDriftOuterArg,
            diskTurbulenceInner: config.diskTurbulenceInnerArg,
            diskTurbulenceOuter: config.diskTurbulenceOuterArg,
            diskFlowStep: config.diskFlowStepArg,
            diskFlowSteps: config.diskFlowStepsArg,
            diskMdotEdd: config.diskMdotEddArg,
            diskRadiativeEfficiency: config.diskRadiativeEfficiencyArg,
            diskPhysicsMode: config.diskPhysicsModeArg,
            diskPlungeFloor: config.diskPlungeFloorArg,
            diskThickScale: config.diskThickScaleArg,
            diskColorFactor: config.diskColorFactorArg,
            diskReturningRad: config.diskReturningRadArg,
            diskPrecisionTexture: config.diskPrecisionTextureArg,
            diskPrecisionClouds: config.diskPrecisionCloudsEnabled,
            diskCloudCoverage: config.diskCloudCoverageArg,
            diskCloudOpticalDepth: config.diskCloudOpticalDepthArg,
            diskCloudPorosity: config.diskCloudPorosityArg,
            diskCloudShadowStrength: config.diskCloudShadowStrengthArg,
            diskReturnBounces: config.diskReturnBouncesArg,
            diskRTSteps: config.diskRTStepsArg,
            diskScatteringAlbedo: config.diskScatteringAlbedoArg,
            diskVolumeEnabled: config.diskVolumeEnabled,
            diskVolumeFormat: (config.diskVolumeFormatArg == 1) ? "grmhd_dual_float4" : "legacy_float4",
            diskVolumePath: config.diskVolumeLegacyEnabled ? config.diskVolumePathArg : "",
            diskVol0Path: config.diskVol0PathResolved,
            diskVol1Path: config.diskVol1PathResolved,
            diskVolumeR: config.diskVolumeR,
            diskVolumePhi: config.diskVolumePhi,
            diskVolumeZ: config.diskVolumeZ,
            diskVolumeRNormMin: config.diskVolumeRMin,
            diskVolumeRNormMax: config.diskVolumeRMax,
            diskVolumeZNormMax: config.diskVolumeZMax,
            diskVolumeTauScale: config.diskVolumeTauScaleArg,
            diskNuObsHz: config.diskNuObsHzArg,
            diskGrmhdDensityScale: config.diskGrmhdDensityScaleArg,
            diskGrmhdBScale: config.diskGrmhdBScaleArg,
            diskGrmhdEmissionScale: config.diskGrmhdEmissionScaleArg,
            diskGrmhdAbsorptionScale: config.diskGrmhdAbsorptionScaleArg,
            diskGrmhdVelScale: config.diskGrmhdVelScaleArg,
            diskGrmhdDebug: config.diskGrmhdDebugName,
            visibleMode: config.visibleModeEnabled && config.diskPhysicsModeID == 3,
            visibleSamples: config.visibleSamplesArg,
            visibleTeffModel: config.visibleTeffModelName,
            visibleTeffT0: config.visibleTeffT0Arg,
            visibleTeffR0Rs: config.visibleTeffR0RsArg,
            visibleTeffP: config.visibleTeffPArg,
            visibleBhMass: config.visibleBhMassArg,
            visibleMdot: config.visibleMdotArg,
            visibleRInRs: config.visibleRInRsArg,
            visiblePhotosphereRhoThreshold: config.photosphereRhoThresholdResolved,
            visiblePolicy: config.visiblePolicyName,
            visibleEmissionModel: config.visibleEmissionModelName,
            visibleSynchAlpha: config.visibleSynchAlphaArg,
            exposureMode: config.exposureModeName,
            exposureEV: config.exposureEVArg,
            diskAtlasEnabled: config.diskAtlasEnabled,
            diskAtlasPath: config.diskAtlasEnabled ? config.diskAtlasPathArg : "",
            diskAtlasWidth: config.diskAtlasWidth,
            diskAtlasHeight: config.diskAtlasHeight,
            diskAtlasTempScale: config.diskAtlasTempScaleArg,
            diskAtlasDensityBlend: config.diskAtlasDensityBlendArg,
            diskAtlasVrScale: config.diskAtlasVrScaleArg,
            diskAtlasVphiScale: config.diskAtlasVphiScaleArg,
            diskAtlasRNormMin: config.diskAtlasRMin,
            diskAtlasRNormMax: config.diskAtlasRMax,
            diskAtlasRNormWarp: config.diskAtlasRWarp,
            tileSize: effectiveTile,
            composeGPU: config.composeGPU,
            downsample: config.downsampleArg,
            outputWidth: outWidth,
            outputHeight: outHeight,
            exposure: Double(composeExposure),
            look: config.composeLook,
            cameraModel: config.cameraModelName,
            cameraPsfSigmaPx: Double(config.cameraPsfSigmaArg),
            cameraReadNoise: Double(config.cameraReadNoiseArg),
            cameraShotNoise: Double(config.cameraShotNoiseArg),
            cameraFlareStrength: Double(config.cameraFlareStrengthArg),
            backgroundMode: config.backgroundModeName,
            backgroundStarDensity: Double(config.backgroundStarDensityArg),
            backgroundStarStrength: Double(config.backgroundStarStrengthArg),
            backgroundNebulaStrength: Double(config.backgroundNebulaStrengthArg),
            collisionStride: collisionStride
        )
    }

    static func writeMetadata(meta: RenderMeta, outPath: String, linear32OutPath: String, useLinear32Intermediate: Bool, discardCollisionOutput: Bool, outSize: Int, linearOutSize: Int, hitCount: Int) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metaData = try encoder.encode(meta)
        if useLinear32Intermediate {
            let metaURL = URL(fileURLWithPath: linear32OutPath + ".json")
            try metaData.write(to: metaURL)
            print("Saved hdr32 intermediate at:", URL(fileURLWithPath: linear32OutPath).path)
            print("Saved hdr32 intermediate (\(linearOutSize) bytes, hits=\(hitCount))")
            print("Saved meta at:", metaURL.path)
        } else if !discardCollisionOutput {
            let metaURL = URL(fileURLWithPath: outPath + ".json")
            try metaData.write(to: metaURL)
            print("Saved at:", URL(fileURLWithPath: outPath).path)
            print("Saved collisions.bin (\(outSize) bytes, hits=\(hitCount))")
            print("Saved meta at:", metaURL.path)
        } else {
            print("Collision output skipped (discard mode), hits=\(hitCount)")
        }
    }
}
