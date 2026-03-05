import Foundation

enum ParamsBuilder {
    @inline(__always)
    static func build(from logical: LogicalParams) -> LogicalParams {
        // Phase 1 keeps runtime behavior in AppMain and uses this as a stable seam for future extraction.
        logical
    }
}
