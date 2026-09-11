import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let device = MTLCreateSystemDefaultDevice()!
// Run from the repository root: swift Tools/render_cellular_wormhole_preview.swift
let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let root = repo.appendingPathComponent("AudioSampleBuffer/VisualEffects/Metal").path + "/"
let output = repo.appendingPathComponent("build/CellularWormholePreview")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let common = try String(contentsOfFile: root + "ShaderCommon.metal", encoding: .utf8)
let shader = try String(contentsOfFile: root + "CellularWormholeShader.metal", encoding: .utf8).replacingOccurrences(of: "#include \"ShaderCommon.metal\"", with: "")
let vertex = """
vertex RasterizerData previewVertex(uint vid [[vertex_id]]) {
 float2 p[4] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};
 RasterizerData o; o.position=float4(p[vid],0,1); o.texCoord=p[vid]*0.5+0.5; o.color=float4(1); return o;
}
"""
let lib = try device.makeLibrary(source: common + shader + vertex, options: nil)
let pd = MTLRenderPipelineDescriptor()
pd.vertexFunction = lib.makeFunction(name:"previewVertex")
pd.fragmentFunction = lib.makeFunction(name:"cellularWormholeFragment")
pd.colorAttachments[0].pixelFormat = .rgba8Unorm
let pipeline = try device.makeRenderPipelineState(descriptor:pd)
let queue = device.makeCommandQueue()!
var frames = [String: [UInt8]]()
var frameInputs = [String: [Float]]()
let featureOffsets = ["low": 388, "hit": 389, "melody": 390, "haze": 391,
                      "high": 392, "electric": 393, "chopped": 394, "sweep": 395,
                      "pan": 396, "echo": 397, "sidechain": 398,
                      "pluck": 404, "sound-wall": 405]
let featureCases = featureOffsets.keys.sorted().map { ($0, Float(0.18)) }
let cases = [("quiet",Float(0)),("beat",Float(0.9)),
                      ("silent-stale-features",Float(0)),
                      ("single-band",Float(0)),("motion",Float(0)),
                      ("climax",Float(0.55)),
                      ("feature-base",Float(0.18)),("impact-late",Float(0.18)),
                      ("layered",Float(0.45)),("llm-theme",Float(0.45))] + featureCases
for (name, level) in cases {
 let w=900, h=900
 let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:w,height:h,mipmapped:false)
 td.usage = [.renderTarget]; td.storageMode = .shared
 let tex=device.makeTexture(descriptor:td)!
 // Shared Uniforms: two matrices, time/resolution, 80 bands, 12 float4s.
 var values=[Float](repeating:0,count:32+8+320+48)
 values[32]=4; values[34]=2; values[36]=Float(w); values[37]=Float(h); values[38]=1
 if name == "motion" { values[32] = 5; values[34] = 3 }
 for i in 0..<80 {values[40+i*4]=level * (0.25 + 0.75 * Float(i%9)/8);values[41+i*4]=values[40+i*4]*0.8}
 values[360]=0.32; values[361]=0.24; values[362]=level; values[363]=18
 values[360+7]=1.15; values[360+11]=level; values[383]=1.08
 values[360+14]=level*0.7; values[360+15]=level*0.5; values[360+16]=level*0.6;values[360+17]=level*0.7
 if name == "single-band" { values[40+24*4]=1; values[41+24*4]=1 }
 if let offset = featureOffsets[name] { values[offset] = 0.85 }
 // Keep sweep active in the baseline to isolate pan's effect on its shafts.
 if name == "feature-base" || featureOffsets[name] != nil || name == "impact-late" {
     values[395] = name == "sweep" ? 0.85 : 0.18
 }
 if name == "impact-late" { values[361] = 0.7 }
 if name == "climax" {
     values[366] = 0.95
     values[388] = 0.75; values[389] = 0.82; values[390] = 0.70
     values[392] = 0.86; values[399] = 0.90; values[405] = 0.76
 }
 if name == "silent-stale-features" {
     for offset in featureOffsets.values { values[offset] = 0.95 }
     values[362] = 0.9
 }
 if name == "layered" || name == "llm-theme" {
     for offset in featureOffsets.values { values[offset] = 0.64 }
     values[389] = 0.92; values[392] = 0.85; values[395] = 0.78
     values[362] = 0.85
 }
 if name == "llm-theme" {
     values[376+3] = 1
     values[380] = 0.92
     values[381] = 0.10
     values[382] = 0.48
     values[383] = 1.08
 }
 frameInputs[name] = values
 let buf=device.makeBuffer(bytes:values,length:values.count*4,options:.storageModeShared)!
 let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=tex;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
 let cmd=queue.makeCommandBuffer()!;let enc=cmd.makeRenderCommandEncoder(descriptor:pass)!
 enc.setRenderPipelineState(pipeline);enc.setFragmentBuffer(buf,offset:0,index:0);enc.drawPrimitives(type:.triangleStrip,vertexStart:0,vertexCount:4);enc.endEncoding();cmd.commit();cmd.waitUntilCompleted()
 if let e=cmd.error {throw e}
 var bytes=[UInt8](repeating:0,count:w*h*4);tex.getBytes(&bytes,bytesPerRow:w*4,from:MTLRegionMake2D(0,0,w,h),mipmapLevel:0)
 frames[name] = bytes
 let provider=CGDataProvider(data:Data(bytes) as CFData)!
 let image=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
 let dest=CGImageDestinationCreateWithURL(output.appendingPathComponent("\(name).png") as CFURL,UTType.png.identifier as CFString,1,nil)!
 CGImageDestinationAddImage(dest,image,nil);CGImageDestinationFinalize(dest)
 print(name, "rendered", cmd.gpuEndTime-cmd.gpuStartTime)
}

// Exercise the actual Metal shader: a single band must alter pores even with
// zero global energy/beat, and the full-spectrum beat must change the frame.
let quiet = frames["quiet"]!
precondition(quiet == frames["silent-stale-features"]!,
             "Stale analysis features must not trigger music layers in silence")
for name in ["beat", "single-band", "motion", "climax", "llm-theme"] {
    let changed = zip(quiet, frames[name]!).filter { $0 != $1 }.count
    precondition(changed > 100, "Audio input failed to change the rendered tunnel")
    print("\(name): \(changed) changed color channels")
}
for name in featureOffsets.keys.sorted() + ["impact-late"] {
    let changed = zip(frames["feature-base"]!, frames[name]!).filter { $0 != $1 }.count
    precondition(changed > 100, "Feature \(name) did not independently affect the scene")
    print("\(name): \(changed) changed channels vs identical-spectrum baseline")
}
let themeChanges = zip(frames["layered"]!, frames["llm-theme"]!).filter { $0 != $1 }.count
precondition(themeChanges > 100, "LLM palette failed with identical audio and time")

// Reproduce CPU uniform reuse while GPU frames are pending, as can happen
// under UI/scrolling load. Snapshots must match the serial reference exactly.
for snapshot in [false, true] {
    let byteCount = frameInputs["quiet"]!.count * MemoryLayout<Float>.stride
    let scratch = device.makeBuffer(length: byteCount, options: .storageModeShared)!
    var pending = [(MTLCommandBuffer, MTLTexture, String)]()
    for name in ["quiet", "layered", "high", "llm-theme", "beat", "single-band"] {
        frameInputs[name]!.withUnsafeBytes { source in
            scratch.contents().copyMemory(from: source.baseAddress!, byteCount: byteCount)
        }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                          width: 900, height: 900, mipmapped: false)
        td.usage = [.renderTarget]; td.storageMode = .shared
        let texture = device.makeTexture(descriptor: td)!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let command = queue.makeCommandBuffer()!
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        encoder.setRenderPipelineState(pipeline)
        if snapshot {
            encoder.setFragmentBytes(scratch.contents(), length: byteCount, index: 0)
        } else {
            encoder.setFragmentBuffer(scratch, offset: 0, index: 0)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        pending.append((command, texture, name))
    }
    // Submit only after all CPU updates, forcing the overlap deterministically.
    for (command, _, _) in pending { command.commit() }
    var mismatches = 0
    for (command, texture, name) in pending {
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var pixels = [UInt8](repeating: 0, count: 900 * 900 * 4)
        texture.getBytes(&pixels, bytesPerRow: 900 * 4,
                         from: MTLRegionMake2D(0, 0, 900, 900), mipmapLevel: 0)
        if pixels != frames[name]! { mismatches += 1 }
    }
    precondition(snapshot ? mismatches == 0 : mismatches > 0,
                 "In-flight uniform regression failed (snapshot=\(snapshot))")
    print("In-flight frame mismatches (snapshot=\(snapshot)): \(mismatches)/6")
}
print("Previews: \(output.path)")
