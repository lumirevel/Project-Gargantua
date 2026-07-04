import Foundation

/// First-principles returning-radiation (disk self-irradiation) transfer.
///
/// A luminous accretion disk emits photons that do not all escape: a fraction
/// follow bent, out-of-plane null geodesics and strike the disk again at another
/// radius, adding to the local heating. This is a real GR effect (Cunningham
/// 1976) that brightens and hardens the inner disk and scales strongly with spin.
///
/// This module computes the axisymmetric returning-radiation transfer by
/// integrating Kerr null geodesics on the CPU (Hamiltonian form, so turning
/// points need no manual sign handling), then folds the returned flux into the
/// Novikov-Thorne flux profile. It is pure and deterministic: given (a, r_in,
/// r_out, F_NT), it returns the radial temperature-enhancement ratio
/// `E(r) = T_tot/T_NT` plus energy-budget diagnostics. It runs once per render
/// config (spin/r_in fixed), like the disk atlas.
///
/// Units: geometric M = 1 (so the horizon is r_+ = 1 + sqrt(1-a^2), the
/// Schwarzschild ISCO is 6). Spin `a` is prograde-positive, matching
/// `diskKerrISCOM` in DiskOrbit.swift.
enum ReturningRadiation {

    struct Result {
        /// Radial grid (r/M), log-spaced over [r_in, r_out].
        let radii: [Double]
        /// Enhancement ratio E(r) = T_tot/T_NT >= 1 on `radii`.
        let enhancement: [Double]
        /// Fraction of emitted luminosity that returns to the disk (first bounce).
        let returningFraction: Double
        /// Fraction captured by the horizon.
        let capturedFraction: Double
        /// Fraction that escapes to infinity / outer boundary.
        let escapedFraction: Double
        /// Peak enhancement (at the inner edge).
        let peakEnhancement: Double
    }

    struct Config {
        var spin: Double
        var rInner: Double          // r_in / M (ISCO or given inner edge)
        var rOuter: Double          // r_out / M
        var strength: Double        // physical opt-in scale (0 => E == 1 everywhere)
        var bounces: Int            // return generations (>=1)
        var radialSamples: Int      // enhancement grid resolution
        var emitterSamples: Int     // log-r emitters used to build the transfer
        var polarSamples: Int       // comoving polar-angle samples per emitter
        var azimuthSamples: Int     // comoving azimuth samples per emitter
    }

    // MARK: - Public entry

    /// Novikov-Thorne flux shape closure returns F_NT(r)/F_ref on r/M (any
    /// positive scale; only ratios matter for the enhancement).
    static func compute(config c: Config, fluxNT: (Double) -> Double) -> Result {
        let a = min(max(c.spin, 0.0), 0.9985)
        let rIn = max(c.rInner, horizonRadius(a) * 1.0005)
        let rOut = max(c.rOuter, rIn * 1.5)
        let nR = max(c.radialSamples, 16)

        // Output radial grid (log-spaced).
        var radii = [Double](repeating: 0, count: nR)
        for i in 0..<nR {
            let t = Double(i) / Double(nR - 1)
            radii[i] = rIn * pow(rOut / rIn, t)
        }

        // Absent strength, the effect is identically off (byte-safe off switch).
        if !(c.strength > 1e-9) {
            return Result(radii: radii, enhancement: [Double](repeating: 1.0, count: nR),
                          returningFraction: 0, capturedFraction: 0, escapedFraction: 1,
                          peakEnhancement: 1.0)
        }

        // Emitter log-r grid; each emitter carries local NT flux F_NT(r_e).
        let nE = max(c.emitterSamples, 24)
        var emitR = [Double](repeating: 0, count: nE)
        var emitF = [Double](repeating: 0, count: nE)
        var emitArea = [Double](repeating: 0, count: nE)   // proper-ish annulus weight 2*pi*r*dr
        for i in 0..<nE {
            let t = (Double(i) + 0.5) / Double(nE)
            let r = rIn * pow(rOut / rIn, t)
            emitR[i] = r
            emitF[i] = max(fluxNT(r), 0.0)
            // d(r) for a log grid: r * d(ln r); ln-step = ln(rOut/rIn)/nE.
            let dlnr = log(rOut / rIn) / Double(nE)
            emitArea[i] = 2.0 * Double.pi * r * (r * dlnr)
        }

        // Build the first-bounce transfer: returned energy binned by landing r.
        // landDep[j] accumulates returning flux deposited into output bin j.
        var landDep = [Double](repeating: 0, count: nR)
        var totalEmitted = 0.0
        var totalReturned = 0.0
        var totalCaptured = 0.0
        var totalEscaped = 0.0

        let nPolar = max(c.polarSamples, 6)
        let nAzim = max(c.azimuthSamples, 8)

        for ie in 0..<nE {
            let re = emitR[ie]
            let emitLuminosity = emitF[ie] * emitArea[ie]
            if !(emitLuminosity > 0) { continue }
            let emit = EmitterFrame(r: re, a: a)

            // Hemisphere emission (upper); the lower hemisphere is symmetric and
            // deposits the same way, so we integrate one and the flux weights
            // already represent the full surface emission normalized to 1.
            var dirWeightSum = 0.0
            // First pass: normalization of the flux weight over the hemisphere so
            // sum(weight) == 1 (isotropic comoving surface brightness -> flux ~ cos).
            var samples: [(E: Double, L: Double, pr: Double, ptheta: Double, w: Double, up: Bool)] = []
            samples.reserveCapacity(nPolar * nAzim * 2)
            for ip in 0..<nPolar {
                // polar angle alpha in (0, pi/2): cos-weighted for flux through the
                // surface with isotropic comoving intensity (Lambertian).
                let ua = (Double(ip) + 0.5) / Double(nPolar)
                let alpha = 0.5 * Double.pi * ua
                let cosA = cos(alpha), sinA = sin(alpha)
                let fluxW = cosA * sinA           // cos(theta) * sin(theta) d(theta)
                for ja in 0..<nAzim {
                    let beta = 2.0 * Double.pi * (Double(ja) + 0.5) / Double(nAzim)
                    for up in [true, false] {
                        let mom = emit.photon(alpha: alpha, beta: beta, cosA: cosA, sinA: sinA, up: up)
                        samples.append((mom.E, mom.L, mom.pr, mom.ptheta, fluxW, up))
                        dirWeightSum += fluxW
                    }
                }
            }
            let wNorm = (dirWeightSum > 0) ? (1.0 / dirWeightSum) : 0.0

            for s in samples {
                let frac = s.w * wNorm                    // fraction of this emitter's flux
                let dLum = emitLuminosity * frac
                totalEmitted += dLum
                let outcome = integrate(a: a, rHorizon: horizonRadius(a),
                                        rIn: rIn, rOut: rOut,
                                        r0: re, E: s.E, L: s.L, pr0: s.pr, ptheta0: s.ptheta,
                                        up: s.up)
                switch outcome.kind {
                case .captured: totalCaptured += dLum
                case .escaped:  totalEscaped += dLum
                case .returned:
                    // Redshift of the bundle between emitter and lander (both on
                    // circular geodesics). g = (p.u)_land / (p.u)_emit; p.u_emit = -1
                    // by tetrad construction, so g = -(p.u)_land.
                    let land = OrbitFrame(r: outcome.rLand, a: a)
                    let pu = -(s.E) * land.ut + (s.L) * land.uphi   // p.u = p_t u^t + p_phi u^phi = -E u^t + L u^phi
                    let g = max(-pu, 1e-6)
                    // Incident heating flux ~ received energy; use g as the bundle
                    // energy-shift. (Overall normalization is physical: returned
                    // energy is a redistributed fraction of emitted energy.)
                    let deposited = dLum * g
                    totalReturned += dLum
                    accumulateLanding(&landDep, radii: radii, rLand: outcome.rLand, energy: deposited)
                }
            }
        }

        let returningFraction = (totalEmitted > 0) ? totalReturned / totalEmitted : 0
        let capturedFraction = (totalEmitted > 0) ? totalCaptured / totalEmitted : 0
        let escapedFraction = (totalEmitted > 0) ? totalEscaped / totalEmitted : 0

        // Peak NT flux, to floor the ratio denominator: the NT profile vanishes at
        // the zero-torque inner edge (and is tiny at the far outer edge), where a
        // raw F_ret/F_NT would blow up. Flooring at a small fraction of the peak
        // keeps the fractional enhancement finite there (T_NT itself -> 0 at the
        // exact ISCO, so the multiplicative form loses nothing physical), and the
        // enhancement is clamped to a physical ceiling.
        var fNTpeak = 1e-30
        for j in 0..<nR { fNTpeak = max(fNTpeak, fluxNT(radii[j])) }
        let fNTfloor = 1e-3 * fNTpeak
        let enhanceCeil = 2.0   // returning radiation enhances the continuum modestly

        // Convert deposited returning energy per output bin to an incident flux
        // F_ret(r) = landDep / annulusArea(r), then E(r) = (1 + s*F_ret/F_NT)^(1/4).
        var enhancement = [Double](repeating: 1.0, count: nR)
        var peak = 1.0
        let dlnrOut = log(rOut / rIn) / Double(max(nR - 1, 1))
        for j in 0..<nR {
            let r = radii[j]
            let area = 2.0 * Double.pi * r * (r * dlnrOut)
            let fRet = (area > 0) ? landDep[j] / area : 0.0
            let fNT = max(fluxNT(r), fNTfloor)
            // First bounce; multi-bounce geometric closure below.
            var ratio = fRet / fNT
            if c.bounces > 1 {
                // Each further generation returns ~returningFraction of the added
                // flux; geometric sum 1 + q + q^2 + ... capped by bounces.
                let q = min(max(returningFraction, 0.0), 0.9)
                var extra = ratio, term = ratio
                for _ in 1..<c.bounces { term *= q; extra += term }
                ratio = extra
            }
            let e = min(pow(max(1.0 + c.strength * ratio, 1.0), 0.25), enhanceCeil)
            enhancement[j] = e
            peak = max(peak, e)
        }

        return Result(radii: radii, enhancement: enhancement,
                      returningFraction: returningFraction,
                      capturedFraction: capturedFraction,
                      escapedFraction: escapedFraction,
                      peakEnhancement: peak)
    }

    // MARK: - Kerr helpers (M = 1)

    static func horizonRadius(_ a: Double) -> Double { 1.0 + sqrt(max(1.0 - a * a, 0.0)) }

    /// Circular equatorial geodesic orbit frame (prograde).
    struct OrbitFrame {
        let ut: Double     // u^t
        let uphi: Double   // u^phi
        let omega: Double  // d(phi)/dt
        init(r: Double, a: Double) {
            let rr = max(r, 1e-6)
            let omega = 1.0 / (pow(rr, 1.5) + a)          // prograde Omega
            let denom = 1.0 - 3.0 / rr + 2.0 * a * pow(rr, -1.5)
            let ut = 1.0 / sqrt(max(denom, 1e-9))
            self.omega = omega
            self.ut = ut
            self.uphi = omega * ut
        }
    }

    /// Orthonormal comoving tetrad of a circular equatorial emitter and the map
    /// from a comoving emission direction to Boyer-Lindquist photon momenta.
    struct EmitterFrame {
        let r: Double, a: Double
        let orbit: OrbitFrame
        // e_(phi) = A d_t + B d_phi (unit, orthogonal to u, in the t-phi plane).
        let ephiT: Double, ephiP: Double
        // metric (equator, M=1)
        let gtt: Double, gtp: Double, gpp: Double, grr: Double, gthth: Double
        let deltaOverR: Double  // sqrt(Delta)/r for the radial leg

        init(r: Double, a: Double) {
            self.r = r; self.a = a
            self.orbit = OrbitFrame(r: r, a: a)
            let rr = r
            let delta = rr * rr - 2.0 * rr + a * a
            gtt = -(1.0 - 2.0 / rr)
            gtp = -2.0 * a / rr
            gpp = rr * rr + a * a + 2.0 * a * a / rr
            grr = rr * rr / max(delta, 1e-9)
            gthth = rr * rr
            deltaOverR = sqrt(max(delta, 0.0)) / rr

            // Solve e_(phi) = A d_t + B d_phi with e_(phi).u = 0, |e_(phi)| = 1.
            let ut = orbit.ut, up = orbit.uphi
            // u.e = A(gtt ut + gtp up) + B(gtp ut + gpp up) = 0  -> A/B = -(gtp ut+gpp up)/(gtt ut+gtp up)
            let c1 = gtt * ut + gtp * up
            let c2 = gtp * ut + gpp * up
            // choose B, A along the orthogonal direction
            var A = c2
            var B = -c1
            // normalize: gtt A^2 + 2 gtp A B + gpp B^2 = 1
            let norm2 = gtt * A * A + 2.0 * gtp * A * B + gpp * B * B
            let inv = 1.0 / sqrt(max(norm2, 1e-12))
            A *= inv; B *= inv
            self.ephiT = A; self.ephiP = B
        }

        /// Comoving direction (alpha from disk normal, beta azimuth) -> conserved
        /// (E, L) and initial momenta (p_r, p_theta). `up` selects the hemisphere.
        func photon(alpha: Double, beta: Double, cosA: Double, sinA: Double, up: Bool)
            -> (E: Double, L: Double, pr: Double, ptheta: Double) {
            // Contravariant momentum in BL from the tetrad legs (E_com = 1):
            //   p = e_(t) + sinA cosB e_(r) + sinA sinB e_(phi) + cosA e_(zhat)
            // e_(t) = u ; e_(r)^r = sqrt(Delta)/r ; e_(phi) = A d_t + B d_phi ;
            // e_(zhat) = -e_(theta) = -(1/r) d_theta  (upward = decreasing theta).
            let zsign = up ? 1.0 : -1.0
            let pt = orbit.ut + sinA * sin(beta) * ephiT
            let pph = orbit.uphi + sinA * sin(beta) * ephiP
            let pr_con = sinA * cos(beta) * deltaOverR            // p^r
            let pth_con = zsign * cosA * (-1.0 / r)               // p^theta
            // Lower indices.
            let p_t = gtt * pt + gtp * pph
            let p_ph = gtp * pt + gpp * pph
            let p_r = grr * pr_con
            let p_th = gthth * pth_con
            let E = -p_t
            let L = p_ph
            return (E, L, p_r, p_th)
        }
    }

    // MARK: - Geodesic integration (Hamiltonian, affine)

    enum OutcomeKind { case captured, escaped, returned }
    struct Outcome { let kind: OutcomeKind; let rLand: Double }

    /// Inverse-metric components (Boyer-Lindquist, M=1).
    private static func invMetric(_ r: Double, _ theta: Double, _ a: Double)
        -> (gtt: Double, gtp: Double, gpp: Double, grr: Double, gthth: Double) {
        let sin2 = max(sin(theta) * sin(theta), 1e-12)
        let cos2 = cos(theta) * cos(theta)
        let sigma = r * r + a * a * cos2
        let delta = r * r - 2.0 * r + a * a
        let sd = max(sigma * delta, 1e-12)
        let gtt = -((r * r + a * a) * (r * r + a * a) - a * a * delta * sin2) / sd
        let gtp = -(2.0 * a * r) / sd
        let gpp = (delta - a * a * sin2) / (sd * sin2)
        let grr = delta / sigma
        let gthth = 1.0 / sigma
        return (gtt, gtp, gpp, grr, gthth)
    }

    /// Hamiltonian derivatives d(r,theta,p_r,p_theta)/d(lambda) for fixed E,L.
    private static func deriv(_ r: Double, _ th: Double, _ pr: Double, _ pth: Double,
                              E: Double, L: Double, a: Double)
        -> (dr: Double, dth: Double, dpr: Double, dpth: Double) {
        let m = invMetric(r, th, a)
        let dr = m.grr * pr
        let dth = m.gthth * pth
        // H = 1/2[ gtt E^2 - 2 gtp E L + gpp L^2 + grr pr^2 + gthth pth^2 ]  (p_t=-E)
        // dp_r = -dH/dr, dp_theta = -dH/dtheta (numeric derivatives of inv metric).
        let hR = 1e-4 * max(r, 1.0)
        let hT = 1e-4
        func H(_ rr: Double, _ tt: Double) -> Double {
            let mm = invMetric(rr, tt, a)
            return 0.5 * (mm.gtt * E * E - 2.0 * mm.gtp * E * L + mm.gpp * L * L
                          + mm.grr * pr * pr + mm.gthth * pth * pth)
        }
        let dpr = -(H(r + hR, th) - H(r - hR, th)) / (2.0 * hR)
        let dpth = -(H(r, th + hT) - H(r, th - hT)) / (2.0 * hT)
        return (dr, dth, dpr, dpth)
    }

    static func integrate(a: Double, rHorizon: Double, rIn: Double, rOut: Double,
                          r0: Double, E: Double, L: Double, pr0: Double, ptheta0: Double,
                          up: Bool) -> Outcome {
        var r = r0
        var th = Double.pi / 2.0
        var pr = pr0
        var pth = ptheta0
        let horizonStop = rHorizon * 1.001
        let escapeStop = max(rOut * 1.35, r0 * 1.35)
        // The disk is razor-thin; a photon has genuinely "left" it (rather than
        // skimmed the surface at emission) only once its latitude excursion
        // exceeds a small disk-thickness-scale angle. Only then can a re-crossing
        // of the equatorial plane count as a return, which also prevents the
        // emission point (theta == pi/2 exactly at step 0) from being mistaken for
        // a landing.
        let excursionThresh = 0.05
        var hasLeft = false
        let maxSteps = 20000

        for _ in 0..<maxSteps {
            // Adaptive affine step: finer near the horizon.
            let scale = min(max((r - rHorizon) / max(rHorizon, 1.0), 0.02), 1.0)
            let dl = 0.06 * scale * max(r, 1.0)

            // RK4
            let k1 = deriv(r, th, pr, pth, E: E, L: L, a: a)
            let k2 = deriv(r + 0.5 * dl * k1.dr, th + 0.5 * dl * k1.dth,
                           pr + 0.5 * dl * k1.dpr, pth + 0.5 * dl * k1.dpth, E: E, L: L, a: a)
            let k3 = deriv(r + 0.5 * dl * k2.dr, th + 0.5 * dl * k2.dth,
                           pr + 0.5 * dl * k2.dpr, pth + 0.5 * dl * k2.dpth, E: E, L: L, a: a)
            let k4 = deriv(r + dl * k3.dr, th + dl * k3.dth,
                           pr + dl * k3.dpr, pth + dl * k3.dpth, E: E, L: L, a: a)

            let rNext = r + dl / 6.0 * (k1.dr + 2 * k2.dr + 2 * k3.dr + k4.dr)
            let thNext = th + dl / 6.0 * (k1.dth + 2 * k2.dth + 2 * k3.dth + k4.dth)
            let prNext = pr + dl / 6.0 * (k1.dpr + 2 * k2.dpr + 2 * k3.dpr + k4.dpr)
            let pthNext = pth + dl / 6.0 * (k1.dpth + 2 * k2.dpth + 2 * k3.dpth + k4.dpth)

            // Genuine equatorial re-crossing: only once the ray has actually left
            // the disk (hasLeft, set from PRIOR steps), and the pre-step latitude is
            // off-plane, and the sign of (theta - pi/2) flips across this step.
            let d0 = th - Double.pi / 2.0
            let d1 = thNext - Double.pi / 2.0
            if hasLeft && d0 != 0.0 && ((d0 < 0) != (d1 < 0)) {
                let frac = abs(d0) / max(abs(d0) + abs(d1), 1e-12)
                let rLand = r + (rNext - r) * frac
                if rLand >= rIn && rLand <= rOut {
                    return Outcome(kind: .returned, rLand: min(max(rLand, rIn), rOut))
                } else if rLand < rIn {
                    return Outcome(kind: .captured, rLand: rLand)   // crosses inside ISCO -> plunges in
                } else {
                    return Outcome(kind: .escaped, rLand: rLand)    // crosses outside the disk -> escapes
                }
            }

            r = rNext; th = thNext; pr = prNext; pth = pthNext
            if abs(th - Double.pi / 2.0) > excursionThresh { hasLeft = true }

            if r <= horizonStop { return Outcome(kind: .captured, rLand: r) }
            if r >= escapeStop { return Outcome(kind: .escaped, rLand: r) }
        }
        return Outcome(kind: .escaped, rLand: r)
    }

    /// Deposit returning energy into the two nearest output bins (linear in log r).
    private static func accumulateLanding(_ dep: inout [Double], radii: [Double],
                                          rLand: Double, energy: Double) {
        let n = radii.count
        if n == 0 { return }
        if rLand <= radii[0] { dep[0] += energy; return }
        if rLand >= radii[n - 1] { dep[n - 1] += energy; return }
        // binary search
        var lo = 0, hi = n - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if radii[mid] <= rLand { lo = mid } else { hi = mid }
        }
        let t = (log(rLand) - log(radii[lo])) / max(log(radii[hi]) - log(radii[lo]), 1e-12)
        dep[lo] += energy * (1.0 - t)
        dep[hi] += energy * t
    }
}
