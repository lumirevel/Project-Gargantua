#!/usr/bin/env swift
import Foundation
import Metal
import simd

struct RoomRTParams {
    var width: UInt32
    var height: UInt32
    var spp: UInt32
    var apertureSpp: UInt32
    var focusDepth: Float
    var fNumber: Float
    var dofStrength: Float
    var apertureBlades: UInt32
    var bokehTargets: UInt32
    var colorChart: UInt32
    var pad0: UInt32 = 0
    var pad1: UInt32 = 0
}

func value(_ name: String, default fallback: String) -> String {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return fallback }
    return args[i + 1]
}

func flag(_ name: String) -> Bool {
    CommandLine.arguments.contains(name)
}

let outPath = value("--out", default: "/private/tmp/rt_room_gpu.linear32f32")
let width = UInt32(value("--width", default: "480"))!
let height = UInt32(value("--height", default: "270"))!
let spp = UInt32(value("--spp", default: "1"))!
let apertureSpp = UInt32(value("--aperture-spp", default: "0"))!
let focusDepth = Float(value("--focus-depth", default: "4.55"))!
let fNumber = Float(value("--f-number", default: "1.4"))!
let dofStrength = Float(value("--dof-strength", default: "1.8"))!
let apertureBlades = UInt32(value("--aperture-blades", default: "6"))!

let shader = #"""
#include <metal_stdlib>
using namespace metal;

struct RoomRTParams {
    uint width;
    uint height;
    uint spp;
    uint apertureSpp;
    float focusDepth;
    float fNumber;
    float dofStrength;
    uint apertureBlades;
    uint bokehTargets;
    uint colorChart;
    uint pad0;
    uint pad1;
};

struct Hit {
    float t;
    float3 p;
    float3 n;
    int mat;
};

static inline float3 safe_norm(float3 v) {
    return normalize(v + float3(1.0e-20));
}

static inline float hash11(float x) {
    return fract(sin(x * 127.1f) * 43758.5453f);
}

static inline float3 sky(float3 rd) {
    float t = 0.5f * (rd.y + 1.0f);
    return mix(float3(0.015f, 0.018f, 0.022f), float3(0.055f, 0.070f, 0.095f), t);
}

static inline bool plane_hit(float3 ro, float3 rd, float3 p0, float3 n, float2 ar, float2 br, int axA, int axB, thread Hit& best, int mat) {
    float denom = dot(n, rd);
    if (fabs(denom) < 1.0e-6f) return false;
    float t = dot(p0 - ro, n) / denom;
    if (t < 1.0e-4f || t >= best.t) return false;
    float3 p = ro + rd * t;
    float vals[3] = { p.x, p.y, p.z };
    if (vals[axA] < ar.x || vals[axA] > ar.y || vals[axB] < br.x || vals[axB] > br.y) return false;
    best.t = t; best.p = p; best.n = n; best.mat = mat;
    return true;
}

static inline bool sphere_hit(float3 ro, float3 rd, float3 c, float r, thread Hit& best, int mat) {
    float3 oc = ro - c;
    float b = dot(oc, rd);
    float cc = dot(oc, oc) - r * r;
    float h = b * b - cc;
    if (h < 0.0f) return false;
    float s = sqrt(h);
    float t = -b - s;
    if (t < 1.0e-4f) t = -b + s;
    if (t < 1.0e-4f || t >= best.t) return false;
    float3 p = ro + rd * t;
    best.t = t; best.p = p; best.n = (p - c) / r; best.mat = mat;
    return true;
}

static inline bool refract_dir(float3 rd, float3 n, float eta, thread float3& outDir) {
    float cosi = -dot(n, rd);
    float sint2 = eta * eta * max(0.0f, 1.0f - cosi * cosi);
    if (sint2 > 1.0f) return false;
    float cost = sqrt(max(0.0f, 1.0f - sint2));
    outDir = safe_norm(eta * rd + (eta * cosi - cost) * n);
    return true;
}

static inline Hit intersect_scene(float3 ro, float3 rd, constant RoomRTParams& P) {
    Hit h; h.t = 1.0e20f; h.p = 0.0f; h.n = 0.0f; h.mat = -1;
    plane_hit(ro, rd, float3(0,-1,0), float3(0,1,0), float2(-2.2f,2.2f), float2(-3.1f,1.4f), 0, 2, h, 0);
    plane_hit(ro, rd, float3(0,2,0), float3(0,-1,0), float2(-2.2f,2.2f), float2(-3.1f,1.4f), 0, 2, h, 0);
    plane_hit(ro, rd, float3(0,0,-3), float3(0,0,1), float2(-2.2f,2.2f), float2(-1.0f,2.0f), 0, 1, h, 1);
    plane_hit(ro, rd, float3(-2.2f,0,0), float3(1,0,0), float2(-3.1f,1.4f), float2(-1.0f,2.0f), 2, 1, h, 2);
    plane_hit(ro, rd, float3(2.2f,0,0), float3(-1,0,0), float2(-3.1f,1.4f), float2(-1.0f,2.0f), 2, 1, h, 0);
    plane_hit(ro, rd, float3(0,1.995f,0), float3(0,-1,0), float2(-0.85f,0.85f), float2(-0.55f,0.55f), 0, 2, h, 6);
    sphere_hit(ro, rd, float3(-0.85f,-0.45f,-1.75f), 0.55f, h, 3);
    sphere_hit(ro, rd, float3(0.35f,-0.50f,-1.45f), 0.50f, h, 4);
    sphere_hit(ro, rd, float3(1.05f,-0.62f,-2.10f), 0.38f, h, 5);
    // High-contrast rear-wall target behind the glass sphere. It makes
    // refraction and rear-surface visibility inspectable in room validation.
    plane_hit(ro, rd, float3(0,0,-2.985f), float3(0,0,1), float2(-0.02f,0.38f), float2(-0.76f,-0.36f), 0, 1, h, 36);
    plane_hit(ro, rd, float3(0,0,-2.984f), float3(0,0,1), float2(0.38f,0.78f), float2(-0.76f,-0.36f), 0, 1, h, 37);
    plane_hit(ro, rd, float3(0,0,-2.983f), float3(0,0,1), float2(-0.02f,0.38f), float2(-0.36f,0.04f), 0, 1, h, 37);
    plane_hit(ro, rd, float3(0,0,-2.982f), float3(0,0,1), float2(0.38f,0.78f), float2(-0.36f,0.04f), 0, 1, h, 36);
    if (P.bokehTargets != 0) {
        sphere_hit(ro, rd, float3(-1.25f,0.45f,-2.72f), 0.045f, h, 20);
        sphere_hit(ro, rd, float3(-0.78f,0.82f,-2.88f), 0.038f, h, 21);
        sphere_hit(ro, rd, float3(0.88f,0.52f,-2.66f), 0.042f, h, 22);
        sphere_hit(ro, rd, float3(1.35f,0.95f,-2.92f), 0.035f, h, 21);
    }
    if (P.colorChart != 0) {
        float x0 = -1.60f, y0 = 0.72f, dx = 0.36f, dy = 0.28f;
        for (int j = 0; j < 2; ++j) {
            for (int i = 0; i < 3; ++i) {
                float cx = x0 + float(i) * 0.46f;
                float cy = y0 - float(j) * 0.40f;
                plane_hit(ro, rd, float3(0,0,-2.985f), float3(0,0,1), float2(cx,cx+dx), float2(cy,cy+dy), 0, 1, h, 30 + j * 3 + i);
            }
        }
    }
    return h;
}

static inline float3 albedo_for(int mat) {
    if (mat == 1) return float3(0.84f,0.72f,0.58f);
    if (mat == 2) return float3(0.55f,0.62f,0.76f);
    if (mat == 3) return float3(0.92f,0.88f,0.78f);
    if (mat == 4) return float3(0.94f,0.98f,1.00f);
    if (mat == 5) return float3(0.96f,0.22f,0.10f);
    if (mat == 30) return float3(0.92f,0.18f,0.12f);
    if (mat == 31) return float3(0.16f,0.72f,0.24f);
    if (mat == 32) return float3(0.14f,0.30f,0.90f);
    if (mat == 33) return float3(0.94f,0.82f,0.18f);
    if (mat == 34) return float3(0.82f,0.20f,0.82f);
    if (mat == 35) return float3(0.18f,0.82f,0.86f);
    if (mat == 36) return float3(0.05f,0.055f,0.06f);
    if (mat == 37) return float3(0.96f,0.94f,0.82f);
    return float3(0.78f,0.76f,0.70f);
}

static inline float3 emission_for(int mat) {
    if (mat == 6) return float3(18.0f,15.4f,11.8f);
    if (mat == 20) return float3(55.0f,34.0f,13.0f);
    if (mat == 21) return float3(62.0f,58.0f,48.0f);
    if (mat == 22) return float3(12.0f,24.0f,60.0f);
    return float3(0.0f);
}

static inline float shadow_vis(float3 p, float3 n, float3 lp, constant RoomRTParams& P) {
    float3 l = lp - p;
    float d = length(l);
    float3 ld = l / max(d, 1.0e-4f);
    Hit sh = intersect_scene(p + n * 0.002f, ld, P);
    return (sh.mat >= 0 && sh.t < d - 0.02f && sh.mat != 6) ? 0.0f : 1.0f;
}

static inline float3 direct_light(float3 p, float3 n, constant RoomRTParams& P) {
    float3 L = 0.0f;
    float3 pts[5] = {
        float3(-0.2975f,1.98f,-0.1925f), float3(0.2975f,1.98f,-0.1925f),
        float3(-0.2975f,1.98f,0.1925f), float3(0.2975f,1.98f,0.1925f),
        float3(0.0f,1.98f,0.0f)
    };
    for (int i = 0; i < 5; ++i) {
        float3 v = pts[i] - p;
        float dist2 = max(dot(v, v), 0.02f);
        float3 ld = v * rsqrt(dist2);
        float ndl = max(dot(n, ld), 0.0f);
        float vis = shadow_vis(p, n, pts[i], P);
        L += float3(18.0f,15.4f,11.8f) * ndl * vis / dist2;
    }
    return L * 0.12f;
}

static inline float3 shade_simple(float3 ro, float3 rd, constant RoomRTParams& P) {
    Hit h = intersect_scene(ro, rd, P);
    if (h.mat < 0) return sky(rd);
    float3 e = emission_for(h.mat);
    if (dot(e,e) > 0.0f) return e;
    float3 a = albedo_for(h.mat);
    float3 amb = 0.025f * sky(h.n);
    return a * (amb + direct_light(h.p, h.n, P));
}

static inline float3 shade_secondary(float3 ro, float3 rd, constant RoomRTParams& P) {
    Hit h = intersect_scene(ro, rd, P);
    if (h.mat < 0) return sky(rd);
    float3 e = emission_for(h.mat);
    if (dot(e,e) > 0.0f) return e;
    float3 a = albedo_for(h.mat);
    float3 base = a * (0.025f * sky(h.n) + direct_light(h.p, h.n, P));
    if (h.mat == 4) {
        float cosi = clamp(-dot(h.n, rd), 0.0f, 1.0f);
        float fres = 0.04f + 0.96f * pow(1.0f - cosi, 5.0f);
        float3 refl = shade_simple(h.p + h.n * 0.004f, safe_norm(reflect(rd, h.n)), P);
        float3 refrIn;
        if (!refract_dir(rd, h.n, 1.0f / 1.48f, refrIn)) {
            return refl;
        }
        Hit exitHit = intersect_scene(h.p - h.n * 0.004f, refrIn, P);
        float3 trn;
        float pathLen = 0.65f;
        if (exitHit.mat == 4) {
            float3 refrOut;
            pathLen = length(exitHit.p - h.p);
            if (refract_dir(refrIn, -exitHit.n, 1.48f, refrOut)) {
                trn = shade_simple(exitHit.p + exitHit.n * 0.004f, refrOut, P);
            } else {
                trn = shade_simple(exitHit.p - exitHit.n * 0.004f, safe_norm(reflect(refrIn, -exitHit.n)), P);
            }
        } else {
            trn = shade_simple(h.p - h.n * 0.004f, refrIn, P);
        }
        float3 tint = exp(-float3(0.026f,0.010f,0.004f) * pathLen);
        return base * 0.025f + mix(trn * tint, refl, fres);
    }
    return base;
}

static inline float3 trace_room(float3 ro, float3 rd, constant RoomRTParams& P) {
    Hit h = intersect_scene(ro, rd, P);
    if (h.mat < 0) return sky(rd);
    float3 e = emission_for(h.mat);
    if (dot(e,e) > 0.0f) return e;
    float3 a = albedo_for(h.mat);
    float3 base = a * (0.025f * sky(h.n) + direct_light(h.p, h.n, P));
    if (h.mat == 3) {
        float3 rr = reflect(rd, h.n);
        // Metal reflections must preserve the material behavior of the object
        // they reflect.  In particular, a reflected glass sphere should still
        // show refraction/Fresnel instead of collapsing to diffuse albedo.
        return base * 0.08f + shade_secondary(h.p + h.n * 0.004f, safe_norm(rr), P) * a * 0.92f;
    }
    if (h.mat == 4) {
        float cosi = clamp(-dot(h.n, rd), 0.0f, 1.0f);
        float fres = 0.04f + 0.96f * pow(1.0f - cosi, 5.0f);
        float3 refl = shade_simple(h.p + h.n * 0.004f, safe_norm(reflect(rd, h.n)), P);
        float3 refrIn;
        if (!refract_dir(rd, h.n, 1.0f / 1.48f, refrIn)) {
            return refl;
        }
        Hit exitHit = intersect_scene(h.p - h.n * 0.004f, refrIn, P);
        float3 trn;
        float pathLen = 0.65f;
        if (exitHit.mat == 4) {
            float3 refrOut;
            pathLen = length(exitHit.p - h.p);
            if (refract_dir(refrIn, -exitHit.n, 1.48f, refrOut)) {
                trn = shade_simple(exitHit.p + exitHit.n * 0.004f, refrOut, P);
            } else {
                trn = shade_simple(exitHit.p - exitHit.n * 0.004f, safe_norm(reflect(refrIn, -exitHit.n)), P);
            }
        } else {
            trn = shade_simple(h.p - h.n * 0.004f, refrIn, P);
        }
        float3 tint = exp(-float3(0.026f,0.010f,0.004f) * pathLen);
        return base * 0.025f + mix(trn * tint, refl, fres);
    }
    return base;
}

static inline float primary_depth(float3 ro, float3 rd, float focusDepth, constant RoomRTParams& P) {
    Hit h = intersect_scene(ro, rd, P);
    if (h.mat < 0) return focusDepth;
    if (h.mat != 4) return h.t;

    float cosi = clamp(-dot(h.n, rd), 0.0f, 1.0f);
    float fres = 0.04f + 0.96f * pow(1.0f - cosi, 5.0f);
    float3 refrIn;
    if (!refract_dir(rd, h.n, 1.0f / 1.48f, refrIn)) {
        return h.t;
    }
    Hit exitHit = intersect_scene(h.p - h.n * 0.004f, refrIn, P);
    if (exitHit.mat != 4) {
        return h.t;
    }
    float3 refrOut;
    if (!refract_dir(refrIn, -exitHit.n, 1.48f, refrOut)) {
        return h.t + exitHit.t;
    }
    Hit seen = intersect_scene(exitHit.p + exitHit.n * 0.004f, refrOut, P);
    float transmitDepth = h.t + exitHit.t + ((seen.mat < 0) ? max(focusDepth - h.t - exitHit.t, 0.0f) : seen.t);
    // A single depth channel cannot represent reflected and transmitted layers.
    // Use the same Schlick mix as color so DOF follows the dominant visible layer.
    return mix(transmitDepth, h.t, clamp(fres, 0.0f, 1.0f));
}

static inline float2 aperture_sample(uint i, uint n, uint blades) {
    float u = (float(i) + 0.5f) / max(float(n), 1.0f);
    float theta = float(i) * 2.39996323f;
    float r = sqrt(u);
    if (blades >= 3) {
        float sector = 6.2831853f / float(blades);
        float local = fmod(theta + 0.5f * sector, sector) - 0.5f * sector;
        float edge = cos(0.5f * sector) / max(cos(local), 1.0e-4f);
        r *= clamp(edge, 0.0f, 1.0f);
    }
    return r * float2(cos(theta), sin(theta));
}

kernel void room_rt_kernel(device float4* outLinear [[buffer(0)]],
                           constant RoomRTParams& P [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= P.width || gid.y >= P.height) return;
    float3 cam = float3(0.0f, 0.40f, 3.20f);
    float3 target = float3(0.05f, -0.08f, -1.50f);
    float3 forward = safe_norm(target - cam);
    float3 right = safe_norm(cross(forward, float3(0,1,0)));
    float3 up = safe_norm(cross(right, forward));
    float fov = 58.0f * 0.01745329252f;
    float scale = tan(0.5f * fov);
    float aspect = float(P.width) / float(P.height);
    uint samples = max(P.spp, 1u);
    uint apertureSamples = P.apertureSpp;
    if (apertureSamples > 0) samples = max(apertureSamples, 1u);
    float3 col = 0.0f;
    float depthMin = P.focusDepth;
    for (uint s = 0; s < samples; ++s) {
        float jx = (P.spp <= 1 || apertureSamples > 0) ? 0.5f : hash11(float(gid.x) * 17.0f + float(gid.y) * 3.0f + float(s) * 11.0f);
        float jy = (P.spp <= 1 || apertureSamples > 0) ? 0.5f : hash11(float(gid.x) * 5.0f + float(gid.y) * 19.0f + float(s) * 7.0f);
        float px = ((float(gid.x) + jx) / float(P.width) * 2.0f - 1.0f) * aspect * scale;
        float py = (1.0f - (float(gid.y) + jy) / float(P.height) * 2.0f) * scale;
        float3 rd0 = safe_norm(forward + px * right + py * up);
        float3 ro = cam;
        float3 rd = rd0;
        if (apertureSamples > 0) {
            float tFocus = P.focusDepth / max(dot(rd0, forward), 1.0e-4f);
            float3 fp = cam + rd0 * tFocus;
            float apertureRadius = 0.09f * max(P.dofStrength, 0.0f) / max(P.fNumber, 0.7f);
            float2 ap = aperture_sample(s, samples, P.apertureBlades);
            ro = cam + apertureRadius * (ap.x * right + ap.y * up);
            rd = safe_norm(fp - ro);
        }
        col += trace_room(ro, rd, P);
        float d = primary_depth(cam, rd0, P.focusDepth, P);
        depthMin = (s == 0) ? d : min(depthMin, d);
    }
    col /= float(samples);
    uint outY = P.height - 1u - gid.y;
    uint idx = outY * P.width + gid.x;
    float depthOut = (apertureSamples > 0) ? P.focusDepth : depthMin;
    outLinear[idx] = float4(max(col, 0.0f), 2.0f + max(depthOut, 0.0f));
}
"""#

guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue() else {
    fatalError("Metal device unavailable")
}

let library = try device.makeLibrary(source: shader, options: nil)
let function = library.makeFunction(name: "room_rt_kernel")!
let pipeline = try device.makeComputePipelineState(function: function)

var params = RoomRTParams(
    width: width,
    height: height,
    spp: spp,
    apertureSpp: apertureSpp,
    focusDepth: focusDepth,
    fNumber: fNumber,
    dofStrength: dofStrength,
    apertureBlades: apertureBlades,
    bokehTargets: flag("--bokeh-targets") ? 1 : 0,
    colorChart: flag("--color-chart") ? 1 : 0
)
let count = Int(width * height)
let outBuffer = device.makeBuffer(length: count * MemoryLayout<SIMD4<Float>>.stride, options: [.storageModeShared])!
let paramsBuffer = device.makeBuffer(bytes: &params, length: MemoryLayout<RoomRTParams>.stride, options: [.storageModeShared])!

let commandBuffer = queue.makeCommandBuffer()!
let encoder = commandBuffer.makeComputeCommandEncoder()!
encoder.setComputePipelineState(pipeline)
encoder.setBuffer(outBuffer, offset: 0, index: 0)
encoder.setBuffer(paramsBuffer, offset: 0, index: 1)
let tg = MTLSize(width: 16, height: 16, depth: 1)
let grid = MTLSize(width: Int(width), height: Int(height), depth: 1)
encoder.dispatchThreads(grid, threadsPerThreadgroup: tg)
encoder.endEncoding()
commandBuffer.commit()
commandBuffer.waitUntilCompleted()
if let error = commandBuffer.error {
    fatalError("Metal command failed: \(error)")
}

let data = Data(bytes: outBuffer.contents(), count: count * MemoryLayout<SIMD4<Float>>.stride)
try data.write(to: URL(fileURLWithPath: outPath), options: [.atomic])
print("wrote \(outPath) \(width)x\(height) spp=\(spp) apertureSpp=\(apertureSpp)")
