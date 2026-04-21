import Foundation
import Metal

struct RenderComposeLegacyPhaseResult {
    let composeExposure: Float
    let nextProgressMark: Int
    let lastProgressPrint: TimeInterval
}

enum RenderComposeLegacyPhase {
    static func execute(
        _ input: RenderComposePhaseInput,
        composeExposure initialComposeExposure: Float,
        nextProgressMark initialNextProgressMark: Int,
        lastProgressPrint initialLastProgressPrint: TimeInterval
    ) throws -> RenderComposeLegacyPhaseResult {
        let config = input.config
        let params = input.params
        let runtime = input.runtime
        let policy = input.policy
        let frameResources = input.frameResources
        let device = runtime.device
        let queue = runtime.queue

        let width = config.width
        let height = config.height
        let downsampleArg = config.downsampleArg
        let composeGPU = config.composeGPU
        let composeChunkArg = config.composeChunkArg
        let autoExposureEnabled = config.autoExposureEnabled
        let composeLookID = config.composeLookID
        let composeDitherArg = config.composeDitherArg
        let composeInnerEdgeArg = config.composeInnerEdgeArg
        let composeSpectralStepArg = config.composeSpectralStepArg
        let spectralEncodingID = config.spectralEncodingID
        let composePrecisionID = config.composePrecisionID
        let composeAnalysisMode = config.composeAnalysisMode
        let composeCameraModelID = config.composeCameraModelID
        let composeCameraPsfSigmaArg = config.composeCameraPsfSigmaArg
        let composeCameraReadNoiseArg = config.composeCameraReadNoiseArg
        let composeCameraShotNoiseArg = config.composeCameraShotNoiseArg
        let composeCameraFlareStrengthArg = config.composeCameraFlareStrengthArg
        let backgroundModeID = config.backgroundModeID
        let backgroundStarDensityArg = config.backgroundStarDensityArg
        let backgroundStarStrengthArg = config.backgroundStarStrengthArg
        let backgroundNebulaStrengthArg = config.backgroundNebulaStrengthArg
        let preserveHighlightColor = config.preserveHighlightColor
        let diskVolumeEnabled = config.diskVolumeEnabled
        let diskPhysicsModeID = config.diskPhysicsModeID
        let visibleModeEnabled = config.visibleModeEnabled
        let visibleSamplesArg = config.visibleSamplesArg
        let visibleTeffModelID = config.visibleTeffModelID
        let diskColorFactorArg = config.diskColorFactorArg
        let photosphereRhoThresholdResolved = config.photosphereRhoThresholdResolved
        let visibleEmissionModelID = config.visibleEmissionModelID
        let visibleSynchAlphaArg = config.visibleSynchAlphaArg
        let diskNuObsHzArg = config.diskNuObsHzArg
        let diskPlungeFloorArg = config.diskPlungeFloorArg
        let diskInnerRadiusCompose = config.diskInnerRadiusCompose
        let diskHorizonRadiusCompose = config.diskHorizonRadiusCompose
        let composeLumLogMin: Float = (diskPhysicsModeID == 3) ? -36.0 : 8.0
        let composeLumLogMax: Float = (diskPhysicsModeID == 3) ? 4.0 : 20.0
        let outWidth = policy.outWidth
        let outHeight = policy.outHeight
        let count = policy.count
        let stride = policy.stride
        let composePipeline = runtime.composePipeline
        let activeCloudHistPipeline = input.collisionLite32Enabled ? runtime.cloudHistLitePipeline : runtime.cloudHistPipeline
        let tg = RenderThreadgroups.twoDimensional(runtime.composePipeline)
        let composeOps = composeGPU ? (outWidth * outHeight) : 0

        let hitOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.hit) ?? 0
        let tOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.T) ?? 8
        let vDiskOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.v_disk) ?? 16
        let directOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.direct_world) ?? 32
        let noiseOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.noise) ?? 48
        let emitROffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.emit_r_norm) ?? 52
        let emitPhiOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.emit_phi) ?? 56
        let emitZOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.emit_z_norm) ?? 60

        var composeExposure = initialComposeExposure
        var nextProgressMark = initialNextProgressMark
        var lastProgressPrint = initialLastProgressPrint
        var cloudQ10: Float = 0.0
        var cloudQ90: Float = 1.0
        var cloudInvSpan: Float = 1.0 / max(cloudQ90 - cloudQ10, 1e-6)
        var sampledHits = 0

        let url = frameResources.outputURL
        if autoExposureEnabled && !composeGPU {
            var lumSamples: [Float] = []
            let sampleStride = (config.exposureSamplesArg > 0) ? max(1, count / max(config.exposureSamplesArg, 1)) : 1
            let stepNm = Double(max(composeSpectralStepArg, 0.25))
            let luma = SIMD3<Double>(0.2126, 0.7152, 0.0722)
            let rs = Double(params.rs)
            let ghM = 1.0e35
            let gg = 6.67430e-11
            let cc = 299_792_458.0
            let xyzRow0 = SIMD3<Double>(3.2406, -1.5372, -0.4986)
            let xyzRow1 = SIMD3<Double>(-0.9689, 1.8758, 0.0415)
            let xyzRow2 = SIMD3<Double>(0.0557, -0.2040, 1.0570)
            let camX = Double(params.camPos.x)
            let camY = Double(params.camPos.y)
            let camZ = Double(params.camPos.z)
            let rObs = max(sqrt(camX * camX + camY * camY + camZ * camZ), rs * 1.0001)
            let sampleHandle = try FileHandle(forReadingFrom: url)
            defer { try? sampleHandle.close() }
            let scanRecords = max(1, composeChunkArg)
            let scanBytes = scanRecords * stride
            var globalStart = 0
            while true {
                let data = try sampleHandle.read(upToCount: scanBytes) ?? Data()
                if data.isEmpty { break }
                let recCount = data.count / stride
                var chunkT: [Double] = []
                var chunkV: [SIMD3<Double>] = []
                var chunkD: [SIMD3<Double>] = []
                var chunkN: [Double] = []
                var chunkI: [Double] = []
                var chunkEmitR: [Double] = []
                var chunkEmitPhi: [Double] = []
                var chunkEmitZ: [Double] = []
                data.withUnsafeBytes { raw in
                    guard let basePtr = raw.baseAddress else { return }
                    for i in 0..<recCount {
                        let absIdx = globalStart + i
                        if config.exposureSamplesArg > 0 && ((absIdx % sampleStride) != 0) { continue }
                        let base = i * stride
                        var hit: UInt32 = 0
                        withUnsafeMutableBytes(of: &hit) { dst in dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + hitOffset), count: MemoryLayout<UInt32>.size)) }
                        if hit == 0 { continue }
                        var t: Float = 0
                        withUnsafeMutableBytes(of: &t) { dst in dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + tOffset), count: MemoryLayout<Float>.size)) }
                        var v4 = SIMD4<Float>(repeating: 0)
                        withUnsafeMutableBytes(of: &v4) { dst in dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + vDiskOffset), count: MemoryLayout<SIMD4<Float>>.size)) }
                        var d4 = SIMD4<Float>(repeating: 0)
                        withUnsafeMutableBytes(of: &d4) { dst in dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + directOffset), count: MemoryLayout<SIMD4<Float>>.size)) }
                        var n: Float = 0
                        withUnsafeMutableBytes(of: &n) { dst in dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + noiseOffset), count: MemoryLayout<Float>.size)) }
                        var emitR: Float = 0
                        withUnsafeMutableBytes(of: &emitR) { dst in dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + emitROffset), count: MemoryLayout<Float>.size)) }
                        var emitPhi: Float = 0
                        withUnsafeMutableBytes(of: &emitPhi) { dst in dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + emitPhiOffset), count: MemoryLayout<Float>.size)) }
                        var emitZ: Float = 0
                        withUnsafeMutableBytes(of: &emitZ) { dst in dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + emitZOffset), count: MemoryLayout<Float>.size)) }
                        chunkT.append(max(Double(t), 1.0))
                        chunkV.append(SIMD3<Double>(Double(v4.x), Double(v4.y), Double(v4.z)))
                        chunkD.append(SIMD3<Double>(Double(d4.x), Double(d4.y), Double(d4.z)))
                        chunkN.append(Double(n))
                        chunkI.append(max(Double(v4.w), 0.0))
                        chunkEmitR.append(Double(emitR))
                        chunkEmitPhi.append(Double(emitPhi))
                        chunkEmitZ.append(Double(emitZ))
                    }
                }
                if !chunkT.isEmpty {
                    var procNoise = chunkN
                    if composeAnalysisMode == 0 && spectralEncodingID == 0 {
                        var maxAbsN = 0.0
                        for n in procNoise { maxAbsN = max(maxAbsN, abs(n)) }
                        if maxAbsN < 1e-6 {
                            let re = max(config.rcp, 1.2) * rs
                            for i in 0..<procNoise.count {
                                let vx = chunkV[i].x
                                let vy = chunkV[i].y
                                let speed = max(hypot(vx, vy), 1e-30)
                                let r = gg * ghM / max(speed * speed, 1e-30)
                                let u = min(max((r - rs) / max(re - rs, 1e-12), 0.0), 1.0)
                                let phi = atan2(-vx, vy)
                                let theta = phi + 1.9 * log(max(r / rs, 1.0))
                                procNoise[i] = min(max(0.65 * sin(18.0 * u + 3.0 * cos(theta)) + 0.35 * cos(11.0 * theta), -1.0), 1.0)
                            }
                        }
                    }
                    var cloudVals = [Float](repeating: 0, count: procNoise.count)
                    if composeAnalysisMode == 0 {
                        for i in 0..<procNoise.count {
                            let n = min(max(procNoise[i], -1.0), 1.0)
                            let c = (n < -1e-6) ? min(max(0.5 + 0.5 * n, 0.0), 1.0) : min(max(n, 0.0), 1.0)
                            cloudVals[i] = Float(c)
                        }
                    } else {
                        for i in 0..<cloudVals.count { cloudVals[i] = 0.5 }
                    }
                    var sortedCloud = cloudVals
                    sortedCloud.sort()
                    cloudQ10 = percentileSorted(sortedCloud, 0.08)
                    cloudQ90 = percentileSorted(sortedCloud, 0.92)
                    cloudInvSpan = 1.0 / max(cloudQ90 - cloudQ10, 1e-6)
                    var chunkLum: [Float] = []
                    chunkLum.reserveCapacity(chunkT.count)
                    for i in 0..<chunkT.count {
                        if diskPhysicsModeID == 3 {
                            let rgb: SIMD3<Double>
                            if composeAnalysisMode >= 11 && composeAnalysisMode <= 14 {
                                var raw = 0.0
                                var lo = -30.0
                                var hi = 2.0
                                if composeAnalysisMode == 11 { raw = max(chunkEmitR[i], 0.0); lo = -16.0 }
                                else if composeAnalysisMode == 12 { raw = max(chunkEmitPhi[i], 0.0); lo = -20.0; hi = 4.0 }
                                else if composeAnalysisMode == 13 { raw = max(chunkEmitZ[i], 0.0); lo = -40.0; hi = -20.0 }
                                else { raw = max(chunkN[i], 0.0); lo = -40.0; hi = -20.0 }
                                let lv = log10(max(raw, 1e-38))
                                let t = min(max((lv - lo) / max(hi - lo, 1e-9), 0.0), 1.0)
                                rgb = SIMD3<Double>(repeating: t)
                            } else if composeAnalysisMode == 15 {
                                let teff = max(chunkT[i], 1.0)
                                let lv = log10(teff)
                                let t = min(max((lv - 2.0) / max(7.0 - 2.0, 1e-9), 0.0), 1.0)
                                rgb = SIMD3<Double>(repeating: t)
                            } else if composeAnalysisMode == 16 {
                                let g = min(max(chunkV[i].x, 1e-6), 1e6)
                                let lv = log10(g)
                                let t = min(max((lv - (-2.0)) / max(2.0 - (-2.0), 1e-9), 0.0), 1.0)
                                rgb = SIMD3<Double>(repeating: t)
                            } else if visibleModeEnabled {
                                let g = min(max(chunkV[i].x, 1e-4), 1e4)
                                let tEmit = max(chunkT[i], 1.0)
                                let scalarI = max(chunkI[i], 0.0)
                                let fCol = (visibleTeffModelID == 2) ? max(diskColorFactorArg, 1.0) : 1.0
                                let tSpec = tEmit * fCol
                                let colorDilution = 1.0 / pow(fCol, 4.0)
                                let usePackedVisibleAnchors = (diskPhysicsModeID == 3 && photosphereRhoThresholdResolved <= 0.0 && chunkEmitR[i] > 0.0 && chunkEmitPhi[i] > 0.0 && chunkEmitZ[i] > 0.0)
                                let nLam = max(8, visibleSamplesArg)
                                let lamMin = 380.0
                                let lamMax = 780.0
                                let dLamNm = (lamMax - lamMin) / Double(max(nLam - 1, 1))
                                let dLamM = dLamNm * 1e-9
                                let g3 = g * g * g
                                var X = 0.0, Y = 0.0, Z = 0.0, peakLamNm = lamMin, peakIlam = 0.0
                                if usePackedVisibleAnchors {
                                    let lamRnm = 650.0, lamGnm = 550.0, lamBnm = 450.0
                                    let lamRm = lamRnm * 1e-9, lamGm = lamGnm * 1e-9, lamBm = lamBnm * 1e-9
                                    let iNuR = max(chunkEmitR[i], 1e-38), iNuG = max(chunkEmitPhi[i], 1e-38), iNuB = max(chunkEmitZ[i], 1e-38)
                                    let iLamR = iNuR * cc / max(lamRm * lamRm, 1e-30)
                                    let iLamG = iNuG * cc / max(lamGm * lamGm, 1e-30)
                                    let iLamB = iNuB * cc / max(lamBm * lamBm, 1e-30)
                                    let xR = log(lamRnm), xG = log(lamGnm), xB = log(lamBnm)
                                    let yR = log(max(iLamR, 1e-38)), yG = log(max(iLamG, 1e-38)), yB = log(max(iLamB, 1e-38))
                                    let slopeBG = (yG - yB) / max(xG - xB, 1e-12)
                                    let slopeGR = (yR - yG) / max(xR - xG, 1e-12)
                                    for j in 0..<nLam {
                                        let lamNm = lamMin + dLamNm * Double(j)
                                        let xLam = log(max(lamNm, 1e-9))
                                        let logILam = (lamNm <= lamGnm) ? (yB + slopeBG * (xLam - xB)) : (yG + slopeGR * (xLam - xG))
                                        let iLamObs = exp(min(max(logILam, -90.0), 90.0))
                                        let (xb, yb, zb) = cieXYZBar(lamNm)
                                        X += iLamObs * xb * dLamM; Y += iLamObs * yb * dLamM; Z += iLamObs * zb * dLamM
                                        if iLamObs > peakIlam { peakIlam = iLamObs; peakLamNm = lamNm }
                                    }
                                } else {
                                    for j in 0..<nLam {
                                        let lamNm = lamMin + dLamNm * Double(j)
                                        let lamM = lamNm * 1e-9
                                        let nuObs = cc / max(lamM, 1e-30)
                                        let nuEm = nuObs / max(g, 1e-8)
                                        let iNuEm = visibleINuEmit(nuEm, tSpec, visibleEmissionModelID, visibleSynchAlphaArg)
                                        let iNuObs = g3 * iNuEm
                                        let iLamObs = iNuObs * cc / max(lamM * lamM, 1e-30) * colorDilution
                                        let (xb, yb, zb) = cieXYZBar(lamNm)
                                        X += iLamObs * xb * dLamM; Y += iLamObs * yb * dLamM; Z += iLamObs * zb * dLamM
                                        if iLamObs > peakIlam { peakIlam = iLamObs; peakLamNm = lamNm }
                                    }
                                    if scalarI > 1e-18 {
                                        let nuObsRef = max(diskNuObsHzArg, 1e6)
                                        let nuEmRef = nuObsRef / max(g, 1e-8)
                                        let iNuPred = g3 * visibleINuEmit(nuEmRef, tSpec, visibleEmissionModelID, visibleSynchAlphaArg) * colorDilution
                                        let amp = min(max(scalarI / max(iNuPred, 1e-38), 0.0), 1e12)
                                        X *= amp; Y *= amp; Z *= amp
                                    }
                                }
                                if composeAnalysisMode == 17 {
                                    let lv = log10(max(Y, 1e-38)); let t = min(max((lv - (-30.0)) / max(4.0 - (-30.0), 1e-9), 0.0), 1.0); rgb = SIMD3<Double>(repeating: t)
                                } else if composeAnalysisMode == 18 {
                                    let w = min(max((peakLamNm - 380.0) / (780.0 - 380.0), 0.0), 1.0)
                                    let r = min(max(1.5 - abs(4.0 * w - 3.0), 0.0), 1.0)
                                    let gch = min(max(1.5 - abs(4.0 * w - 2.0), 0.0), 1.0)
                                    let b = min(max(1.5 - abs(4.0 * w - 1.0), 0.0), 1.0)
                                    rgb = SIMD3<Double>(r, gch, b)
                                } else {
                                    var rgbLin = SIMD3<Double>(xyzRow0.x * X + xyzRow0.y * Y + xyzRow0.z * Z, xyzRow1.x * X + xyzRow1.y * Y + xyzRow1.z * Z, xyzRow2.x * X + xyzRow2.y * Y + xyzRow2.z * Z)
                                    rgbLin.x = max(rgbLin.x, 0.0); rgbLin.y = max(rgbLin.y, 0.0); rgbLin.z = max(rgbLin.z, 0.0)
                                    let d = chunkD[i]
                                    let mu = abs(d.z) / max(sqrt(d.x * d.x + d.y * d.y + d.z * d.z), 1e-30)
                                    let limb = 0.4 + 0.6 * min(max(mu, 0.0), 1.0)
                                    rgb = rgbLin * limb
                                }
                            } else {
                                let iNu = max(chunkI[i], 0.0); rgb = SIMD3<Double>(repeating: iNu)
                            }
                            chunkLum.append(Float(rgb.x * luma.x + rgb.y * luma.y + rgb.z * luma.z)); continue
                        }
                        let v = chunkV[i], d = chunkD[i]
                        let colorDilution: Double = (diskPhysicsModeID == 2) ? (1.0 / pow(max(diskColorFactorArg, 1.0), 4.0)) : 1.0
                        let gTotal: Double
                        if spectralEncodingID == 1 {
                            gTotal = min(max(v.x, 1e-4), 1e4)
                        } else {
                            let vNorm = max(sqrt(v.x * v.x + v.y * v.y + v.z * v.z), 1e-30)
                            let dNorm = max(sqrt(d.x * d.x + d.y * d.y + d.z * d.z), 1e-30)
                            let beta = min(max(vNorm / cc, 0.0), 0.999999)
                            let gamma = 1.0 / sqrt(max(1.0 - beta * beta, 1e-18))
                            let vd = v.x * d.x + v.y * d.y + v.z * d.z
                            let cosTheta = min(max(vd / (vNorm * dNorm), -1.0), 1.0)
                            let delta = 1.0 / max(gamma * (1.0 - beta * cosTheta), 1e-9)
                            let rEmitLegacy = max(gg * ghM / max(vNorm * vNorm, 1e-30), rs * 1.0001)
                            let gravNum = min(max(1.0 - rs / rEmitLegacy, 1e-8), 1.0)
                            let gravDen = min(max(1.0 - rs / rObs, 1e-8), 1.0)
                            let gGr = sqrt(min(max(gravNum / gravDen, 1e-8), 4.0))
                            gTotal = min(max(delta * gGr, 1e-4), 1e4)
                        }
                        let tObs = max(chunkT[i] * gTotal, 1.0)
                        var X = 0.0, Y = 0.0, Z = 0.0
                        if visibleModeEnabled {
                            let nLam = max(8, visibleSamplesArg)
                            let lamMin = 380.0
                            let lamMax = 780.0
                            let dLamNm = (lamMax - lamMin) / Double(max(nLam - 1, 1))
                            let dLamM = dLamNm * 1e-9
                            for j in 0..<nLam {
                                let lam = lamMin + dLamNm * Double(j)
                                let (xb, yb, zb) = cieXYZBar(lam)
                                let lamM = lam * 1e-9
                                let b = planckLambda(lamM, tObs) * colorDilution
                                X += b * xb * dLamM
                                Y += b * yb * dLamM
                                Z += b * zb * dLamM
                            }
                        } else {
                            var lam = 380.0
                            while lam <= 750.001 {
                                let (xb, yb, zb) = cieXYZBar(lam)
                                let lamM = lam * 1e-9
                                let b = planckLambda(lamM, tObs) * colorDilution
                                X += b * xb; Y += b * yb; Z += b * zb
                                lam += stepNm
                            }
                        }
                        var rgb = SIMD3<Double>(xyzRow0.x * X + xyzRow0.y * Y + xyzRow0.z * Z, xyzRow1.x * X + xyzRow1.y * Y + xyzRow1.z * Z, xyzRow2.x * X + xyzRow2.y * Y + xyzRow2.z * Z)
                        rgb.x = max(rgb.x, 0.0); rgb.y = max(rgb.y, 0.0); rgb.z = max(rgb.z, 0.0)
                        let mu = abs(d.z) / max(sqrt(d.x * d.x + d.y * d.y + d.z * d.z), 1e-30)
                        let limb: Double = (diskPhysicsModeID == 2) ? ((3.0 / 7.0) * (1.0 + 2.0 * min(max(mu, 0.0), 1.0))) : (0.4 + 0.6 * min(max(mu, 0.0), 1.0))
                        rgb *= limb
                        if spectralEncodingID == 1 && diskPhysicsModeID == 1 {
                            let rEmit = max(v.y, rs * 1.0001)
                            let xDen = max(diskInnerRadiusCompose - diskHorizonRadiusCompose, 1e-9)
                            let x = min(max((rEmit - diskHorizonRadiusCompose) / xDen, 0.0), 1.0)
                            let xSoft = x * x * (3.0 - 2.0 * x)
                            let floor = 0.35 * min(max(diskPlungeFloorArg, 0.0), 1.0)
                            let gate = floor + (1.0 - floor) * pow(max(xSoft, 1e-4), 2.2)
                            rgb *= gate
                        }
                        if composeAnalysisMode == 0 {
                            var cloud = min(max((Double(cloudVals[i]) - Double(cloudQ10)) * Double(1.0 / max(cloudQ90 - cloudQ10, 1e-6)), 0.0), 1.0)
                            cloud = 0.18 + 0.82 * cloud
                            let core = pow(cloud, 1.15)
                            let clump = pow(core, 2.2)
                            let vvoid = pow(1.0 - cloud, 1.8)
                            let density = 0.62 + 1.28 * core
                            rgb *= density
                            rgb *= (1.0 + 0.34 * clump)
                            rgb *= (1.0 - 0.14 * vvoid)
                            rgb.x *= (1.0 + 0.12 * clump)
                            rgb.z *= (1.0 - 0.08 * clump)
                        }
                        chunkLum.append(Float(rgb.x * luma.x + rgb.y * luma.y + rgb.z * luma.z))
                    }
                    if !chunkLum.isEmpty {
                        let lumStride = max(1, chunkLum.count / 8192)
                        var j = 0
                        while j < chunkLum.count { lumSamples.append(chunkLum[j]); sampledHits += 1; j += lumStride }
                    }
                }
                globalStart += recCount
            }
            if lumSamples.isEmpty {
                composeExposure = 1.0
            } else {
                lumSamples.sort()
                let p50 = percentileSorted(lumSamples, 0.50)
                let p995 = percentileSorted(lumSamples, 0.995)
                var targetWhite: Float = composeTargetWhite(composeLookID)
                if diskVolumeEnabled && diskPhysicsModeID != 3 { targetWhite *= 2.2 }
                let pFloor: Float = (diskPhysicsModeID == 3) ? 1e-30 : 1e-12
                composeExposure = targetWhite / max(p995, pFloor)
                print("lum p50=\(p50), p99.5=\(p995), exposureSamples=\(sampledHits)")
            }
        }
        print("compose cloud normalization q10=\(cloudQ10) q90=\(cloudQ90)")
        let composeModeLabel = composeGPU ? "gpu-tiled-compose" : "cpu-compose"
        let exposureModeLabel = composeGPU ? "gpu-tiled" : "cpu"
        print("compose path=\(composeModeLabel)")
        print("exposure=\(composeExposure) (auto=\(autoExposureEnabled), mode=\(exposureModeLabel))")

        var composeParamsBase = params
        var composeParamsTemplate = ComposeParams(
            tileWidth: 0, tileHeight: 0, downsample: UInt32(downsampleArg), outTileWidth: 0, outTileHeight: 0,
            srcOffsetX: 0, srcOffsetY: 0, outOffsetX: 0, outOffsetY: 0,
            fullInputWidth: UInt32(width), fullInputHeight: UInt32(height), exposure: composeExposure,
            dither: composeDitherArg, innerEdgeMult: composeInnerEdgeArg, spectralStep: composeSpectralStepArg,
            cloudQ10: cloudQ10, cloudInvSpan: cloudInvSpan, look: composeLookID, spectralEncoding: spectralEncodingID,
            precisionMode: composePrecisionID, analysisMode: composeAnalysisMode, cloudBins: 2048, lumBins: 4096,
            lumLogMin: composeLumLogMin, lumLogMax: composeLumLogMax, cameraModel: composeCameraModelID,
            cameraPsfSigmaPx: composeCameraPsfSigmaArg, cameraReadNoise: composeCameraReadNoiseArg,
            cameraShotNoise: composeCameraShotNoiseArg, cameraFlareStrength: composeCameraFlareStrengthArg,
            backgroundMode: backgroundModeID, backgroundStarDensity: backgroundStarDensityArg,
            backgroundStarStrength: backgroundStarStrengthArg, backgroundNebulaStrength: backgroundNebulaStrengthArg,
            preserveHighlightColor: preserveHighlightColor, diskNoiseModel: params.diskNoiseModel,
            _pad0: 0, _pad1: 0, _pad2: 0
        )
        let composeBaseBuf = device.makeBuffer(bytes: &composeParamsBase, length: MemoryLayout<PackedParams>.stride, options: [])!
        let rawComposeRows = max(1, composeChunkArg / max(width, 1))
        var composeRows = max(downsampleArg, (rawComposeRows / downsampleArg) * downsampleArg)
        if composeRows <= 0 { composeRows = downsampleArg }
        if composeRows > height { composeRows = height }
        let composeTileTotal = max(1, (height + composeRows - 1) / composeRows)
        if composeGPU && autoExposureEnabled && diskPhysicsModeID != 3 {
            let cloudBins = 2048
            let lumBins = 4096
            var cloudHistGlobal = [UInt32](repeating: 0, count: cloudBins)
            var lumHistGlobal = [UInt32](repeating: 0, count: lumBins)
            let histTg = RenderThreadgroups.oneDimensional(activeCloudHistPipeline)
            let lumTg = RenderThreadgroups.oneDimensional(runtime.lumHistPipeline)
            let tileInBuf = device.makeBuffer(length: width * composeRows * stride, options: .storageModeShared)!
            let cloudHistBuf = device.makeBuffer(length: cloudBins * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
            let lumHistBuf = device.makeBuffer(length: lumBins * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
            let histParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: [])!
            let corrHandle = try FileHandle(forReadingFrom: url)
            defer { try? corrHandle.close() }

            var pty = 0
            while pty < height {
                let tileH = min(composeRows, height - pty)
                let tileW = width
                let tileCount = tileW * tileH
                let rowBytes = tileW * stride
                for row in 0..<tileH {
                    let offset = ((pty + row) * width) * stride
                    try corrHandle.seek(toOffset: UInt64(offset))
                    let rowData = try corrHandle.read(upToCount: rowBytes) ?? Data()
                    if rowData.count != rowBytes { throw NSError(domain: "Blackhole", code: 2, userInfo: [NSLocalizedDescriptionKey: "short read while compose cloud histogram"]) }
                    _ = rowData.withUnsafeBytes { raw in memcpy(tileInBuf.contents().advanced(by: row * rowBytes), raw.baseAddress!, rowBytes) }
                }
                var histParams = composeParamsTemplate
                histParams.tileWidth = UInt32(tileW)
                histParams.tileHeight = UInt32(tileH)
                histParams.srcOffsetX = 0
                histParams.srcOffsetY = UInt32(pty)
                updateBuffer(histParamBuf, with: &histParams)
                memset(cloudHistBuf.contents(), 0, cloudBins * MemoryLayout<UInt32>.stride)
                let cloudCmd = queue.makeCommandBuffer()!
                let cloudEnc = cloudCmd.makeComputeCommandEncoder()!
                cloudEnc.setComputePipelineState(activeCloudHistPipeline)
                cloudEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                cloudEnc.setBuffer(histParamBuf, offset: 0, index: 1)
                cloudEnc.setBuffer(tileInBuf, offset: 0, index: 2)
                cloudEnc.setBuffer(cloudHistBuf, offset: 0, index: 3)
                cloudEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: histTg)
                cloudEnc.endEncoding()
                cloudCmd.commit()
                cloudCmd.waitUntilCompleted()
                let cp = cloudHistBuf.contents().bindMemory(to: UInt32.self, capacity: cloudBins)
                for i in 0..<cloudBins { cloudHistGlobal[i] = cloudHistGlobal[i] &+ cp[i] }
                pty += tileH
            }

            cloudQ10 = cloudHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.08, 0.0, 1.0) }
            cloudQ90 = cloudHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.92, 0.0, 1.0) }
            cloudInvSpan = 1.0 / max(cloudQ90 - cloudQ10, 1e-6)

            try corrHandle.seek(toOffset: 0)
            pty = 0
            while pty < height {
                let tileH = min(composeRows, height - pty)
                let tileW = width
                let tileCount = tileW * tileH
                let rowBytes = tileW * stride
                for row in 0..<tileH {
                    let offset = ((pty + row) * width) * stride
                    try corrHandle.seek(toOffset: UInt64(offset))
                    let rowData = try corrHandle.read(upToCount: rowBytes) ?? Data()
                    if rowData.count != rowBytes { throw NSError(domain: "Blackhole", code: 2, userInfo: [NSLocalizedDescriptionKey: "short read while compose luminance histogram"]) }
                    _ = rowData.withUnsafeBytes { raw in memcpy(tileInBuf.contents().advanced(by: row * rowBytes), raw.baseAddress!, rowBytes) }
                }
                var lumParams = composeParamsTemplate
                lumParams.tileWidth = UInt32(tileW)
                lumParams.tileHeight = UInt32(tileH)
                lumParams.srcOffsetX = 0
                lumParams.srcOffsetY = UInt32(pty)
                lumParams.cloudQ10 = cloudQ10
                lumParams.cloudInvSpan = cloudInvSpan
                updateBuffer(histParamBuf, with: &lumParams)
                memset(lumHistBuf.contents(), 0, lumBins * MemoryLayout<UInt32>.stride)
                let lumCmd = queue.makeCommandBuffer()!
                let lumEnc = lumCmd.makeComputeCommandEncoder()!
                lumEnc.setComputePipelineState(runtime.lumHistPipeline)
                lumEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                lumEnc.setBuffer(histParamBuf, offset: 0, index: 1)
                lumEnc.setBuffer(tileInBuf, offset: 0, index: 2)
                lumEnc.setBuffer(lumHistBuf, offset: 0, index: 3)
                lumEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: lumTg)
                lumEnc.endEncoding()
                lumCmd.commit()
                lumCmd.waitUntilCompleted()
                let lp = lumHistBuf.contents().bindMemory(to: UInt32.self, capacity: lumBins)
                for i in 0..<lumBins { lumHistGlobal[i] = lumHistGlobal[i] &+ lp[i] }
                pty += tileH
            }

            let p50Log = lumHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.50, composeLumLogMin, composeLumLogMax) }
            let p995Log = lumHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.995, composeLumLogMin, composeLumLogMax) }
            let p50 = Float(pow(10.0, Double(p50Log)))
            let gpuP995 = Float(pow(10.0, Double(p995Log)))
            var targetWhite: Float = composeTargetWhite(composeLookID)
            if diskVolumeEnabled && diskPhysicsModeID != 3 { targetWhite *= 2.2 }
            let pFloor: Float = (diskPhysicsModeID == 3) ? 1e-30 : 1e-12
            composeExposure = targetWhite / max(gpuP995, pFloor)
            print("lum(hist) p50=\(p50), p99.5=\(gpuP995), mode=gpu-tiled")
        }

        composeParamsTemplate.exposure = composeExposure
        var rgb = [UInt8](repeating: 0, count: outWidth * outHeight * 3)
        let readHandle = try FileHandle(forReadingFrom: url)
        defer { try? readHandle.close() }
        var composed = 0
        var cty = 0
        var composeTileIndex = 0
        while cty < height {
            let tileH = min(composeRows, height - cty)
            let tileW = width
            let tileCount = tileW * tileH
            let rowBytes = tileW * stride
            let tileInBuf = device.makeBuffer(length: tileCount * stride, options: .storageModeShared)!
            for row in 0..<tileH {
                let offset = ((cty + row) * width) * stride
                try readHandle.seek(toOffset: UInt64(offset))
                let rowData = try readHandle.read(upToCount: rowBytes) ?? Data()
                if rowData.count != rowBytes { throw NSError(domain: "Blackhole", code: 2, userInfo: [NSLocalizedDescriptionKey: "short read while composing"]) }
                _ = rowData.withUnsafeBytes { raw in memcpy(tileInBuf.contents().advanced(by: row * rowBytes), raw.baseAddress!, rowBytes) }
            }
            let outTileW = tileW / downsampleArg
            let outTileH = tileH / downsampleArg
            let outTileCount = outTileW * outTileH
            let outOffsetY = (height - cty - tileH) / downsampleArg
            composeParamsTemplate.tileWidth = UInt32(tileW)
            composeParamsTemplate.tileHeight = UInt32(tileH)
            composeParamsTemplate.outTileWidth = UInt32(outTileW)
            composeParamsTemplate.outTileHeight = UInt32(outTileH)
            composeParamsTemplate.srcOffsetX = 0
            composeParamsTemplate.srcOffsetY = UInt32(cty)
            composeParamsTemplate.outOffsetX = 0
            composeParamsTemplate.outOffsetY = UInt32(outOffsetY)
            composeParamsTemplate.cloudQ10 = cloudQ10
            composeParamsTemplate.cloudInvSpan = cloudInvSpan
            let composeParamBuf = device.makeBuffer(bytes: &composeParamsTemplate, length: MemoryLayout<ComposeParams>.stride, options: [])!
            let outBuf = device.makeBuffer(length: outTileCount * 4, options: .storageModeShared)!
            let cmd = queue.makeCommandBuffer()!
            let enc = cmd.makeComputeCommandEncoder()!
            enc.setComputePipelineState(composePipeline)
            enc.setBuffer(composeBaseBuf, offset: 0, index: 0)
            enc.setBuffer(composeParamBuf, offset: 0, index: 1)
            enc.setBuffer(tileInBuf, offset: 0, index: 2)
            enc.setBuffer(outBuf, offset: 0, index: 3)
            enc.dispatchThreads(MTLSize(width: outTileW, height: outTileH, depth: 1), threadsPerThreadgroup: tg)
            enc.endEncoding(); cmd.commit(); cmd.waitUntilCompleted()
            let outPtr = outBuf.contents().bindMemory(to: UInt8.self, capacity: outTileCount * 4)
            for row in 0..<outTileH {
                var dst = ((outOffsetY + row) * outWidth) * 3
                let srcBase = row * outTileW * 4
                for col in 0..<outTileW {
                    let s = srcBase + col * 4
                    rgb[dst + 0] = outPtr[s + 0]
                    rgb[dst + 1] = outPtr[s + 1]
                    rgb[dst + 2] = outPtr[s + 2]
                    dst += 3
                }
            }
            composed += outTileCount
            composeTileIndex += 1
            let doneAll = input.totalPixels + composed
            let now = Date().timeIntervalSince1970
            if composed >= composeOps || doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                let composeTaskLabel = composeGPU ? "compose_gpu_tiled" : "compose_cpu"
                emitETAProgress(min(doneAll, input.totalOps), input.totalOps, "swift_compose", "task=\(composeTaskLabel) tile=\(composeTileIndex)/\(composeTileTotal)")
                lastProgressPrint = now
                while nextProgressMark <= doneAll { nextProgressMark += input.progressStep }
            }
            cty += tileH
        }

        try RenderOutputs.writeImage(path: config.imageOutPath, width: outWidth, height: outHeight, rgb: rgb)
        print("Saved image at: \(config.imageOutPath)")

        return RenderComposeLegacyPhaseResult(
            composeExposure: composeExposure,
            nextProgressMark: nextProgressMark,
            lastProgressPrint: lastProgressPrint
        )
    }
}
