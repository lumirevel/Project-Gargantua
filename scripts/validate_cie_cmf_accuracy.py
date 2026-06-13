#!/usr/bin/env python3
"""Quantify CIE color matching function accuracy: Gaussian fit vs CIE 1931 table.

The renderer previously used a multi-Gaussian analytic CMF approximation in
both Metal and Swift spectral paths. This harness reproduces both
implementations and reports blackbody-locus chromaticity error against the
tabulated CIE 1931 2-degree standard observer (the same 5 nm table now compiled
into `Blackhole/Metal/cie_cmf.metalh` and
`Blackhole/Sources/Core/Physics/VisibleSpectrum.swift`).

It also cross-checks the table against published Planckian locus chromaticities
so the table transcription itself is validated, not just the delta between the
two implementations.
"""

from __future__ import annotations

import math

# CIE 1931 2-degree CMF, 380-780 nm at 5 nm (CIE 15 reference values).
# Must stay in sync with Blackhole/Metal/cie_cmf.metalh.
CMF_5NM = [
    (0.001368, 0.000039, 0.006450), (0.002236, 0.000064, 0.010550),
    (0.004243, 0.000120, 0.020050), (0.007650, 0.000217, 0.036210),
    (0.014310, 0.000396, 0.067850), (0.023190, 0.000640, 0.110200),
    (0.043510, 0.001210, 0.207400), (0.077630, 0.002180, 0.371300),
    (0.134380, 0.004000, 0.645600), (0.214770, 0.007300, 1.039050),
    (0.283900, 0.011600, 1.385600), (0.328500, 0.016840, 1.622960),
    (0.348280, 0.023000, 1.747060), (0.348060, 0.029800, 1.782600),
    (0.336200, 0.038000, 1.772110), (0.318700, 0.048000, 1.744100),
    (0.290800, 0.060000, 1.669200), (0.251100, 0.073900, 1.528100),
    (0.195360, 0.090980, 1.287640), (0.142100, 0.112600, 1.041900),
    (0.095640, 0.139020, 0.812950), (0.057950, 0.169300, 0.616200),
    (0.032010, 0.208020, 0.465180), (0.014700, 0.258600, 0.353300),
    (0.004900, 0.323000, 0.272000), (0.002400, 0.407300, 0.212300),
    (0.009300, 0.503000, 0.158200), (0.029100, 0.608200, 0.111700),
    (0.063270, 0.710000, 0.078250), (0.109600, 0.793200, 0.057250),
    (0.165500, 0.862000, 0.042160), (0.225750, 0.914850, 0.029840),
    (0.290400, 0.954000, 0.020300), (0.359700, 0.980300, 0.013400),
    (0.433450, 0.994950, 0.008750), (0.512050, 1.000000, 0.005750),
    (0.594500, 0.995000, 0.003900), (0.678400, 0.978600, 0.002750),
    (0.762100, 0.952000, 0.002100), (0.842500, 0.915400, 0.001800),
    (0.916300, 0.870000, 0.001650), (0.978600, 0.816300, 0.001400),
    (1.026300, 0.757000, 0.001100), (1.056700, 0.694900, 0.001000),
    (1.062200, 0.631000, 0.000800), (1.045600, 0.566800, 0.000600),
    (1.002600, 0.503000, 0.000340), (0.938400, 0.441200, 0.000240),
    (0.854450, 0.381000, 0.000190), (0.751400, 0.321000, 0.000100),
    (0.642400, 0.265000, 0.000050), (0.541900, 0.217000, 0.000030),
    (0.447900, 0.175000, 0.000020), (0.360800, 0.138200, 0.000010),
    (0.283500, 0.107000, 0.000000), (0.218700, 0.081600, 0.000000),
    (0.164900, 0.061000, 0.000000), (0.121200, 0.044580, 0.000000),
    (0.087400, 0.032000, 0.000000), (0.063600, 0.023200, 0.000000),
    (0.046770, 0.017000, 0.000000), (0.032900, 0.011920, 0.000000),
    (0.022700, 0.008210, 0.000000), (0.015840, 0.005723, 0.000000),
    (0.011359, 0.004102, 0.000000), (0.008111, 0.002929, 0.000000),
    (0.005790, 0.002091, 0.000000), (0.004109, 0.001484, 0.000000),
    (0.002899, 0.001047, 0.000000), (0.002049, 0.000740, 0.000000),
    (0.001440, 0.000520, 0.000000), (0.001000, 0.000361, 0.000000),
    (0.000690, 0.000249, 0.000000), (0.000476, 0.000172, 0.000000),
    (0.000332, 0.000120, 0.000000), (0.000235, 0.000085, 0.000000),
    (0.000166, 0.000060, 0.000000), (0.000117, 0.000042, 0.000000),
    (0.000083, 0.000030, 0.000000), (0.000059, 0.000021, 0.000000),
    (0.000042, 0.000015, 0.000000),
]

# Published Planckian locus chromaticities (CIE 1931 2-deg observer), used to
# validate the table transcription end to end.
PLANCKIAN_REFERENCE = {
    3000.0: (0.4369, 0.4041),
    4000.0: (0.3805, 0.3768),
    6500.0: (0.3135, 0.3237),
    10000.0: (0.2807, 0.2884),
}


def cmf_table(lam_nm: float) -> tuple[float, float, float]:
    t = (lam_nm - 380.0) / 5.0
    if t <= 0.0:
        return CMF_5NM[0] if t == 0.0 else (0.0, 0.0, 0.0)
    if t >= 80.0:
        return CMF_5NM[80] if t == 80.0 else (0.0, 0.0, 0.0)
    i0 = int(t)
    f = t - i0
    a, b = CMF_5NM[i0], CMF_5NM[i0 + 1]
    return tuple(a[k] + (b[k] - a[k]) * f for k in range(3))


def cmf_gaussian(lam: float) -> tuple[float, float, float]:
    t1 = (lam - 442.0) * (0.0624 if lam < 442.0 else 0.0374)
    t2 = (lam - 599.8) * (0.0264 if lam < 599.8 else 0.0323)
    t3 = (lam - 501.1) * (0.0490 if lam < 501.1 else 0.0382)
    x = 0.362 * math.exp(-0.5 * t1 * t1) + 1.056 * math.exp(-0.5 * t2 * t2) \
        - 0.065 * math.exp(-0.5 * t3 * t3)
    t1 = (lam - 568.8) * (0.0213 if lam < 568.8 else 0.0247)
    t2 = (lam - 530.9) * (0.0613 if lam < 530.9 else 0.0322)
    y = 0.821 * math.exp(-0.5 * t1 * t1) + 0.286 * math.exp(-0.5 * t2 * t2)
    t1 = (lam - 437.0) * (0.0845 if lam < 437.0 else 0.0278)
    t2 = (lam - 459.0) * (0.0385 if lam < 459.0 else 0.0725)
    z = 1.217 * math.exp(-0.5 * t1 * t1) + 0.681 * math.exp(-0.5 * t2 * t2)
    return (max(x, 0.0), max(y, 0.0), max(z, 0.0))


def planck_lambda(lam_m: float, temp: float) -> float:
    c1 = 1.1910429e-16
    c2 = 1.4387769e-2
    x = c2 / (lam_m * temp)
    if x > 700.0:
        return 0.0
    return c1 / (lam_m ** 5 * math.expm1(x))


def blackbody_xy(temp: float, cmf, n: int = 401) -> tuple[float, float]:
    lam_min, lam_max = 380.0, 780.0
    step = (lam_max - lam_min) / (n - 1)
    X = Y = Z = 0.0
    for i in range(n):
        lam_nm = lam_min + step * i
        b = planck_lambda(lam_nm * 1e-9, temp)
        xb, yb, zb = cmf(lam_nm)
        X += b * xb
        Y += b * yb
        Z += b * zb
    s = X + Y + Z
    if s <= 0.0:
        return (0.0, 0.0)
    return (X / s, Y / s)


def main() -> int:
    print("Blackbody chromaticity: Gaussian-fit CMF vs CIE 1931 table")
    print(f"{'T [K]':>8} {'table x,y':>18} {'gauss x,y':>18} "
          f"{'gauss err':>10} {'ref err':>9}")
    failures = 0
    worst_gauss = 0.0
    for temp in (2500.0, 3000.0, 4000.0, 5000.0, 6500.0, 8000.0, 10000.0,
                 15000.0, 20000.0, 30000.0, 50000.0):
        xt, yt = blackbody_xy(temp, cmf_table)
        xg, yg = blackbody_xy(temp, cmf_gaussian)
        gauss_err = math.hypot(xg - xt, yg - yt)
        worst_gauss = max(worst_gauss, gauss_err)
        ref = PLANCKIAN_REFERENCE.get(temp)
        ref_err = math.hypot(xt - ref[0], yt - ref[1]) if ref else float("nan")
        if ref is not None and ref_err > 0.0015:
            failures += 1
        print(f"{temp:8.0f} ({xt:.4f},{yt:.4f})  ({xg:.4f},{yg:.4f}) "
              f"{gauss_err:10.5f} {ref_err:9.5f}" if ref else
              f"{temp:8.0f} ({xt:.4f},{yt:.4f})  ({xg:.4f},{yg:.4f}) "
              f"{gauss_err:10.5f}        --")
    print(f"\nworst Gaussian-fit xy error across sweep: {worst_gauss:.5f}")
    if failures:
        print(f"FAIL: table disagrees with published Planckian locus at "
              f"{failures} temperature(s) by more than 0.0015 in xy")
        return 1
    print("PASS: table matches published Planckian locus within 0.0015 xy")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
