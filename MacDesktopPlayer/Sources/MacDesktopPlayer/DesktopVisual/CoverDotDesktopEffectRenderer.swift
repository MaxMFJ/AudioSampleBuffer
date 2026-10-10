import AppKit
import MetalKit

@MainActor
final class CoverDotDesktopEffectRenderer {
    private let coverPipeline: MTLRenderPipelineState
    private let placeholder: MTLTexture
    private var artwork: MTLTexture?
    private var hasArtwork = false
    private var lastTime: Float = 0
    private var guitarEnvelope: Float = 0
    private var pianoEnvelope: Float = 0
    private let interaction = DesktopCoverInteraction()
    private let lyricRenderer: CoverStageLyrics

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, library: MTLLibrary) {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "DesktopCoverReliefParticles"
        descriptor.vertexFunction = library.makeFunction(name: "desktopCoverReliefVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "desktopCoverReliefFragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let coverPipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            fatalError("无法创建封面 3D 点阵 Metal 渲染管线")
        }
        self.coverPipeline = coverPipeline
        self.lyricRenderer = CoverStageLyrics(device: device, pixelFormat: pixelFormat, library: library)

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: 1, height: 1, mipmapped: false)
        textureDescriptor.usage = .shaderRead
        textureDescriptor.storageMode = .shared
        guard let placeholder = device.makeTexture(descriptor: textureDescriptor) else {
            fatalError("无法创建封面点阵占位纹理")
        }
        let pixel: [UInt8] = [18, 22, 34, 255]
        pixel.withUnsafeBytes {
            placeholder.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 4)
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

    func setLyrics(_ frame: DesktopLyricsFrame) {
        lyricRenderer.update(frame)
    }

    func draw(encoder: MTLRenderCommandEncoder, view: MTKView, audio: VisualAudio, squareCover: Bool) {
        let now = audio.time
        let dt = lastTime > 0 ? min(max(now - lastTime, 0), 0.1) : 0
        lastTime = now
        var values = audio
        let aspect = max(Float(view.drawableSize.width / max(view.drawableSize.height, 1)), 0.1)
        // The cover effect uses the original large square stage. Other effects
        // retain the smaller circular record drawn by the same particle pipeline.
        let coverHeight: Float = squareCover ? 0.68 : 0.56
        let coverWidth = coverHeight / aspect
        let coverLogicalWidth = coverWidth * Float(max(view.bounds.width, 1))
        let coverLogicalHeight = coverHeight * Float(max(view.bounds.height, 1))
        // Grid is measured over the artwork, not the whole desktop. About 2.8 pt
        // between centers keeps small, readable dots consistent on Retina and external displays.
        let discDiameter = min(coverLogicalWidth, coverLogicalHeight)
        let columns = max(2, min(512, Int((discDiameter / 2.8).rounded())))
        let coverRows = columns
        let pitch = min(coverWidth * Float(view.drawableSize.width) / Float(columns),
                        coverHeight * Float(view.drawableSize.height) / Float(coverRows))
        let follow = dt > 0 ? 1 - exp(-6 * dt) : 1
        guitarEnvelope += (min(max(audio.guitar, 0), 1) - guitarEnvelope) * follow
        pianoEnvelope += (min(max(audio.piano, 0), 1) - pianoEnvelope) * follow
        var coverControls = SIMD4<Float>(Float(columns), Float(coverRows), pitch * 0.90, hasArtwork ? 1 : 0)
        var layout = SIMD4<Float>(coverWidth, coverHeight, squareCover ? 1 : 0, 0)
        let input = interaction.update(view: view, dt: dt, coverWidth: coverWidth, coverHeight: coverHeight,
                                       squareCover: squareCover)
        var stage = DesktopCoverStageUniforms()
        // Only the record spins with playback; the square artwork stays upright.
        stage.rotation = SIMD4<Float>(input.0.x, input.0.y, input.0.z,
                                      input.0.w + (squareCover ? 0 : audio.playbackTime * 0.24))
        stage.pointer = input.1
        stage.layout = SIMD4<Float>(aspect, coverHeight, 1, 3.2)
        stage.audio = SIMD4<Float>(guitarEnvelope, pianoEnvelope, min(max(audio.bass, 0), 1), min(max(audio.treble, 0), 1))
        stage.viewport = SIMD4<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height),
                                     Float(view.drawableSize.width / max(view.bounds.width, 1)), audio.time)
        var mood = DesktopMoodService.shared.colors
        encoder.setRenderPipelineState(coverPipeline)
        encoder.setVertexBytes(&values, length: MemoryLayout<VisualAudio>.stride, index: 0)
        encoder.setVertexBytes(&coverControls, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        encoder.setVertexBytes(&mood, length: MemoryLayout<DesktopMoodColors>.stride, index: 3)
        encoder.setVertexBytes(&layout, length: MemoryLayout<SIMD4<Float>>.stride, index: 4)
        encoder.setVertexBytes(&stage, length: MemoryLayout<DesktopCoverStageUniforms>.stride, index: 5)
        encoder.setVertexTexture(artwork ?? placeholder, index: 0)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: columns * coverRows)
        var lyricStage = stage
        lyricStage.rotation.w = 0
        lyricRenderer.draw(encoder: encoder, view: view, stage: lyricStage, highlight: mood.pulseRing)
    }
}
