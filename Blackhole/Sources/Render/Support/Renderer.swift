import Foundation

enum Renderer {
    static func render(config: inout ResolvedRenderConfig, params: PackedParams) throws {
        let uploadedDiskAssetBytes =
            config.diskAtlasData.count + config.diskVolume0Data.count + config.diskVolume1Data.count
        let runtime = try RenderSetup.prepare(config: config, params: params)
        config.uploadedDiskAssetBytes = uploadedDiskAssetBytes
        config.diskAtlasData.removeAll(keepingCapacity: false)
        config.diskVolume0Data.removeAll(keepingCapacity: false)
        config.diskVolume1Data.removeAll(keepingCapacity: false)
        try RenderExecution.execute(config: config, params: params, runtime: runtime)
    }
}
