import AppKit
import MetalKit

@MainActor
protocol DesktopEffectRenderer {
    var effect: DesktopBackgroundEffect { get }
    func setArtwork(_ image: NSImage?, device: MTLDevice)
    func draw(encoder: MTLRenderCommandEncoder, view: MTKView, audio: VisualAudio)
}

/// Central registration point for desktop effects. Add new effect renderers here.
@MainActor
enum DesktopEffectFactory {
    static func make(
        effect: DesktopBackgroundEffect,
        device: MTLDevice,
        pixelFormat: MTLPixelFormat,
        library: MTLLibrary
    ) -> any DesktopEffectRenderer {
        switch effect {
        case .aurora:
            return FullscreenDesktopEffectRenderer(effect: .aurora, vertexName: "auroraDesktopVertex", fragmentName: "desktopFragment", device: device, pixelFormat: pixelFormat, library: library)
        case .tyndall:
            return FullscreenDesktopEffectRenderer(effect: .tyndall, vertexName: "tyndallDesktopVertex", fragmentName: "desktopTyndallFragment", device: device, pixelFormat: pixelFormat, library: library)
        case .coverDots:
            return CoverDotsBackgroundRenderer(device: device, pixelFormat: pixelFormat, library: library)
        case .cellularHive:
            return CellularHiveDesktopEffectRenderer(device: device, pixelFormat: pixelFormat, library: library)
        }
    }
}

private struct DesktopHiveGuitarUniforms {
    var wave0 = SIMD4<Float>(repeating: 0)
    var wave1 = SIMD4<Float>(repeating: 0)
    var wave2 = SIMD4<Float>(repeating: 0)
    var wave3 = SIMD4<Float>(repeating: 0)
    var wave4 = SIMD4<Float>(repeating: 0)
    var wave5 = SIMD4<Float>(repeating: 0)
    var wave6 = SIMD4<Float>(repeating: 0)
    var wave7 = SIMD4<Float>(repeating: 0)
    var color0 = SIMD4<Float>(0.04, 0.88, 1.0, 1)
    var color1 = SIMD4<Float>(1.0, 0.66, 0.08, 1)
    var color2 = SIMD4<Float>(0.45, 1.0, 0.18, 1)
    var color3 = SIMD4<Float>(0.20, 0.45, 1.0, 1)
}

@MainActor
private final class CellularHiveDesktopEffectRenderer: DesktopEffectRenderer {
    let effect = DesktopBackgroundEffect.cellularHive
    private let pipeline: MTLRenderPipelineState
    private var waveAges = Array(repeating: Float(0), count: 8)
    private var waveStrengths = Array(repeating: Float(0), count: 8)
    private var wavePaletteIndices = Array(repeating: Float(0), count: 8)
    private var previousGuitar: Float = 0
    private var lastWaveTriggerTime: Float = 0
    private var nextWaveSlot = 0
    private var nextPalette = 0
    private var lastTime: Float = 0

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, library: MTLLibrary) {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "DesktopEffect.cellularHive"
        descriptor.vertexFunction = library.makeFunction(name: "cellularHiveDesktopVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "cellularHiveDesktopFragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            fatalError("无法创建深空蜂巢 Metal 渲染管线")
        }
        self.pipeline = pipeline
    }

    func setArtwork(_ image: NSImage?, device: MTLDevice) {}

    func draw(encoder: MTLRenderCommandEncoder, view: MTKView, audio: VisualAudio) {
        let dt = lastTime > 0 ? min(max(audio.time - lastTime, 0), 0.12) : 1.0 / 60.0
        lastTime = audio.time
        for index in waveStrengths.indices where waveStrengths[index] > 0 {
            waveAges[index] += dt
            if waveAges[index] >= 2.8 {
                waveAges[index] = 0
                waveStrengths[index] = 0
            }
        }

        let guitar = min(max(audio.guitar, 0), 1)
        if guitar > 0.12, guitar - previousGuitar > 0.022,
           lastWaveTriggerTime <= 0 || audio.time - lastWaveTriggerTime >= 0.38 {
            var slot = nextWaveSlot
            for offset in 0..<8 {
                let candidate = (nextWaveSlot + offset) % 8
                if waveStrengths[candidate] <= 0 {
                    slot = candidate
                    break
                }
            }
            waveAges[slot] = 0
            waveStrengths[slot] = guitar
            wavePaletteIndices[slot] = Float(nextPalette % 4)
            nextPalette += 1
            nextWaveSlot = (slot + 1) % 8
            lastWaveTriggerTime = audio.time
        }
        previousGuitar = guitar

        var waves = DesktopHiveGuitarUniforms()
        let mood = DesktopMoodService.shared.colors
        waves.color0 = mood.pulseRing
        waves.color1 = mood.coronaFilaments
        waves.color2 = mood.volumetricBeam
        waves.color3 = mood.rotatingBeam
        for index in 0..<8 {
            let wave = SIMD4<Float>(waveAges[index], waveStrengths[index], wavePaletteIndices[index], 0)
            switch index {
            case 0: waves.wave0 = wave
            case 1: waves.wave1 = wave
            case 2: waves.wave2 = wave
            case 3: waves.wave3 = wave
            case 4: waves.wave4 = wave
            case 5: waves.wave5 = wave
            case 6: waves.wave6 = wave
            default: waves.wave7 = wave
            }
        }

        var values = audio
        var moodValues = mood
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&values, length: MemoryLayout<VisualAudio>.stride, index: 0)
        encoder.setFragmentBytes(&moodValues, length: MemoryLayout<DesktopMoodColors>.stride, index: 1)
        encoder.setFragmentBytes(&waves, length: MemoryLayout<DesktopHiveGuitarUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}

@MainActor
private final class CoverDotsBackgroundRenderer: DesktopEffectRenderer {
    let effect = DesktopBackgroundEffect.coverDots
    private let pipeline: MTLRenderPipelineState
    private let placeholder: MTLTexture
    private var artwork: MTLTexture?
    private var hasArtwork = false
    private var beatEnvelope: Float = 0
    private var beatAge: Float = 1
    private var previousBass: Float = 0
    private var previousDrums: Float = 0
    private var lastTime: Float = 0

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, library: MTLLibrary) {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "DesktopCoverDotsBackground"
        descriptor.vertexFunction = library.makeFunction(name: "desktopDotParticleVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "desktopDotParticleFragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            fatalError("无法创建封面外鼓点点阵 Metal 渲染管线")
        }
        self.pipeline = pipeline

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb,
            width: 1, height: 1, mipmapped: false)
        textureDescriptor.usage = .shaderRead
        textureDescriptor.storageMode = .shared
        guard let placeholder = device.makeTexture(descriptor: textureDescriptor) else {
            fatalError("无法创建封面外点阵占位纹理")
        }
        let pixel: [UInt8] = [18, 22, 34, 255]
        pixel.withUnsafeBytes {
            placeholder.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                                withBytes: $0.baseAddress!, bytesPerRow: 4)
        }
        self.placeholder = placeholder
    }

    func setArtwork(_ image: NSImage?, device: MTLDevice) {
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            artwork = nil
            hasArtwork = false
            return
        }
        artwork = try? MTKTextureLoader(device: device).newTexture(cgImage: cgImage, options: [
            .SRGB: true,
            .origin: MTKTextureLoader.Origin.topLeft,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ])
        hasArtwork = artwork != nil
    }

    func draw(encoder: MTLRenderCommandEncoder, view: MTKView, audio: VisualAudio) {
        let dt = lastTime > 0 ? min(max(audio.time - lastTime, 0), 0.1) : 0
        lastTime = audio.time
        beatEnvelope *= exp(-1.8 * dt)
        beatAge += dt
        let bassRise = max(audio.bass - previousBass, 0)
        let drumRise = max(audio.drums - previousDrums, 0)
        let hitStrength = max(bassRise * 5.5, drumRise * 3.2)
        if hitStrength > 0.23, beatAge > 0.16 {
            beatEnvelope = max(beatEnvelope, min(1, hitStrength))
            beatAge = 0
        }
        previousBass = audio.bass
        previousDrums = audio.drums

        let columns = 256
        let rows = max(1, Int((Float(columns) / max(audio.aspectRatio, 0.1)).rounded()))
        var values = audio
        var controls = SIMD4<Float>(Float(columns), 1, hasArtwork ? 1 : 0, Float(view.drawableSize.height))
        // The center samples are replaced by the independent square 3D cover.
        var style = SIMD4<Float>(0, beatEnvelope, beatAge, 1)
        var mood = DesktopMoodService.shared.colors
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&values, length: MemoryLayout<VisualAudio>.stride, index: 0)
        encoder.setVertexBytes(&controls, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        encoder.setVertexBytes(&style, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
        encoder.setVertexBytes(&mood, length: MemoryLayout<DesktopMoodColors>.stride, index: 3)
        encoder.setVertexTexture(artwork ?? placeholder, index: 0)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: columns * rows)
    }
}

@MainActor
private struct TyndallActivation {
    var startedAt: Float = -1
    var strength: Float = 0

    mutating func update(input: Float, threshold: Float, minimumStrength: Float,
                         duration: Float, time: Float, playing: Bool) {
        guard playing else {
            self = TyndallActivation()
            return
        }
        if startedAt >= 0, time - startedAt < duration { return }
        if input >= threshold {
            startedAt = time
            strength = max(input, minimumStrength)
        } else {
            self = TyndallActivation()
        }
    }
}

private struct TyndallAnimationUniforms {
    var starts = SIMD4<Float>(repeating: -1) // vocal, treble, piano, guitar
    var strengths = SIMD4<Float>(repeating: 0)
    var peak = SIMD4<Float>(-1, 0, 0, 0) // guitar peak start and strength
}

@MainActor
private final class FullscreenDesktopEffectRenderer: DesktopEffectRenderer {
    let effect: DesktopBackgroundEffect
    private let pipeline: MTLRenderPipelineState
    private var tyndallActivations = Array(repeating: TyndallActivation(), count: 5)
    private var tyndallBands = SIMD3<Float>(repeating: 0)
    private var lastTyndallTime: Float = -1
    private var lastTyndallPlaybackTime: Float = -1

    init(effect: DesktopBackgroundEffect, vertexName: String, fragmentName: String, device: MTLDevice, pixelFormat: MTLPixelFormat, library: MTLLibrary) {
        self.effect = effect
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "DesktopEffect.\(effect)"
        descriptor.vertexFunction = library.makeFunction(name: vertexName)
        descriptor.fragmentFunction = library.makeFunction(name: fragmentName)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            fatalError("无法创建 \(effect.title) Metal 渲染管线")
        }
        self.pipeline = pipeline
    }

    func setArtwork(_ image: NSImage?, device: MTLDevice) {}

    func draw(encoder: MTLRenderCommandEncoder, view: MTKView, audio: VisualAudio) {
        var values = audio
        var mood = DesktopMoodService.shared.colors
        var animation = TyndallAnimationUniforms()
        if effect == .tyndall {
            let playing = audio.playing > 0.5
            let dt = lastTyndallTime >= 0 ? min(max(audio.time - lastTyndallTime, 0), 0.1) : 1.0 / 60.0
            let playbackJump = lastTyndallPlaybackTime >= 0
                && abs(audio.playbackTime - lastTyndallPlaybackTime) > max(0.35, dt * 3)
            if !playing || playbackJump {
                tyndallActivations = Array(repeating: TyndallActivation(), count: 5)
                tyndallBands = SIMD3<Float>(repeating: 0)
            }
            lastTyndallTime = audio.time
            lastTyndallPlaybackTime = audio.playbackTime

            let source = SIMD3<Float>(audio.bass, audio.mid, audio.treble)
            let follow: Float = 1 - exp(-(playing ? 9.0 : 15.0) * dt)
            tyndallBands += (source - tyndallBands) * follow
            values.bass = tyndallBands.x
            values.mid = tyndallBands.y
            values.treble = tyndallBands.z

            let inputs = [audio.vocal, audio.treble, audio.piano, audio.guitar, audio.guitarPeak]
            let thresholds: [Float] = [0.06, 0.045, 0.12, 0.13, 0.48]
            let minimums: [Float] = [0.32, 0.13, 0.20, 0.20, 0.85]
            let durations: [Float] = [12, 14, 15.384615, 9, 13]
            for index in tyndallActivations.indices {
                tyndallActivations[index].update(input: inputs[index], threshold: thresholds[index],
                                                 minimumStrength: minimums[index], duration: durations[index],
                                                 time: audio.time, playing: playing)
            }
            animation.starts = SIMD4<Float>(tyndallActivations[0].startedAt, tyndallActivations[1].startedAt,
                                            tyndallActivations[2].startedAt, tyndallActivations[3].startedAt)
            animation.strengths = SIMD4<Float>(tyndallActivations[0].strength, tyndallActivations[1].strength,
                                               tyndallActivations[2].strength, tyndallActivations[3].strength)
            animation.peak = SIMD4<Float>(tyndallActivations[4].startedAt, tyndallActivations[4].strength, 0, 0)
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&values, length: MemoryLayout<VisualAudio>.stride, index: 0)
        encoder.setFragmentBytes(&mood, length: MemoryLayout<DesktopMoodColors>.stride, index: 1)
        if effect == .tyndall {
            encoder.setFragmentBytes(&animation, length: MemoryLayout<TyndallAnimationUniforms>.stride, index: 2)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
