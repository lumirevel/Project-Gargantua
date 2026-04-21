import Foundation

struct LogicalParams {
    var rawArguments: [String]
    var runRegression: Bool
    var printPackedLayout: Bool
    var validatePackedABI: Bool
    var dumpPackedParamsPath: String

    var camera = CameraParams()
    var disk = DiskParams()
    var volume = VolumeParams()
    var visible = VisibleParams()
    var compose = ComposeParamsLogical()
    var debug = DebugParams()
    var perf = PerfParams()
}

struct CameraParams {
    var fovDeg: Double = 90.0
    var rollDeg: Double = 0.0
}

struct DiskParams {
    var mode: String = "auto"
    var model: String = "auto"
}

struct VolumeParams {
    var enabled: Bool = false
}

struct VisibleParams {
    var enabled: Bool = false
}

struct ComposeParamsLogical {
    var gpu: Bool = false
}

struct DebugParams {
    var enabled: Bool = false
}

struct PerfParams {
    var traceInFlight: Int = 0
}
