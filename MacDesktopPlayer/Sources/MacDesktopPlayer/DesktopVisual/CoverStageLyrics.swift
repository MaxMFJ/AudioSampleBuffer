import AppKit
import Metal
import MetalKit

/// High-resolution text masks on quads share the cover's Metal projection.
/// Mineradio's lyrics are textured text meshes; its separate star-river is the particle layer.
@MainActor
final class CoverStageLyrics {
    private struct Row {
        let texture: MTLTexture
        let aspect: Float
    }

    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private let particlePipeline: MTLRenderPipelineState
    private var rows: [Row] = []
    private var displayRows: [DesktopLyricsFrame.Row] = []
    private var lastWeights: [CGFloat] = []
    private var lastTexts: [String] = []
    private var lastTimelineIndices: [Int] = []
    private var rowStartTimes: [TimeInterval] = []
    private var effect: DesktopCoverLyricsEffect = .classic
    private var effectIntensity: CGFloat = 0.55

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, library: MTLLibrary) {
        self.device = device
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "DesktopCoverStageLyrics"
        descriptor.vertexFunction = library.makeFunction(name: "desktopStageLyricVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "desktopStageLyricFragment")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            fatalError("无法创建封面舞台歌词 Metal 渲染管线")
        }
        self.pipeline = pipeline

        let particleDescriptor = MTLRenderPipelineDescriptor()
        particleDescriptor.label = "DesktopCoverStageLyrics.ParticleEffect"
        particleDescriptor.vertexFunction = library.makeFunction(name: "desktopStageLyricParticleVertex")
        particleDescriptor.fragmentFunction = library.makeFunction(name: "desktopStageLyricParticleFragment")
        particleDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        particleDescriptor.colorAttachments[0].isBlendingEnabled = true
        particleDescriptor.colorAttachments[0].rgbBlendOperation = .add
        particleDescriptor.colorAttachments[0].alphaBlendOperation = .add
        particleDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        particleDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        particleDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        particleDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let particlePipeline = try? device.makeRenderPipelineState(descriptor: particleDescriptor) else {
            fatalError("无法创建封面舞台歌词粒子特效管线")
        }
        self.particlePipeline = particlePipeline
    }

    func update(_ frame: DesktopLyricsFrame, effect: DesktopCoverLyricsEffect, intensity: CGFloat) {
        let texts = frame.rows.map(\.text)
        let weights = frame.rows.map { $0.fontWeight.rawValue }
        let now = ProcessInfo.processInfo.systemUptime
        if self.effect != effect {
            rowStartTimes = Array(repeating: now, count: frame.rows.count)
        } else {
            if rowStartTimes.count > frame.rows.count { rowStartTimes.removeLast(rowStartTimes.count - frame.rows.count) }
            while rowStartTimes.count < frame.rows.count { rowStartTimes.append(now) }
            for index in frame.rows.indices where index >= lastTexts.count ||
                (lastTexts.indices.contains(index) && lastTexts[index] != texts[index]) ||
                (lastTimelineIndices.indices.contains(index) && lastTimelineIndices[index] != frame.rows[index].timelineIndex) {
                rowStartTimes[index] = now
            }
        }
        self.effect = effect
        effectIntensity = min(max(intensity, 0), 1)
        if texts != lastTexts || weights != lastWeights {
            rows = frame.rows.map { makeRow(text: $0.text, weight: $0.fontWeight) }
            lastTexts = texts
            lastWeights = weights
        }
        lastTimelineIndices = frame.rows.map(\.timelineIndex)
        displayRows = frame.rows
    }

    func draw(encoder: MTLRenderCommandEncoder, view: MTKView,
              stage: DesktopCoverStageUniforms, highlight: SIMD4<Float>) {
        guard rows.count == displayRows.count else { return }
        var stage = stage
        var highlight = SIMD4<Float>(max(highlight.x, 0.66), max(highlight.y, 0.84), max(highlight.z, 0.98), 1)
        let particleEffect = effect == .particleAssembly
        encoder.setRenderPipelineState(particleEffect ? particlePipeline : pipeline)

        for index in rows.indices {
            let row = rows[index]
            guard !lastTexts[index].isEmpty else { continue }
            let display = displayRows[index]
            let projectionScale = max(stage.layout.y, 0.01)
            let worldHeight = (Float(display.fontSize) / max(Float(view.bounds.height), 1)) / projectionScale
            var placement = SIMD4<Float>(Float(display.position.x - 0.5) * stage.layout.x / projectionScale,
                Float(0.5 - display.position.y) / projectionScale,
                worldHeight * row.aspect, worldHeight)
            let widthLimit = Float(display.maxWidthFraction) * stage.layout.x / projectionScale
            if placement.z > widthLimit {
                let fit = widthLimit / placement.z
                placement.z *= fit
                placement.w *= fit
            }
            let age = Float(max(0, ProcessInfo.processInfo.systemUptime - rowStartTimes[index]))
            var style = SIMD4<Float>(display.progress, display.isActive ? 1 : 0, Float(display.opacity), age)
            var effectParameters = SIMD4<Float>(Float(effect.shaderMode), Float(effectIntensity), 0, 0)
            encoder.setVertexBytes(&placement, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.setVertexBytes(&style, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
            encoder.setVertexBytes(&effectParameters, length: MemoryLayout<SIMD4<Float>>.stride, index: 4)
            encoder.setFragmentBytes(&effectParameters, length: MemoryLayout<SIMD4<Float>>.stride, index: 4)
            encoder.setVertexBytes(&stage, length: MemoryLayout<DesktopCoverStageUniforms>.stride, index: 5)
            encoder.setVertexBytes(&highlight, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
            encoder.setFragmentBytes(&highlight, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
            encoder.setFragmentTexture(row.texture, index: 1)
            if particleEffect {
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 48 * 28)
            } else {
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }
    }

    private func makeRow(text: String, weight: NSFont.Weight) -> Row {
        let empty = Row(texture: makeTexture(width: 1, height: 1, bytes: [UInt8](repeating: 0, count: 4)),
                        aspect: 1)
        guard !text.isEmpty else { return empty }
        var fontSize: CGFloat = 128
        var font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        var attributed = NSAttributedString(string: text, attributes: attributes)
        var bounds = attributed.boundingRect(with: NSSize(width: 12_000, height: 240),
                                              options: [.usesLineFragmentOrigin, .usesFontLeading])
        if bounds.width > 12_000 {
            fontSize *= 12_000 / bounds.width
            font = NSFont.systemFont(ofSize: fontSize, weight: weight)
            attributes = [.font: font, .foregroundColor: NSColor.white]
            attributed = NSAttributedString(string: text, attributes: attributes)
            bounds = attributed.boundingRect(with: NSSize(width: 12_000, height: 240),
                                              options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        let width = max(8, min(12_000, Int(ceil(bounds.width + 48))))
        let height = max(8, Int(ceil(bounds.height + 40)))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB,
                                             bitmapFormat: [], bytesPerRow: width * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return empty }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        attributed.draw(at: NSPoint(x: 24 - bounds.origin.x, y: 20 - bounds.origin.y))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.bitmapData else { return empty }
        let bytes = Array(UnsafeBufferPointer(start: data, count: height * bitmap.bytesPerRow))
        let texture = makeTexture(width: width, height: height, bytes: bytes)
        let aspect = Float(width) / Float(height)
        return Row(texture: texture, aspect: aspect)
    }

    private func makeTexture(width: Int, height: Int, bytes: [UInt8]) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                   width: width, height: height,
                                                                   mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        let texture = device.makeTexture(descriptor: descriptor)!
        bytes.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

}
