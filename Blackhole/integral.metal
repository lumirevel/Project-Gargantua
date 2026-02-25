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
    float3 v_disk;       // disk local velocity in world coords
    float3 direct_world; // -unit(worldVel) (Python과 동일)
    float  noise;        // 1단계는 0으로
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

static inline float fade(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

static inline float lerp1(float a, float b, float t) {
    return a + t * (b - a);
}

static inline uint hash2(uint x, uint y, uint base) {
    uint h = x * 374761393u + y * 668265263u + base * 362437u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h ^= (h >> 16);
    return h;
}

static inline float grad2(uint h, float x, float y) {
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

static inline int pos_mod(int x, int m) {
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

    int rx0 = pos_mod(x0, repeatX);
    int ry0 = pos_mod(y0, repeatY);
    int rx1 = pos_mod(x1, repeatX);
    int ry1 = pos_mod(y1, repeatY);

    float n00 = grad2(hash2(uint(rx0), uint(ry0), base), xf, yf);
    float n10 = grad2(hash2(uint(rx1), uint(ry0), base), xf - 1.0, yf);
    float n01 = grad2(hash2(uint(rx0), uint(ry1), base), xf, yf - 1.0);
    float n11 = grad2(hash2(uint(rx1), uint(ry1), base), xf - 1.0, yf - 1.0);

    float u = fade(xf);
    float v = fade(yf);
    float nx0 = lerp1(n00, n10, u);
    float nx1 = lerp1(n01, n11, u);
    return lerp1(nx0, nx1, v);
}

static inline float disk_texture_noise(float dxy, float phi, float z, constant Params& P) {
    float denom = max(P.re - P.rs, 1e-6);
    float u = clamp((dxy - P.rs) / denom, 0.0, 1.0);

    float spiral = phi + 1.8 * log(max(dxy / P.rs, 1.0));
    float c = cos(spiral);
    float s = sin(spiral);

    float bx = 12.0 * u + 2.6 * c;
    float by = 2.6 * s;

    float w1 = perlin2_repeat(96.0 * bx, 96.0 * by, 8192, 8192, 23u);
    float w2 = perlin2_repeat(144.0 * bx + 1.6 * w1, 144.0 * by - 1.1 * w1, 8192, 8192, 71u);

    float fbm = 0.0;
    float amp = 1.0;
    float freq = 1.0;
    float ampSum = 0.0;
    for (int i = 0; i < 5; ++i) {
        float nx = (bx + 0.20 * w1) * freq;
        float ny = (by + 0.18 * w2) * freq;
        float n = perlin2_repeat(128.0 * nx, 128.0 * ny, 8192, 8192, 101u + uint(i * 53));
        fbm += amp * n;
        ampSum += amp;
        amp *= 0.55;
        freq *= 2.0;
    }
    fbm = (ampSum > 0.0) ? (fbm / ampSum) : 0.0;

    float zFade = exp(-abs(z) / max(1.25 * P.he, 1e-6));
    float edgeIn = smoothstep(0.01, 0.08, u);
    float edgeOut = 1.0 - smoothstep(0.94, 0.998, u);
    float radialFade = edgeIn * edgeOut;

    return clamp(3.2 * fbm * zFade * radialFade, -1.0, 1.0);
}

kernel void renderBH(constant Params& P [[buffer(0)]],
                     device CollisionInfo* outInfo [[buffer(1)]],
                     uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= P.width || gid.y >= P.height) return;
    uint idx = gid.y * P.width + gid.x;

    // Eye의 screenCoord 생성과 동일한 스케일: [-w/2, w/2], [-h/2, h/2]
    float x = (float(gid.x) + 0.5) - float(P.width)  * 0.5;
    float y = (float(gid.y) + 0.5) - float(P.height) * 0.5;

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
    info.v_disk = float3(0);
    info.direct_world = float3(0);
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
                        info.v_disk = v_disk;
                        info.direct_world = -direct;
                        float phiPos = atan2(hitPos.y, hitPos.x);
                        info.noise = disk_texture_noise(dxy, phiPos, hitPos.z, P);

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
                        if (dxy > P.rs && dxy < P.re) {
                            // Kerr disk emissivity shift:
                            // encode exact GR g-factor in v_disk.x and emission radius in v_disk.y.
                            float r_M = dxy / max(massLen, 1e-12);
                            float omega = -1.0 / max(pow(r_M, 1.5) + a, 1e-8); // flipped disk rotation
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
                            float T  = T0 * pow(dxy / P.rs, -0.75);

                            info.hit = 1;
                            info.ct  = state.t * massLen;
                            info.T   = T;
                            info.v_disk = float3(g_factor, dxy, 0.0);
                            info.direct_world = -direct;
                            float phiPos = atan2(hitPos.y, hitPos.x);
                            info.noise = disk_texture_noise(dxy, phiPos, hitPos.z, P);

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
