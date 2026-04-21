import Foundation

struct DiskVolumeAssembly {
    let diskVolumeTauScaleArg: Double
    let diskVolumeFormatArg: UInt32
    let diskVolumeLegacyEnabled: Bool
    let diskVolumeGRMHDEnabled: Bool
    let diskVolumeThickEnabled: Bool
    let diskVolumeEnabled: Bool
    let diskVolume0Data: Data
    let diskVolume1Data: Data
    let diskVolumeR: Int
    let diskVolumePhi: Int
    let diskVolumeZ: Int
    let diskVolumeRMin: Double
    let diskVolumeRMax: Double
    let diskVolumeZMax: Double
    let diskVol0PathResolved: String
    let diskVol1PathResolved: String
    let photosphereRhoThresholdResolved: Double
}

enum ParamsBuilderDiskVolume {
    static func resolve(
        diskPhysicsModeID: UInt32,
        thickCloudExplicit: Bool,
        diskVolumePathArg: String,
        diskVol0PathArg: String,
        diskVol1PathArg: String,
        diskMetaPathArg: String,
        diskVolumeTauScaleRawArg: Double,
        diskVolumeROverrideArg: Int,
        diskVolumePhiOverrideArg: Int,
        diskVolumeZOverrideArg: Int,
        rcp: Double,
        visibleModeEnabled: Bool,
        photosphereRhoThresholdArg: Double
    ) -> DiskVolumeAssembly {
        let volumeMode = ParamsBuilderPolicy.resolveVolumeMode(
            diskPhysicsModeID: diskPhysicsModeID,
            thickCloudExplicit: thickCloudExplicit,
            diskVolumePathArg: diskVolumePathArg,
            diskVol0PathArg: diskVol0PathArg,
            diskVol1PathArg: diskVol1PathArg,
            diskVolumeTauScaleRawArg: diskVolumeTauScaleRawArg
        )

        let diskVolumeResource = ParamsBuilderAssets.loadDiskVolumeResources(
            legacyEnabled: volumeMode.diskVolumeLegacyEnabled,
            grmhdEnabled: volumeMode.diskVolumeGRMHDEnabled,
            diskVolumePathArg: diskVolumePathArg,
            diskVol0PathArg: diskVol0PathArg,
            diskVol1PathArg: diskVol1PathArg,
            diskMetaPathArg: diskMetaPathArg,
            rOverride: diskVolumeROverrideArg,
            phiOverride: diskVolumePhiOverrideArg,
            zOverride: diskVolumeZOverrideArg
        )

        let diskVolumeRMin = max(0.0, diskVolumeResource.metaRMin ?? 1.0)
        let diskVolumeRMax = max(diskVolumeRMin + 1e-6, diskVolumeResource.metaRMax ?? max(rcp, diskVolumeRMin + 0.1))
        let diskVolumeZMax = max(1e-4, diskVolumeResource.metaZMax ?? 0.35)
        let photosphereRhoThresholdResolved = ParamsBuilderAssets.clampPhotosphereThreshold(
            diskPhysicsModeID: diskPhysicsModeID,
            visibleModeEnabled: visibleModeEnabled,
            photosphereRhoThreshold: photosphereRhoThresholdArg,
            diskVolumeFormatArg: volumeMode.diskVolumeFormatArg,
            diskVolume0Data: diskVolumeResource.volume0Data
        )

        return DiskVolumeAssembly(
            diskVolumeTauScaleArg: volumeMode.diskVolumeTauScaleArg,
            diskVolumeFormatArg: volumeMode.diskVolumeFormatArg,
            diskVolumeLegacyEnabled: volumeMode.diskVolumeLegacyEnabled,
            diskVolumeGRMHDEnabled: volumeMode.diskVolumeGRMHDEnabled,
            diskVolumeThickEnabled: volumeMode.diskVolumeThickEnabled,
            diskVolumeEnabled: volumeMode.diskVolumeEnabled,
            diskVolume0Data: diskVolumeResource.volume0Data,
            diskVolume1Data: diskVolumeResource.volume1Data,
            diskVolumeR: diskVolumeResource.r,
            diskVolumePhi: diskVolumeResource.phi,
            diskVolumeZ: diskVolumeResource.z,
            diskVolumeRMin: diskVolumeRMin,
            diskVolumeRMax: diskVolumeRMax,
            diskVolumeZMax: diskVolumeZMax,
            diskVol0PathResolved: diskVolumeResource.vol0PathResolved,
            diskVol1PathResolved: diskVolumeResource.vol1PathResolved,
            photosphereRhoThresholdResolved: photosphereRhoThresholdResolved
        )
    }
}
