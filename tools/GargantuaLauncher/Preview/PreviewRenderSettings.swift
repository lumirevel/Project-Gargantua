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

    /// Resolution ladder for the refine pass, rendered one step at a time once the
    /// camera settles. The renderer is deterministic (every pixel is traced on the
    /// GPU each pass — there is no Monte-Carlo noise to average down), so the
    /// "progressive" axis that actually buys anything here is *resolution*: render
    /// an intermediate width first so a sharper-than-drag image appears quickly,
    /// then climb to full width. Each step meets or exceeds the previous one and
    /// strictly exceeds `fastWidth`; frames advance the ladder in arrival order.
    /// The top width appears twice: all rungs but the last render with the fast
    /// (drag-grade) trace profile, so the duplicate shows a full-sharpness frame
    /// ~3x sooner while the exact final-integrator frame replaces it right after.
    var refineLadder: [Int] {
        switch self {
        case .low: return [176, 240, 240]
        case .medium: return [240, 340, 340]
        case .high: return [320, 480, 480]
        }
    }

    /// Longest-edge width for the final refined frame (top of the ladder).
    var refineWidth: Int { refineLadder.last ?? fastWidth }
}
