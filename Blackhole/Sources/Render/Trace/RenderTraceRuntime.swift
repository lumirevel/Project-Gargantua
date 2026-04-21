import Foundation
import Metal

final class RenderTraceRuntime {
    private let linearCloudBins: Int
    private let totalOps: Int
    private let totalPixels: Int
    private let progressStep: Int
    private let useLinear32Intermediate: Bool

    private let errorLock = NSLock()
    private var storedError: Error?

    private(set) var linearCloudHistGlobal: [UInt32]
    private(set) var linearCloudSampleCount: UInt64 = 0
    private(set) var hitCount = 0
    private(set) var donePixels = 0
    private(set) var nextProgressMark: Int
    private(set) var lastProgressPrint = Date().timeIntervalSince1970

    init(
        linearCloudBins: Int,
        totalOps: Int,
        totalPixels: Int,
        progressStep: Int,
        useLinear32Intermediate: Bool
    ) {
        self.linearCloudBins = linearCloudBins
        self.totalOps = totalOps
        self.totalPixels = totalPixels
        self.progressStep = progressStep
        self.useLinear32Intermediate = useLinear32Intermediate
        self.linearCloudHistGlobal = [UInt32](repeating: 0, count: linearCloudBins)
        self.nextProgressMark = progressStep
    }

    func currentError() -> Error? {
        errorLock.lock()
        defer { errorLock.unlock() }
        return storedError
    }

    func storeErrorIfNeeded(_ error: Error) {
        errorLock.lock()
        if storedError == nil {
            storedError = error
        }
        errorLock.unlock()
    }

    func recordTileCompletion(
        _ completion: RenderTraceCompletionResult,
        tile: RenderTraceTile
    ) {
        hitCount += completion.localHits
        if useLinear32Intermediate {
            for i in 0..<linearCloudBins {
                linearCloudHistGlobal[i] = linearCloudHistGlobal[i] &+ completion.linearCloudHist[i]
            }
            linearCloudSampleCount += completion.linearCloudSampleCount
        }

        donePixels += tile.pixelCount
    }

    func emitTraceProgress(tile: RenderTraceTile, traceTileTotal: Int) {
        let now = Date().timeIntervalSince1970
        guard donePixels >= totalPixels || donePixels >= nextProgressMark || (now - lastProgressPrint) >= 0.5 else {
            return
        }
        emitETAProgress(donePixels, totalOps, "swift_trace", "task=trace tile=\(tile.ordinal)/\(traceTileTotal)")
        lastProgressPrint = now
        while nextProgressMark <= donePixels {
            nextProgressMark += progressStep
        }
    }

    func finalizeHitCount(from directLinearHitCountBuf: MTLBuffer?) -> Int {
        guard let directLinearHitCountBuf else { return hitCount }
        return Int(directLinearHitCountBuf.contents().bindMemory(to: UInt32.self, capacity: 1).pointee)
    }

    func makeResult(overridingHitCount hitCountOverride: Int? = nil) -> RenderTracePhaseResult {
        RenderTracePhaseResult(
            hitCount: hitCountOverride ?? hitCount,
            donePixels: donePixels,
            nextProgressMark: nextProgressMark,
            lastProgressPrint: lastProgressPrint,
            linearCloudHistGlobal: linearCloudHistGlobal,
            linearCloudSampleCount: linearCloudSampleCount
        )
    }
}
