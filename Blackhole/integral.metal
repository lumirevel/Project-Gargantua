//
//  integral.metal
//  Blackhole
//
//  Created by 김령교 on 2/20/26.
//

#include <metal_stdlib>
using namespace metal;

#define M_PI 3.14159265358979323846f

struct Params {
    uint   width;
    uint   height;
    uint   fullWidth;
    uint   fullHeight;
    uint   offsetX;
    uint   offsetY;

    float3 camPos;     // p
    float3 planeX;
    float3 planeY;
    float3 z;
    float  d;          // resol/(2*tan(pi/3))

    float  rs;
    float  re;
    float  he;

    float  M;
    float  G;
    float  c;
    float  k;

    float  h;
    int    maxSteps;

    float  eps;        // horizon guard (예: 1e-5)
    int    metric;     // 0=schwarzschild, 1=kerr
    float  spin;       // a/M in [-1,1)
    int    kerrSubsteps;
    float  kerrTol;    // adaptive RK45 relative tolerance
    float  kerrEscapeMult;
    float  kerrRadialScale;  // Kerr ray-init radial calibration
    float  kerrAzimuthScale; // Kerr ray-init angular calibration
    float  kerrImpactScale;
    float  diskFlowTime;
    float  diskOrbitalBoost;
    float  diskRadialDrift;
    float  diskTurbulence;
    float  diskOrbitalBoostInner;
    float  diskOrbitalBoostOuter;
    float  diskRadialDriftInner;
    float  diskRadialDriftOuter;
    float  diskTurbulenceInner;
    float  diskTurbulenceOuter;
    float  diskFlowStep;
    float  diskFlowSteps;
    uint   diskAtlasMode;
    uint   diskAtlasWidth;
    uint   diskAtlasHeight;
    uint   diskAtlasWrapPhi;
    float  diskAtlasTempScale;
    float  diskAtlasDensityBlend;
    float  diskAtlasVrScale;
    float  diskAtlasVphiScale;
    float  diskAtlasRNormMin;
    float  diskAtlasRNormMax;
    float  diskAtlasRNormWarp;
    uint   diskNoiseModel; // 0=streamline cloud, 1=perlin texture
    float  diskMdotEdd;    // mdot / mdot_edd
    float  diskRadiativeEfficiency; // thin-disk eta
    uint   diskPhysicsMode; // 0=thin, 1=thick/plasma, 2=precision-nt
    float  diskPlungeFloor; // inner plunging emissivity floor (thick/precision)
    float  diskThickScale;  // thick-mode vertical half-thickness multiplier
    float  diskColorFactor; // hardening factor f_col (precision mode)
    float  diskReturningRad; // returning-radiation boost strength (precision)
    float  diskPrecisionTexture; // micro texture amplitude (precision)
    float  diskCloudCoverage; // clump covering fraction (precision clouds)
    float  diskCloudOpticalDepth; // reference LOS optical depth
    float  diskCloudPorosity; // empty-gap probability control
    float  diskCloudShadowStrength; // attenuation blend strength
    uint   diskReturnBounces; // returning-radiation bounce order (precision)
    uint   diskRTSteps; // volumetric RT march steps (0=adaptive)
    float  diskScatteringAlbedo; // scattering albedo for precision clouds
    float  _padPhysics;
};

struct CollisionInfo {
    uint   hit;          // 0 or 1
    float  ct;           // c * t
    float  T;            // disk temperature
    float  _pad0;
    float4 v_disk;       // x/y/z used, w padding
    float4 direct_world; // x/y/z used, w padding
    float  noise;        // 1단계는 0으로
    float  emit_r_norm;  // r / rs at sampled emission point
    float  emit_phi;     // atan2(y, x) in world disk plane
    float  emit_z_norm;  // z / rs at sampled emission point
};

static inline float3 conv(float r, float theta, float phi) {
    return float3(r * sin(theta) * cos(phi),
                  r * sin(theta) * sin(phi),
                  r * cos(theta));
}

static inline float4 schwarzschild_accel(float4 p, float4 v, constant Params& P) {
    float r = max(p.y, P.rs * (1.0 + P.eps));

    float dt = v.x;
    float dr = v.y;
    float dphi = v.w;

    float w  = 1.0 - P.rs / r;
    float dw = P.rs / (r * r);

    float ddt = -dw / w * dr * dt;
    float ddr = w * (r * dphi * dphi
                    + dw * (((dr / w) * (dr / w)) - (P.c * dt) * (P.c * dt)) * 0.5);
    float ddtheta = 0.0;
    float ddphi   = -2.0 * (dr / r) * dphi;

    return float4(ddt, ddr, ddtheta, ddphi);
}

static inline float4 kerr_equatorial_accel(float4 p, float4 v, constant Params& P) {
    float r = max(p.y, P.rs * (1.0 + P.eps));
    float rs = P.rs;
    float c = P.c;
    float a = clamp(P.spin, -0.999, 0.999) * (0.5 * rs);

    float dt = v.x;
    float dr = v.y;
    float dphi = v.w;

    float delta = r * r - rs * r + a * a;
    delta = max(delta, 1e-6);

    float dgtt = -(c * c * rs) / (r * r);
    float dgtphi = (a * rs * c) / (r * r);
    float dgphiphi = 2.0 * r - (a * a * rs) / (r * r);
    float ddelta = 2.0 * r - rs;
    float dgrr = (2.0 * r * delta - r * r * ddelta) / (delta * delta);

    // Exact inverse terms in equatorial Kerr BL with t in seconds.
    float gttInv = -(r * r + a * a + (a * a * rs / r)) / (c * c * delta);
    float gtphiInv = -(a * rs) / (c * r * delta);
    float gphiInv = (1.0 - rs / r) / delta;
    float grrInv = delta / (r * r);

    float gamma_t_tr = 0.5 * (gttInv * dgtt + gtphiInv * dgtphi);
    float gamma_t_rphi = 0.5 * (gttInv * dgtphi + gtphiInv * dgphiphi);

    float gamma_phi_tr = 0.5 * (gtphiInv * dgtt + gphiInv * dgtphi);
    float gamma_phi_rphi = 0.5 * (gtphiInv * dgtphi + gphiInv * dgphiphi);

    float gamma_r_tt = -0.5 * grrInv * dgtt;
    float gamma_r_tphi = -0.5 * grrInv * dgtphi;
    float gamma_r_rr = 0.5 * grrInv * dgrr;
    float gamma_r_phiphi = -0.5 * grrInv * dgphiphi;

    float ddt = -2.0 * (gamma_t_tr * dt * dr + gamma_t_rphi * dr * dphi);
    float ddr = -(gamma_r_tt * dt * dt
                + 2.0 * gamma_r_tphi * dt * dphi
                + gamma_r_rr * dr * dr
                + gamma_r_phiphi * dphi * dphi);
    float ddtheta = 0.0;
    float ddphi = -2.0 * (gamma_phi_tr * dt * dr + gamma_phi_rphi * dr * dphi);

    return float4(ddt, ddr, ddtheta, ddphi);
}

static inline float4 metric_accel(float4 p, float4 v, constant Params& P) {
    if (P.metric == 0) return schwarzschild_accel(p, v, P);
    return kerr_equatorial_accel(p, v, P);
}

static inline void rk4_step_h(thread float4 &p, thread float4 &v, constant Params& P, float h) {
    float4 k1_p = h * v;
    float4 k1_v = h * metric_accel(p, v, P);

    float4 k2_p = h * (v + 0.5 * k1_v);
    float4 k2_v = h * metric_accel(p + 0.5 * k1_p, v + 0.5 * k1_v, P);

    float4 k3_p = h * (v + 0.5 * k2_v);
    float4 k3_v = h * metric_accel(p + 0.5 * k2_p, v + 0.5 * k2_v, P);

    float4 k4_p = h * (v + k3_v);
    float4 k4_v = h * metric_accel(p + k3_p, v + k3_v, P);

    p += (k1_p + 2.0 * k2_p + 2.0 * k3_p + k4_p) / 6.0;
    v += (k1_v + 2.0 * k2_v + 2.0 * k3_v + k4_v) / 6.0;

    if (p.y < 0.0) {
        p.y = -p.y;
        p.w = fmod(p.w + M_PI, 2.0 * M_PI);
        if (p.w < 0.0) p.w += 2.0 * M_PI;
    }
}

static inline void rk4_step(thread float4 &p, thread float4 &v, constant Params& P) {
    rk4_step_h(p, v, P, P.h);
}

struct KerrState {
    float t;
    float r;
    float theta;
    float phi;
    float pr;
    float ptheta;
};

struct KerrDeriv {
    float t;
    float r;
    float theta;
    float phi;
    float pr;
    float ptheta;
};

struct KerrInvMetric {
    float gtt;
    float gtphi;
    float gphiphi;
    float grr;
    float gthetatheta;
};

struct KerrCovMetric {
    float gtt;
    float gtphi;
    float gphiphi;
    float grr;
    float gthetatheta;
    float sigma;
    float delta;
    float A;
};

static inline KerrState kerr_state_add(KerrState s, KerrDeriv k, float scale) {
    KerrState out;
    out.t = s.t + scale * k.t;
    out.r = s.r + scale * k.r;
    out.theta = s.theta + scale * k.theta;
    out.phi = s.phi + scale * k.phi;
    out.pr = s.pr + scale * k.pr;
    out.ptheta = s.ptheta + scale * k.ptheta;
    return out;
}

static inline KerrCovMetric kerr_cov_metric(float r, float theta, float a) {
    float rr = max(r, 1e-6);
    float th = clamp(theta, 1e-5, M_PI - 1e-5);
    float sth = sin(th);
    float cth = cos(th);
    float sth2 = max(sth * sth, 1e-10);
    float cth2 = cth * cth;

    float sigma = rr * rr + a * a * cth2;
    float delta = rr * rr - 2.0 * rr + a * a;
    float rsqPlusA2 = rr * rr + a * a;
    float A = rsqPlusA2 * rsqPlusA2 - a * a * delta * sth2;

    KerrCovMetric g;
    g.gtt = -(1.0 - (2.0 * rr / sigma));
    g.gtphi = -(2.0 * a * rr * sth2 / sigma);
    g.gphiphi = (A * sth2 / sigma);
    g.grr = sigma / max(delta, 1e-10);
    g.gthetatheta = sigma;
    g.sigma = sigma;
    g.delta = delta;
    g.A = A;
    return g;
}

static inline KerrInvMetric kerr_inv_metric(float r, float theta, float a) {
    float rr = max(r, 1e-6);
    float th = clamp(theta, 1e-5, M_PI - 1e-5);
    float sth = sin(th);
    float cth = cos(th);
    float sth2 = max(sth * sth, 1e-10);
    float cth2 = cth * cth;

    float sigma = rr * rr + a * a * cth2;
    float delta = max(rr * rr - 2.0 * rr + a * a, 1e-10);
    float rsqPlusA2 = rr * rr + a * a;
    float A = rsqPlusA2 * rsqPlusA2 - a * a * delta * sth2;

    KerrInvMetric g;
    g.gtt = -A / (sigma * delta);
    g.gtphi = -(2.0 * a * rr) / (sigma * delta);
    g.gphiphi = (delta - a * a * sth2) / (sigma * delta * sth2);
    g.grr = delta / sigma;
    g.gthetatheta = 1.0 / sigma;
    return g;
}

static inline void kerr_rhs_hamiltonian(KerrState s,
                                        float a,
                                        float Lz,
                                        thread KerrDeriv& dy,
                                        thread float& nullResidual)
{
    float r = max(s.r, 1e-6);
    float th = clamp(s.theta, 1e-5, M_PI - 1e-5);
    float p_t = -1.0;
    float p_phi = Lz;
    float pr = s.pr;
    float pth = s.ptheta;

    float a2 = a * a;
    float r2 = r * r;
    float rsqPlusA2 = r2 + a2;
    
    float sth = sin(th);
    float cth = cos(th);
    float s2 = max(sth * sth, 1e-10); // 0으로 나누기 방지
    float sc = sth * cth;

    // 공통 분모 및 기본 계량 항 계산
    float sigma = r2 + a2 * cth * cth;
    float delta = max(r2 - 2.0 * r + a2, 1e-10);
    
    float A = rsqPlusA2 * rsqPlusA2 - a2 * delta * s2;
    float D = max(sigma * delta, 1e-12);
    float D2 = max(D * D, 1e-24);
    float sigma2 = sigma * sigma;

    // 1. 역계량 텐서 (Inverse Metric) 컴포넌트
    float gtt = -A / D;
    float gtphi = -(2.0 * a * r) / D;
    float gphiphi = (delta - a2 * s2) / (D * s2);
    float grr = delta / sigma;
    float gthth = 1.0 / sigma;

    // 2. 위치의 도함수 계산 (x_dot = g^{mu nu} p_nu)
    dy.t = gtt * p_t + gtphi * p_phi;
    dy.phi = gtphi * p_t + gphiphi * p_phi;
    dy.r = grr * pr;
    dy.theta = gthth * pth;

    // 3. 구성 요소들의 해석적 편미분 (Analytical Partial Derivatives)
    float dSigma_dr = 2.0 * r;
    float dSigma_dth = -2.0 * a2 * sc;
    
    float dDelta_dr = 2.0 * (r - 1.0);
    
    float dA_dr = 4.0 * r * rsqPlusA2 - 2.0 * a2 * (r - 1.0) * s2;
    float dA_dth = -2.0 * a2 * delta * sc;
    
    float dD_dr = dSigma_dr * delta + sigma * dDelta_dr;
    float dD_dth = dSigma_dth * delta;

    // g^{tt} 편미분
    float dgr_gtt = -(dA_dr * D - A * dD_dr) / D2;
    float dgt_gtt = -(dA_dth * D - A * dD_dth) / D2;

    // g^{t\phi} 편미분
    float dgr_gtphi = -2.0 * a * (D - r * dD_dr) / D2;
    float dgt_gtphi = (2.0 * a * r * dD_dth) / D2;

    // g^{\phi\phi} 편미분 (몫의 미분법 적용)
    float numPhi = delta - a2 * s2;
    float denPhi = max(D * s2, 1e-12);
    float denPhi2 = max(denPhi * denPhi, 1e-24);
    
    float dNum_dr = dDelta_dr;
    float dNum_dth = -2.0 * a2 * sc;
    
    float dDen_dr = dD_dr * s2;
    float dDen_dth = dD_dth * s2 + D * 2.0 * sc;
    
    float dgr_gphiphi = (dNum_dr * denPhi - numPhi * dDen_dr) / denPhi2;
    float dgt_gphiphi = (dNum_dth * denPhi - numPhi * dDen_dth) / denPhi2;

    // g^{rr} 편미분
    float dgr_grr = (dDelta_dr * sigma - delta * dSigma_dr) / sigma2;
    float dgt_grr = -(delta * dSigma_dth) / sigma2;

    // g^{\theta\theta} 편미분
    float dgr_gthth = -dSigma_dr / sigma2;
    float dgt_gthth = -dSigma_dth / sigma2;

    // 4. 운동량의 도함수 계산 (p_dot = -0.5 * d g^{mu nu} / d x^alpha * p_mu * p_nu)
    float pr2 = pr * pr;
    float pth2 = pth * pth;

    float termR = dgr_gtt * p_t * p_t
                + 2.0 * dgr_gtphi * p_t * p_phi
                + dgr_gphiphi * p_phi * p_phi
                + dgr_grr * pr2
                + dgr_gthth * pth2;
                
    float termT = dgt_gtt * p_t * p_t
                + 2.0 * dgt_gtphi * p_t * p_phi
                + dgt_gphiphi * p_phi * p_phi
                + dgt_grr * pr2
                + dgt_gthth * pth2;

    dy.pr = -0.5 * termR;
    dy.ptheta = -0.5 * termT;

    // 5. 빛의 보존량 검증 (Null constraint residual)
    nullResidual = gtt * p_t * p_t
                 + 2.0 * gtphi * p_t * p_phi
                 + gphiphi * p_phi * p_phi
                 + grr * pr2
                 + gthth * pth2;
}

static inline void kerr_dp45_trial(KerrState s,
                                   float h,
                                   float a,
                                   float Lz,
                                   thread KerrState& outState,
                                   thread float& errNorm,
                                   thread float& nullResidualOut)
{
    const float a21 = 1.0 / 5.0;
    const float a31 = 3.0 / 40.0, a32 = 9.0 / 40.0;
    const float a41 = 44.0 / 45.0, a42 = -56.0 / 15.0, a43 = 32.0 / 9.0;
    const float a51 = 19372.0 / 6561.0, a52 = -25360.0 / 2187.0, a53 = 64448.0 / 6561.0, a54 = -212.0 / 729.0;
    const float a61 = 9017.0 / 3168.0, a62 = -355.0 / 33.0, a63 = 46732.0 / 5247.0, a64 = 49.0 / 176.0, a65 = -5103.0 / 18656.0;
    const float a71 = 35.0 / 384.0, a73 = 500.0 / 1113.0, a74 = 125.0 / 192.0, a75 = -2187.0 / 6784.0, a76 = 11.0 / 84.0;

    const float b1 = 5179.0 / 57600.0, b3 = 7571.0 / 16695.0, b4 = 393.0 / 640.0;
    const float b5 = -92097.0 / 339200.0, b6 = 187.0 / 2100.0, b7 = 1.0 / 40.0;

    KerrDeriv k1, k2, k3, k4, k5, k6, k7;
    float nr1, nr2, nr3, nr4, nr5, nr6, nr7;
    kerr_rhs_hamiltonian(s, a, Lz, k1, nr1);

    KerrState s2 = kerr_state_add(s, k1, h * a21);
    kerr_rhs_hamiltonian(s2, a, Lz, k2, nr2);

    KerrState s3 = s;
    s3.t += h * (a31 * k1.t + a32 * k2.t);
    s3.r += h * (a31 * k1.r + a32 * k2.r);
    s3.theta += h * (a31 * k1.theta + a32 * k2.theta);
    s3.phi += h * (a31 * k1.phi + a32 * k2.phi);
    s3.pr += h * (a31 * k1.pr + a32 * k2.pr);
    s3.ptheta += h * (a31 * k1.ptheta + a32 * k2.ptheta);
    kerr_rhs_hamiltonian(s3, a, Lz, k3, nr3);

    KerrState s4 = s;
    s4.t += h * (a41 * k1.t + a42 * k2.t + a43 * k3.t);
    s4.r += h * (a41 * k1.r + a42 * k2.r + a43 * k3.r);
    s4.theta += h * (a41 * k1.theta + a42 * k2.theta + a43 * k3.theta);
    s4.phi += h * (a41 * k1.phi + a42 * k2.phi + a43 * k3.phi);
    s4.pr += h * (a41 * k1.pr + a42 * k2.pr + a43 * k3.pr);
    s4.ptheta += h * (a41 * k1.ptheta + a42 * k2.ptheta + a43 * k3.ptheta);
    kerr_rhs_hamiltonian(s4, a, Lz, k4, nr4);

    KerrState s5 = s;
    s5.t += h * (a51 * k1.t + a52 * k2.t + a53 * k3.t + a54 * k4.t);
    s5.r += h * (a51 * k1.r + a52 * k2.r + a53 * k3.r + a54 * k4.r);
    s5.theta += h * (a51 * k1.theta + a52 * k2.theta + a53 * k3.theta + a54 * k4.theta);
    s5.phi += h * (a51 * k1.phi + a52 * k2.phi + a53 * k3.phi + a54 * k4.phi);
    s5.pr += h * (a51 * k1.pr + a52 * k2.pr + a53 * k3.pr + a54 * k4.pr);
    s5.ptheta += h * (a51 * k1.ptheta + a52 * k2.ptheta + a53 * k3.ptheta + a54 * k4.ptheta);
    kerr_rhs_hamiltonian(s5, a, Lz, k5, nr5);

    KerrState s6 = s;
    s6.t += h * (a61 * k1.t + a62 * k2.t + a63 * k3.t + a64 * k4.t + a65 * k5.t);
    s6.r += h * (a61 * k1.r + a62 * k2.r + a63 * k3.r + a64 * k4.r + a65 * k5.r);
    s6.theta += h * (a61 * k1.theta + a62 * k2.theta + a63 * k3.theta + a64 * k4.theta + a65 * k5.theta);
    s6.phi += h * (a61 * k1.phi + a62 * k2.phi + a63 * k3.phi + a64 * k4.phi + a65 * k5.phi);
    s6.pr += h * (a61 * k1.pr + a62 * k2.pr + a63 * k3.pr + a64 * k4.pr + a65 * k5.pr);
    s6.ptheta += h * (a61 * k1.ptheta + a62 * k2.ptheta + a63 * k3.ptheta + a64 * k4.ptheta + a65 * k5.ptheta);
    kerr_rhs_hamiltonian(s6, a, Lz, k6, nr6);

    KerrState s7 = s;
    s7.t += h * (a71 * k1.t + a73 * k3.t + a74 * k4.t + a75 * k5.t + a76 * k6.t);
    s7.r += h * (a71 * k1.r + a73 * k3.r + a74 * k4.r + a75 * k5.r + a76 * k6.r);
    s7.theta += h * (a71 * k1.theta + a73 * k3.theta + a74 * k4.theta + a75 * k5.theta + a76 * k6.theta);
    s7.phi += h * (a71 * k1.phi + a73 * k3.phi + a74 * k4.phi + a75 * k5.phi + a76 * k6.phi);
    s7.pr += h * (a71 * k1.pr + a73 * k3.pr + a74 * k4.pr + a75 * k5.pr + a76 * k6.pr);
    s7.ptheta += h * (a71 * k1.ptheta + a73 * k3.ptheta + a74 * k4.ptheta + a75 * k5.ptheta + a76 * k6.ptheta);
    kerr_rhs_hamiltonian(s7, a, Lz, k7, nr7);

    KerrState y5 = s7;
    KerrState y4 = s;
    y4.t += h * (b1 * k1.t + b3 * k3.t + b4 * k4.t + b5 * k5.t + b6 * k6.t + b7 * k7.t);
    y4.r += h * (b1 * k1.r + b3 * k3.r + b4 * k4.r + b5 * k5.r + b6 * k6.r + b7 * k7.r);
    y4.theta += h * (b1 * k1.theta + b3 * k3.theta + b4 * k4.theta + b5 * k5.theta + b6 * k6.theta + b7 * k7.theta);
    y4.phi += h * (b1 * k1.phi + b3 * k3.phi + b4 * k4.phi + b5 * k5.phi + b6 * k6.phi + b7 * k7.phi);
    y4.pr += h * (b1 * k1.pr + b3 * k3.pr + b4 * k4.pr + b5 * k5.pr + b6 * k6.pr + b7 * k7.pr);
    y4.ptheta += h * (b1 * k1.ptheta + b3 * k3.ptheta + b4 * k4.ptheta + b5 * k5.ptheta + b6 * k6.ptheta + b7 * k7.ptheta);

    float eT = abs(y5.t - y4.t) / max(1.0, max(abs(s.t), abs(y5.t)));
    float eR = abs(y5.r - y4.r) / max(1.0, max(abs(s.r), abs(y5.r)));
    float eTheta = abs(y5.theta - y4.theta) / max(1.0, max(abs(s.theta), abs(y5.theta)));
    float ePhi = abs(y5.phi - y4.phi) / max(1.0, max(abs(s.phi), abs(y5.phi)));
    float ePr = abs(y5.pr - y4.pr) / max(1.0, max(abs(s.pr), abs(y5.pr)));
    float ePth = abs(y5.ptheta - y4.ptheta) / max(1.0, max(abs(s.ptheta), abs(y5.ptheta)));
    errNorm = max(max(max(eT, eR), max(eTheta, ePhi)), max(ePr, ePth));
    if (!isfinite(errNorm)) errNorm = 1e30;

    outState = y5;
    nullResidualOut = nr7;
}

static inline bool kerr_init_hamiltonian(const float3 camPos,
                                         const float3 dirWorld,
                                         float a,
                                         constant Params& P,
                                         thread KerrState& state,
                                         thread float& Lz,
                                         thread float& horizonGeom)
{
    float massLen = 0.5 * P.rs;
    float rCamMeters = length(camPos);
    if (!(rCamMeters > 1e-12)) return false;
    float r0 = rCamMeters / max(massLen, 1e-12);

    float cosTheta0 = clamp(camPos.z / rCamMeters, -1.0, 1.0);
    float theta0 = acos(cosTheta0);
    float phi0 = atan2(camPos.y, camPos.x);
    float sinTheta0 = sin(theta0);
    float cosTheta0v = cos(theta0);
    float sinPhi0 = sin(phi0);
    float cosPhi0 = cos(phi0);

    float3 eR = float3(sinTheta0 * cosPhi0, sinTheta0 * sinPhi0, cosTheta0v);
    float3 eTheta = float3(cosTheta0v * cosPhi0, cosTheta0v * sinPhi0, -sinTheta0);
    float3 ePhi = float3(-sinPhi0, cosPhi0, 0.0);

    float nr = dot(dirWorld, eR);
    float nth = dot(dirWorld, eTheta);
    float nphi = dot(dirWorld, ePhi);
    float radialScale = max(P.kerrRadialScale, 0.01);
    float angularScaleInit = max(P.kerrAzimuthScale, 0.01);
    nr *= radialScale;
    nth *= angularScaleInit;
    nphi *= angularScaleInit;
    float nNorm = length(float3(nr, nth, nphi));
    if (!(nNorm > 1e-8)) return false;
    nr /= nNorm;
    nth /= nNorm;
    nphi /= nNorm;

    KerrCovMetric cov = kerr_cov_metric(r0, theta0, a);
    if (!(cov.delta > 1e-8)) return false;

    float alpha = sqrt(max((cov.sigma * cov.delta) / max(cov.A, 1e-12), 1e-12));
    float omega = (2.0 * a * r0) / max(cov.A, 1e-12);
    float sqrtGrr = sqrt(max(cov.grr, 1e-12));
    float sqrtGth = sqrt(max(cov.gthetatheta, 1e-12));
    float sqrtGphi = sqrt(max(cov.gphiphi, 1e-12));

    float kt = 1.0 / alpha;
    float kr = nr / sqrtGrr;
    float kth = nth / sqrtGth;
    float kphi = omega * kt + nphi / sqrtGphi;

    float p_t = cov.gtt * kt + cov.gtphi * kphi;
    float p_phi = cov.gtphi * kt + cov.gphiphi * kphi;
    float E = -p_t;
    if (!(E > 1e-8)) return false;

    state.t = 0.0;
    state.r = r0;
    state.theta = clamp(theta0, 1e-4, M_PI - 1e-4);
    state.phi = phi0;
    state.pr = (cov.grr * kr) / E;
    state.ptheta = (cov.gthetatheta * kth) / E;
    Lz = p_phi / E;

    KerrInvMetric inv = kerr_inv_metric(state.r, state.theta, a);
    float rest = inv.gtt
               + 2.0 * inv.gtphi * (-Lz)
               + inv.gphiphi * Lz * Lz
               + inv.gthetatheta * state.ptheta * state.ptheta;
    float rhs = -rest;
    if (rhs < -1e-3) return false;
    if (!isfinite(state.pr) || !isfinite(state.ptheta) || !isfinite(Lz)) return false;

    horizonGeom = 1.0 + sqrt(max(0.0, 1.0 - a * a));
    return true;
}

static inline float disk_kerr_isco_M(float a) {
    float aSafe = clamp(a, -0.999, 0.999);
    float a2 = aSafe * aSafe;
    float z1 = 1.0 + pow(max(1.0 - a2, 0.0), 1.0 / 3.0) * (pow(1.0 + aSafe, 1.0 / 3.0) + pow(1.0 - aSafe, 1.0 / 3.0));
    float z2 = sqrt(max(3.0 * a2 + z1 * z1, 0.0));
    float sgn = (aSafe >= 0.0) ? 1.0 : -1.0;
    return 3.0 + z2 - sgn * sqrt(max((3.0 - z1) * (3.0 + z1 + 2.0 * z2), 0.0));
}

static inline float disk_horizon_radius_m(constant Params& P);

static inline float disk_inner_radius_m(constant Params& P) {
    if (P.metric == 0) {
        // Schwarzschild prograde ISCO = 6M = 3rs.
        return 3.0 * P.rs;
    }
    float massLen = 0.5 * P.rs;
    float rI = disk_kerr_isco_M(clamp(P.spin, -0.999, 0.999)) * massLen;
    float rH = disk_horizon_radius_m(P);
    // Keep ISCO physically valid even when r_isco < rs at high prograde spin.
    return max(rI, rH * (1.0 + 16.0 * P.eps));
}

static inline float disk_horizon_radius_m(constant Params& P) {
    if (P.metric == 0) return P.rs;
    float a = clamp(abs(P.spin), 0.0, 0.999);
    float massLen = 0.5 * P.rs;
    float rPlusM = 1.0 + sqrt(max(1.0 - a * a, 0.0));
    return max(rPlusM * massLen, 0.25 * P.rs);
}

static inline float disk_emit_min_radius_m(constant Params& P) {
    float rIn = disk_inner_radius_m(P);
    if (P.diskPhysicsMode == 2u) {
        float plungeFloor = clamp(P.diskPlungeFloor, 0.0, 1.0);
        if (!(plungeFloor > 1e-6)) return rIn;
        float rH = disk_horizon_radius_m(P);
        float rPlungeMin = max(rH * (1.0 + 6.0 * P.eps), 0.90 * P.rs);
        float w = clamp(plungeFloor * 1.8, 0.0, 1.0);
        return mix(rIn, rPlungeMin, w);
    }
    if (P.diskPhysicsMode != 1u) return rIn;
    float rH = disk_horizon_radius_m(P);
    // Thick mode can emit inside ISCO, but avoid pushing too close to horizon by default.
    return max(rH * (1.0 + 6.0 * P.eps), 0.80 * P.rs);
}

static inline float disk_half_thickness_m(float rEmitM, constant Params& P) {
    if (P.diskPhysicsMode != 1u) return P.he;
    float rr = rEmitM / max(P.rs, 1e-6);
    // Thicker around inner/mid disk, taper near horizon and far outer edge.
    float innerRamp = smoothstep(0.9, 1.6, rr);
    float outerRamp = 1.0 - smoothstep(4.0, 9.0, rr);
    float band = clamp(innerRamp * outerRamp, 0.0, 1.0);
    float thickMul = 1.0 + (max(P.diskThickScale, 1.0) - 1.0) * band;
    return max(P.he * thickMul, P.he);
}

static inline float disk_nt_flux_shape(float rM, float rMsM, float a) {
    if (!(rM > rMsM)) return 0.0;
    float aSafe = clamp(a, -0.999, 0.999);
    float x = sqrt(max(rM, 1e-12));
    float x0 = sqrt(max(rMsM, 1e-12));
    float psi = acos(clamp(aSafe, -0.999999, 0.999999)) / 3.0;
    float x1 =  2.0 * cos(psi - M_PI / 3.0);
    float x2 =  2.0 * cos(psi + M_PI / 3.0);
    float x3 = -2.0 * cos(psi);
    float f0 = x - x0 - 1.5 * aSafe * log(max(x / max(x0, 1e-12), 1e-12));
    float d1 = x1 * (x1 - x2) * (x1 - x3);
    float d2 = x2 * (x2 - x1) * (x2 - x3);
    float d3 = x3 * (x3 - x1) * (x3 - x2);
    d1 = (abs(d1) > 1e-12) ? d1 : copysign(1e-12, d1);
    d2 = (abs(d2) > 1e-12) ? d2 : copysign(1e-12, d2);
    d3 = (abs(d3) > 1e-12) ? d3 : copysign(1e-12, d3);
    float t1 = 3.0 * pow(x1 - aSafe, 2.0) / d1;
    float t2 = 3.0 * pow(x2 - aSafe, 2.0) / d2;
    float t3 = 3.0 * pow(x3 - aSafe, 2.0) / d3;
    float e1 = (abs(x0 - x1) > 1e-12) ? (x0 - x1) : copysign(1e-12, x0 - x1);
    float e2 = (abs(x0 - x2) > 1e-12) ? (x0 - x2) : copysign(1e-12, x0 - x2);
    float e3 = (abs(x0 - x3) > 1e-12) ? (x0 - x3) : copysign(1e-12, x0 - x3);
    float l1 = log(max((x - x1) / e1, 1e-12));
    float l2 = log(max((x - x2) / e2, 1e-12));
    float l3 = log(max((x - x3) / e3, 1e-12));
    float q = f0 - t1 * l1 - t2 * l2 - t3 * l3;
    float den = max(4.0 * M_PI * rM * x * x * (x * x * x - 3.0 * x + 2.0 * aSafe), 1e-12);
    float fpt = 1.5 * q / den;
    return (isfinite(fpt) && (fpt > 0.0)) ? fpt : 0.0;
}

static inline float disk_nt_flux_correction(float rM, float rMsM, float a) {
    if (!(rM > rMsM)) return 0.0;
    float fpt = disk_nt_flux_shape(rM, rMsM, a);
    if (!(fpt > 0.0)) return 0.0;
    float fnt = (3.0 / (8.0 * M_PI)) * pow(max(rM, 1e-9), -3.0) * max(1.0 - sqrt(rMsM / rM), 0.0);
    if (!(fnt > 0.0)) return 0.0;
    float corr = fpt / fnt;
    if (!isfinite(corr)) return 0.0;
    return clamp(corr, 0.0, 8.0);
}

static inline float disk_effective_temperature(float rEmitM, float rInnerM, constant Params& P) {
    const float sigmaSB = 5.670374419e-8;
    const float kappaEs = 0.04;
    // Evaluate F(r) in dimensionless r/rs form to avoid float overflow.
    // F = (3/8) * (mdotEdd/eta) * c^3/(kappa_es * rs) * rr^-3 * (1 - sqrt(rr_in/rr))
    float eta = clamp(P.diskRadiativeEfficiency, 0.01, 0.42);
    float mdotNorm = max(P.diskMdotEdd, 1e-5);
    float rsSafe = max(P.rs, 1e-6);
    float rr = max(rEmitM / rsSafe, 1.0 + 1e-6);
    float rrIn = max(rInnerM / rsSafe, 1.0);
    float pref = (3.0 / 8.0) * (mdotNorm / eta) * (P.c * P.c * P.c) / max(kappaEs * rsSafe, 1e-20);
    if (rr > rrIn) {
        float boundary = max(1.0 - sqrt(rrIn / rr), 0.0);
        float flux = pref * pow(rr, -3.0) * boundary;
        if (P.diskPhysicsMode == 2u) {
            float massLen = 0.5 * rsSafe;
            float rM = rEmitM / max(massLen, 1e-12);
            float rMsM = rInnerM / max(massLen, 1e-12);
            float a = (P.metric == 0) ? 0.0 : clamp(P.spin, -0.999, 0.999);
            float rel = disk_nt_flux_correction(rM, rMsM, a);
            flux *= rel;
        }
        float t4 = flux / sigmaSB;
        if (!(t4 > 0.0) || !isfinite(t4)) return 0.0;
        float tEff = pow(t4, 0.25);
        if (P.diskPhysicsMode == 2u) {
            float fCol = max(P.diskColorFactor, 1.0);
            return tEff * fCol;
        }
        return tEff;
    }
    if (P.diskPhysicsMode == 2u) {
        float plungeFloor = clamp(P.diskPlungeFloor, 0.0, 1.0);
        if (!(plungeFloor > 1e-6)) return 0.0;

        // Precision mode: allow weak plunging emission continuation inside ISCO.
        // This keeps NT-like behavior outside ISCO while avoiding an artificial hard void.
        float rH = disk_horizon_radius_m(P) * (1.0 + 2.0 * P.eps);
        float rrH = max(rH / rsSafe, 0.2);
        float rrAnchor = rrIn * 1.02;
        float boundaryAnchor = max(1.0 - sqrt(rrIn / rrAnchor), 0.0);
        float fluxAnchor = pref * pow(rrAnchor, -3.0) * boundaryAnchor;
        float tAnchor = pow(max(fluxAnchor / sigmaSB, 1e-20), 0.25);
        if (!isfinite(tAnchor)) tAnchor = 0.0;

        float x = clamp((rr - rrH) / max(rrIn - rrH, 1e-6), 0.0, 1.0);
        float xSoft = smoothstep(0.0, 1.0, x);
        float captureProfile = pow(max(xSoft, 1e-4), 2.8);
        float floorProfile = pow(max(xSoft, 1e-4), 1.1);
        float plungeMix = plungeFloor * floorProfile + (1.0 - plungeFloor) * captureProfile;
        float advectiveCool = pow(max(rr / max(rrIn, 1e-4), 1e-4), 1.35);
        float captureFade = smoothstep(0.20, 0.90, xSoft);

        float fCol = max(P.diskColorFactor, 1.0);
        float tPlunge = max(tAnchor * plungeMix * advectiveCool * captureFade * fCol, 0.0);
        return isfinite(tPlunge) ? tPlunge : 0.0;
    }

    if (P.diskPhysicsMode != 1u) return 0.0;

    // Thick mode: finite but smooth plunging emissivity continuation inside ISCO.
    float rH = disk_horizon_radius_m(P) * (1.0 + 2.0 * P.eps);
    float rrH = max(rH / rsSafe, 0.2);
    float rrAnchor = rrIn * 1.03;
    float boundaryAnchor = max(1.0 - sqrt(rrIn / rrAnchor), 0.0);
    float fluxAnchor = pref * pow(rrAnchor, -3.0) * boundaryAnchor;
    float tAnchor = pow(max(fluxAnchor / sigmaSB, 1e-20), 0.25);
    if (!isfinite(tAnchor)) tAnchor = 0.0;

    float x = clamp((rr - rrH) / max(rrIn - rrH, 1e-6), 0.0, 1.0);
    float xSoft = smoothstep(0.0, 1.0, x);
    float plungeFloor = clamp(P.diskPlungeFloor, 0.0, 1.0);
    // Suppress horizon-proximate emission more strongly, while keeping a tunable floor.
    float captureProfile = pow(max(xSoft, 1e-4), 2.3);
    float floorProfile = max(xSoft, 1e-4);
    float plungeMix = plungeFloor * floorProfile + (1.0 - plungeFloor) * captureProfile;
    float advectiveCool = pow(max(rr / max(rrIn, 1e-4), 1e-4), 1.1);
    float captureFade = smoothstep(0.15, 0.80, xSoft);
    float thickT = max(tAnchor * plungeMix * advectiveCool * captureFade, 0.0);
    return isfinite(thickT) ? thickT : 0.0;
}

static inline bool disk_schwarzschild_circular_constants(float rM,
                                                         thread float& E,
                                                         thread float& L)
{
    if (!(rM > 3.01)) return false;
    float den = sqrt(max(rM * (rM - 3.0), 1e-12));
    E = (rM - 2.0) / den;
    L = rM / sqrt(max(rM - 3.0, 1e-12));
    return isfinite(E) && isfinite(L) && (E > 0.0);
}

static inline bool disk_schwarzschild_plunge_local_beta(float rM,
                                                        float rMsM,
                                                        thread float& betaR,
                                                        thread float& betaPhi)
{
    betaR = 0.0;
    betaPhi = 0.0;
    float Ems = 0.0;
    float Lms = 0.0;
    if (!disk_schwarzschild_circular_constants(rMsM, Ems, Lms)) return false;
    float w = 1.0 - 2.0 / max(rM, 1e-6);
    if (!(w > 1e-8)) return false;
    float ur2 = Ems * Ems - w * (1.0 + (Lms * Lms) / max(rM * rM, 1e-12));
    if (!(ur2 >= 0.0)) ur2 = 0.0;
    float ur = -sqrt(max(ur2, 0.0)); // inward plunge
    float ut = Ems / w;
    if (!(ut > 1e-8)) return false;
    float uphi = Lms / max(rM * rM, 1e-12);
    float drdt = ur / ut;
    betaR = drdt / w;
    betaPhi = (rM * uphi / ut) / sqrt(max(w, 1e-12));
    float beta2 = betaR * betaR + betaPhi * betaPhi;
    if (!isfinite(beta2)) return false;
    if (beta2 > 0.999 * 0.999) {
        float scale = 0.999 / sqrt(max(beta2, 1e-12));
        betaR *= scale;
        betaPhi *= scale;
    }
    return true;
}

static inline bool disk_kerr_circular_constants(float rM,
                                                float a,
                                                thread float& E,
                                                thread float& L)
{
    float rr = max(rM, 1e-6);
    float x = sqrt(rr);
    float denTerm = rr * x - 3.0 * x + 2.0 * a;
    if (!(denTerm > 1e-10)) return false;
    float den = pow(rr, 0.75) * sqrt(denTerm);
    if (!(den > 1e-12)) return false;
    E = (rr * x - 2.0 * x + a) / den;
    L = (rr * rr - 2.0 * a * x + a * a) / den;
    return isfinite(E) && isfinite(L) && (E > 0.0);
}

static inline bool disk_kerr_plunge_kinematics(float rM,
                                               float rMsM,
                                               float a,
                                               thread float& omega,
                                               thread float& drdt,
                                               thread float& vrRatioOut)
{
    float Ems = 0.0;
    float Lms = 0.0;
    if (!disk_kerr_circular_constants(rMsM, a, Ems, Lms)) return false;
    KerrCovMetric cov = kerr_cov_metric(rM, 0.5 * M_PI, a);
    float det = cov.gtphi * cov.gtphi - cov.gtt * cov.gphiphi;
    if (!(det > 1e-12)) return false;
    float ut = (Ems * cov.gphiphi + Lms * cov.gtphi) / det;
    float uphi = (-Ems * cov.gtphi - Lms * cov.gtt) / det;
    if (!(ut > 1e-8) || !isfinite(uphi)) return false;
    float ur2Num = -1.0
                 - cov.gtt * ut * ut
                 - 2.0 * cov.gtphi * ut * uphi
                 - cov.gphiphi * uphi * uphi;
    float ur2 = ur2Num / max(cov.grr, 1e-12);
    float ur = -sqrt(max(ur2, 0.0)); // inward plunge
    omega = uphi / ut;
    drdt = ur / ut;
    if (!isfinite(omega) || !isfinite(drdt)) return false;
    float vrRef = sqrt(max(1.0 / max(rM, 1e-6), 1e-8));
    vrRatioOut = clamp(drdt / max(vrRef, 1e-6), -1.0, 1.0);
    return true;
}

static inline bool inside_disk_volume(float3 pos, constant Params& P) {
    float dxy = length(float2(pos.x, pos.y));
    float rMin = disk_emit_min_radius_m(P);
    float halfH = disk_half_thickness_m(dxy, P);
    return (dxy > rMin && dxy < P.re && abs(pos.z) < halfH);
}

static inline bool segment_enter_disk(float3 p0,
                                      float3 p1,
                                      constant Params& P,
                                      thread float& tEnter)
{
    bool in0 = inside_disk_volume(p0, P);
    bool in1 = inside_disk_volume(p1, P);

    if (!in0 && in1) {
        float lo = 0.0;
        float hi = 1.0;
        for (int i = 0; i < 10; ++i) {
            float mid = 0.5 * (lo + hi);
            bool inMid = inside_disk_volume(mix(p0, p1, mid), P);
            if (inMid) hi = mid;
            else lo = mid;
        }
        tEnter = hi;
        return true;
    }

    // Outside -> outside skip protection for thin disk crossings.
    const int coarse = 48;
    bool prevIn = in0;
    float prevT = 0.0;
    for (int i = 1; i <= coarse; ++i) {
        float t = float(i) / float(coarse);
        bool nowIn = inside_disk_volume(mix(p0, p1, t), P);
        if (!prevIn && nowIn) {
            float lo = prevT;
            float hi = t;
            for (int j = 0; j < 10; ++j) {
                float mid = 0.5 * (lo + hi);
                bool inMid = inside_disk_volume(mix(p0, p1, mid), P);
                if (inMid) hi = mid;
                else lo = mid;
            }
            tEnter = hi;
            return true;
        }
        prevIn = nowIn;
        prevT = t;
    }
    return false;
}

static inline float hash13(float3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float2 hash23(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract(float2((p3.x + p3.y) * p3.z,
                        (p3.x + p3.z) * p3.y));
}

static inline float noise3D(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);

    float n000 = hash13(i + float3(0.0, 0.0, 0.0));
    float n100 = hash13(i + float3(1.0, 0.0, 0.0));
    float n010 = hash13(i + float3(0.0, 1.0, 0.0));
    float n110 = hash13(i + float3(1.0, 1.0, 0.0));
    float n001 = hash13(i + float3(0.0, 0.0, 1.0));
    float n101 = hash13(i + float3(1.0, 0.0, 1.0));
    float n011 = hash13(i + float3(0.0, 1.0, 1.0));
    float n111 = hash13(i + float3(1.0, 1.0, 1.0));

    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z);
}

static inline float fbm(float3 p) {
    float total = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 4; ++i) {
        total += noise3D(p * frequency) * amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
        p += float3(0.25);
    }
    return total;
}

static inline float2 disk_div_free_turbulence(float2 q, float phase) {
    const float eps = 0.07;
    float3 base = float3(q * 4.5, phase * 0.3);
    float psiXm = noise3D(base + float3(-eps, 0.0, 0.0));
    float psiXp = noise3D(base + float3( eps, 0.0, 0.0));
    float psiYm = noise3D(base + float3(0.0, -eps, 0.0));
    float psiYp = noise3D(base + float3(0.0,  eps, 0.0));
    float dpsiDx = (psiXp - psiXm) / (2.0 * eps);
    float dpsiDy = (psiYp - psiYm) / (2.0 * eps);
    return float2(dpsiDy, -dpsiDx);
}

static inline float disk_particle_cell_density(float2 uv, float phase) {
    float2 cell = floor(uv);
    float2 f = fract(uv);
    float bestD2 = 1e9;
    for (int oy = -1; oy <= 1; ++oy) {
        for (int ox = -1; ox <= 1; ++ox) {
            float2 g = float2(float(ox), float(oy));
            float2 id = cell + g;
            float2 jitter = hash23(id + float2(phase * 0.37, -phase * 0.23));
            float2 center = g + jitter;
            float2 d = f - center;
            bestD2 = min(bestD2, dot(d, d));
        }
    }
    float dist = sqrt(bestD2);
    return smoothstep(0.62, 0.10, dist);
}

static inline float perlin_fade(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

static inline float perlin_lerp(float a, float b, float t) {
    return a + t * (b - a);
}

static inline uint perlin_hash2(uint x, uint y, uint seed) {
    uint h = x * 374761393u + y * 668265263u + seed * 2246822519u + 3266489917u;
    h ^= (h >> 13);
    h *= 1274126177u;
    h ^= (h >> 16);
    return h;
}

static inline float perlin_grad2(uint h, float x, float y) {
    switch (h & 7u) {
        case 0u: return  x + y;
        case 1u: return -x + y;
        case 2u: return  x - y;
        case 3u: return -x - y;
        case 4u: return  x;
        case 5u: return -x;
        case 6u: return  y;
        default: return -y;
    }
}

static inline int perlin_pos_mod(int x, int m) {
    int r = x % m;
    return (r < 0) ? (r + m) : r;
}

static inline float perlin2_repeat(float x, float y, int repeatX, int repeatY, uint base) {
    int x0 = int(floor(x));
    int y0 = int(floor(y));
    int x1 = x0 + 1;
    int y1 = y0 + 1;

    float xf = x - float(x0);
    float yf = y - float(y0);

    int rx0 = perlin_pos_mod(x0, repeatX);
    int ry0 = perlin_pos_mod(y0, repeatY);
    int rx1 = perlin_pos_mod(x1, repeatX);
    int ry1 = perlin_pos_mod(y1, repeatY);

    float n00 = perlin_grad2(perlin_hash2(uint(rx0), uint(ry0), base), xf, yf);
    float n10 = perlin_grad2(perlin_hash2(uint(rx1), uint(ry0), base), xf - 1.0, yf);
    float n01 = perlin_grad2(perlin_hash2(uint(rx0), uint(ry1), base), xf, yf - 1.0);
    float n11 = perlin_grad2(perlin_hash2(uint(rx1), uint(ry1), base), xf - 1.0, yf - 1.0);

    float u = perlin_fade(xf);
    float v = perlin_fade(yf);
    float nx0 = perlin_lerp(n00, n10, u);
    float nx1 = perlin_lerp(n01, n11, u);
    return perlin_lerp(nx0, nx1, v);
}

static inline float disk_perlin_texture_noise(float dxy, float phi, float z, constant Params& P) {
    float denom = max(P.re - P.rs, 1e-6);
    float u = clamp((dxy - P.rs) / denom, 0.0, 1.0);

    float spiral = phi + 1.8 * log(max(dxy / P.rs, 1.0));
    float c = cos(spiral);
    float s = sin(spiral);

    float bx = 12.0 * u + 2.6 * c;
    float by = 2.6 * s;

    float w1 = perlin2_repeat(96.0 * bx, 96.0 * by, 8192, 8192, 23u);
    float w2 = perlin2_repeat(144.0 * bx + 1.6 * w1, 144.0 * by - 1.1 * w1, 8192, 8192, 71u);

    float fbmVal = 0.0;
    float amp = 1.0;
    float freq = 1.0;
    float ampSum = 0.0;
    for (int i = 0; i < 5; ++i) {
        float nx = (bx + 0.20 * w1) * freq;
        float ny = (by + 0.18 * w2) * freq;
        float n = perlin2_repeat(128.0 * nx, 128.0 * ny, 8192, 8192, 101u + uint(i * 53));
        fbmVal += amp * n;
        ampSum += amp;
        amp *= 0.55;
        freq *= 2.0;
    }
    fbmVal = (ampSum > 0.0) ? (fbmVal / ampSum) : 0.0;

    float zFade = exp(-abs(z) / max(1.25 * P.he, 1e-6));
    float edgeIn = smoothstep(0.01, 0.08, u);
    float edgeOut = 1.0 - smoothstep(0.94, 0.998, u);
    float radialFade = edgeIn * edgeOut;

    // Normalize to [0,1] so compose path remains consistent with cloud normalization.
    float n = clamp(3.2 * fbmVal * zFade * radialFade, -1.0, 1.0);
    return 0.5 + 0.5 * n;
}

static inline float disk_precision_texture_factor(float dxy, float phi, float z, constant Params& P) {
    float amp = clamp(P.diskPrecisionTexture, 0.0, 1.0);
    if (!(amp > 1e-6)) return 1.0;
    float base = disk_perlin_texture_noise(dxy, phi + 0.23 * P.diskFlowTime, z, P);
    float centered = 2.0 * base - 1.0;
    float rsSafe = max(P.rs, 1e-6);
    float rr = dxy / rsSafe;
    float radial = smoothstep(1.05, 1.9, rr) * (1.0 - smoothstep(10.0, 18.0, rr));
    float vertical = exp(-abs(z) / max(1.5 * P.he, 1e-6));
    float phaseWave = sin(7.0 * phi + 0.55 * log(max(rr, 1.0)));
    float micro = 0.72 * centered + 0.28 * phaseWave;
    float fac = 1.0 + (0.48 * amp * radial * vertical) * micro;
    return clamp(fac, 0.20, 2.10);
}

static inline float disk_flow_radial_mix(float rRs, constant Params& P) {
    float reRs = max(P.re / max(P.rs, 1e-6), 1.02);
    float x = clamp((rRs - 1.0) / max(reRs - 1.0, 1e-6), 0.0, 1.0);
    return smoothstep(0.0, 1.0, x);
}

static inline float disk_orbital_boost_at_r(float rRs, constant Params& P) {
    float t = disk_flow_radial_mix(rRs, P);
    return mix(P.diskOrbitalBoostInner, P.diskOrbitalBoostOuter, t);
}

static inline float disk_radial_drift_at_r(float rRs, constant Params& P) {
    float t = disk_flow_radial_mix(rRs, P);
    return mix(P.diskRadialDriftInner, P.diskRadialDriftOuter, t);
}

static inline float disk_turbulence_at_r(float rRs, constant Params& P) {
    float t = disk_flow_radial_mix(rRs, P);
    return mix(P.diskTurbulenceInner, P.diskTurbulenceOuter, t);
}

static inline float disk_kepler_omega(float rRs, constant Params& P) {
    float rr = max(rRs, 1.0001);
    float omega = 1.0 / max(pow(rr, 1.5), 1e-6);
    if (P.metric == 1) {
        float a = clamp(P.spin, -0.999, 0.999);
        omega = 1.0 / max(pow(rr, 1.5) + a, 1e-6);
    }
    return disk_orbital_boost_at_r(rr, P) * omega;
}

static inline float disk_cloud_noise(float r, float phi, float z, float ctLen, constant Params& P) {
    float rs = max(P.rs, 1e-6);
    float reRs = max(P.re / rs, 1.02);
    float heRs = max(P.he / rs, 1e-5);
    float heRsSafe = max(heRs, 1e-6);
    float spanRs = max(reRs - 1.0, 1e-6);

    float rRs = clamp(r / rs, 1.0005, reRs * 1.10);
    float phiFlow = phi;
    float zRs = z / rs;

    float accum = 0.0;
    float wsum = 0.0;
    float phase = P.diskFlowTime + 0.28 * (ctLen / rs);
    int streamSteps = clamp((int)round(P.diskFlowSteps), 2, 24);
    float baseDt = clamp(P.diskFlowStep, 0.02, 0.60);
    const float invTwoPi = 0.5 / M_PI;

    for (int i = 0; i < streamSteps; ++i) {
        float radialNorm = clamp((rRs - 1.0) / spanRs, 0.0, 1.0);
        float dt = baseDt * mix(0.55, 1.0, radialNorm);
        float2 er = float2(cos(phiFlow), sin(phiFlow));
        float2 ephi = float2(-er.y, er.x);
        float2 q = radialNorm * er;
        float localPhase = phase - float(i) * dt;

        float2 turbPlane = disk_div_free_turbulence(q + 0.35 * ephi, localPhase);
        float turbR = dot(turbPlane, er);
        float turbPhi = dot(turbPlane, ephi);
        float turbZ = 2.0 * noise3D(float3(q * 5.0, localPhase * 0.8 + 17.0)) - 1.0;
        float turbAmp = disk_turbulence_at_r(rRs, P);

        float omega = disk_kepler_omega(rRs, P);
        omega += (0.18 * turbAmp * turbPhi) / max(rRs, 1.0);

        float inward = disk_radial_drift_at_r(rRs, P) * (0.35 + 0.65 * sqrt(1.0 / max(rRs, 1.0)));
        float vR = -inward + 0.28 * turbAmp * turbR;
        float vZ = -0.30 * (zRs / heRsSafe) + 0.22 * turbAmp * turbZ;

        // Backtrace streamline so local density reflects particles flowing from upstream.
        rRs = clamp(rRs - vR * dt, 1.0005, reRs * 1.15);
        phiFlow -= omega * dt;
        zRs -= vZ * dt * heRs;

        float phiWrap = phiFlow * invTwoPi;
        float azCells = mix(48.0, 180.0, 1.0 - radialNorm);
        float2 uv = float2(radialNorm * 14.0,
                           phiWrap * azCells + localPhase * (2.0 + 3.0 * (1.0 - radialNorm)));
        float particle = disk_particle_cell_density(uv, localPhase + 19.3 * radialNorm);

        float3 filPos = float3(q * (8.0 + 4.0 * (1.0 - radialNorm)),
                               (zRs / heRsSafe) * 0.9);
        filPos.z += localPhase * 0.33;
        float fil = fbm(filPos);
        float ridge = 1.0 - abs(2.0 * fil - 1.0);
        float filament = smoothstep(0.38, 0.86, ridge);

        float radialEdge = smoothstep(0.01, 0.10, radialNorm) * (1.0 - smoothstep(0.90, 1.0, radialNorm));
        float verticalEdge = 1.0 - smoothstep(0.75, 1.9, abs(zRs) / heRsSafe);
        float sample = mix(particle, filament, 0.35) * radialEdge * verticalEdge;

        float w = pow(0.74, float(i));
        accum += sample * w;
        wsum += w;
    }

    if (!(wsum > 0.0)) return 0.0;
    float density = accum / wsum;
    density = pow(clamp(density, 0.0, 1.0), 0.85);
    return density;
}

static inline uint disk_atlas_index(uint x, uint y, constant Params& P) {
    return y * P.diskAtlasWidth + x;
}

static inline float4 disk_sample_atlas(float r, float phi, constant Params& P, device const float4* diskAtlas) {
    if (P.diskAtlasMode == 0u || P.diskAtlasWidth == 0u || P.diskAtlasHeight == 0u) {
        return float4(1.0, 0.0, 0.0, 1.0);
    }

    float rs = max(P.rs, 1e-6);
    float reRs = max(P.re / rs, 1.0001);
    float atlasRMin = max(P.diskAtlasRNormMin, 0.0);
    float atlasRMax = max(P.diskAtlasRNormMax, atlasRMin + 1e-6);
    if (!(atlasRMax > atlasRMin)) {
        atlasRMin = 1.0;
        atlasRMax = reRs;
    }
    float r01 = clamp((r / rs - atlasRMin) / max(atlasRMax - atlasRMin, 1e-6), 0.0, 1.0);
    float rWarp = max(P.diskAtlasRNormWarp, 1e-3);
    float rNorm = pow(r01, rWarp);
    float phiNorm = phi * (0.5 / M_PI);
    if (P.diskAtlasWrapPhi != 0u) {
        phiNorm = fract(phiNorm);
    } else {
        phiNorm = clamp(phiNorm, 0.0, 1.0);
    }

    float atlasX = phiNorm * float(max(P.diskAtlasWidth - 1u, 0u));
    float atlasY = rNorm * float(max(P.diskAtlasHeight - 1u, 0u));
    uint x0 = uint(floor(atlasX));
    uint y0 = uint(floor(atlasY));
    uint x1 = (P.diskAtlasWrapPhi != 0u) ? ((x0 + 1u) % max(P.diskAtlasWidth, 1u)) : min(x0 + 1u, P.diskAtlasWidth - 1u);
    uint y1 = min(y0 + 1u, P.diskAtlasHeight - 1u);
    float tx = atlasX - float(x0);
    float ty = atlasY - float(y0);

    float4 a00 = diskAtlas[disk_atlas_index(x0, y0, P)];
    float4 a10 = diskAtlas[disk_atlas_index(x1, y0, P)];
    float4 a01 = diskAtlas[disk_atlas_index(x0, y1, P)];
    float4 a11 = diskAtlas[disk_atlas_index(x1, y1, P)];
    float4 a0 = mix(a00, a10, tx);
    float4 a1 = mix(a01, a11, tx);
    return mix(a0, a1, ty);
}

static inline void init_collision_info(thread CollisionInfo& info) {
    info.hit = 0;
    info.ct  = 0.0;
    info.T   = 0.0;
    info.v_disk = float4(0);
    info.direct_world = float4(0);
    info.noise = 0.0;
    info.emit_r_norm = 0.0;
    info.emit_phi = 0.0;
    info.emit_z_norm = 0.0;
}

static inline float3 disk_sample_probe_pos(float3 hitPos,
                                           float3 world0,
                                           float3 worldPos,
                                           constant Params& P)
{
    float3 segProbe = worldPos - world0;
    float segProbeLen2 = dot(segProbe, segProbe);
    float3 samplePos = hitPos;
    if (segProbeLen2 > 1e-20) {
        float3 probe = hitPos + normalize(segProbe) * (0.35 * P.he);
        if (inside_disk_volume(probe, P)) samplePos = probe;
    }
    return samplePos;
}

static inline void disk_set_noise_and_bridge(thread CollisionInfo& info,
                                             float3 samplePos,
                                             float ctLen,
                                             constant Params& P,
                                             device const float4* diskAtlas)
{
    float sampleR = length(float2(samplePos.x, samplePos.y));
    float phiPos = atan2(samplePos.y, samplePos.x);
    float baseNoise = (P.diskNoiseModel == 1u)
        ? disk_perlin_texture_noise(sampleR, phiPos, samplePos.z, P)
        : disk_cloud_noise(sampleR, phiPos, samplePos.z, ctLen, P);
    float atlasDensity = clamp(disk_sample_atlas(sampleR, phiPos, P, diskAtlas).y, 0.0, 1.0);
    float densityBlend = (P.diskAtlasMode != 0u) ? clamp(P.diskAtlasDensityBlend, 0.0, 1.0) : 0.0;
    if (P.diskPhysicsMode == 1u) {
        float rH = disk_horizon_radius_m(P);
        float rIn = disk_inner_radius_m(P);
        float x = clamp((sampleR - rH) / max(rIn - rH, 1e-6), 0.0, 1.0);
        float xSoft = smoothstep(0.0, 1.0, x);
        float plungeKeep = smoothstep(0.20, 0.95, xSoft);
        // Reduce high-contrast texture inside plunging region to avoid stitched center look.
        baseNoise = mix(0.12, baseNoise, plungeKeep);
        densityBlend *= plungeKeep;
    }
    info.noise = mix(baseNoise, atlasDensity, densityBlend);
    info.emit_r_norm = sampleR / max(P.rs, 1e-6);
    info.emit_phi = phiPos;
    info.emit_z_norm = samplePos.z / max(P.rs, 1e-6);
}

kernel void renderBH(constant Params& P [[buffer(0)]],
                     device CollisionInfo* outInfo [[buffer(1)]],
                     device const float4* diskAtlas [[buffer(2)]],
                     uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= P.width || gid.y >= P.height) return;
    uint idx = gid.y * P.width + gid.x;

    // Eye의 screenCoord 생성과 동일한 스케일: [-w/2, w/2], [-h/2, h/2]
    uint gx = gid.x + P.offsetX;
    uint gy = gid.y + P.offsetY;
    float x = (float(gx) + 0.5) - float(P.fullWidth)  * 0.5;
    float y = (float(gy) + 0.5) - float(P.fullHeight) * 0.5;

    float3 dir = normalize(x * P.planeX + y * P.planeY - P.d * P.z);

    // Lux basis (newX,newY,newZ)
    float3 newX = normalize(P.camPos);           // p.unit
    float3 newZ = normalize(cross(newX, dir));   // newX.cross(direction).unit
    float3 newY = cross(newZ, newX);             // newZ.cross(newX).unit (이미 정규에 가까움)

    float r0 = length(P.camPos);

    // Python의 local = c * inverse * direction.unit 과 동일:
    // inverse rows = (newX,newY,newZ)
    float3 local = P.c * float3(dot(newX, dir), dot(newY, dir), dot(newZ, dir));

    bool hasPrev = false;
    float3 world0 = float3(0);

    CollisionInfo info;
    init_collision_info(info);

    float4 p = float4(0.0, r0, M_PI * 0.5, 0.0);
    float dt   = 0.1;
    float dr   = local.x;
    float dphi = local.y / max(r0, 1e-6);
    float4 v = float4(dt, dr, 0.0, dphi);

    if (P.metric == 0) {
        float horizonRadius = P.rs * (1.0 + P.eps);
        float diskInner = disk_inner_radius_m(P);
        float diskEmitMin = disk_emit_min_radius_m(P);

        for (int i=0; i<P.maxSteps; ++i) {
            float4 pPrev = p;
            float4 vPrev = v;
            rk4_step(p, v, P);

            float3 localPos = conv(p.y, p.z, p.w);
            float3 worldPos = localPos.x * newX + localPos.y * newY + localPos.z * newZ;

            if (hasPrev) {
                float tEnter = 0.0;
                bool entered = false;
                float3 hitPos = float3(0.0);

                // Curved-path guard: split one Schwarzschild RK step into two half steps.
                float4 pMid = pPrev;
                float4 vMid = vPrev;
                rk4_step_h(pMid, vMid, P, 0.5 * P.h);
                float3 localMid = conv(pMid.y, pMid.z, pMid.w);
                float3 worldMid = localMid.x * newX + localMid.y * newY + localMid.z * newZ;
                if (segment_enter_disk(world0, worldMid, P, tEnter)) {
                    hitPos = mix(world0, worldMid, tEnter);
                    entered = true;
                } else if (segment_enter_disk(worldMid, worldPos, P, tEnter)) {
                    hitPos = mix(worldMid, worldPos, tEnter);
                    entered = true;
                }
                if (!entered && segment_enter_disk(world0, worldPos, P, tEnter)) {
                    hitPos = mix(world0, worldPos, tEnter);
                    entered = true;
                }

                if (entered) {
                    float dxy = length(float2(hitPos.x, hitPos.y));
                    if (dxy > diskEmitMin && dxy < P.re) {
                        float phiHit = atan2(hitPos.y, hitPos.x);
                        float4 atlas = disk_sample_atlas(dxy, phiHit, P, diskAtlas);
                        float absV = sqrt(P.G * P.M / dxy);
                        float invDxy = 1.0 / max(dxy, 1e-6);
                        float3 er = float3(hitPos.x * invDxy, hitPos.y * invDxy, 0.0);
                        float3 ephi = float3(hitPos.y * invDxy, -hitPos.x * invDxy, 0.0);
                        float vrRatio = 0.0;
                        float vphiScale = 1.0;
                        float tempScale = 1.0;
                        if (P.diskPhysicsMode != 2u) {
                            vrRatio = clamp(atlas.z * P.diskAtlasVrScale, -1.0, 1.0);
                            vphiScale = clamp(atlas.w * P.diskAtlasVphiScale, 0.0, 4.0);
                            tempScale = clamp(atlas.x * P.diskAtlasTempScale, 0.05, 20.0);
                        }
                        float3 v_disk = absV * (vrRatio * er + vphiScale * ephi);
                        if (P.diskPhysicsMode != 0u && dxy < diskInner * (1.0 - 1e-4)) {
                            float massLen = 0.5 * P.rs;
                            float rM = dxy / max(massLen, 1e-12);
                            float rMsM = diskInner / max(massLen, 1e-12);
                            float betaR = 0.0;
                            float betaPhi = 0.0;
                            if (disk_schwarzschild_plunge_local_beta(rM, rMsM, betaR, betaPhi)) {
                                v_disk = P.c * (betaR * er + betaPhi * ephi);
                                float vrRef = sqrt(max(1.0 / max(rM, 1e-6), 1e-8));
                                vrRatio = clamp(betaR / max(vrRef, 1e-6), -1.0, 1.0);
                            }
                        }
                        float vMag = length(v_disk);
                        float vCap = 0.999 * P.c;
                        if (vMag > vCap && vMag > 1e-9) v_disk *= (vCap / vMag);

                        float rState = p.y;
                        float phi = p.w;
                        float dx = cos(phi) * v.y - rState * sin(phi) * v.w;
                        float dy = sin(phi) * v.y + rState * cos(phi) * v.w;
                        float3 worldVel = dx * newX + dy * newY;
                        float3 direct = normalize(worldVel);
                        float3 obsDir = -direct;

                        float beta = clamp(length(v_disk) / max(P.c, 1e-9), 0.0, 0.999999);
                        float gamma = 1.0 / sqrt(max(1.0 - beta * beta, 1e-12));
                        float cosTheta = clamp(dot(v_disk, obsDir) / max(length(v_disk) * length(obsDir), 1e-30), -1.0, 1.0);
                        float doppler = 1.0 / max(gamma * (1.0 + beta * cosTheta), 1e-9);
                        float g_gr = sqrt(clamp(1.0 - P.rs / max(dxy, 1.0001 * P.rs), 1e-8, 1.0));
                        float g_factor = clamp(doppler * g_gr, 1e-4, 1e4);

                        float T = disk_effective_temperature(dxy, diskInner, P);
                        T *= tempScale;
                        if (P.diskPhysicsMode == 2u) {
                            T *= disk_precision_texture_factor(dxy, phiHit, hitPos.z, P);
                        }

                        float ctLen = P.c * p.x;
                        info.hit = 1;
                        info.ct  = ctLen;
                        info.T   = T;
                        info.v_disk = float4(g_factor, dxy, vrRatio, 0.0);
                        info.direct_world = float4(obsDir, 0.0);
                        float3 samplePos = disk_sample_probe_pos(hitPos, world0, worldPos, P);
                        disk_set_noise_and_bridge(info, samplePos, ctLen, P, diskAtlas);

                        outInfo[idx] = info;
                        return;
                    }
                }
            }

            hasPrev = true;
            world0 = worldPos;

            float dxy = length(float2(worldPos.x, worldPos.y));
            if (dxy > max(P.kerrEscapeMult, 1.0) * P.re) break;
            if (p.y < horizonRadius) break;
            if (!(isfinite(p.x) && isfinite(p.y) && isfinite(p.w))) break;
        }
    } else {
        float massLen = 0.5 * P.rs;
        float a = clamp(P.spin, -0.999, 0.999);
        float escapeRadius = max(P.kerrEscapeMult, 1.0) * P.re;
        float diskInner = disk_inner_radius_m(P);
        float diskInnerM = diskInner / max(massLen, 1e-12);
        float diskEmitMin = disk_emit_min_radius_m(P);
        KerrState state;
        float Lz = 0.0;
        float horizonGeom = 0.0;
        if (!kerr_init_hamiltonian(P.camPos, dir, a, P, state, Lz, horizonGeom)) {
            outInfo[idx] = info;
            return;
        }

        float hStep = max(P.h, 1e-6);
        float hMin = max(P.h * 0.02, 1e-6);
        float hMax = max(P.h * 2.0, hMin);
        float tol = max(P.kerrTol, 1e-6);
        int stepMul = max(P.kerrSubsteps, 1);
        int targetSteps = min(P.maxSteps * stepMul, 40000);
        int accepted = 0;
        int guard = 0;

        while (accepted < targetSteps && guard < targetSteps * 12) {
            guard += 1;
            KerrState trial;
            float errNorm = 0.0;
            float nullResidual = 0.0;
            kerr_dp45_trial(state, hStep, a, Lz, trial, errNorm, nullResidual);

            if (!(isfinite(errNorm) && isfinite(trial.r) && isfinite(trial.theta) && isfinite(trial.phi) && isfinite(trial.t))) {
                break;
            }

            float drJump = abs(trial.r - state.r);
            float dThetaJump = abs(trial.theta - state.theta);
            float dPhiJump = abs(trial.phi - state.phi);
            float rScale = max(state.r, 1.0);
            bool jumpBad = (drJump > 0.20 * rScale) || (dThetaJump > 0.12) || (dPhiJump > 0.8);
            if (jumpBad) {
                errNorm = max(errNorm, tol * 32.0);
            }

            if (errNorm <= tol || hStep <= hMin * 1.01) {
                KerrState prevState = state;
                float hUsed = hStep;
                state = trial;
                accepted += 1;

                float thetaMin = 1e-4;
                if (state.theta < thetaMin) {
                    state.theta = thetaMin;
                    state.ptheta = abs(state.ptheta);
                } else if (state.theta > M_PI - thetaMin) {
                    state.theta = M_PI - thetaMin;
                    state.ptheta = -abs(state.ptheta);
                }

                state.phi = fmod(state.phi, 2.0 * M_PI);
                if (state.phi < 0.0) state.phi += 2.0 * M_PI;

                float ratio = max(errNorm / tol, 1e-8);
                float grow = clamp(0.9 * pow(ratio, -0.2), 0.25, 2.5);
                hStep = clamp(hStep * grow, hMin, hMax);
                if (abs(nullResidual) > 1e-6) {
                    hStep = max(hMin, hStep * 0.5);
                }

                float radiusMeters = max(state.r, 0.0) * massLen;
                float3 worldPos = conv(radiusMeters, state.theta, state.phi);

                if (hasPrev) {
                    float tEnter = 0.0;
                    bool entered = false;
                    float3 hitPos = float3(0.0);

                    // Curved-path guard: split one accepted Kerr segment into two half segments.
                    KerrState midState;
                    float midErr = 0.0;
                    float midNull = 0.0;
                    kerr_dp45_trial(prevState, 0.5 * hUsed, a, Lz, midState, midErr, midNull);
                    if (isfinite(midState.r) && isfinite(midState.theta) && isfinite(midState.phi)) {
                        midState.theta = clamp(midState.theta, 1e-4, M_PI - 1e-4);
                        midState.phi = fmod(midState.phi, 2.0 * M_PI);
                        if (midState.phi < 0.0) midState.phi += 2.0 * M_PI;
                        float3 midWorld = conv(max(midState.r, 0.0) * massLen, midState.theta, midState.phi);
                        if (segment_enter_disk(world0, midWorld, P, tEnter)) {
                            hitPos = mix(world0, midWorld, tEnter);
                            entered = true;
                        } else if (segment_enter_disk(midWorld, worldPos, P, tEnter)) {
                            hitPos = mix(midWorld, worldPos, tEnter);
                            entered = true;
                        }
                    }
                    if (!entered && segment_enter_disk(world0, worldPos, P, tEnter)) {
                        hitPos = mix(world0, worldPos, tEnter);
                        entered = true;
                    }

                    if (entered) {
                        float dxy = length(float2(hitPos.x, hitPos.y));
                        float r_M = dxy / max(massLen, 1e-12);
                        float rEmitMinM = diskEmitMin / max(massLen, 1e-12);

                        if (r_M > rEmitMinM && dxy < P.re) {
                            float phiHit = atan2(hitPos.y, hitPos.x);
                            float4 atlas = disk_sample_atlas(dxy, phiHit, P, diskAtlas);
                            float vrRatio = 0.0;
                            float vphiScale = 1.0;
                            float tempScale = 1.0;
                            if (P.diskPhysicsMode != 2u) {
                                vrRatio = clamp(atlas.z * P.diskAtlasVrScale, -1.0, 1.0);
                                vphiScale = clamp(atlas.w * P.diskAtlasVphiScale, 0.0, 4.0);
                                tempScale = clamp(atlas.x * P.diskAtlasTempScale, 0.05, 20.0);
                            }
                            float omegaK = 1.0 / max(pow(r_M, 1.5) + a, 1e-8);
                            float omega = omegaK * vphiScale;
                            float drdt = vrRatio * sqrt(1.0 / max(r_M, 1.0));
                            if (P.diskPhysicsMode != 0u && r_M < diskInnerM * (1.0 - 1e-4)) {
                                float plungeOmega = omega;
                                float plungeDrdt = drdt;
                                float plungeVrRatio = vrRatio;
                                if (disk_kerr_plunge_kinematics(r_M, diskInnerM, a, plungeOmega, plungeDrdt, plungeVrRatio)) {
                                    omega = plungeOmega;
                                    drdt = plungeDrdt;
                                    vrRatio = plungeVrRatio;
                                }
                            }
                            KerrCovMetric diskCov = kerr_cov_metric(r_M, 0.5 * M_PI, a);
                            float uDen = -(diskCov.gtt
                                         + 2.0 * omega * diskCov.gtphi
                                         + omega * omega * diskCov.gphiphi
                                         + diskCov.grr * drdt * drdt);
                            if (!(uDen > 1e-12)) {
                                omega = omegaK;
                                drdt = 0.0;
                                uDen = -(diskCov.gtt
                                       + 2.0 * omega * diskCov.gtphi
                                       + omega * omega * diskCov.gphiphi);
                            }
                            float u_t = 1.0 / sqrt(max(uDen, 1e-12));
                            float E_emit = u_t * (1.0 - omega * Lz - drdt * state.pr);
                            if (!(E_emit > 1e-8)) {
                                E_emit = u_t * max(1.0 - omega * Lz, 1e-8);
                            }
                            float g_factor = 1.0 / max(E_emit, 1e-8);
                            if (!isfinite(g_factor)) g_factor = 1.0;
                            g_factor = clamp(g_factor, 1e-4, 1e4);

                            float3 segDir = worldPos - world0;
                            float segLen2 = dot(segDir, segDir);
                            float3 direct = (segLen2 > 1e-20) ? normalize(segDir) : normalize(dir);
                            float3 obsDir = -direct;

                            float T = disk_effective_temperature(dxy, diskInner, P);
                            T *= tempScale;
                            if (P.diskPhysicsMode == 2u) {
                                T *= disk_precision_texture_factor(dxy, phiHit, hitPos.z, P);
                            }

                            float ctLen = state.t * massLen;
                            info.hit = 1;
                            info.ct  = ctLen;
                            info.T   = T;
                            info.v_disk = float4(g_factor, dxy, vrRatio, 0.0);
                            info.direct_world = float4(obsDir, 0.0);
                            float3 samplePos = disk_sample_probe_pos(hitPos, world0, worldPos, P);
                            disk_set_noise_and_bridge(info, samplePos, ctLen, P, diskAtlas);

                            outInfo[idx] = info;
                            return;
                        }
                    }
                }

                hasPrev = true;
                world0 = worldPos;

                float dxy = length(float2(worldPos.x, worldPos.y));
                if (dxy > escapeRadius) break;
                if (state.r <= horizonGeom * (1.0 + P.eps)) break;
                if (!(isfinite(state.r) && isfinite(state.theta) && isfinite(state.phi) && isfinite(state.t))) break;
            } else {
                float ratio = max(errNorm / tol, 1e-8);
                float shrink = clamp(0.9 * pow(ratio, -0.25), 0.1, 0.5);
                hStep = max(hMin, hStep * shrink);
            }
        }
    }

    outInfo[idx] = info;
}

struct ComposeParams {
    uint  tileWidth;
    uint  tileHeight;
    uint  downsample;
    uint  outTileWidth;
    uint  outTileHeight;
    uint  srcOffsetX;
    uint  srcOffsetY;
    uint  outOffsetX;
    uint  outOffsetY;
    uint  fullInputWidth;
    uint  fullInputHeight;
    float exposure;
    float dither;
    float innerEdgeMult;
    float spectralStep;
    float cloudQ10;
    float cloudInvSpan;
    uint  look;
    uint  spectralEncoding;
    uint  precisionMode;
    uint  analysisMode;
    uint  cloudBins;
    uint  lumBins;
    float lumLogMin;
    float lumLogMax;
};

constant ushort BAYER8_LUT[64] = {
     0,48,12,60, 3,51,15,63,
    32,16,44,28,35,19,47,31,
     8,56, 4,52,11,59, 7,55,
    40,24,36,20,43,27,39,23,
     2,50,14,62, 1,49,13,61,
    34,18,46,30,33,17,45,29,
    10,58, 6,54, 9,57, 5,53,
    42,26,38,22,41,25,37,21
};

static inline float3 comp_xyz_to_rgb(float3 xyz) {
    float3 r;
    r.x =  3.2406 * xyz.x + -1.5372 * xyz.y + -0.4986 * xyz.z;
    r.y = -0.9689 * xyz.x +  1.8758 * xyz.y +  0.0415 * xyz.z;
    r.z =  0.0557 * xyz.x + -0.2040 * xyz.y +  1.0570 * xyz.z;
    return max(r, 0.0);
}


static inline float comp_aces(float x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

static inline float3 comp_apply_look(float3 rgb, uint look) {
    if (look == 1u) { // interstellar
        float3 out;
        out.x = 1.08 * rgb.x + 0.03 * rgb.y - 0.03 * rgb.z;
        out.y = 0.02 * rgb.x + 1.02 * rgb.y - 0.01 * rgb.z;
        out.z = -0.03 * rgb.x + 0.00 * rgb.y + 0.90 * rgb.z;
        out = clamp(out, 0.0, 1.0);
        out = precise::pow(out, float3(0.95));
        return clamp(out, 0.0, 1.0);
    }
    if (look == 2u) { // eht
        float3 out;
        out.x = 1.30 * rgb.x + 0.22 * rgb.y - 0.02 * rgb.z;
        out.y = 0.18 * rgb.x + 1.03 * rgb.y - 0.07 * rgb.z;
        out.z = -0.06 * rgb.x + 0.02 * rgb.y + 0.52 * rgb.z;
        out = clamp(out, 0.0, 1.0);
        float y = dot(out, float3(0.2126, 0.7152, 0.0722));
        out = 0.75 * out + 0.25 * float3(y);
        out = precise::pow(out, float3(1.05));
        return clamp(out, 0.0, 1.0);
    }
    return clamp(rgb, 0.0, 1.0);
}

static inline void comp_cie_xyz_bar(float lam, thread float& x_bar, thread float& y_bar, thread float& z_bar) {
    float t1 = (lam - 442.0) * ((lam < 442.0) ? 0.0624 : 0.0374);
    float t2 = (lam - 599.8) * ((lam < 599.8) ? 0.0264 : 0.0323);
    float t3 = (lam - 501.1) * ((lam < 501.1) ? 0.0490 : 0.0382);
    x_bar = 0.362 * precise::exp(-0.5 * t1 * t1) + 1.056 * precise::exp(-0.5 * t2 * t2) - 0.065 * precise::exp(-0.5 * t3 * t3);

    t1 = (lam - 568.8) * ((lam < 568.8) ? 0.0213 : 0.0247);
    t2 = (lam - 530.9) * ((lam < 530.9) ? 0.0613 : 0.0322);
    y_bar = 0.821 * precise::exp(-0.5 * t1 * t1) + 0.286 * precise::exp(-0.5 * t2 * t2);

    t1 = (lam - 437.0) * ((lam < 437.0) ? 0.0845 : 0.0278);
    t2 = (lam - 459.0) * ((lam < 459.0) ? 0.0385 : 0.0725);
    z_bar = 1.217 * precise::exp(-0.5 * t1 * t1) + 0.681 * precise::exp(-0.5 * t2 * t2);

    x_bar = max(x_bar, 0.0);
    y_bar = max(y_bar, 0.0);
    z_bar = max(z_bar, 0.0);
}


static inline float comp_planck_lambda(float lam_m, float T) {
    const float C1 = 1.1910429e-16;
    const float C2 = 1.4387769e-2;
    float x = C2 / max(lam_m * T, 1e-30);
    x = clamp(x, 1e-8, 700.0);
    if (x > 80.0) {
        // For large x, exp(x) is enormous and radiance is effectively zero.
        return 0.0;
    }
    float denom = max(precise::exp(x) - 1.0, 1e-20);
    return C1 / (pow(lam_m, 5.0) * denom);
}


static inline float comp_synthetic_noise(float3 v_disk, constant Params& P) {
    float2 vxy = v_disk.xy;
    float speed = length(vxy);
    float r_emit = (P.G * P.M) / max(speed * speed, 1e-30);
    float u = clamp((r_emit - P.rs) / max(P.re - P.rs, 1e-12), 0.0, 1.0);
    float phi = atan2(-vxy.x, vxy.y);
    float theta = phi + 1.9 * log(max(r_emit / max(P.rs, 1e-6), 1.0));
    float cloud = 0.65 * sin(18.0 * u + 3.0 * cos(theta)) + 0.35 * cos(11.0 * theta);
    return clamp(cloud, -1.0, 1.0);
}

static inline float comp_cloud_raw(const CollisionInfo rec, constant Params& P, constant ComposeParams& C) {
    float n = rec.noise;
    if (abs(n) < 1e-6 && C.spectralEncoding == 0u) {
        n = comp_synthetic_noise(rec.v_disk.xyz, P);
    }
    n = clamp(n, -1.0, 1.0);
    return (n < -1e-6) ? clamp(0.5 + 0.5 * n, 0.0, 1.0) : clamp(n, 0.0, 1.0);
}

static inline float comp_cloud_norm_from_raw(float cloudRaw, constant ComposeParams& C) {
    float cloud = clamp((cloudRaw - C.cloudQ10) * C.cloudInvSpan, 0.0, 1.0);
    return 0.18 + 0.82 * cloud;
}

static inline float3 comp_apply_cloud_to_rgb(float3 rgb, float cloudNorm) {
    float core = precise::pow(cloudNorm, 1.15);
    float clump = precise::pow(core, 2.2);
    float vvoid = precise::pow(1.0 - cloudNorm, 1.8);
    float density = 0.62 + 1.28 * core;
    rgb *= density;
    rgb *= (1.0 + 0.34 * clump);
    rgb *= (1.0 - 0.14 * vvoid);
    rgb.x *= (1.0 + 0.12 * clump);
    rgb.z *= (1.0 - 0.08 * clump);
    return rgb;
}

static inline float comp_hash13(float3 p) {
    float h = sin(dot(p, float3(12.9898, 78.233, 37.719)));
    return fract(h * 43758.5453);
}

static inline float comp_limb_factor(float mu, constant Params& P) {
    float m = clamp(mu, 0.0, 1.0);
    if (P.diskPhysicsMode == 2u) {
        // Scattering-dominated atmosphere (Chandrasekhar H-function linearized form).
        return (3.0 / 7.0) * (1.0 + 2.0 * m);
    }
    return 0.4 + 0.6 * m;
}

static inline float comp_precision_returning_radiation_factor(const CollisionInfo rec,
                                                             constant Params& P,
                                                             constant ComposeParams& C,
                                                             float cloudRaw)
{
    if (P.diskPhysicsMode != 2u) return 1.0;
    float ret = clamp(P.diskReturningRad, 0.0, 1.0);
    if (!(ret > 1e-6)) return 1.0;

    float rEmit = max(rec.v_disk.y, P.rs * 1.0001);
    float rIn = disk_inner_radius_m(P);
    float rH = disk_horizon_radius_m(P);
    float span = max(2.8 * rIn - rIn, 1e-6);
    float x = clamp((rEmit - rIn) / span, 0.0, 1.0);
    float innerWeight = 1.0 - smoothstep(0.0, 1.0, x);
    float horizonGate = smoothstep(rH * (1.02 + 16.0 * P.eps), rIn, rEmit);

    float spinFac = (P.metric == 0) ? 0.14 : pow(clamp(abs(P.spin), 0.0, 0.999), 1.6);

    float3 d = rec.direct_world.xyz;
    float mu = abs(d.z) / max(length(d), 1e-30);
    float bending = 0.35 + 0.65 * pow(1.0 - clamp(mu, 0.0, 1.0), 0.72);

    float cloudNorm = comp_cloud_norm_from_raw(clamp(cloudRaw, 0.0, 1.0), C);
    float c = clamp((cloudNorm - 0.18) / 0.82, 0.0, 1.0);
    float coverage = clamp(P.diskCloudCoverage, 0.0, 1.0);
    float tau0 = max(P.diskCloudOpticalDepth, 0.0);
    float albedo = clamp(P.diskScatteringAlbedo, 0.0, 1.0);
    uint bounceCount = clamp(P.diskReturnBounces, 1u, 4u);
    float reprocess = 1.0 - exp(-tau0 * (0.30 + 0.70 * coverage * c));
    float absorbFrac = clamp(0.45 + 0.55 * reprocess, 0.0, 1.0);

    float firstBounce = ret
                      * (0.22 + 0.78 * spinFac)
                      * innerWeight
                      * bending
                      * horizonGate
                      * absorbFrac;
    firstBounce = clamp(firstBounce, 0.0, 0.95);

    // Multi-bounce geometric approximation: I_ret ~ f1 * (1 + q + q^2 + ...)
    float q = albedo
            * (0.20 + 0.55 * spinFac)
            * (0.35 + 0.65 * bending)
            * (0.40 + 0.60 * innerWeight)
            * (0.55 + 0.45 * horizonGate);
    q = clamp(q, 0.0, 0.88);

    float accum = 0.0;
    float term = firstBounce;
    for (uint b = 0u; b < bounceCount; ++b) {
        accum += term;
        term *= q;
    }
    return 1.0 + clamp(accum, 0.0, 1.6);
}

static inline float3 comp_apply_precision_cloud_to_rgb(float3 rgb,
                                                       const CollisionInfo rec,
                                                       constant Params& P,
                                                       constant ComposeParams& C,
                                                       float cloudRaw)
{
    float coverage = clamp(P.diskCloudCoverage, 0.0, 1.0);
    float tau0 = max(P.diskCloudOpticalDepth, 0.0);
    float porosity = clamp(P.diskCloudPorosity, 0.0, 1.0);
    float shadowStrength = clamp(P.diskCloudShadowStrength, 0.0, 1.0);
    float albedo = clamp(P.diskScatteringAlbedo, 0.0, 1.0);
    if (!(coverage > 1e-6) || (!(tau0 > 1e-6) && !(porosity > 1e-6) && !(shadowStrength > 1e-6))) {
        return rgb;
    }

    float cloudNorm = comp_cloud_norm_from_raw(clamp(cloudRaw, 0.0, 1.0), C);
    float c = clamp((cloudNorm - 0.18) / 0.82, 0.0, 1.0);
    float baseClump = smoothstep(max(0.0, 1.0 - coverage), 1.0, c);

    float3 d = rec.direct_world.xyz;
    float dNorm = max(length(d), 1e-30);
    float3 rayDir = d / dNorm;
    float mu = abs(rayDir.z);

    float rEmit = max(rec.v_disk.y, P.rs * 1.0001);
    float halfH = disk_half_thickness_m(rEmit, P);
    float span = max(P.re - P.rs, 1e-6);
    float u = clamp((rEmit - P.rs) / span, 0.0, 1.0);
    float innerBoost = 1.0 + 0.36 * (1.0 - smoothstep(0.06, 0.42, u));

    // Use physical LOS distance through local disk volume (meters).
    float pathMeters = (1.6 * halfH) / max(mu, 0.085);
    pathMeters = clamp(pathMeters, 0.15 * P.rs, 3.5 * P.rs);
    float pathRs = pathMeters / max(P.rs, 1e-6);

    uint nSteps = clamp(P.diskRTSteps, 0u, 32u);
    if (nSteps == 0u) {
        float suggested = 6.0 + 1.0 * tau0 * innerBoost + 4.5 * pathRs;
        nSteps = uint(clamp(suggested, 6.0, 24.0));
    }
    nSteps = max(nSteps, 4u);

    float ds = pathMeters / float(nSteps);
    float alphaBase = (tau0 * innerBoost) / max(pathMeters, 1e-9);
    float phaseScatter = 0.5 * (1.0 + mu * mu); // Thomson-like angular term
    float3 I = rgb;
    float trans = 1.0;
    const float3 scatterTint = float3(1.08, 1.0, 0.93);
    float rInner = disk_inner_radius_m(P);
    float tRef = max(rec.T, 1.0);

    float r0 = max(rec.emit_r_norm * P.rs, P.rs * 1.0001);
    float phi0 = rec.emit_phi;
    float z0 = rec.emit_z_norm * P.rs;
    float3 emitPos = float3(r0 * cos(phi0), r0 * sin(phi0), z0);

    for (uint i = 0u; i < 32u; ++i) {
        if (i >= nSteps) break;
        float s = (float(i) + 0.5) / float(nSteps);
        float signedOffset = (s - 0.5) * pathMeters;
        float3 samplePos = emitPos + rayDir * signedOffset;
        if (!inside_disk_volume(samplePos, P)) continue;

        float sampleR = length(samplePos.xy);
        float samplePhi = atan2(samplePos.y, samplePos.x);
        float sampleZ = samplePos.z;
        float ctLocal = rec.ct + signedOffset;

        float localCloud = disk_cloud_noise(sampleR, samplePhi, sampleZ, ctLocal, P);
        if (P.diskNoiseModel == 1u) {
            float perlin = disk_perlin_texture_noise(sampleR, samplePhi, sampleZ, P);
            localCloud = 0.55 * localCloud + 0.45 * clamp(0.5 + 0.5 * perlin, 0.0, 1.0);
        }
        float phase = 2.0 * s - 1.0;
        float jitter = comp_hash13(float3(21.0 * sampleR / max(P.rs, 1e-6) + 13.0 * phase,
                                          9.0 * samplePhi - 7.0 * phase,
                                          15.0 * sampleZ / max(P.rs, 1e-6) + 3.0 * localCloud));
        localCloud = clamp(0.84 * localCloud + 0.16 * jitter, 0.0, 1.0);

        float localClump = smoothstep(max(0.0, 1.0 - coverage), 1.0, localCloud);
        float holeField = comp_hash13(float3(19.1 * sampleR / max(P.rs, 1e-6) + 11.0 * phase,
                                             23.0 * samplePhi - 7.0 * phase,
                                             17.0 * sampleZ / max(P.rs, 1e-6) + 13.0 * localCloud));
        float holeThreshold = porosity * mix(0.94, 0.36, localClump);
        float occupied = smoothstep(holeThreshold - 0.07, holeThreshold + 0.07, holeField);
        float fill = clamp(localClump * occupied, 0.0, 1.0);
        fill = mix(fill, localClump, 0.18);

        float density = mix(0.06, 1.0, fill);
        float dTau = min(alphaBase * density * ds, 3.5);
        float stepTrans = exp(-dTau);
        float absorbed = 1.0 - stepTrans;

        float tStep = disk_effective_temperature(sampleR, rInner, P);
        tStep *= disk_precision_texture_factor(sampleR, samplePhi, sampleZ, P);
        float tRatio = pow(clamp(tStep / tRef, 0.04, 12.0), 4.0);

        float3 thermalSrc = rgb * tRatio * (0.10 + 0.90 * fill);
        float scatterAmp = (0.10 + 0.90 * phaseScatter) * (0.20 + 0.80 * fill);
        float lumI = dot(I, float3(0.2126, 0.7152, 0.0722));
        float3 scatterSrc = scatterTint * lumI * scatterAmp;
        float3 source = mix(thermalSrc, scatterSrc, albedo);

        I = I * stepTrans + source * absorbed;
        trans *= stepTrans;
    }

    float attenuation = mix(1.0, trans, shadowStrength);
    float porosityLift = mix(1.0, 1.0 + 0.35 * porosity * (1.0 - baseClump), 0.65);
    float floor = 0.04 + 0.24 * porosity;
    float3 out = I * attenuation * porosityLift;
    return max(out, rgb * floor);
}

static inline float3 comp_linear_rgb_precloud(const CollisionInfo rec,
                                              constant Params& P,
                                              constant ComposeParams& C)
{
    float g_total = 1.0;
    if (C.spectralEncoding == 1u) {
        g_total = clamp(rec.v_disk.x, 1e-4, 1e4);
    } else {
        float3 v = rec.v_disk.xyz;
        float3 d = rec.direct_world.xyz;
        float v_norm = length(v);
        float d_norm = length(d);
        float dot_vd = dot(v, d);
        float beta = clamp(v_norm / max(P.c, 1e-12), 0.0, 0.999999);
        float cos_theta = clamp(dot_vd / max(v_norm * d_norm, 1e-30), -1.0, 1.0);
        float gamma = 1.0 / sqrt(max(1.0 - beta * beta, 1e-12));
        float delta = 1.0 / max(gamma * (1.0 + beta * cos_theta), 1e-9);
        float r_emit_legacy = (P.G * P.M) / max(v_norm * v_norm, 1e-30);
        r_emit_legacy = max(r_emit_legacy, P.rs * 1.0001);
        float g_gr = sqrt(clamp(1.0 - P.rs / r_emit_legacy, 1e-8, 1.0));
        g_total = clamp(delta * g_gr, 1e-4, 1e4);
    }

    float T_emit = max(rec.T, 1.0);
    float T_obs = max(T_emit * g_total, 1.0);
    float colorDilution = 1.0;
    if (P.diskPhysicsMode == 2u) {
        float fCol = max(P.diskColorFactor, 1.0);
        colorDilution = 1.0 / pow(fCol, 4.0);
    }

    float X = 0.0;
    float Y = 0.0;
    float Z = 0.0;
    float cX = 0.0;
    float cY = 0.0;
    float cZ = 0.0;
    bool kahan = (C.precisionMode != 0u);
    float step = max(C.spectralStep, 0.25);
    for (float lam = 380.0; lam <= 750.001; lam += step) {
        float lam_m = lam * 1e-9;
        float x_bar, y_bar, z_bar;
        comp_cie_xyz_bar(lam, x_bar, y_bar, z_bar);
        float b = comp_planck_lambda(lam_m, T_obs) * colorDilution;
        if (kahan) {
            float yx = b * x_bar - cX;
            float tx = X + yx;
            cX = (tx - X) - yx;
            X = tx;

            float yy = b * y_bar - cY;
            float ty = Y + yy;
            cY = (ty - Y) - yy;
            Y = ty;

            float yz = b * z_bar - cZ;
            float tz = Z + yz;
            cZ = (tz - Z) - yz;
            Z = tz;
        } else {
            X += b * x_bar;
            Y += b * y_bar;
            Z += b * z_bar;
        }
    }

    float3 rgb = comp_xyz_to_rgb(float3(X, Y, Z));

    float3 d_world = rec.direct_world.xyz;
    float mu = abs(d_world.z) / max(length(d_world), 1e-30);
    float limb = comp_limb_factor(mu, P);
    rgb *= limb;
    if (C.spectralEncoding == 1u && P.diskPhysicsMode == 1u) {
        float rEmit = max(rec.v_disk.y, P.rs * 1.0001);
        float rIn = disk_inner_radius_m(P);
        float rH = disk_horizon_radius_m(P) * (1.0 + 2.0 * P.eps);
        float x = clamp((rEmit - rH) / max(rIn - rH, 1e-6), 0.0, 1.0);
        float xSoft = smoothstep(0.0, 1.0, x);
        float floor = 0.35 * clamp(P.diskPlungeFloor, 0.0, 1.0);
        float gate = floor + (1.0 - floor) * pow(max(xSoft, 1e-4), 2.2);
        rgb *= clamp(gate, 0.0, 1.0);
    }
    return rgb;
}

static inline float3 comp_linear_rgb(const CollisionInfo rec,
                                     constant Params& P,
                                     constant ComposeParams& C)
{
    float3 rgb = comp_linear_rgb_precloud(rec, P, C);
    float cloudRaw = comp_cloud_raw(rec, P, C);
    if (P.diskPhysicsMode == 2u) {
        float retFactor = comp_precision_returning_radiation_factor(rec, P, C, cloudRaw);
        rgb *= retFactor;
    }
    if (P.diskPhysicsMode == 2u) {
        if (C.analysisMode == 1u) return rgb;
        return comp_apply_precision_cloud_to_rgb(rgb, rec, P, C, cloudRaw);
    }
    if (C.analysisMode != 0u) return rgb;
    float cloud = comp_cloud_norm_from_raw(cloudRaw, C);
    return comp_apply_cloud_to_rgb(rgb, cloud);
}

static inline float comp_log10(float x) {
    return log(max(x, 1e-30)) * 0.4342944819032518;
}

static inline float comp_bayer8(uint x, uint y) {
    uint idx = ((y & 7u) << 3u) | (x & 7u);
    return ((float(BAYER8_LUT[idx]) + 0.5) / 64.0) - 0.5;
}

static inline float3 comp_shade(const CollisionInfo rec,
                                constant Params& P,
                                constant ComposeParams& C)
{
    if (rec.hit == 0u) return float3(0.0);
    float3 rgb = comp_linear_rgb(rec, P, C);
    float3 rgbExp = rgb * max(C.exposure, 1e-30);
    float lum = dot(rgbExp, float3(0.2126, 0.7152, 0.0722));
    float lumTm = comp_aces(lum);
    float scale = lumTm / max(lum, 1e-12);
    float3 rgbTm = rgbExp * scale;
    rgbTm = comp_apply_look(rgbTm, C.look);
    float3 srgb = precise::pow(clamp(rgbTm, 0.0, 1.0), float3(1.0 / 2.2));
    return srgb;
}

static inline float3 comp_shade_linear(float3 rgb, constant ComposeParams& C)
{
    float3 rgbExp = rgb * max(C.exposure, 1e-30);
    float lum = dot(rgbExp, float3(0.2126, 0.7152, 0.0722));
    float lumTm = comp_aces(lum);
    float scale = lumTm / max(lum, 1e-12);
    float3 rgbTm = rgbExp * scale;
    rgbTm = comp_apply_look(rgbTm, C.look);
    float3 srgb = precise::pow(clamp(rgbTm, 0.0, 1.0), float3(1.0 / 2.2));
    return srgb;
}

kernel void composeLinearRGB(constant Params& P [[buffer(0)]],
                             constant ComposeParams& C [[buffer(1)]],
                             device const CollisionInfo* inInfo [[buffer(2)]],
                             device float4* outLinear [[buffer(3)]],
                             uint gid [[thread_position_in_grid]])
{
    uint count = C.tileWidth * C.tileHeight;
    if (gid >= count) return;
    uint lx = gid % C.tileWidth;
    uint ly = gid / C.tileWidth;
    if (ly >= C.tileHeight) return;

    uint gx = C.srcOffsetX + lx;
    uint gy = C.srcOffsetY + ly;
    uint gidx = gy * C.fullInputWidth + gx;

    CollisionInfo rec = inInfo[gid];
    if (rec.hit == 0u) {
        outLinear[gidx] = float4(0.0);
        return;
    }
    float3 rgb = comp_linear_rgb(rec, P, C);
    outLinear[gidx] = float4(rgb, 1.0);
}

kernel void composeLinearRGBTile(constant Params& P [[buffer(0)]],
                                 constant ComposeParams& C [[buffer(1)]],
                                 device const CollisionInfo* inInfo [[buffer(2)]],
                                 device float4* outLinear [[buffer(3)]],
                                 uint gid [[thread_position_in_grid]])
{
    uint count = C.tileWidth * C.tileHeight;
    if (gid >= count) return;
    CollisionInfo rec = inInfo[gid];
    if (rec.hit == 0u) {
        outLinear[gid] = float4(0.0, 0.0, 0.0, -1.0);
        return;
    }
    float cloudRaw = comp_cloud_raw(rec, P, C);
    float3 rgbBase = comp_linear_rgb_precloud(rec, P, C);
    if (P.diskPhysicsMode == 2u) {
        float retFactor = comp_precision_returning_radiation_factor(rec, P, C, cloudRaw);
        rgbBase *= retFactor;
    }
    if (P.diskPhysicsMode == 2u && C.analysisMode == 2u) {
        float3 rgb = comp_apply_precision_cloud_to_rgb(rgbBase, rec, P, C, cloudRaw);
        outLinear[gid] = float4(rgb, cloudRaw);
        return;
    }
    outLinear[gid] = float4(rgbBase, cloudRaw);
}

kernel void composeCloudHist(constant Params& P [[buffer(0)]],
                             constant ComposeParams& C [[buffer(1)]],
                             device const CollisionInfo* inInfo [[buffer(2)]],
                             device atomic_uint* outHist [[buffer(3)]],
                             uint gid [[thread_position_in_grid]])
{
    uint count = C.tileWidth * C.tileHeight;
    if (gid >= count) return;
    CollisionInfo rec = inInfo[gid];
    if (rec.hit == 0u) return;
    uint bins = max(C.cloudBins, 1u);
    float cloud = comp_cloud_raw(rec, P, C);
    uint bin = min((uint)floor(cloud * float(bins - 1u) + 0.5), bins - 1u);
    atomic_fetch_add_explicit(&(outHist[bin]), 1u, memory_order_relaxed);
}

kernel void composeLumHist(constant Params& P [[buffer(0)]],
                           constant ComposeParams& C [[buffer(1)]],
                           device const CollisionInfo* inInfo [[buffer(2)]],
                           device atomic_uint* outHist [[buffer(3)]],
                           uint gid [[thread_position_in_grid]])
{
    uint count = C.tileWidth * C.tileHeight;
    if (gid >= count) return;
    CollisionInfo rec = inInfo[gid];
    if (rec.hit == 0u) return;
    float3 rgb = comp_linear_rgb(rec, P, C);
    float lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    uint bins = max(C.lumBins, 1u);
    float t = (comp_log10(max(lum, 1e-30)) - C.lumLogMin) / max(C.lumLogMax - C.lumLogMin, 1e-6);
    t = clamp(t, 0.0, 1.0);
    uint bin = min((uint)floor(t * float(bins - 1u) + 0.5), bins - 1u);
    atomic_fetch_add_explicit(&(outHist[bin]), 1u, memory_order_relaxed);
}

kernel void composeLumHistLinear(constant ComposeParams& C [[buffer(0)]],
                                 device const float4* inLinear [[buffer(1)]],
                                 device atomic_uint* outHist [[buffer(2)]],
                                 uint gid [[thread_position_in_grid]])
{
    uint count = C.tileWidth * C.tileHeight;
    if (gid >= count) return;
    uint lx = gid % C.tileWidth;
    uint ly = gid / C.tileWidth;
    if (ly >= C.tileHeight) return;

    uint gx = C.srcOffsetX + lx;
    uint gy = C.srcOffsetY + ly;
    uint gidx = gy * C.fullInputWidth + gx;
    float4 rgbw = inLinear[gidx];
    if (rgbw.w <= 0.0) return;
    float lum = dot(rgbw.xyz, float3(0.2126, 0.7152, 0.0722));
    uint bins = max(C.lumBins, 1u);
    float t = (comp_log10(max(lum, 1e-30)) - C.lumLogMin) / max(C.lumLogMax - C.lumLogMin, 1e-6);
    t = clamp(t, 0.0, 1.0);
    uint bin = min((uint)floor(t * float(bins - 1u) + 0.5), bins - 1u);
    atomic_fetch_add_explicit(&(outHist[bin]), 1u, memory_order_relaxed);
}

kernel void composeLumHistLinearTileCloud(constant ComposeParams& C [[buffer(0)]],
                                          device const float4* inLinear [[buffer(1)]],
                                          device atomic_uint* outHist [[buffer(2)]],
                                          uint gid [[thread_position_in_grid]])
{
    uint count = C.tileWidth * C.tileHeight;
    if (gid >= count) return;
    float4 rgbw = inLinear[gid];
    if (rgbw.w < 0.0) return;
    float3 rgb = rgbw.xyz;
    if (C.analysisMode == 0u) {
        float cloud = comp_cloud_norm_from_raw(clamp(rgbw.w, 0.0, 1.0), C);
        rgb = comp_apply_cloud_to_rgb(rgbw.xyz, cloud);
    }
    float lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    uint bins = max(C.lumBins, 1u);
    float t = (comp_log10(max(lum, 1e-30)) - C.lumLogMin) / max(C.lumLogMax - C.lumLogMin, 1e-6);
    t = clamp(t, 0.0, 1.0);
    uint bin = min((uint)floor(t * float(bins - 1u) + 0.5), bins - 1u);
    atomic_fetch_add_explicit(&(outHist[bin]), 1u, memory_order_relaxed);
}

kernel void composeBH(constant Params& P [[buffer(0)]],
                      constant ComposeParams& C [[buffer(1)]],
                      device const CollisionInfo* inInfo [[buffer(2)]],
                      device uchar4* outRGBA [[buffer(3)]],
                      uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= C.outTileWidth || gid.y >= C.outTileHeight) return;

    uint globalOutX = C.outOffsetX + gid.x;
    uint globalOutY = C.outOffsetY + gid.y;
    uint ds = max(C.downsample, 1u);

    float3 acc = float3(0.0);
    uint cnt = 0u;
    for (uint sy = 0u; sy < ds; ++sy) {
        for (uint sx = 0u; sx < ds; ++sx) {
            uint srcX = globalOutX * ds + sx;
            uint srcY = C.fullInputHeight - 1u - (globalOutY * ds + sy);
            if (srcX < C.srcOffsetX || srcX >= C.srcOffsetX + C.tileWidth) continue;
            if (srcY < C.srcOffsetY || srcY >= C.srcOffsetY + C.tileHeight) continue;

            uint lx = srcX - C.srcOffsetX;
            uint ly = srcY - C.srcOffsetY;
            uint lidx = ly * C.tileWidth + lx;
            acc += comp_shade(inInfo[lidx], P, C);
            cnt += 1u;
        }
    }

    float3 color = (cnt > 0u) ? (acc / float(cnt)) : float3(0.0);
    if (C.dither > 0.0) {
        float d = comp_bayer8(globalOutX, globalOutY) * (C.dither / 255.0);
        color = clamp(color + float3(d), 0.0, 1.0);
    }

    uchar4 pix;
    pix.x = uchar(clamp(color.x * 255.0 + 0.5, 0.0, 255.0));
    pix.y = uchar(clamp(color.y * 255.0 + 0.5, 0.0, 255.0));
    pix.z = uchar(clamp(color.z * 255.0 + 0.5, 0.0, 255.0));
    pix.w = 255u;
    outRGBA[gid.y * C.outTileWidth + gid.x] = pix;
}

kernel void composeBHLinear(constant ComposeParams& C [[buffer(0)]],
                            device const float4* inLinear [[buffer(1)]],
                            device uchar4* outRGBA [[buffer(2)]],
                            uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= C.outTileWidth || gid.y >= C.outTileHeight) return;

    uint globalOutX = C.outOffsetX + gid.x;
    uint globalOutY = C.outOffsetY + gid.y;
    uint ds = max(C.downsample, 1u);

    float3 acc = float3(0.0);
    uint cnt = 0u;
    for (uint sy = 0u; sy < ds; ++sy) {
        for (uint sx = 0u; sx < ds; ++sx) {
            uint srcX = globalOutX * ds + sx;
            uint srcY = C.fullInputHeight - 1u - (globalOutY * ds + sy);
            if (srcX < C.srcOffsetX || srcX >= C.srcOffsetX + C.tileWidth) continue;
            if (srcY < C.srcOffsetY || srcY >= C.srcOffsetY + C.tileHeight) continue;

            uint srcIdx = srcY * C.fullInputWidth + srcX;
            float3 rgb = inLinear[srcIdx].xyz;
            acc += comp_shade_linear(rgb, C);
            cnt += 1u;
        }
    }

    float3 color = (cnt > 0u) ? (acc / float(cnt)) : float3(0.0);
    if (C.dither > 0.0) {
        float d = comp_bayer8(globalOutX, globalOutY) * (C.dither / 255.0);
        color = clamp(color + float3(d), 0.0, 1.0);
    }

    uchar4 pix;
    pix.x = uchar(clamp(color.x * 255.0 + 0.5, 0.0, 255.0));
    pix.y = uchar(clamp(color.y * 255.0 + 0.5, 0.0, 255.0));
    pix.z = uchar(clamp(color.z * 255.0 + 0.5, 0.0, 255.0));
    pix.w = 255u;
    outRGBA[gid.y * C.outTileWidth + gid.x] = pix;
}

kernel void composeBHLinearTile(constant ComposeParams& C [[buffer(0)]],
                                device const float4* inLinear [[buffer(1)]],
                                device uchar4* outRGBA [[buffer(2)]],
                                uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= C.outTileWidth || gid.y >= C.outTileHeight) return;

    uint globalOutX = C.outOffsetX + gid.x;
    uint globalOutY = C.outOffsetY + gid.y;
    uint ds = max(C.downsample, 1u);

    float3 acc = float3(0.0);
    uint cnt = 0u;
    for (uint sy = 0u; sy < ds; ++sy) {
        for (uint sx = 0u; sx < ds; ++sx) {
            uint srcX = globalOutX * ds + sx;
            uint srcY = C.fullInputHeight - 1u - (globalOutY * ds + sy);
            if (srcX < C.srcOffsetX || srcX >= C.srcOffsetX + C.tileWidth) continue;
            if (srcY < C.srcOffsetY || srcY >= C.srcOffsetY + C.tileHeight) continue;

            uint lx = srcX - C.srcOffsetX;
            uint ly = srcY - C.srcOffsetY;
            uint lidx = ly * C.tileWidth + lx;
            float4 rgbw = inLinear[lidx];
            if (rgbw.w < 0.0) continue;
            float3 rgb = rgbw.xyz;
            if (C.analysisMode == 0u) {
                float cloud = comp_cloud_norm_from_raw(clamp(rgbw.w, 0.0, 1.0), C);
                rgb = comp_apply_cloud_to_rgb(rgbw.xyz, cloud);
            }
            acc += comp_shade_linear(rgb, C);
            cnt += 1u;
        }
    }

    float3 color = (cnt > 0u) ? (acc / float(cnt)) : float3(0.0);
    if (C.dither > 0.0) {
        float d = comp_bayer8(globalOutX, globalOutY) * (C.dither / 255.0);
        color = clamp(color + float3(d), 0.0, 1.0);
    }

    uchar4 pix;
    pix.x = uchar(clamp(color.x * 255.0 + 0.5, 0.0, 255.0));
    pix.y = uchar(clamp(color.y * 255.0 + 0.5, 0.0, 255.0));
    pix.z = uchar(clamp(color.z * 255.0 + 0.5, 0.0, 255.0));
    pix.w = 255u;
    outRGBA[gid.y * C.outTileWidth + gid.x] = pix;
}
