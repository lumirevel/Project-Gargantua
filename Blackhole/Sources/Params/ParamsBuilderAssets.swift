import Foundation

struct RuntimeIOResolution {
    let composeGPU: Bool
    let gpuFullCompose: Bool
    let discardCollisionOutput: Bool
    let linear32Intermediate: Bool
    let linear32OutPath: String
    let outPath: String
    let imageOutPath: String
    let traceHDRDirectMode: String
}

struct DiskAtlasResourceResolution {
    let data: Data
    let width: Int
    let height: Int
    let rNormMin: Double?
    let rNormMax: Double?
    let rNormWarp: Double?
}

struct DiskVolumeResourceResolution {
    let volume0Data: Data
    let volume1Data: Data
    let r: Int
    let phi: Int
    let z: Int
    let metaRMin: Double?
    let metaRMax: Double?
    let metaZMax: Double?
    let vol0PathResolved: String
    let vol1PathResolved: String
}

enum ParamsBuilderAssets {
    static func validateRemovedFlags(cliArguments: [String]) {
        if cliArguments.contains("--kerr-use-u") {
            FileHandle.standardError.write(Data("error: --kerr-use-u has been removed after validation tests showed no practical gain.\n".utf8))
            exit(2)
        }
        if cliArguments.contains("--sample") {
            FileHandle.standardError.write(Data("error: --sample has been removed. Use --ssaa (1, 2, 4) in run_pipeline.sh.\n".utf8))
            exit(2)
        }
    }

    static func resolveRuntimeIO(
        cliArguments: [String],
        rawOutputPath: String,
        explicitImageOutPath: String
    ) -> RuntimeIOResolution {
        let outputLooksLikeCollision = rawOutputPath.lowercased().hasSuffix(".bin")
        let composeGPU = true
        let linear32Intermediate = flagArgAny(["--linear32-intermediate", "--hdr-intermediate"])
        let gpuFullCompose = !linear32Intermediate
        let discardCollisionOutput = !flagArgAny(["--debug"])
        let linear32OutPath = stringArgAny(["--linear32-out", "--hdr-out"], default: rawOutputPath + ".linear32f32")
        let outPath: String = {
            if !explicitImageOutPath.isEmpty { return rawOutputPath }
            if outputLooksLikeCollision { return rawOutputPath }
            if let dot = rawOutputPath.lastIndex(of: ".") {
                return String(rawOutputPath[..<dot]) + ".collisions.bin"
            }
            return rawOutputPath + ".collisions.bin"
        }()
        let imageOutPath: String = {
            if !explicitImageOutPath.isEmpty { return explicitImageOutPath }
            if outputLooksLikeCollision {
                let trimmed = String(rawOutputPath.dropLast(4))
                return trimmed.isEmpty ? "blackhole_gpu.png" : trimmed + ".png"
            }
            return rawOutputPath
        }()
        if flagArgAny(["--compose-gpu", "--gpu-compose", "--gpu-full-compose", "--compose-in-memory", "--discard-collisions", "--skip-collision-dump"]) {
            FileHandle.standardError.write(Data("warn: compose/intermediate runtime flags are deprecated and ignored; GPU full-compose with automatic memory management is now the default.\n".utf8))
        }
        let traceHDRDirectMode = stringArgAny(["--trace-hdr-direct", "--trace-linear-hdr"], default: "auto").lowercased()
        if !["auto", "on", "off"].contains(traceHDRDirectMode) {
            fail("invalid --trace-hdr-direct \(traceHDRDirectMode). use auto|on|off")
        }
        return RuntimeIOResolution(
            composeGPU: composeGPU,
            gpuFullCompose: gpuFullCompose,
            discardCollisionOutput: discardCollisionOutput,
            linear32Intermediate: linear32Intermediate,
            linear32OutPath: linear32OutPath,
            outPath: outPath,
            imageOutPath: imageOutPath,
            traceHDRDirectMode: traceHDRDirectMode
        )
    }

    static func loadDiskAtlasResource(
        enabled: Bool,
        path: String,
        widthOverride: Int,
        heightOverride: Int
    ) -> DiskAtlasResourceResolution {
        if enabled {
            do {
                let loaded = try loadDiskAtlas(path: path, widthOverride: widthOverride, heightOverride: heightOverride)
                return DiskAtlasResourceResolution(
                    data: loaded.data,
                    width: loaded.width,
                    height: loaded.height,
                    rNormMin: loaded.rNormMin,
                    rNormMax: loaded.rNormMax,
                    rNormWarp: loaded.rNormWarp
                )
            } catch {
                fail("failed to load --disk-atlas: \(error.localizedDescription)")
            }
        }

        var fallback = SIMD4<Float>(1.0, 0.0, 0.0, 1.0)
        return DiskAtlasResourceResolution(
            data: withUnsafeBytes(of: &fallback) { Data($0) },
            width: 1,
            height: 1,
            rNormMin: nil,
            rNormMax: nil,
            rNormWarp: nil
        )
    }

    static func loadDiskVolumeResources(
        legacyEnabled: Bool,
        grmhdEnabled: Bool,
        diskVolumePathArg: String,
        diskVol0PathArg: String,
        diskVol1PathArg: String,
        diskMetaPathArg: String,
        rOverride: Int,
        phiOverride: Int,
        zOverride: Int
    ) -> DiskVolumeResourceResolution {
        if grmhdEnabled && (diskVol0PathArg.isEmpty || diskVol1PathArg.isEmpty) {
            fail("grmhd mode requires --disk-vol0 <path> and --disk-vol1 <path>")
        }

        if legacyEnabled {
            do {
                let loaded = try loadDiskVolume(
                    path: diskVolumePathArg,
                    metaPath: diskMetaPathArg,
                    rOverride: rOverride,
                    phiOverride: phiOverride,
                    zOverride: zOverride
                )
                var empty = SIMD4<Float>(repeating: 0.0)
                return DiskVolumeResourceResolution(
                    volume0Data: loaded.data,
                    volume1Data: withUnsafeBytes(of: &empty) { Data($0) },
                    r: loaded.r,
                    phi: loaded.phi,
                    z: loaded.z,
                    metaRMin: loaded.rNormMin,
                    metaRMax: loaded.rNormMax,
                    metaZMax: loaded.zNormMax,
                    vol0PathResolved: diskVolumePathArg,
                    vol1PathResolved: ""
                )
            } catch {
                fail("failed to load --disk-volume: \(error.localizedDescription)")
            }
        }

        if grmhdEnabled {
            do {
                let loaded0 = try loadDiskVolume(
                    path: diskVol0PathArg,
                    metaPath: diskMetaPathArg,
                    rOverride: rOverride,
                    phiOverride: phiOverride,
                    zOverride: zOverride
                )
                let loaded1 = try loadDiskVolume(
                    path: diskVol1PathArg,
                    metaPath: diskMetaPathArg,
                    rOverride: rOverride,
                    phiOverride: phiOverride,
                    zOverride: zOverride
                )
                if loaded0.r != loaded1.r || loaded0.phi != loaded1.phi || loaded0.z != loaded1.z {
                    fail("grmhd volume dimensions mismatch: vol0=\(loaded0.r)x\(loaded0.phi)x\(loaded0.z), vol1=\(loaded1.r)x\(loaded1.phi)x\(loaded1.z)")
                }
                return DiskVolumeResourceResolution(
                    volume0Data: loaded0.data,
                    volume1Data: loaded1.data,
                    r: loaded0.r,
                    phi: loaded0.phi,
                    z: loaded0.z,
                    metaRMin: loaded0.rNormMin ?? loaded1.rNormMin,
                    metaRMax: loaded0.rNormMax ?? loaded1.rNormMax,
                    metaZMax: loaded0.zNormMax ?? loaded1.zNormMax,
                    vol0PathResolved: diskVol0PathArg,
                    vol1PathResolved: diskVol1PathArg
                )
            } catch {
                fail("failed to load --disk-vol0/--disk-vol1: \(error.localizedDescription)")
            }
        }

        var empty = SIMD4<Float>(repeating: 0.0)
        let emptyData = withUnsafeBytes(of: &empty) { Data($0) }
        return DiskVolumeResourceResolution(
            volume0Data: emptyData,
            volume1Data: emptyData,
            r: 1,
            phi: 1,
            z: 1,
            metaRMin: nil,
            metaRMax: nil,
            metaZMax: nil,
            vol0PathResolved: "",
            vol1PathResolved: ""
        )
    }

    static func clampPhotosphereThreshold(
        diskPhysicsModeID: UInt32,
        visibleModeEnabled: Bool,
        photosphereRhoThreshold: Double,
        diskVolumeFormatArg: UInt32,
        diskVolume0Data: Data
    ) -> Double {
        guard diskPhysicsModeID == 3, visibleModeEnabled, photosphereRhoThreshold > 0.0, diskVolumeFormatArg == 1 else {
            return photosphereRhoThreshold
        }

        let rhoMax = estimateGRMHDRhoMax(vol0Data: diskVolume0Data)
        guard rhoMax > 0.0, photosphereRhoThreshold > rhoMax else {
            return photosphereRhoThreshold
        }

        let clamped = max(rhoMax * 0.25, rhoMax * 1e-3)
        FileHandle.standardError.write(
            Data(
                String(
                    format: "warn: --photosphere-rho-threshold %.6e exceeds volume rho max %.6e; clamping to %.6e\n",
                    photosphereRhoThreshold,
                    rhoMax,
                    clamped
                ).utf8
            )
        )
        return clamped
    }
}
