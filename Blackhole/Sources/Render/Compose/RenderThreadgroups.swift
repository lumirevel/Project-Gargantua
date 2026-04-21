import Foundation
import Metal

enum RenderThreadgroups {
    static func oneDimensional(
        _ pipeline: MTLComputePipelineState,
        maxWidth: Int = 256,
        preferredSIMDGroups: Int = 4
    ) -> MTLSize {
        let threadWidth = max(1, pipeline.threadExecutionWidth)
        let maxThreads = max(1, pipeline.maxTotalThreadsPerThreadgroup)
        let widthCap = max(1, min(maxWidth, maxThreads))
        let preferred = max(threadWidth, min(widthCap, max(64, threadWidth * preferredSIMDGroups)))
        let aligned = max(threadWidth, (preferred / threadWidth) * threadWidth)
        return MTLSize(width: min(widthCap, aligned), height: 1, depth: 1)
    }

    static func twoDimensional(
        _ pipeline: MTLComputePipelineState,
        maxWidth: Int = 32,
        maxHeight: Int = 8,
        preferredSIMDGroups: Int = 4
    ) -> MTLSize {
        let threadWidth = max(1, pipeline.threadExecutionWidth)
        let maxThreads = max(1, pipeline.maxTotalThreadsPerThreadgroup)
        let width = max(1, min(maxWidth, threadWidth))
        let preferredThreads = min(maxThreads, max(64, threadWidth * preferredSIMDGroups))
        let height = max(1, min(maxHeight, preferredThreads / max(width, 1)))
        return MTLSize(width: width, height: height, depth: 1)
    }
}
