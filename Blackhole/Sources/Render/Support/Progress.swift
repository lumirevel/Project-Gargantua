import Foundation

@inline(__always)
func emitETAProgress(_ done: Int, _ total: Int, _ phase: String, _ extra: String = "") {
    let safeTotal = max(total, 1)
    let suffix = extra.isEmpty ? "" : " " + extra
    let line = "ETA_PROGRESS \(done) \(safeTotal) \(phase)\(suffix)\n"
    FileHandle.standardError.write(Data(line.utf8))
}
