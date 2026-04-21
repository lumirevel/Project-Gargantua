import Foundation

enum RenderTraceTraversal {
    static func forEachTile(
        input: RenderTracePhaseInput,
        runtime: RenderTraceRuntime,
        inFlightSemaphore: DispatchSemaphore,
        traceDispatchGroup: DispatchGroup,
        ioQueue: DispatchQueue
    ) throws {
        var traceTileIndex = 0
        var traceDispatchIndex = 0
        var ty = 0
        while ty < input.height {
            var tx = 0
            while tx < input.width {
                let tile = RenderTraceTile(
                    originX: tx,
                    originY: ty,
                    width: min(input.effectiveTile, input.width - tx),
                    height: min(input.effectiveTile, input.height - ty),
                    ordinal: traceTileIndex + 1
                )
                traceTileIndex += 1

                inFlightSemaphore.wait()
                if let error = runtime.currentError() {
                    inFlightSemaphore.signal()
                    throw error
                }

                let slot = input.traceSlots[traceDispatchIndex % input.maxInFlight]
                traceDispatchIndex += 1
                RenderTraceSubmission.submit(
                    input: input,
                    tile: tile,
                    slot: slot,
                    runtime: runtime,
                    inFlightSemaphore: inFlightSemaphore,
                    traceDispatchGroup: traceDispatchGroup,
                    ioQueue: ioQueue
                )

                tx += tile.width
            }
            ty += min(input.effectiveTile, input.height - ty)
        }
    }
}
