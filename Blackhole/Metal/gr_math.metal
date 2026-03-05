// Auto-split from integral.metal (Phase 2 refactor).
#if defined(BH_INCLUDE_GR_MATH) && (BH_INCLUDE_GR_MATH)
constant int  FC_METRIC [[function_constant(0)]];
constant uint FC_PHYSICS_MODE [[function_constant(1)]];
constant uint FC_VISIBLE_MODE [[function_constant(2)]];
constant uint FC_TRACE_DEBUG_OFF [[function_constant(3)]];

// Hot-path helper: keep algebraically equivalent x^(3/2) while avoiding generic pow().
static inline float pow_1p5(float x) {
    float xr = max(x, 0.0);
    return xr * sqrt(xr);
}

static inline bool visible_mode_enabled_fc() {
    return FC_VISIBLE_MODE != 0u;
}

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
    uint   diskNoiseModel; // 0=streamline cloud, 1=perlin soft, 2=perlin ec7 legacy, 3=perlin classic (f552 style)
    float  diskMdotEdd;    // mdot / mdot_edd
    float  diskRadiativeEfficiency; // thin-disk eta
    uint   diskPhysicsMode; // 0=thin, 1=thick/plasma, 2=precision-nt, 3=grmhd-scalar-rt
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
    uint   diskVolumeMode; // 0=off, 1=on
    uint   diskVolumeR;
    uint   diskVolumePhi;
    uint   diskVolumeZ;
    float  diskVolumeRNormMin;
    float  diskVolumeRNormMax;
    float  diskVolumeZNormMax;
    float  diskVolumeTauScale;
    uint   diskVolumeFormat; // 0=legacy float4, 1=grmhd dual volume
    uint   diskVolumeR0;
    uint   diskVolumePhi0;
    uint   diskVolumeZ0;
    uint   diskVolumeR1;
    uint   diskVolumePhi1;
    uint   diskVolumeZ1;
    float  diskNuObsHz;
    float  diskGrmhdDensityScale;
    float  diskGrmhdBScale;
    float  diskGrmhdEmissionScale;
    float  diskGrmhdAbsorptionScale;
    float  diskGrmhdVelScale;
    uint   diskGrmhdDebugView; // 0=off, 1=max_rho, 2=max_b2, 3=max_jnu, 4=max_inu
    uint   diskPolarizedRT; // 0=off, 1=approx Stokes transport
    float  diskPolarizationFrac; // intrinsic linear pol fraction at emission
    float  diskFaradayRotScale; // Q/U rotation scale
    float  diskFaradayConvScale; // U/V conversion scale
    uint   visibleMode; // 0=off, 1=visible-spectrum rendering
    uint   visibleSamples; // wavelength sample count for CIE integration
    uint   visibleTeffModel; // 0=parametric, 1=thin-disk simplified
    uint   visiblePad0;
    float  visibleTeffT0;
    float  visibleTeffR0;
    float  visibleTeffP;
    float  visiblePhotosphereRhoThreshold;
    float  visibleBhMass;
    float  visibleMdot;
    float  visibleRIn;
    float  visibleKappa;
    uint   visibleEmissionModel; // 0=blackbody, 1=synchrotron-like powerlaw
    float  visibleEmissionAlpha; // spectral slope for powerlaw model
    uint   rayBundleSSAA; // 0=off(single ray), 1=4x sub-pixel SSAA in kernel
    uint   rayBundleJacobian; // 0=off, 1=ray-differential magnification weighting
    float  rayBundleJacobianStrength; // multiplicative gain on Jacobian magnification
    float  rayBundleFootprintClamp; // symmetric clamp in log2-space around 1.0
    uint   coolAbsorptionMode; // 0=off, 1=enable cool gas/dust absorption
    float  coolDustToGas; // dust-to-gas mass ratio for cool phase
    float  coolDustKappaV; // dust opacity at 550nm [cm^2/g_dust]
    float  coolDustBeta; // opacity wavelength slope
    float  coolDustTSub; // dust sublimation temperature [K]
    float  coolDustTWidth; // sublimation transition width [K]
    float  coolGasKappa0; // cool gas opacity normalization [cm^2/g]
    float  coolGasNuSlope; // frequency slope for cool-gas opacity
    float  coolClumpStrength; // unresolved clumpiness boost strength
    float  coolAbsorptionPad;
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

// Lite collision payload for linear32 path (2xfloat4 = 32 bytes).
// Keeps only fields required by non-debug/non-visible compose in legacy disk modes.
struct CollisionLite32 {
    float4 vDiskXYZ_T;      // {v_disk.x, v_disk.y, v_disk.z, T}
    float4 noise_dirOct_hit; // {noise, dirOct.x, dirOct.y, hit(0/1)}
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
    if (FC_METRIC == 0) return schwarzschild_accel(p, v, P);
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

#endif
