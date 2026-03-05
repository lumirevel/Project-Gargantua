import Foundation
import Metal

typealias PackedParams = Params

func printPackedParamsLayout() {
    print("PackedParams.layout size=\(MemoryLayout<PackedParams>.size) stride=\(MemoryLayout<PackedParams>.stride) align=\(MemoryLayout<PackedParams>.alignment)")
    print("CollisionInfo.layout size=\(MemoryLayout<CollisionInfo>.size) stride=\(MemoryLayout<CollisionInfo>.stride) align=\(MemoryLayout<CollisionInfo>.alignment)")
    print("CollisionLite32.layout size=\(MemoryLayout<CollisionLite32>.size) stride=\(MemoryLayout<CollisionLite32>.stride) align=\(MemoryLayout<CollisionLite32>.alignment)")
    print("ComposeParams.layout size=\(MemoryLayout<ComposeParams>.size) stride=\(MemoryLayout<ComposeParams>.stride) align=\(MemoryLayout<ComposeParams>.alignment)")
}

func dumpPackedParams(_ params: inout PackedParams, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let data = withUnsafeBytes(of: &params) { Data($0) }
    try data.write(to: url)
}
