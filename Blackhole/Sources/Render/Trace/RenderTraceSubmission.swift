import Foundation
import Metal

enum RenderTraceSubmission {
    static func submit(
        input: RenderTracePhaseInput,
        tile: RenderTraceTile,
        slot: InFlightTraceSlot,
        runtime: RenderTraceRuntime,
        inFlightSemaphore: DispatchSemaphore,
        traceDispatchGroup: DispatchGroup,
        ioQueue: DispatchQueue
    ) {
        RenderTraceTileSupport.configureSlot(input: input, slot: slot, tile: tile)

        traceDispatchGroup.enter()
        let cmd = RenderTraceTileSupport.makeCommandBuffer(input: input, slot: slot, tile: tile)
        cmd.addCompletedHandler { cmdBuf in
            ioQueue.async {
                defer {
                    inFlightSemaphore.signal()
                    traceDispatchGroup.leave()
                }
                if runtime.currentError() != nil { return }
                if cmdBuf.status != .completed {
                    runtime.storeErrorIfNeeded(
                        cmdBuf.error ?? NSError(
                            domain: "Blackhole",
                            code: 70,
                            userInfo: [NSLocalizedDescriptionKey: "trace command buffer failed"]
                        )
                    )
                    return
                }
                do {
                    let completion = try RenderTraceCompletion.processTile(input: input, slot: slot, tile: tile)
                    runtime.recordTileCompletion(completion, tile: tile)
                } catch {
                    runtime.storeErrorIfNeeded(error)
                    return
                }
                runtime.emitTraceProgress(tile: tile, traceTileTotal: input.traceTileTotal)
            }
        }
        cmd.commit()
    }
}
