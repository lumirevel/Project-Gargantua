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
    float  spin;       // a/M in [0,1)
    int    kerrSubsteps;
    float  kerrTol;    // adaptive RK45 relative tolerance
    float  kerrEscapeMult;
    float  kerrRadialScale;  // Kerr ray-init radial calibration
    float  kerrAzimuthScale; // Kerr ray-init angular calibration
    float  kerrImpactScale;
    float  _padMetric0;
    int    _padMetric1;
};

struct CollisionInfo {
    uint   hit;          // 0 or 1
    float  ct;           // c * t
    float  T;            // disk temperature
    float  _pad0;
    float4 v_disk;       // x/y/z used, w padding
    float4 direct_world; // x/y/z used, w padding
    float  noise;        // 1단계는 0으로
    float  _pad3_0;
    float  _pad3_1;
    float  _pad3_2;
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
    float a = clamp(P.spin, 0.0, 0.999) * (0.5 * rs);

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
    const float focusRange = 0.50;
    float diskHNorm = P.he / max(P.rs, 1e-6);
    float thinBlend = clamp((diskHNorm - 0.02) / 0.06, 0.0, 1.0);
    float focusStrength = 0.25 * thinBlend;
    float tangent = sqrt(max(nth * nth + nphi * nphi, 1e-12));
    float focus = clamp((focusRange - tangent) / focusRange, 0.0, 1.0);
    float radialScale = max(P.kerrRadialScale, 0.01) * (1.0 - focusStrength * focus);
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

    float angularScale = max(P.kerrImpactScale, 0.05);
    Lz *= angularScale;
    state.ptheta *= angularScale;

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

static inline bool inside_disk_volume(float3 pos, constant Params& P) {
    float dxy = length(float2(pos.x, pos.y));
    return (dxy > P.rs && dxy < P.re && abs(pos.z) < P.he);
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

static inline float disk_cloud_noise(float r, float phi, float z, constant Params& P) {
    float r_norm = (r - P.rs) / max(P.re - P.rs, 1e-6);
    float h_norm = z / max(P.he, 1e-6);

    float shear_speed = 15.0 / (sqrt(max(r_norm, 0.0)) + 0.1);
    float angle = phi + shear_speed;

    float3 pos = float3(r_norm * 4.0 * cos(angle),
                        r_norm * 4.0 * sin(angle),
                        h_norm * 1.5);

    float3 warp;
    warp.x = fbm(pos + float3(1.2, 3.4, 0.0));
    warp.y = fbm(pos + float3(8.3, 0.7, 0.0));
    warp.z = fbm(pos + float3(0.1, 5.2, 0.0));

    float n = fbm(pos + warp * 1.8);

    float radial_edge = smoothstep(0.0, 0.1, r_norm) * (1.0 - smoothstep(0.9, 1.0, r_norm));
    // Rays are recorded at disk-entry points, so keep boundary density non-zero.
    float vertical_edge = 1.0 - smoothstep(0.8, 1.6, abs(h_norm));

    n = (n - 0.4) * 2.5;

    return clamp(n * radial_edge * vertical_edge, 0.0, 1.0);
}

kernel void renderBH(constant Params& P [[buffer(0)]],
                     device CollisionInfo* outInfo [[buffer(1)]],
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
    info.hit = 0;
    info.ct  = 0.0;
    info.T   = 0.0;
    info.v_disk = float4(0);
    info.direct_world = float4(0);
    info.noise = 0.0;

    float4 p = float4(0.0, r0, M_PI * 0.5, 0.0);
    float dt   = 0.1;
    float dr   = local.x;
    float dphi = local.y / max(r0, 1e-6);
    float4 v = float4(dt, dr, 0.0, dphi);

    if (P.metric == 0) {
        float horizonRadius = P.rs * (1.0 + P.eps);

        for (int i=0; i<P.maxSteps; ++i) {
            rk4_step(p, v, P);

            float3 localPos = conv(p.y, p.z, p.w);
            float3 worldPos = localPos.x * newX + localPos.y * newY + localPos.z * newZ;

            if (hasPrev) {
                float tEnter = 0.0;
                if (segment_enter_disk(world0, worldPos, P, tEnter)) {
                    float3 hitPos = mix(world0, worldPos, tEnter);
                    float dxy = length(float2(hitPos.x, hitPos.y));
                    if (dxy > P.rs && dxy < P.re) {
                        float absV = sqrt(P.G * P.M / dxy);
                        float3 phiVec = normalize(float3(hitPos.y, -hitPos.x, 0.0));
                        float3 v_disk = absV * phiVec;

                        float rState = p.y;
                        float phi = p.w;
                        float dx = cos(phi) * v.y - rState * sin(phi) * v.w;
                        float dy = sin(phi) * v.y + rState * cos(phi) * v.w;
                        float3 worldVel = dx * newX + dy * newY;
                        float3 direct = normalize(worldVel);

                        float T0 = pow((3.0 * P.G * P.M) / (8.0 * M_PI * pow(P.rs, 3.0) * P.k), 0.25);
                        float T  = T0 * pow(dxy / P.rs, -0.75);

                        info.hit = 1;
                        info.ct  = P.c * p.x;
                        info.T   = T;
                        info.v_disk = float4(v_disk, 0.0);
                        info.direct_world = float4(-direct, 0.0);
                        float3 segProbe = worldPos - world0;
                        float segProbeLen2 = dot(segProbe, segProbe);
                        float3 samplePos = hitPos;
                        if (segProbeLen2 > 1e-20) {
                            float3 probe = hitPos + normalize(segProbe) * (0.35 * P.he);
                            if (inside_disk_volume(probe, P)) samplePos = probe;
                        }
                        float sampleR = length(float2(samplePos.x, samplePos.y));
                        float phiPos = atan2(samplePos.y, samplePos.x);
                        info.noise = disk_cloud_noise(sampleR, phiPos, samplePos.z, P);

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
        float a = clamp(P.spin, 0.0, 0.999);
        float escapeRadius = max(P.kerrEscapeMult, 1.0) * P.re;
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

                        float a2 = a * a;
                        float z1 = 1.0 + pow(max(1.0 - a2, 0.0), 1.0 / 3.0) * (pow(1.0 + a, 1.0 / 3.0) + pow(1.0 - a, 1.0 / 3.0));
                        float z2 = sqrt(max(3.0 * a2 + z1 * z1, 0.0));
                        float r_isco = 3.0 + z2 - sqrt(max((3.0 - z1) * (3.0 + z1 + 2.0 * z2), 0.0));

                        if (r_M > r_isco && dxy < P.re) {
                            float omega = 1.0 / max(pow(r_M, 1.5) + a, 1e-8);
                            KerrCovMetric diskCov = kerr_cov_metric(r_M, 0.5 * M_PI, a);
                            float uDen = -(diskCov.gtt
                                         + 2.0 * omega * diskCov.gtphi
                                         + omega * omega * diskCov.gphiphi);
                            float u_t = 1.0 / sqrt(max(uDen, 1e-12));
                            float E_emit = u_t * (1.0 - omega * Lz);
                            float g_factor = 1.0 / max(E_emit, 1e-8);
                            if (!isfinite(g_factor)) g_factor = 1.0;
                            g_factor = clamp(g_factor, 1e-4, 1e4);

                            float3 segDir = worldPos - world0;
                            float segLen2 = dot(segDir, segDir);
                            float3 direct = (segLen2 > 1e-20) ? normalize(segDir) : normalize(dir);

                            float T0 = pow((3.0 * P.G * P.M) / (8.0 * M_PI * pow(P.rs, 3.0) * P.k), 0.25);
                            float T_newtonian = T0 * pow(dxy / P.rs, -0.75);
                            float boundary_factor = pow(max(1.0 - sqrt(r_isco / r_M), 0.0), 0.25);
                            float T = T_newtonian * boundary_factor;

                            info.hit = 1;
                            info.ct  = state.t * massLen;
                            info.T   = T;
                            info.v_disk = float4(g_factor, dxy, 0.0, 0.0);
                            info.direct_world = float4(-direct, 0.0);
                            float3 segProbe = worldPos - world0;
                            float segProbeLen2 = dot(segProbe, segProbe);
                            float3 samplePos = hitPos;
                            if (segProbeLen2 > 1e-20) {
                                float3 probe = hitPos + normalize(segProbe) * (0.35 * P.he);
                                if (inside_disk_volume(probe, P)) samplePos = probe;
                            }
                            float sampleR = length(float2(samplePos.x, samplePos.y));
                            float phiPos = atan2(samplePos.y, samplePos.x);
                            info.noise = disk_cloud_noise(sampleR, phiPos, samplePos.z, P);

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

static inline float3 comp_linear_rgb_precloud(const CollisionInfo rec,
                                              constant Params& P,
                                              constant ComposeParams& C)
{
    float g_total = 1.0;
    float r_emit = P.rs * 2.0;
    if (C.spectralEncoding == 1u) {
        g_total = clamp(rec.v_disk.x, 1e-4, 1e4);
        r_emit = max(rec.v_disk.y, P.rs * 1.0001);
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
        r_emit = (P.G * P.M) / max(v_norm * v_norm, 1e-30);
        r_emit = max(r_emit, P.rs * 1.0001);
        float g_gr = sqrt(clamp(1.0 - P.rs / r_emit, 1e-8, 1.0));
        g_total = clamp(delta * g_gr, 1e-4, 1e4);
    }

    float T_emit = max(rec.T, 1.0);
    float T_obs = max(T_emit * g_total, 1.0);

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
        float b = comp_planck_lambda(lam_m, T_obs) * precise::pow(g_total, 3.0);
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

    float r_in = max(C.innerEdgeMult, 1.0) * P.rs;
    float boundary = clamp(1.0 - sqrt(r_in / max(r_emit, r_in)), 0.0, 1.0);
    float3 d_world = rec.direct_world.xyz;
    float mu = abs(d_world.z) / max(length(d_world), 1e-30);
    float limb = 0.4 + 0.6 * clamp(mu, 0.0, 1.0);
    rgb *= boundary * limb;
    return rgb;
}

static inline float3 comp_linear_rgb(const CollisionInfo rec,
                                     constant Params& P,
                                     constant ComposeParams& C)
{
    float3 rgb = comp_linear_rgb_precloud(rec, P, C);
    float cloudRaw = comp_cloud_raw(rec, P, C);
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
    float3 rgb = comp_linear_rgb_precloud(rec, P, C);
    float cloudRaw = comp_cloud_raw(rec, P, C);
    outLinear[gid] = float4(rgb, cloudRaw);
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
    float cloud = comp_cloud_norm_from_raw(clamp(rgbw.w, 0.0, 1.0), C);
    float3 rgb = comp_apply_cloud_to_rgb(rgbw.xyz, cloud);
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
            float cloud = comp_cloud_norm_from_raw(clamp(rgbw.w, 0.0, 1.0), C);
            float3 rgb = comp_apply_cloud_to_rgb(rgbw.xyz, cloud);
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
