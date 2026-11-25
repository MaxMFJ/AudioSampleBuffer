import AppKit
import MetalKit
import simd

@MainActor
final class VectorAssaultDesktopEffectRenderer: DesktopEffectRenderer {
    let effect = DesktopBackgroundEffect.vectorAssault
    struct Vertex { var position: SIMD2<Float>; var color: SIMD4<Float> }
    private let pipeline: MTLRenderPipelineState
    private let device: MTLDevice
    private var paths = [[SIMD2<Float>]](); private var lengths = [Float](); private var speeds = [Float](); private var widths = [Float]()
    private var arrowClock: Float = 0; private var cameraClock: Float = 0; private var songIdentity: Int = 0
    private var previousSongTime: Float = -1
    private var tempoScale: Float = 1
    private var arrowMotionGate: Float = 0
    private var cameraMotionGate: Float = 0
    private var beatDrive: Float = 0
    private var lastBeatSequence: UInt64 = 0
    private var lastBeatTime: Float = -1
    private var beatOffsets = [Float](repeating: 0, count: 48)
    private var sustainedGuitar: Float = 0
    private var sustainedPiano: Float = 0
    private var bassPeak: Float = 0.03
    private var guitarPeak: Float = 0.018
    private var gridEnergyPulse: Float = 0
    private var videoPulse: Float = 0
    private var videoWasActive = false
    private var smoothedBass: Float = 0
    private var otherPeak: Float = 0
    private var vocalPeak: Float = 0

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, library: MTLLibrary) {
        let d = MTLRenderPipelineDescriptor(); d.label = "DesktopEffect.vectorAssault"
        d.vertexFunction = library.makeFunction(name: "vectorAssaultDesktopVertex")
        d.fragmentFunction = library.makeFunction(name: "vectorAssaultDesktopFragment")
        d.colorAttachments[0].pixelFormat = pixelFormat; d.colorAttachments[0].isBlendingEnabled = true
        d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha; d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        d.colorAttachments[0].sourceAlphaBlendFactor = .one; d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let p = try? device.makeRenderPipelineState(descriptor: d) else { fatalError("无法创建 Vector Assault Metal 渲染管线") }; pipeline = p; self.device = device; buildPaths()
    }
    func setArtwork(_ image: NSImage?, device: MTLDevice) {}

    func draw(encoder: MTLRenderCommandEncoder, view: MTKView, audio: VisualAudio) {
        let playing = audio.playing > 0.5
        let songTime = audio.playbackTime
        let seeked = previousSongTime >= 0 && (songTime + 0.05 < previousSongTime || songTime - previousSongTime > 0.3)
        if audio.songIdentity != songIdentity || seeked {
            songIdentity = audio.songIdentity
            arrowClock = songTime * 1.2
            cameraClock = arrowClock
            tempoScale = 1
            arrowMotionGate = 0
            cameraMotionGate = 0
            beatDrive = 0
            sustainedGuitar = 0
            sustainedPiano = 0
            beatOffsets = [Float](repeating: 0, count: 48)
            lastBeatSequence = audio.beatSequence
            lastBeatTime = -1
            gridEnergyPulse = 0
            videoPulse = 0
            videoWasActive = false
            smoothedBass = 0
            otherPeak = 0
            vocalPeak = 0
        }
        let songDelta = playing && !seeked && previousSongTime >= 0 ? min(max(songTime - previousSongTime, 0), 0.1) : 0
        previousSongTime = songTime
        let activity = Self.clamp((audio.activityEnergy - 0.025) / 0.10)
        let vocalActivity = Self.clamp((audio.vocal - 0.06) / 0.34)
        let otherActivity = Self.clamp((audio.other - 0.06) / 0.19)
        vocalPeak = max(vocalPeak, audio.vocal)
        otherPeak = max(otherPeak, audio.other)
        let cameraActivity = vocalPeak > 0.40 ? vocalActivity : (otherPeak > 0.24 ? otherActivity : activity)
        let follow = 1 - exp(-songDelta * 12)
        arrowMotionGate += (activity - arrowMotionGate) * follow
        cameraMotionGate += (cameraActivity - cameraMotionGate) * follow
        let targetTempo = audio.bpm >= 60 && audio.bpm <= 200 ? max(0.75, min(1.30, sqrt(audio.bpm / 120))) : 1
        tempoScale += (targetTempo - tempoScale) * (1 - exp(-songDelta * 2))
        beatDrive *= exp(-songDelta * 5)
        let newBeat = audio.beatSequence != lastBeatSequence
        lastBeatSequence = audio.beatSequence
        if newBeat && playing && (lastBeatTime < 0 || audio.time - lastBeatTime >= 0.12) {
            beatDrive = max(beatDrive, audio.beatIntensity)
            lastBeatTime = audio.time
            for lane in 0..<22 where lane % 6 != 0 && lane % 6 != 3 {
                let head = (arrowClock * speeds[lane] + Float(lane) * 177 + beatOffsets[lane]).truncatingRemainder(dividingBy: lengths[lane] + 950)
                var traveled: Float = 0
                for point in 1..<(paths[lane].count - 1) {
                    traveled += simd_length(paths[lane][point] - paths[lane][point - 1])
                    let gap = traveled - head
                    if gap >= 0 && gap <= 18 + 18 * audio.beatIntensity {
                        beatOffsets[lane] += gap + 0.5
                        break
                    }
                }
            }
        }
        let drum = Self.clamp(audio.drums)
        arrowClock += songDelta * 1.2 * tempoScale * arrowMotionGate * (0.78 + 0.32 * beatDrive + 0.18 * drum)
        cameraClock += songDelta * 1.2 * tempoScale * cameraMotionGate * (0.62 + 0.54 * beatDrive + 0.14 * drum)
        let sustainFollow = 1 - exp(-songDelta * 3)
        sustainedGuitar += (Self.clamp(audio.guitar) - sustainedGuitar) * sustainFollow
        sustainedPiano += (Self.clamp(audio.piano) - sustainedPiano) * sustainFollow
        let bass = Self.clamp(audio.vectorSubBass)
        smoothedBass += (bass - smoothedBass) * (1 - exp(-songDelta * 7))
        let mood = DesktopMoodService.shared.colors
        let fallback = [SIMD3<Float>(41/255,32/255,54/255), SIMD3<Float>(77/255,54/255,94/255), SIMD3<Float>(129/255,93/255,156/255), SIMD3<Float>(176/255,133/255,205/255), SIMD3<Float>(37/255,27/255,48/255), SIMD3<Float>(223/255,190/255,232/255), SIMD3<Float>(104/255,73/255,121/255)]
        let colors: [SIMD3<Float>] = DesktopMoodService.shared.isLLMGenerated ?
            [mood.coronaFilaments, mood.volumetricBeam, mood.pulseRing, mood.topLightArray,
             mood.atmosphere, mood.edgeLight, mood.rotatingBeam].map { SIMD3<Float>($0.x, $0.y, $0.z) } : fallback
        let f = SIMD2<Float>(cos(-Float.pi/4),sin(-Float.pi/4))
        let camera = f * cameraClock * 260 * 0.53 * 0.75
        let zoom: Float = 1 + 0.75 * 0.07
        let pixelX = Float(view.drawableSize.width) * zoom / 390
        let pixelY = Float(view.drawableSize.height) * zoom / 390
        let geometryScale = min(1, 3 / max(1, min(pixelX, pixelY)))
        func pixelFeather(_ normal: SIMD2<Float>) -> Float {
            0.9 / max(1, simd_length(SIMD2<Float>(normal.x * pixelX, normal.y * pixelY)))
        }
        var v = [Vertex](); v.reserveCapacity(70000)
        func project(_ p: SIMD2<Float>) -> SIMD2<Float> { let q=p-camera-SIMD2<Float>(195,195); return SIMD2(q.x*zoom*2/390,-q.y*zoom*2/390) }
        func quad(_ a: SIMD2<Float>,_ b: SIMD2<Float>,_ w: Float,_ c: SIMD4<Float>) { let d=simd_normalize(b-a), n=SIMD2(-d.y,d.x)*w, q=[project(a-n),project(a+n),project(b+n),project(b-n)]; v += [Vertex(position:q[0],color:c),Vertex(position:q[1],color:c),Vertex(position:q[2],color:c),Vertex(position:q[0],color:c),Vertex(position:q[2],color:c),Vertex(position:q[3],color:c)] }
        bassPeak = max(bassPeak * exp(-songDelta * 0.26), max(bass, 0.03))
        guitarPeak = max(guitarPeak * exp(-songDelta * 0.48), max(audio.guitar, 0.018))
        let normalizedBass = min(1, pow(max(0, bass) / max(0.038, bassPeak * 0.66), 0.78))
        let normalizedGuitar = min(1, pow(max(0, audio.guitar) / max(0.020, guitarPeak * 0.74), 0.92))
        let bassHigh = Self.smoothstep(0.86, 0.98, normalizedBass) * Self.smoothstep(0.12, 0.28, bass)
        let guitarHigh = Self.smoothstep(0.76, 0.94, normalizedGuitar) * Self.smoothstep(0.14, 0.34, audio.guitar)
        let climaxHigh = Self.smoothstep(0.58, 0.82, audio.activityClimax)
        gridEnergyPulse += (max(bassHigh, max(guitarHigh, climaxHigh)) - gridEnergyPulse) * (1 - exp(-songDelta * 8))
        let videoActive = audio.visualVideoActive > 0.5
        if videoActive && !videoWasActive { videoPulse = 1 }
        videoWasActive = videoActive
        videoPulse *= exp(-songDelta * 2.2)
        let highGlow = max(gridEnergyPulse, videoPulse)
        let gridTint = DesktopMoodService.shared.isLLMGenerated ? colors[5] : SIMD3<Float>(150/255,106/255,177/255)
        let grid = SIMD4(gridTint.x, gridTint.y, gridTint.z, 0.10 + highGlow * 0.48)
        func disc(_ center: SIMD2<Float>, _ radius: Float, _ color: SIMD4<Float>) {
            for segment in 0..<8 {
                let a0 = Float(segment) * .pi / 4, a1 = Float(segment + 1) * .pi / 4
                let p0 = center + SIMD2<Float>(cos(a0), sin(a0)) * radius
                let p1 = center + SIMD2<Float>(cos(a1), sin(a1)) * radius
                v += [Vertex(position: project(center), color: color), Vertex(position: project(p0), color: color), Vertex(position: project(p1), color: color)]
            }
        }
        for axis in 0..<2 {
            let coordinate = axis == 0 ? camera.x : camera.y
            let origin: Float = axis == 0 ? -1000 : -1800
            let first = Int(origin + floor((coordinate + 195 - 500 - origin) / 75) * 75)
            let lastLine = Int(coordinate + 195 + 500)
            for line in stride(from: first, through: lastLine, by: 75) {
                let linePosition = Float(line)
                let a = axis == 0 ? SIMD2<Float>(linePosition, camera.y - 800) : SIMD2<Float>(camera.x - 800, linePosition)
                let b = axis == 0 ? SIMD2<Float>(linePosition, camera.y + 1200) : SIMD2<Float>(camera.x + 1200, linePosition)
                let gridNormal = axis == 0 ? SIMD2<Float>(1, 0) : SIMD2<Float>(0, 1)
                quad(a, b, 0.5 * pixelFeather(gridNormal) / 0.9, grid)
                guard highGlow > 0.08 else { continue }
                var phase = (arrowClock * (120 + 140 * highGlow) + linePosition * 0.73).truncatingRemainder(dividingBy: 1800)
                if phase < 0 { phase += 1800 }
                for dot in 0..<3 {
                    let along = -720 + (phase + Float(dot) * 600).truncatingRemainder(dividingBy: 1800)
                    let center = axis == 0 ? SIMD2<Float>(linePosition, camera.y + along) : SIMD2<Float>(camera.x + along, linePosition)
                    let radius = (1.25 + 1.25 * highGlow) * geometryScale
                    let streak = (9 + 11 * highGlow) * geometryScale
                    let tail = center - (axis == 0 ? SIMD2<Float>(0, streak) : SIMD2<Float>(streak, 0))
                    let side = axis == 0 ? SIMD2<Float>(radius * 0.45, 0) : SIMD2<Float>(0, radius * 0.45)
                    let tint = colors[2]
                    let headColor = SIMD4<Float>(tint.x, tint.y, tint.z, 0.12 + 0.56 * highGlow)
                    let tailColor = SIMD4<Float>(tint.x, tint.y, tint.z, 0)
                    let p = [tail, center + side, center, center - side]
                    for index in [0,1,2,0,2,3] {
                        v.append(Vertex(position: project(p[index]), color: index == 0 ? tailColor : headColor))
                    }
                    disc(center, radius, headColor)
                }
            }
        }
        let centerTile = max(0, Int(floor(cameraClock * 260 * 0.53 * 0.75 / 1200)))
        for tile in max(0, centerTile - 3)...(centerTile + 1) {
            let offset = f * (Float(tile) * 1200)
            for (i,path) in paths.enumerated() {
                if i >= 22 { break }
                let pts = (i % 6 == 0 || i % 6 == 3) ? [path[0], path[0] + f * lengths[i]] : path
                let llm = DesktopMoodService.shared.isLLMGenerated
                let col = i % 6 == 0 ? (llm ? colors[0] * 0.55 + colors[2] * 0.45 : colors[2]) :
                          (i % 6 == 3 ? (llm ? colors[1] * 0.55 + colors[3] * 0.45 : colors[3]) :
                          (i % 6 == 1 ? (llm ? colors[6] * 0.55 + colors[5] * 0.45 : colors[5]) : colors[i % colors.count]))
                let life: Float = i % 6 == 0 ? 0.22 + 0.78 * sustainedGuitar : (i % 6 == 3 ? 0.22 + 0.78 * sustainedPiano : 1)
                let c = SIMD4(col.x,col.y,col.z,life)
                let head = fmod(arrowClock * speeds[i] + Float(i) * 177 + beatOffsets[i], lengths[i] + 950)
                let tail = max(0, head - (330 + (speeds[i] - 150) / 180 * 450) * 1.4)
                let visibleHead = min(head, lengths[i])
                if tail >= visibleHead { continue }
                var visible = [SIMD2<Float>]()
                var run: Float = 0
                for j in 0..<(pts.count - 1) {
                    let segment = pts[j + 1] - pts[j]
                    let segmentLength = simd_length(segment)
                    let lo = max(tail, run), hi = min(visibleHead, run + segmentLength)
                    if hi > lo {
                        let a = pts[j] + segment * ((lo - run) / max(segmentLength, 1)) + offset
                        let b = pts[j] + segment * ((hi - run) / max(segmentLength, 1)) + offset
                        if visible.isEmpty || simd_length(visible[visible.count - 1] - a) > 0.01 { visible.append(a) }
                        visible.append(b)
                    }
                    run += segmentLength
                }
                guard visible.count >= 2 else { continue }
                let minX = visible.map(\.x).min() ?? 0, maxX = visible.map(\.x).max() ?? 0
                let minY = visible.map(\.y).min() ?? 0, maxY = visible.map(\.y).max() ?? 0
                if maxX < camera.x - 100 || minX > camera.x + 490 || maxY < camera.y - 100 || minY > camera.y + 490 { continue }
                let halfWidth = widths[i] * (1 + smoothedBass * 0.65) * 0.5 * geometryScale
                var stations = [[Vertex]]()
                for j in visible.indices {
                    let incoming = j == 0 ? simd_normalize(visible[1] - visible[0]) : simd_normalize(visible[j] - visible[j - 1])
                    let outgoing = j == visible.count - 1 ? incoming : simd_normalize(visible[j + 1] - visible[j])
                    let tangent = j == 0 ? outgoing : (j == visible.count - 1 ? incoming : simd_normalize(incoming + outgoing))
                    let normal = SIMD2<Float>(-tangent.y, tangent.x)
                    let previousNormal = SIMD2<Float>(-incoming.y, incoming.x)
                    let miter = j == 0 || j == visible.count - 1 ? 1 : min(3, 1 / max(0.3333, abs(simd_dot(normal, previousNormal))))
                    let core = halfWidth * miter
                    let outer = core + pixelFeather(normal)
                    let transparent = SIMD4<Float>(c.x, c.y, c.z, 0)
                    stations.append([
                        Vertex(position: project(visible[j] - normal * outer), color: transparent),
                        Vertex(position: project(visible[j] - normal * core), color: c),
                        Vertex(position: project(visible[j] + normal * core), color: c),
                        Vertex(position: project(visible[j] + normal * outer), color: transparent)
                    ])
                }
                for j in 0..<(stations.count - 1) {
                    for band in 0..<3 {
                        let a = stations[j][band], b = stations[j][band + 1]
                        let c0 = stations[j + 1][band], d0 = stations[j + 1][band + 1]
                        v += [a, b, c0, b, d0, c0]
                    }
                }
                let pos = visible[visible.count - 1]
                let dir = simd_normalize(pos - visible[visible.count - 2])
                let n=SIMD2(-dir.y,dir.x), h=max(20, widths[i] * 3.1) * geometryScale, wing=max(13, widths[i] * 1.7) * geometryScale, hc=SIMD4(col.x,col.y,col.z,life)
                let q = [pos + dir * h * 0.47, pos - dir * h * 0.5 + n * wing,
                         pos - dir * h * 0.27, pos - dir * h * 0.5 - n * wing]
                v += [Vertex(position:project(q[0]),color:hc),Vertex(position:project(q[1]),color:hc),Vertex(position:project(q[2]),color:hc),Vertex(position:project(q[0]),color:hc),Vertex(position:project(q[2]),color:hc),Vertex(position:project(q[3]),color:hc)]
                let center = (q[0] + q[1] + q[2] + q[3]) * 0.25
                let clear = SIMD4<Float>(hc.x, hc.y, hc.z, 0)
                for edge in 0..<4 {
                    let a = q[edge], b = q[(edge + 1) % 4]
                    let feather = pixelFeather(n)
                    let outerA = center + (a - center) * (1 + feather / h)
                    let outerB = center + (b - center) * (1 + feather / h)
                    v += [Vertex(position:project(a),color:hc),Vertex(position:project(outerA),color:clear),Vertex(position:project(b),color:hc),
                          Vertex(position:project(outerA),color:clear),Vertex(position:project(outerB),color:clear),Vertex(position:project(b),color:hc)]
                }
                if i % 8 == 0 {
                    let highlight = DesktopMoodService.shared.isLLMGenerated ? colors[2] : SIMD3<Float>(236/255,189/255,247/255)
                    let accent = SIMD4<Float>(highlight.x, highlight.y, highlight.z, 0.45)
                    for j in 0..<(visible.count - 1) {
                        quad(visible[j], visible[j + 1], max(0.4, widths[i] * 0.06) * geometryScale, accent)
                    }
                }
            }
        }
        let byteCount = v.count * MemoryLayout<Vertex>.stride
        let buffer: MTLBuffer? = v.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: byteCount, options: .storageModeShared)
        }
        guard let buffer else { return }; encoder.setRenderPipelineState(pipeline); encoder.setVertexBuffer(buffer, offset: 0, index: 0); encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:v.count)
    }
    private static func smoothstep(_ a: Float, _ b: Float, _ value: Float) -> Float {
        let t = min(max((value - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
    private static func clamp(_ value: Float) -> Float { min(max(value, 0), 1) }
    private func buildPaths() {
        func random(_ n: Double) -> Float {
            let x = sin(n * 127.1 + 78.233) * 43758.5453
            return Float(x - floor(x))
        }
        let forward = SIMD2<Float>(cos(-Float.pi / 4), sin(-Float.pi / 4))
        let lateral = SIMD2<Float>(-forward.y, forward.x)
        for a in 0..<48 {
            let seed = Double(a) * 23 + 11
            var point = SIMD2<Float>(-310 + random(seed) * 331.5, 253.5 + random(seed + 1) * 370.5)
            var path = [point]
            var length: Float = 0
            let direction: Float = a % 2 == 0 ? 1 : -1
            for k in 0..<22 {
                let step = (64 + random(seed + Double(k * 5 + 3)) * 145) * (0.65 + random(Double(a + 201)) * 0.65)
                point += forward * step
                length += step
                path.append(point)
                if k < 21 {
                    let side = (38 + random(seed + Double(k * 5 + 4)) * 132) * (k % 2 == 0 ? direction : -direction)
                    point += lateral * side
                    length += abs(side)
                    path.append(point)
                }
            }
            let variance = random(Double(a * 9 + 7))
            paths.append(path)
            lengths.append(length)
            speeds.append(150 + variance * 180)
            widths.append(5 + variance * 11 + (a % 7 == 0 ? 7 : 0))
        }
    }
}
