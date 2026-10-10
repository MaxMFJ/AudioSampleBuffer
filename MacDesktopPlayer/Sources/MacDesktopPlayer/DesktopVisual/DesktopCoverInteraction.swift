import AppKit
import CoreGraphics
import simd

/// One transform and deformation field is uploaded to both artwork and lyric particles.
struct DesktopCoverStageUniforms {
    var rotation = SIMD4<Float>(0, 0, 1, 0) // yaw, pitch, zoom, roll
    var pointer = SIMD4<Float>(-10, -10, 0, 0.22) // NDC x/y, force, radius
    var layout = SIMD4<Float>(1, 0.68, 1, 3.2) // screen aspect, cover height, image aspect, camera distance
    var audio = SIMD4<Float>(repeating: 0) // guitar, piano, bass, treble
    var viewport = SIMD4<Float>(1, 1, 1, 0) // drawable size, pixel ratio, time
}

@MainActor
final class DesktopCoverInteraction {
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var velocity = SIMD2<Float>(repeating: 0)
    private var previousMouse: NSPoint?
    private var wasDown = false
    private var dragging = false
    private var hover: Float = 0
    private var lastPressTime: Double = -10
    private var pressPoint = NSPoint.zero
    private var resetHeld = false
    private var pressDepth: Float = 0

    /// Passive polling requires no event tap or input-monitoring permission and never
    /// consumes Finder clicks. Option-drag is the deliberate object-spin gesture.
    func update(view: NSView, dt: Float, coverWidth: Float, coverHeight: Float,
                squareCover: Bool) -> (SIMD4<Float>, SIMD4<Float>) {
        let mouse = NSEvent.mouseLocation
        // AppKit's cached modifier/button state can lag while Finder owns the
        // drag. Read the combined system session without intercepting events.
        let down = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let option = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
        guard let window = view.window else { return (.init(yaw, pitch, 1, 0), .init(-10, -10, 0, 0.22)) }
        let rect = view.convert(view.bounds, to: nil)
        let screenRect = window.convertToScreen(rect)
        let ndc = SIMD2<Float>(Float((mouse.x - screenRect.minX) / max(screenRect.width, 1)) * 2 - 1,
                               Float((mouse.y - screenRect.minY) / max(screenRect.height, 1)) * 2 - 1)
        let coverPosition = SIMD2<Float>(ndc.x / max(coverWidth, 0.001), ndc.y / max(coverHeight, 0.001))
        let onArtwork = squareCover
            ? max(abs(coverPosition.x), abs(coverPosition.y)) <= 1.18
            : simd_length(coverPosition) <= 1.18
        let now = ProcessInfo.processInfo.systemUptime
        // The wallpaper window ignores mouse events, so Finder continues to own
        // desktop clicks. Avoid CGWindowList occlusion checks here: Finder's
        // desktop/icon windows can incorrectly make the artwork look covered.
        let ownPanelAtPointer = (NSApp?.windows ?? []).contains(where: {
            $0 !== window && $0.isVisible && !$0.ignoresMouseEvents &&
            $0.occlusionState.contains(.visible) && $0.frame.contains(mouse)
        })
        let eligible = screenRect.contains(mouse) && !ownPanelAtPointer
        if !down { resetHeld = false }
        // Acquire after Finder activation too: the initial down may precede the
        // next display frame or an application's activation transition.
        if down && option && eligible && onArtwork && !dragging && !resetHeld {
            if !wasDown && now - lastPressTime < 0.32 && hypot(mouse.x - pressPoint.x, mouse.y - pressPoint.y) < 12 {
                yaw = 0; pitch = 0; velocity = .zero
                resetHeld = true
            } else {
                dragging = true
                velocity = .zero
                previousMouse = mouse
                NSLog("[CoverInteraction] Option drag started")
            }
            lastPressTime = now
            pressPoint = mouse
        }
        if dragging && down && option && eligible, let previousMouse {
            let change = SIMD2<Float>(Float(mouse.x - previousMouse.x), Float(mouse.y - previousMouse.y)) * 0.006
            yaw += change.x
            pitch -= change.y
            if dt > 0 { velocity = simd_clamp(change / dt * 0.40, .init(repeating: -5), .init(repeating: 5)) }
        } else {
            if !down || !option || !eligible { dragging = false }
            yaw += velocity.x * dt
            pitch -= velocity.y * dt
            velocity *= exp(-5.5 * dt)
        }
        let target: Float = eligible ? 1 : 0
        hover += (target - hover) * (1 - exp(-12 * max(dt, 0.001)))
        let pressTarget: Float = (eligible && onArtwork && down && !option) ? 1 : 0
        pressDepth += (pressTarget - pressDepth) * (1 - exp(-15 * max(dt, 0.001)))
        previousMouse = mouse
        wasDown = down
        // Positive hover force lifts particles; a held click blends to negative
        // force, which the shared projection interprets as a broad indentation.
        let pointerForce = hover * 0.22 - pressDepth * 1.22
        return (.init(yaw, pitch, 1, 0), .init(ndc.x, ndc.y, pointerForce, 0.30))
    }

    func reset() {
        yaw = 0; pitch = 0; velocity = .zero; dragging = false; resetHeld = false; pressDepth = 0; lastPressTime = -10
    }
}
