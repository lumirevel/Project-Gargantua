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

    /// Longest-edge width for the immediate, rough pass. Kept small because the
    /// renderer has a fixed ~0.5 s per-launch cost, so a lower resolution buys
    /// the biggest responsiveness gain.
    var fastWidth: Int {
        switch self {
        case .low: return 112
        case .medium: return 144
        case .high: return 192
        }
    }

    /// Longest-edge width for the refined pass (rendered when the camera settles).
    var refineWidth: Int {
        switch self {
        case .low: return 240
        case .medium: return 340
        case .high: return 480
        }
    }
}
