import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
// swift -import-objc-header AudioSampleBuffer/VisualEffects/Metal/GlassResonanceAudio.h Tools/render_glass_resonance_preview.swift
let repo=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let output=repo.appendingPathComponent("build/GlassResonancePreview")
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let root=repo.appendingPathComponent("AudioSampleBuffer/VisualEffects/Metal")
let source=try String(contentsOf:root.appendingPathComponent("ShaderCommon.metal"),encoding:.utf8)+String(contentsOf:root.appendingPathComponent("GlassResonanceShader.metal"),encoding:.utf8).replacingOccurrences(of:"#include \"ShaderCommon.metal\"",with:"")
let device=MTLCreateSystemDefaultDevice()!, queue=device.makeCommandQueue()!
let library=try device.makeLibrary(source:source,options:nil)
func pipeline(_ vertex:String,_ fragment:String,_ format:MTLPixelFormat,_ depth:Bool=false)throws->MTLRenderPipelineState {
 let d=MTLRenderPipelineDescriptor();d.vertexFunction=library.makeFunction(name:vertex);d.fragmentFunction=library.makeFunction(name:fragment);d.colorAttachments[0].pixelFormat=format
 if depth { d.depthAttachmentPixelFormat = .depth32Float };return try device.makeRenderPipelineState(descriptor:d)
}
let glass=try pipeline("glassResonanceVertex","glassResonanceFragment",.rgba16Float,true)
let rearPipeline=try pipeline("glassResonanceVertex","glassBackFragment",.rgba16Float,true)
let backdrop=try pipeline("glassFullscreenVertex","glassBackdropFragment",.rgba16Float,true)
let blur=try pipeline("glassFullscreenVertex","glassBloomHorizontal",.rgba16Float)
let composite=try pipeline("glassFullscreenVertex","glassCompositeFragment",.rgba8Unorm)
let dd=MTLDepthStencilDescriptor();dd.depthCompareFunction = .less;dd.isDepthWriteEnabled=true
let depthState=device.makeDepthStencilState(descriptor:dd)!
var indices=[UInt16]()
for i in 0..<160 {for j in 0..<28 {let a=UInt16(i*29+j),b=UInt16((i+1)*29+j);indices += [a,a+1,b,a+1,b+1,b]}}
let indexBuffer=device.makeBuffer(bytes:indices,length:indices.count*2)!
func texture(_ format:MTLPixelFormat,_ side:Int)->MTLTexture {
 let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:side,height:side,mipmapped:false)
 d.storageMode = .shared;d.usage = [.renderTarget,.shaderRead];return device.makeTexture(descriptor:d)!
}
func pass(_ texture:MTLTexture)->MTLRenderPassDescriptor {
 let p=MTLRenderPassDescriptor();p.colorAttachments[0].texture=texture;p.colorAttachments[0].loadAction = .clear;p.colorAttachments[0].storeAction = .store;return p
}
func save(_ bytes:[UInt8],_ w:Int,_ h:Int,_ name:String) {
 let provider=CGDataProvider(data:Data(bytes) as CFData)!
 let image=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
 let dest=CGImageDestinationCreateWithURL(output.appendingPathComponent(name+".png") as CFURL,UTType.png.identifier as CFString,1,nil)!
 CGImageDestinationAddImage(dest,image,nil);CGImageDestinationFinalize(dest)
}
var timings=[Double]()
func render(_ name:String,_ state:GlassAudioState,_ side:Int=900,_ aspect:Float=1)->[UInt8] {
 let rear=texture(.rgba16Float,side), scene=texture(.rgba16Float,side), depth=texture(.depth32Float,side), bloom=texture(.rgba16Float,side/2), result=texture(.rgba8Unorm,side)
 var u=[Float](repeating:0,count:408);u[36]=Float(side);u[37]=Float(side);u[38]=aspect
 u[360]=state.low;u[361]=state.mid;u[362]=state.high;u[363]=state.impact
 u[364]=state.phase;u[365]=state.strain;u[366]=state.impactAge;u[367]=state.energy;u[368]=0.32;u[369]=1.05
 let cmd=queue.makeCommandBuffer()!, p=pass(rear);p.depthAttachment.texture=depth;p.depthAttachment.loadAction = .clear;p.depthAttachment.storeAction = .dontCare;p.depthAttachment.clearDepth=1
 let e=cmd.makeRenderCommandEncoder(descriptor:p)!
 e.setVertexBytes(u,length:u.count*4,index:0);e.setFragmentBytes(u,length:u.count*4,index:0);e.setRenderPipelineState(backdrop);e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
 e.setDepthStencilState(depthState);e.setFrontFacing(.counterClockwise);e.setCullMode(.front);e.setRenderPipelineState(rearPipeline);e.drawIndexedPrimitives(type:.triangle,indexCount:indices.count,indexType:.uint16,indexBuffer:indexBuffer,indexBufferOffset:0);e.endEncoding()
 p.colorAttachments[0].texture=scene
 let front=cmd.makeRenderCommandEncoder(descriptor:p)!
 front.setVertexBytes(u,length:u.count*4,index:0);front.setFragmentBytes(u,length:u.count*4,index:0);front.setRenderPipelineState(backdrop);front.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
 front.setDepthStencilState(depthState);front.setFrontFacing(.counterClockwise);front.setCullMode(.back);front.setRenderPipelineState(glass);front.setFragmentTexture(rear,index:0);front.drawIndexedPrimitives(type:.triangle,indexCount:indices.count,indexType:.uint16,indexBuffer:indexBuffer,indexBufferOffset:0);front.endEncoding()
 let b=cmd.makeRenderCommandEncoder(descriptor:pass(bloom))!;b.setRenderPipelineState(blur);b.setFragmentTexture(scene,index:0);b.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3);b.endEncoding()
 let c=cmd.makeRenderCommandEncoder(descriptor:pass(result))!;c.setRenderPipelineState(composite);c.setFragmentBytes(u,length:u.count*4,index:0);c.setFragmentTexture(scene,index:0);c.setFragmentTexture(bloom,index:1);c.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3);c.endEncoding();cmd.commit();cmd.waitUntilCompleted()
 precondition(cmd.error == nil,"GPU failed: \(String(describing:cmd.error))")
 let ms=(cmd.gpuEndTime-cmd.gpuStartTime)*1000;timings.append(ms)
 var bytes=[UInt8](repeating:0,count:side*side*4);result.getBytes(&bytes,bytesPerRow:side*4,from:MTLRegionMake2D(0,0,side,side),mipmapLevel:0)
 save(bytes,side,side,name)
 if aspect<1 {let width=Int(Float(side)*aspect);var crop=[UInt8]();for row in 0..<side {let start=(row*side+(side-width)/2)*4;crop.append(contentsOf:bytes[start..<start+width*4])};save(crop,width,side,name+"-phone")}
 print("\(name): \(String(format:"%.2f",ms)) ms GPU");return bytes
}
// Production C envelope, isolated frequency inputs at identical time / rotation.
func state(_ band:Range<Int>,_ level:Float,_ fps:Int=30)->GlassAudioState {
 var s=GlassAudioState(),bands=[Float](repeating:0,count:80)
 for i in band {bands[i]=level}
 for _ in 0..<fps {glassAudioStep(&s,bands,0,0,0,0,1.15,1/Float(fps))}
 s.phase=0.50;return s
}
let silent=state(0..<80,0), low=state(0..<22,0.75), mid=state(22..<53,0.75), high=state(53..<80,0.75)
let quiet=render("quiet",silent)
for (name,s) in [("bass",low),("mid",mid),("high",high)] {
 let pixels=render(name,s);let changed=zip(quiet,pixels).filter{$0 != $1}.count
 precondition(changed>1000,"\(name) failed to affect actual Metal render")
 print("\(name) changed \(changed) channels")
}
var music=state(0..<80,0.44);music.phase=0.50
let musicImage=render("music",music)
var hit=music;glassAudioStep(&hit,[Float](repeating:0.6,count:80),0.95,0.75,0,0.9,1.15,1/30);hit.phase=music.phase
let hitImage=render("impact",hit)
precondition(zip(musicImage,hitImage).filter{$0 != $1}.count>1000)
var climax=state(0..<80,0.9);climax.phase=0.50
_ = render("climax",climax)
_ = render("portrait",music,1200,390/844)
_ = render("reduced",music,600,390/844)
var rotated=music;rotated.phase=1.2;_ = render("rotation",rotated)
// Silence must ignore stale analysis; sustain must not repeatedly retrigger.
var stale=GlassAudioState(), zeros=[Float](repeating:0,count:80)
for _ in 0..<120 {glassAudioStep(&stale,zeros,1,1,1,1,1.15,1/30)}
precondition(stale.impact==0 && stale.low==0 && stale.strain==0)
var sustain=state(0..<22,0.8)
precondition(sustain.impact<0.005,"Sustained bass falsely repeats impacts")
for _ in 0..<120 {glassAudioStep(&sustain,zeros,0,0,0,0,1.15,1/30)}
precondition(sustain.low<0.001 && sustain.impact<0.001,"Silence does not decay")
let a=state(0..<80,0.6,24), b=state(0..<80,0.6,60)
precondition(abs(a.low-b.low)<0.001 && abs(a.strain-b.strain)<0.025,"Envelope depends on FPS")
var invalid=GlassAudioState();glassAudioStep(&invalid,[Float](repeating:.nan,count:80),.infinity,.nan,.nan,.nan,1.15,1/30)
precondition(invalid.low.isFinite && invalid.impact.isFinite)
print("PASS: independent bands, impact, silent stale features, sustain rejection, silence release, 24/60 fps, finite values.")
print("GPU timings on \(device.name); host results are not iPhone thermal measurements: \(timings)")

// Optional PCM artifacts from probe_glass_audio.c close the FFT -> GPU path.
for k in 0..<3 {
 let path=output.appendingPathComponent("pcm-\(k).bin")
 if let data=try? Data(contentsOf:path), data.count==MemoryLayout<GlassAudioState>.size {
   var s=data.withUnsafeBytes { $0.loadUnaligned(as:GlassAudioState.self) };s.phase=0.50
   let pixels=render("pcm-\(k)",s)
   precondition(zip(quiet,pixels).filter{$0 != $1}.count>1000,"PCM failed to change Metal frame")
 }
}
