//
//  main.swift
//  Blackhole
//
//  Created by 김령교 on 2/20/26.
//

import Foundation
import Metal

struct Params {
    var width: UInt32
    var height: UInt32

    var camPos: SIMD3<Float>
    var planeX: SIMD3<Float>
    var planeY: SIMD3<Float>
    var z: SIMD3<Float>
    var d: Float

    var rs: Float
    var re: Float
    var he: Float

    var M: Float
    var G: Float
    var c: Float
    var k: Float

    var h: Float
    var maxSteps: Int32

    var eps: Float
}

struct CollisionInfo {
    var hit: UInt32
    var ct: Float
    var T: Float
    var v_disk: SIMD3<Float>
    var direct_world: SIMD3<Float>
    var noise: Float
}

func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let len = sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
    return v / len
}

func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x)
}

let device = MTLCreateSystemDefaultDevice()!
let queue = device.makeCommandQueue()!

let library = device.makeDefaultLibrary()!
let fn = library.makeFunction(name: "renderBH")!
let pipeline = try device.makeComputePipelineState(function: fn)

let width = 1200
let height = 1200

// physics.py constants
let c: Double = 299_792_458
let G: Double = 6.67430e-11
let k: Double = 1.380649e-23

// Blackhole defaults: M=1e35, rcp=4, disk h=3e6
let M: Double = 1e35
let rsD = 2.0 * G * M / (c*c)
let rcp: Double = 4.0
let reD = rsD * rcp
let heD: Double = 3e6

// camera: p = rs * (5,0,0.2)
let camPos = SIMD3<Float>(Float(rsD*5.0), Float(0.0), Float(rsD*0.2))

// Eye basis (target = 0)
let target = SIMD3<Float>(0,0,0)
let z = normalize(camPos)   // Python에서 target=0이면 z = p.unit가 됨

let vup = SIMD3<Float>(0, Float(sin(Double.pi/12.0)), Float(cos(Double.pi/12.0)))
let planeX = normalize(cross(vup, z))
let planeY = normalize(cross(z, planeX))

let d = Float(Double(width) / (2.0 * tan(Double.pi/3.0)))  // 너 코드와 동일

var params = Params(
    width: UInt32(width),
    height: UInt32(height),
    camPos: camPos,
    planeX: planeX,
    planeY: planeY,
    z: z,
    d: d,
    rs: Float(rsD),
    re: Float(reD),
    he: Float(heD),
    M: Float(M),
    G: Float(G),
    c: Float(c),
    k: Float(k),
    h: 0.01,              // blackholeMain
    maxSteps: 1000,        // 요청값
    eps: 1e-5
)

let paramBuf = device.makeBuffer(bytes: &params,
                                 length: MemoryLayout<Params>.stride,
                                 options: [])!

let count = width * height
let outSize = count * MemoryLayout<CollisionInfo>.stride
let outBuf = device.makeBuffer(length: outSize, options: .storageModeShared)!

let cmd = queue.makeCommandBuffer()!
let enc = cmd.makeComputeCommandEncoder()!
enc.setComputePipelineState(pipeline)
enc.setBuffer(paramBuf, offset: 0, index: 0)
enc.setBuffer(outBuf, offset: 0, index: 1)

let tg = MTLSize(width: 16, height: 16, depth: 1)
let grid = MTLSize(width: width, height: height, depth: 1)
enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
enc.endEncoding()

cmd.commit()
cmd.waitUntilCompleted()

// Save collisions.bin
let data = Data(bytesNoCopy: outBuf.contents(), count: outSize, deallocator: .none)
//try data.write(to: URL(fileURLWithPath: "collisions.bin"))
let url = URL(fileURLWithPath: "/Users/kimryeong-gyo/Documents/개인 프로젝트/Blackhole/collisions.bin")
try data.write(to: url)
print("Saved at:", url.path)
print("Saved collisions.bin (\(outSize) bytes)")
