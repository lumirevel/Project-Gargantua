import Foundation
import simd

/// Black-hole metric used by the preview ray tracer.
enum PreviewMetric: UInt32 {
    case schwarzschild = 0
    case kerr = 1
}

/// Tone-mapping operator applied at presentation time.
enum PreviewToneMap: String, CaseIterable, Identifiable {
    case reinhard
    case aces
    case linear

    var id: String { rawValue }
    var title: String {
        switch self {
        case .reinhard: return "Reinhard"
        case .aces: return "ACES"
        case .linear: return "Linear"
        }
    }
    var rawMode: UInt32 {
        switch self {
        case .reinhard: return 0
        case .aces: return 1
        case .linear: return 2
        }
    }
}

/// Preview quality tier. Controls resolution scale, march steps and the number
/// of stochastic samples accumulated per frame. This is the "preview is cheaper
/// than final render" seam.
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

    /// Resolution scale used while idle (accumulating).
    var idleScale: Float {
        switch self {
        case .low: return 0.55
        case .medium: return 0.8
        case .high: return 1.0
        }
    }

    /// Resolution scale used while the camera is being manipulated.
    var interactiveScale: Float {
        switch self {
        case .low: return 0.32
        case .medium: return 0.42
        case .high: return 0.55
        }
    }

    /// Geodesic march steps while idle.
    var idleMarchSteps: UInt32 {
        switch self {
        case .low: return 140
        case .medium: return 200
        case .high: return 280
        }
    }

    /// Geodesic march steps while interacting (responsiveness first).
    var interactiveMarchSteps: UInt32 {
        switch self {
        case .low: return 70
        case .medium: return 96
        case .high: return 120
        }
    }

    /// Stochastic samples accumulated each frame.
    var samplesPerFrame: UInt32 {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 2
        }
    }

    /// Sample count at which accumulation is considered converged.
    var maxSamples: UInt32 {
        switch self {
        case .low: return 256
        case .medium: return 512
        case .high: return 1024
        }
    }

    /// Upper bound on the accumulation buffer's longest edge (cost guard).
    var maxResolution: Int {
        switch self {
        case .low: return 720
        case .medium: return 960
        case .high: return 1200
        }
    }
}

/// All renderer-facing parameters gathered from the GUI option panels.
/// Changing any field must reset accumulation (handled by the renderer, which
/// diffs this `Equatable` value each frame).
struct PreviewRenderSettings: Equatable {
    var metric: PreviewMetric
    var spin: Float
    var diskInner: Float
    var diskOuter: Float
    var diskThickness: Float
    var diskDensity: Float
    var diskBrightness: Float
    var diskTempScale: Float
    // Source-model-driven disk surface texture (see PreviewDiskStyle).
    var diskTurbulence: Float
    var diskNoiseScale: Float
    var diskSpiralArms: Float
    var diskSpiralStrength: Float
    var exposure: Float
    var toneMap: PreviewToneMap
    var backgroundStars: Float
    var quality: PreviewQuality

    static let `default` = PreviewRenderSettings(
        metric: .kerr,
        spin: 0.6,
        diskInner: PreviewPhysics.diskInnerRadius(metric: .kerr, spin: 0.6),
        diskOuter: 22.0,
        diskThickness: 0.5,
        diskDensity: 0.78,
        diskBrightness: 1.0,
        diskTempScale: 8600.0,
        diskTurbulence: 0.30,
        diskNoiseScale: 2.2,
        diskSpiralArms: 0,
        diskSpiralStrength: 0,
        exposure: 1.0,
        toneMap: .aces,
        backgroundStars: 1.0,
        quality: .medium
    )
}

/// Maps a GUI accretion-source model to a distinct preview disk appearance, so
/// switching the source in the sidebar visibly changes the live preview. These
/// are cheap stylistic presets (turbulence / spiral banding / temperature /
/// thickness), not a re-derivation of each source's full physics.
struct PreviewDiskStyle {
    var turbulence: Float
    var noiseScale: Float
    var spiralArms: Float
    var spiralStrength: Float
    var tempScale: Float
    var thickness: Float
    var brightnessScale: Float

    static func preset(forSourceID id: String) -> PreviewDiskStyle {
        switch id {
        case "canonical-visible-disk-v1":
            // Clean scientific thin disk: smooth, gently mottled.
            return .init(turbulence: 0.28, noiseScale: 2.0, spiralArms: 0, spiralStrength: 0,
                         tempScale: 8800, thickness: 0.5, brightnessScale: 1.0)
        case "legacy-perlin":
            // Soft turbulent Perlin disk.
            return .init(turbulence: 0.85, noiseScale: 2.8, spiralArms: 0, spiralStrength: 0,
                         tempScale: 7600, thickness: 0.7, brightnessScale: 1.05)
        case "legacy-perlin-classic":
            // Stripe-like banded reproduction.
            return .init(turbulence: 0.55, noiseScale: 2.0, spiralArms: 6, spiralStrength: 0.6,
                         tempScale: 7400, thickness: 0.6, brightnessScale: 1.0)
        case "legacy-perlin-ec7":
            // Crisp high-frequency Perlin.
            return .init(turbulence: 0.95, noiseScale: 4.6, spiralArms: 0, spiralStrength: 0,
                         tempScale: 8000, thickness: 0.5, brightnessScale: 1.1)
        case "legacy-bh-finish-grmhd":
            // Hot, thick, strongly turbulent GRMHD-style torus.
            return .init(turbulence: 0.8, noiseScale: 3.2, spiralArms: 2, spiralStrength: 0.3,
                         tempScale: 9600, thickness: 0.95, brightnessScale: 1.2)
        case "legacy-thin-disk-preset-default":
            // Thin, mostly smooth DNGR-style preset.
            return .init(turbulence: 0.4, noiseScale: 2.4, spiralArms: 0, spiralStrength: 0,
                         tempScale: 8200, thickness: 0.4, brightnessScale: 0.95)
        default:
            return .init(turbulence: 0.4, noiseScale: 2.4, spiralArms: 0, spiralStrength: 0,
                         tempScale: 8200, thickness: 0.6, brightnessScale: 1.0)
        }
    }
}

/// Shared physical helpers (units: M = 1, Schwarzschild radius rs = 2M = 2).
/// Mirrors the offline renderer's `DiskOrbit` conventions so the preview is a
/// reduced-cost reimplementation of the same physical model.
enum PreviewPhysics {
    static let rs: Float = 2.0

    static func horizonRadius(metric: PreviewMetric, spin: Float) -> Float {
        switch metric {
        case .schwarzschild:
            return rs
        case .kerr:
            let a = min(max(abs(spin), 0), 0.999)
            // r+ = (1 + sqrt(1 - a^2)) * M, with M = 1.
            return max(1.0 + (1.0 - a * a).squareRoot(), 0.5 * rs)
        }
    }

    /// Kerr ISCO radius in units of M (matches `diskKerrISCOM`).
    static func kerrISCO(_ spin: Float) -> Float {
        let a = min(max(spin, -0.999), 0.999)
        let a2 = a * a
        let z1 = 1.0 + pow(max(1.0 - a2, 0.0), 1.0 / 3.0)
            * (pow(1.0 + a, 1.0 / 3.0) + pow(1.0 - a, 1.0 / 3.0))
        let z2 = (max(3.0 * a2 + z1 * z1, 0.0)).squareRoot()
        let sgn: Float = a >= 0 ? 1.0 : -1.0
        return 3.0 + z2 - sgn * (max((3.0 - z1) * (3.0 + z1 + 2.0 * z2), 0.0)).squareRoot()
    }

    static func diskInnerRadius(metric: PreviewMetric, spin: Float) -> Float {
        switch metric {
        case .schwarzschild:
            return 3.0 * rs // 6 M
        case .kerr:
            let isco = kerrISCO(spin) // already in M units
            let horizon = horizonRadius(metric: .kerr, spin: spin)
            return max(isco, horizon * 1.02)
        }
    }
}

/// GPU uniform block. Laid out as float4 / uint4 rows so the Swift and Metal
/// structures share an identical 160-byte memory layout (no alignment drift).
struct PreviewUniforms {
    var camPos: SIMD4<Float> = .zero
    var camForward: SIMD4<Float> = .zero
    var camRight: SIMD4<Float> = .zero
    var camUp: SIMD4<Float> = .zero
    var resFov: SIMD4<Float> = .zero    // x=resX, y=resY, z=tanHalfFov, w=aspect
    var disk0: SIMD4<Float> = .zero     // x=spin, y=inner, z=outer, w=thickness
    var disk1: SIMD4<Float> = .zero     // x=brightness, y=density, z=bgStars, w=stepScale
    var disk2: SIMD4<Float> = .zero     // x=escapeR, y=horizon, z=photonR, w=tempScale
    var disk3: SIMD4<Float> = .zero     // x=turbulence, y=noiseScale, z=spiralArms, w=spiralStrength
    var u0: SIMD4<UInt32> = .zero       // x=sampleIndex, y=frameSeed, z=maxSteps, w=metric
    var u1: SIMD4<UInt32> = .zero       // x=samplesPerFrame, y=flags, z=reserved, w=reserved
}

/// Presentation parameters (tone map + exposure) passed to the fragment stage.
struct PreviewPresentParams {
    var exposure: Float = 1.0
    var gamma: Float = 2.2
    var toneMode: UInt32 = 1
    var pad: UInt32 = 0
}
