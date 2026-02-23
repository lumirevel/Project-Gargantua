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

static inline void rk4_step(thread float4 &p, thread float4 &v, constant Params& P) {
    float h = P.h;

    float4 k1_p = h * v;
    float4 k1_v = h * schwarzschild_accel(p, v, P);

    float4 k2_p = h * (v + 0.5 * k1_v);
    float4 k2_v = h * schwarzschild_accel(p + 0.5 * k1_p, v + 0.5 * k1_v, P);

    float4 k3_p = h * (v + 0.5 * k2_v);
    float4 k3_v = h * schwarzschild_accel(p + 0.5 * k2_p, v + 0.5 * k2_v, P);

    float4 k4_p = h * (v + k3_v);
    float4 k4_v = h * schwarzschild_accel(p + k3_p, v + k3_v, P);

    p += (k1_p + 2.0*k2_p + 2.0*k3_p + k4_p) / 6.0;
    v += (k1_v + 2.0*k2_v + 2.0*k3_v + k4_v) / 6.0;

    // Python Lux.update()의 r<0 보정과 동일
    if (p.y < 0.0) {
        p.y = -p.y;
        p.w = fmod(p.w + M_PI, 2.0 * M_PI);
        if (p.w < 0.0) p.w += 2.0 * M_PI;
    }
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

    // Lux 초기 p: (0,r,pi/2,0)
    float4 p = float4(0.0, r0, M_PI * 0.5, 0.0);

    // Python의 local = c * inverse * direction.unit 과 동일:
    // inverse rows = (newX,newY,newZ)
    float3 local = P.c * float3(dot(newX, dir), dot(newY, dir), dot(newZ, dir));

    float dt   = 0.1;       // 너 코드 고정
    float dr   = local.x;   // rVec row
    float dphi = local.y / r0; // phi row / r

    // Lux에서 dtheta는 계산하지만 _v에는 0 넣었음
    float4 v = float4(dt, dr, 0.0, dphi);

    bool hasPrev = false;
    float3 world0 = float3(0);

    CollisionInfo info;
    info.hit = 0;
    info.ct  = 0.0;
    info.T   = 0.0;
    info.v_disk = float3(0);
    info.direct_world = float3(0);
    info.noise = 0.0;

    for (int i=0; i<P.maxSteps; ++i) {
        // RK4
        rk4_step(p, v, P);

        // worldPos = transformMatrix * conv(...)
        // transformMatrix = inverse.T => columns are newX,newY,newZ
        float3 localPos = conv(p.y, p.z, p.w);
        float3 worldPos = localPos.x * newX + localPos.y * newY + localPos.z * newZ;

        if (hasPrev) {
            float tEnter = 0.0;
            if (segment_enter_disk(world0, worldPos, P, tEnter)) {
                float3 hitPos = mix(world0, worldPos, tEnter);
                float dxy = length(float2(hitPos.x, hitPos.y));
                if (dxy > P.rs && dxy < P.re) {
                    // disk velocity (Python과 동일)
                    float absV = sqrt(P.G * P.M / dxy);
                    float3 phiVec = normalize(float3(-hitPos.y, hitPos.x, 0.0));
                    float3 v_disk = absV * phiVec;

                    // Lux.v와 동일한 world velocity 계산
                    // theta=pi/2, dtheta=0 -> dx,dy만 남음
                    float r = p.y;
                    float phi = p.w;

                    float dx = cos(phi) * v.y - r * sin(phi) * v.w;
                    float dy = sin(phi) * v.y + r * cos(phi) * v.w;
                    float dz = 0.0;

                    float3 worldVel = dx * newX + dy * newY + dz * newZ;
                    float3 direct = normalize(worldVel);

                    // Temperature profile (Python과 동일)
                    float T0 = pow((3.0 * P.G * P.M) / (8.0 * M_PI * pow(P.rs, 3.0) * P.k), 0.25);
                    float T  = T0 * pow(dxy / P.rs, -0.75);

                    info.hit = 1;
                    info.ct  = P.c * p.x;
                    info.T   = T;
                    info.v_disk = v_disk;
                    info.direct_world = -direct;  // Python과 동일하게 -direct 저장
                    float phiPos = atan2(hitPos.y, hitPos.x);
                    info.noise = disk_texture_noise(dxy, phiPos, hitPos.z, P);

                    outInfo[idx] = info;
                    return;
                }
            }
        }

        hasPrev = true;
        world0 = worldPos;

        // escape cutoff: 너 코드의 d > 3*re와 같은 의도
        float dxy = length(float2(worldPos.x, worldPos.y));
        if (dxy > 3.0 * P.re) break;

        // horizon guard
        if (p.y < P.rs * (1.0 + P.eps)) break;
    }

    outInfo[idx] = info;
}
