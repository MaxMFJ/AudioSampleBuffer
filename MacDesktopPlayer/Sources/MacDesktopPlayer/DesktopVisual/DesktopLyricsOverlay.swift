import AppKit

/// Flat lyric renderer. All placement, sizing and line selection come from the controller.
@MainActor
final class DesktopLyricsOverlay: NSView {
    private var labels: [NSTextField] = []
    private var rows: [DesktopLyricsFrame.Row] = []

    func update(_ frame: DesktopLyricsFrame, highlight: NSColor) {
        rows = frame.rows
        while labels.count > rows.count { labels.removeLast().removeFromSuperview() }
        while labels.count < rows.count {
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
            shadow.shadowBlurRadius = 12
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            label.shadow = shadow
            addSubview(label)
            labels.append(label)
        }
        for (label, row) in zip(labels, rows) {
            if label.stringValue != row.text { label.stringValue = row.text }
            let font = NSFont.systemFont(ofSize: row.fontSize, weight: row.fontWeight)
            if label.font != font { label.font = font }
            label.isHidden = row.text.isEmpty
            label.textColor = row.isActive ? highlight : NSColor.white.withAlphaComponent(row.opacity)
        }
        isHidden = rows.allSatisfy { $0.text.isEmpty }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        for (label, row) in zip(labels, rows) {
            let width = bounds.width * row.maxWidthFraction
            let height = ceil(label.font!.ascender - label.font!.descender + 8)
            label.frame = NSRect(x: bounds.width * row.position.x - width / 2,
                                 y: bounds.height * (1 - row.position.y) - height / 2,
                                 width: width, height: height)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
