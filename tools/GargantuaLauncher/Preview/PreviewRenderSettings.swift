import Foundation

/// Preview quality tier. The interactive preview runs the *same* offline
/// `Blackhole` renderer as the final output — only the resolution is lowered, so
/// the disk model, colour science and physics match the result exactly. Each
/// camera move first renders a small "fast" frame, then a larger "refine" frame
/// once the camera is still (progressive, rough -> sharp).
enum PreviewQuality: String, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Longest-edge width for the immediate, rough pass.
    var fastWidth: Int {
        switch self {
        case .low: return 160
        case .medium: return 200
        case .high: return 248
        }
    }

    /// Longest-edge width for the refined pass (rendered when the camera settles).
    var refineWidth: Int {
        switch self {
        case .low: return 280
        case .medium: return 384
        case .high: return 512
        }
    }
}
