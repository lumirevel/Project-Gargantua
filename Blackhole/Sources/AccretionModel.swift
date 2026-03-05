import Foundation

protocol AccretionModel {
    var name: String { get }
    func resolvePhysicsMode(parsedModeID: UInt32, parsedModeName: String, rawMode: String) -> (id: UInt32, name: String)
}

struct DefaultAccretionModel: AccretionModel {
    let name: String = "default"

    @inline(__always)
    func resolvePhysicsMode(parsedModeID: UInt32, parsedModeName: String, rawMode _: String) -> (id: UInt32, name: String) {
        // Phase 3 keeps runtime behavior identical to legacy mode resolution.
        (parsedModeID, parsedModeName)
    }
}

enum AccretionModels {
    static let `default`: any AccretionModel = DefaultAccretionModel()
}
