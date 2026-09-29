import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let device = MTLCreateSystemDefaultDevice()!
let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let root = repo.appendingPathComponent("AudioSampleBuffer/VisualEffects/Metal")
let output = repo.appendingPathComponent("build/MirrorStrataPreview")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let common = try String(contentsOf: root.appendingPathComponent("ShaderCommon.metal"), encoding: .utf8)
let frames = try String(contentsOf: root.appendingPathComponent("MirrorStrataShader.metal"), encoding: .utf8)
    .replacingOccurrences(of: "#include \"ShaderCommon.metal\"", with: "")
let glass = try String(contentsOf: root.appendingPathComponent("GlassResonanceShader.metal"), encoding: .utf8)
    .replacingOccurrences(of: "#include \"ShaderCommon.metal\"", with: "")
let lib = try device.makeLibrary(source: common + frames + glass, options: nil)
func pipeline(_ vertex: String, _ fragment: String, _ format: MTLPixelFormat, _ depth: Bool) throws -> MTLRenderPipelineState {
    let d = MTLRenderPipelineDescriptor()
    d.vertexFunction = lib.makeFunction(name: vertex)
    d.fragmentFunction = lib.makeFunction(name: fragment)
    d.colorAttachments[0].pixelFormat = format
    if depth { d.depthAttachmentPixelFormat = .depth32Float }
    return try device.makeRenderPipelineState(descriptor: d)
}
let back = try pipeline("mirrorFrameVertex", "mirrorFrameBackFragment", .rgba16Float, true)
let front = try pipeline("mirrorFrameVertex", "mirrorFrameFragment", .rgba16Float, true)
let backdrop = try pipeline("glassFullscreenVertex", "mirrorBackdropFragment", .rgba16Float, true)
let bloomP = try pipeline("glassFullscreenVertex", "glassBloomHorizontal", .rgba16Float, false)
let composite = try pipeline("glassFullscreenVertex", "glassCompositeFragment", .rgba8Unorm, false)
let dd = MTLDepthStencilDescriptor(); dd.depthCompareFunction = .less; dd.isDepthWriteEnabled = true
let depthState = device.makeDepthStencilState(descriptor: dd)!
let queue = device.makeCommandQueue()!
var indices = [UInt16]()
for i in 0..<128 {
    for j in 0..<16 {
        let a = UInt16(i * 17 + j), b = UInt16((i + 1) * 17 + j)
        indices += [a, a + 1, b, a + 1, b + 1, b]
    }
}
let indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * 2)!
func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int, depth: Bool = false) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
    d.storageMode = .shared
    d.usage = depth ? [.renderTarget] : [.renderTarget, .shaderRead]
    return device.makeTexture(descriptor: d)!
}
func save(_ bytes: [UInt8], _ w: Int, _ h: Int, _ name: String) {
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let dest = CGImageDestinationCreateWithURL(output.appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func write(_ u: inout [Float], _ i: Int, _ x: Float, _ y: Float, _ z: Float) {
    u[i] = x; u[i + 1] = y; u[i + 2] = z; u[i + 3] = 1
}

func render(_ name: String, low: Float, mid: Float, high: Float, climax: Float, phase: Float, wave: Float,
            atmosphere: SIMD3<Float>, primary: SIMD3<Float>, accent: SIMD3<Float>, aspect: Float = 0.46) {
    let side = 900
    let rear = texture(.rgba16Float, side, side)
    let scene = texture(.rgba16Float, side, side)
    let depth = texture(.depth32Float, side, side, depth: true)
    let bloom = texture(.rgba16Float, side / 2, side / 2)
    let result = texture(.rgba8Unorm, side, side)
    var u = [Float](repeating: 0, count: 408)
    u[36] = Float(side); u[37] = Float(side); u[38] = aspect
    for i in 0..<80 {
        let level: Float = i < 22 ? low : (i < 53 ? mid : high)
        u[40 + i * 4] = level
        u[41 + i * 4] = level * 0.85
    }
    let energy = min(low * 0.44 + mid * 0.36 + high * 0.20, 1)
    u[360] = low; u[361] = mid; u[362] = high; u[363] = low * 0.4
    u[364] = phase; u[365] = 0; u[366] = climax; u[367] = energy
    u[368] = 0.42; u[369] = 1.02; u[370] = 1.02; u[371] = 0.20
    u[372] = wave; u[376] = wave > 0 ? 1.0 : 0
    u[380] = 1
    write(&u, 396, atmosphere.x, atmosphere.y, atmosphere.z)
    write(&u, 400, primary.x, primary.y, primary.z)
    write(&u, 404, accent.x, accent.y, accent.z)
    let cmd = queue.makeCommandBuffer()!
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = rear
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.depthAttachment.texture = depth
    pass.depthAttachment.loadAction = .clear
    pass.depthAttachment.storeAction = .dontCare
    pass.depthAttachment.clearDepth = 1
    var enc = cmd.makeRenderCommandEncoder(descriptor: pass)!
    enc.setVertexBytes(u, length: u.count * 4, index: 0)
    enc.setFragmentBytes(u, length: u.count * 4, index: 0)
    enc.setRenderPipelineState(backdrop)
    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    enc.setDepthStencilState(depthState)
    enc.setFrontFacing(.counterClockwise)
    enc.setCullMode(.front)
    enc.setRenderPipelineState(back)
    enc.drawIndexedPrimitives(type: .triangle, indexCount: indices.count, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0, instanceCount: 6)
    enc.endEncoding()
    pass.colorAttachments[0].texture = scene
    enc = cmd.makeRenderCommandEncoder(descriptor: pass)!
    enc.setVertexBytes(u, length: u.count * 4, index: 0)
    enc.setFragmentBytes(u, length: u.count * 4, index: 0)
    enc.setRenderPipelineState(backdrop)
    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    enc.setDepthStencilState(depthState)
    enc.setFrontFacing(.counterClockwise)
    enc.setCullMode(.back)
    enc.setRenderPipelineState(front)
    enc.setFragmentTexture(rear, index: 0)
    enc.drawIndexedPrimitives(type: .triangle, indexCount: indices.count, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0, instanceCount: 6)
    enc.endEncoding()
    let blur = MTLRenderPassDescriptor()
    blur.colorAttachments[0].texture = bloom
    blur.colorAttachments[0].loadAction = .dontCare
    blur.colorAttachments[0].storeAction = .store
    let b = cmd.makeRenderCommandEncoder(descriptor: blur)!
    b.setRenderPipelineState(bloomP)
    b.setFragmentTexture(scene, index: 0)
    b.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    b.endEncoding()
    let cpass = MTLRenderPassDescriptor()
    cpass.colorAttachments[0].texture = result
    cpass.colorAttachments[0].loadAction = .dontCare
    cpass.colorAttachments[0].storeAction = .store
    let c = cmd.makeRenderCommandEncoder(descriptor: cpass)!
    c.setRenderPipelineState(composite)
    c.setFragmentBytes(u, length: u.count * 4, index: 0)
    c.setFragmentTexture(scene, index: 0)
    c.setFragmentTexture(bloom, index: 1)
    c.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    c.endEncoding()
    cmd.commit(); cmd.waitUntilCompleted()
    var bytes = [UInt8](repeating: 0, count: side * side * 4)
    result.getBytes(&bytes, bytesPerRow: side * 4, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
    save(bytes, side, side, name)
    if aspect < 1 {
        let width = Int(Float(side) * aspect)
        var crop = [UInt8]()
        for row in 0..<side {
            let start = (row * side + (side - width) / 2) * 4
            crop.append(contentsOf: bytes[start..<(start + width * 4)])
        }
        save(crop, width, side, name + "-phone")
    }
    print("wrote \(name)")
}

let champagneA = SIMD3<Float>(0.10, 0.08, 0.10)
let champagneP = SIMD3<Float>(0.92, 0.84, 0.70)
let champagneG = SIMD3<Float>(0.86, 0.70, 0.42)
let emeraldA = SIMD3<Float>(0.04, 0.08, 0.07)
let emeraldP = SIMD3<Float>(0.22, 0.48, 0.40)
let emeraldG = SIMD3<Float>(0.72, 0.88, 0.52)
render("quiet", low: 0.08, mid: 0.06, high: 0.05, climax: 0.05, phase: 0.4, wave: 0,
       atmosphere: champagneA, primary: champagneP, accent: champagneG)
render("bass", low: 0.88, mid: 0.2, high: 0.12, climax: 0.15, phase: 0.9, wave: 0.15,
       atmosphere: champagneA, primary: champagneP, accent: champagneG)
render("climax", low: 0.7, mid: 0.7, high: 0.7, climax: 0.95, phase: 1.6, wave: 0.4,
       atmosphere: champagneA, primary: champagneP, accent: champagneG)
render("llm-emerald", low: 0.45, mid: 0.5, high: 0.4, climax: 0.35, phase: 1.1, wave: 0.3,
       atmosphere: emeraldA, primary: emeraldP, accent: emeraldG)
print("done")
