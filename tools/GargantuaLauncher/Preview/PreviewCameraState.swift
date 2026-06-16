import Foundation
import simd

/// Camera pose for the interactive preview viewport, expressed in spherical
/// coordinates around a target point (Google-Earth style orbit camera).
///
/// Convention matches the offline renderer's camera arguments: the accretion
/// disk lies in the world XY plane, the disk normal / spin axis is +Z, and the
/// camera Cartesian position maps directly onto `--camX/--camY/--camZ`.
///
/// - `theta` is the azimuth around the +Z spin axis (radians).
/// - `phi`   is the elevation above the disk plane (radians, 0 == edge-on).
struct PreviewCameraState: Equatable {
    var target: SIMD3<Float>
    var radius: Float
    var theta: Float
    var phi: Float
    var fov: Float
    var roll: Float

    init(
        target: SIMD3<Float> = .zero,
        radius: Float = 18.82,
        theta: Float = .pi,
        phi: Float = 0.2985,
        fov: Float = 58,
        roll: Float = 0
    ) {
        self.target = target
        self.radius = radius
        self.theta = theta
        self.phi = phi
        self.fov = fov
        self.roll = roll
    }

    /// Cartesian eye position. Disk plane = XY, spin axis = +Z.
    var eye: SIMD3<Float> {
        let cp = cos(phi)
        let sp = sin(phi)
        let offset = SIMD3<Float>(cp * sin(theta), cp * cos(theta), sp)
        return target + radius * offset
    }

    /// Orthonormal camera basis (forward, right, up) after applying roll.
    var basis: (forward: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>) {
        let forward = simd_normalize(target - eye)
        let worldUp = SIMD3<Float>(0, 0, 1)
        var right = simd_cross(forward, worldUp)
        // Guard against the degenerate near-pole case where forward ~ worldUp.
        if simd_length(right) < 1e-4 {
            right = SIMD3<Float>(1, 0, 0)
        }
        right = simd_normalize(right)
        var up = simd_normalize(simd_cross(right, forward))

        if abs(roll) > 1e-5 {
            let c = cos(roll)
            let s = sin(roll)
            let rRot = right * c + up * s
            let uRot = up * c - right * s
            right = simd_normalize(rRot)
            up = simd_normalize(uRot)
        }
        return (forward, right, up)
    }

    var azimuthDegrees: Double { Double(theta) * 180.0 / .pi }
    var elevationDegrees: Double { Double(phi) * 180.0 / .pi }
}

/// Orbit camera controller (logic layer). Reference type so that both the
/// SwiftUI model and the Metal renderer can share one source of truth.
///
/// Every mutation bumps `generation`; the renderer compares its last-seen
/// generation each frame and resets sample accumulation whenever it changes.
final class OrbitCameraController {
    private(set) var state: PreviewCameraState
    private(set) var generation: UInt64 = 0

    // Interaction tuning.
    var orbitSpeed: Float = 0.0075
    var zoomSpeed: Float = 0.0016
    // Closest approach. Below ~8 M a head-on Schwarzschild view (disk inner at
    // 6 M, the largest shadow) fills the frame entirely and reads as black, so
    // clamp the zoom to keep every metric/angle non-degenerate.
    var minRadius: Float = 8.0
    var maxRadius: Float = 240.0
    var minPhi: Float = -1.50   // ~ -86 degrees
    var maxPhi: Float = 1.50    // ~ +86 degrees
    var minFov: Float = 14
    var maxFov: Float = 110

    private let defaultState: PreviewCameraState

    init(state: PreviewCameraState = PreviewCameraState()) {
        self.state = state
        self.defaultState = state
    }

    private func bump() { generation &+= 1 }

    /// Pointer/trackpad drag: horizontal -> azimuth, vertical -> elevation.
    func orbit(deltaX: Float, deltaY: Float) {
        state.theta -= deltaX * orbitSpeed
        // Wrap azimuth into a stable range to avoid float drift.
        let twoPi = Float.pi * 2
        if state.theta > twoPi { state.theta -= twoPi }
        if state.theta < -twoPi { state.theta += twoPi }
        state.phi = clampF(state.phi + deltaY * orbitSpeed, minPhi, maxPhi)
        bump()
    }

    /// Wheel / pinch: positive delta zooms in (smaller radius).
    func zoom(delta: Float) {
        state.radius = clampF(state.radius * exp(-delta * zoomSpeed), minRadius, maxRadius)
        bump()
    }

    func setRadius(_ value: Double) {
        state.radius = clampF(Float(value), minRadius, maxRadius)
        bump()
    }

    func setAzimuthDegrees(_ value: Double) {
        state.theta = Float(value * .pi / 180.0)
        bump()
    }

    func setElevationDegrees(_ value: Double) {
        state.phi = clampF(Float(value * .pi / 180.0), minPhi, maxPhi)
        bump()
    }

    func setFov(_ value: Double) {
        state.fov = clampF(Float(value), minFov, maxFov)
        bump()
    }

    func setRoll(_ value: Double) {
        state.roll = Float(value * .pi / 180.0)
        bump()
    }

    func reset() {
        state = defaultState
        bump()
    }
}

@inline(__always)
func clampF(_ value: Float, _ lo: Float, _ hi: Float) -> Float {
    min(max(value, lo), hi)
}
