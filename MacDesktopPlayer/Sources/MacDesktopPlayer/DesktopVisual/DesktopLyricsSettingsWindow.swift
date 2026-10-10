import AppKit

@MainActor
final class DesktopLyricsSettingsWindowController: NSWindowController {
    private let lyricsController: DesktopLyricsController
    private var surface: DesktopLyricsSurface = .overlay
    private let surfacePicker = NSPopUpButton()
    private let enableButton = NSButton(checkboxWithTitle: "显示歌词", target: nil, action: nil)
    private let lineCount = NSSlider(value: 5, minValue: 1, maxValue: 12, target: nil, action: nil)
    private let lineCountValue = NSTextField(labelWithString: "5")
    private let windowPicker = NSPopUpButton()
    private let layoutPicker = NSPopUpButton()
    private let xSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let ySlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let spacingSlider = NSSlider(value: 0.07, minValue: 0.02, maxValue: 0.15, target: nil, action: nil)
    private let widthSlider = NSSlider(value: 0.82, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let fontMode = NSPopUpButton()
    private let fontSize = NSSlider(value: 0.058, minValue: 0.02, maxValue: 0.1, target: nil, action: nil)
    private let fontSizeValue = NSTextField(labelWithString: "")
    private let inactiveScale = NSSlider(value: 0.78, minValue: 0.3, maxValue: 1, target: nil, action: nil)
    private let inactiveOpacity = NSSlider(value: 0.46, minValue: 0, maxValue: 1, target: nil, action: nil)
    private var controls: [NSControl] { [enableButton, lineCount, windowPicker, layoutPicker, xSlider, ySlider, spacingSlider, widthSlider, fontMode, fontSize, inactiveScale, inactiveOpacity] }

    init(controller: DesktopLyricsController) {
        lyricsController = controller
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "歌词管理"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 600, height: 790)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildInterface() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
        root.translatesAutoresizingMaskIntoConstraints = false
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        window?.contentView = glass
        window?.contentView?.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor), root.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window!.contentView!.topAnchor), root.bottomAnchor.constraint(equalTo: window!.contentView!.bottomAnchor)
        ])
        surfacePicker.addItems(withTitles: ["桌面浮层", "封面舞台"]); surfacePicker.target = self; surfacePicker.action = #selector(surfaceChanged)
        root.addArrangedSubview(row("应用到", surfacePicker))
        root.addArrangedSubview(enableButton); enableButton.target = self; enableButton.action = #selector(valueChanged(_:))
        root.addArrangedSubview(section("显示方式"))
        windowPicker.addItems(withTitles: ["当前行居中", "整组切换"]); windowPicker.target = self; windowPicker.action = #selector(valueChanged(_:))
        layoutPicker.addItems(withTitles: ["纵向排列", "分散排列"]); layoutPicker.target = self; layoutPicker.action = #selector(valueChanged(_:))
        root.addArrangedSubview(row("切换方式", windowPicker)); root.addArrangedSubview(row("排列", layoutPicker))
        lineCount.numberOfTickMarks = 12
        lineCount.allowsTickMarkValuesOnly = true
        root.addArrangedSubview(sliderRow("行数", lineCount, lineCountValue, #selector(valueChanged(_:))))
        root.addArrangedSubview(section("位置与尺寸"))
        root.addArrangedSubview(sliderRow("水平位置", xSlider, nil, #selector(valueChanged(_:))))
        root.addArrangedSubview(sliderRow("垂直位置", ySlider, nil, #selector(valueChanged(_:))))
        root.addArrangedSubview(sliderRow("行间距", spacingSlider, nil, #selector(valueChanged(_:))))
        root.addArrangedSubview(sliderRow("最大宽度", widthSlider, nil, #selector(valueChanged(_:))))
        root.addArrangedSubview(section("字体"))
        fontMode.addItems(withTitles: ["固定字号", "相对高度"]); fontMode.target = self; fontMode.action = #selector(valueChanged(_:))
        root.addArrangedSubview(row("字号模式", fontMode)); root.addArrangedSubview(sliderRow("字号 / 高度比例", fontSize, fontSizeValue, #selector(valueChanged(_:))))
        root.addArrangedSubview(sliderRow("非当前行字号", inactiveScale, nil, #selector(valueChanged(_:))))
        root.addArrangedSubview(sliderRow("非当前行透明度", inactiveOpacity, nil, #selector(valueChanged(_:))))
        let footer = NSTextField(labelWithString: "调整实时生效并自动保存。桌面浮层用于无唱片的背景；封面舞台用于封面点阵或圆形唱片。")
        footer.textColor = .secondaryLabelColor; footer.font = .systemFont(ofSize: 11)
        footer.maximumNumberOfLines = 0
        footer.lineBreakMode = .byWordWrapping
        root.addArrangedSubview(footer)
        let reset = NSButton(title: "恢复当前区域默认设置", target: self, action: #selector(reset)); reset.bezelStyle = .rounded; root.addArrangedSubview(reset)
        for view in root.arrangedSubviews {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -44).isActive = true
        }
    }

    private func section(_ title: String) -> NSView { let label = NSTextField(labelWithString: title); label.font = .boldSystemFont(ofSize: 13); label.textColor = .secondaryLabelColor; return label }
    private var readouts: [NSSlider: NSTextField] = [:]

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 14
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
        return stack
    }

    private func sliderRow(_ title: String, _ slider: NSSlider, _ value: NSTextField?, _ action: Selector) -> NSView {
        slider.target = self
        slider.action = action
        slider.isContinuous = true
        slider.setAccessibilityLabel(title)
        let readout = value ?? NSTextField(labelWithString: "")
        readouts[slider] = readout
        readout.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        readout.alignment = .right
        readout.translatesAutoresizingMaskIntoConstraints = false
        readout.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let content = NSStackView(views: [slider, readout])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 12
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row(title, content)
    }

    private func configuration() -> DesktopLyricsConfiguration { lyricsController.configuration(for: surface) }
    private func refresh() {
        let c = configuration(); enableButton.state = c.isEnabled ? .on : .off; lineCount.doubleValue = Double(c.lineCount); lineCountValue.stringValue = "\(c.lineCount)"
        windowPicker.selectItem(at: c.window == .centered ? 0 : 1); layoutPicker.selectItem(at: { if case .scattered = c.layout { return 1 }; return 0 }())
        xSlider.doubleValue = Double(c.position.x); ySlider.doubleValue = Double(c.position.y); spacingSlider.doubleValue = Double(c.lineSpacing); widthSlider.doubleValue = Double(c.maxWidthFraction)
        switch c.fontSize { case .fixed(let points): fontMode.selectItem(at: 0); fontSize.minValue = 12; fontSize.maxValue = 80; fontSize.doubleValue = Double(points); fontSizeValue.stringValue = "\(Int(points)) pt"
        case .relativeToHeight(let fraction, _, _): fontMode.selectItem(at: 1); fontSize.minValue = 0.02; fontSize.maxValue = 0.1; fontSize.doubleValue = Double(fraction); fontSizeValue.stringValue = String(format: "%.1f%%", fraction * 100) }
        inactiveScale.doubleValue = Double(c.inactiveFontScale); inactiveOpacity.doubleValue = Double(c.inactiveOpacity)
        for slider in [xSlider, ySlider, spacingSlider, widthSlider, inactiveScale, inactiveOpacity] {
            readouts[slider]?.stringValue = String(format: "%.0f%%", slider.doubleValue * 100)
        }
        controls.forEach { $0.isEnabled = c.isEnabled || $0 === enableButton }
        if case .scattered = c.layout { spacingSlider.isEnabled = false }

    }

    @objc private func surfaceChanged() { surface = surfacePicker.indexOfSelectedItem == 0 ? .overlay : .coverStage; refresh() }
    @objc private func valueChanged(_ sender: NSControl) {
        var c = configuration()
        c.isEnabled = enableButton.state == .on
        c.lineCount = Int(lineCount.doubleValue.rounded())
        c.window = windowPicker.indexOfSelectedItem == 0 ? .centered : .grouped
        if sender === layoutPicker {
            if layoutPicker.indexOfSelectedItem == 0 { c.layout = .column }
            else {
                // Spread any requested number of lines across two columns.
                let rows = (c.lineCount + 1) / 2
                c.layout = .scattered((0..<c.lineCount).map { index in
                    CGPoint(x: index % 2 == 0 ? -0.22 : 0.22,
                            y: CGFloat(index / 2) * 0.12 - CGFloat(rows - 1) * 0.06)
                })
            }
        } else if sender === lineCount, case .scattered = c.layout {
            let rows = (c.lineCount + 1) / 2
            c.layout = .scattered((0..<c.lineCount).map { index in
                CGPoint(x: index % 2 == 0 ? -0.22 : 0.22,
                        y: CGFloat(index / 2) * 0.12 - CGFloat(rows - 1) * 0.06)
            })
        }
        c.position = CGPoint(x: xSlider.doubleValue, y: ySlider.doubleValue)
        c.lineSpacing = spacingSlider.doubleValue
        c.maxWidthFraction = widthSlider.doubleValue
        c.inactiveFontScale = inactiveScale.doubleValue
        c.inactiveOpacity = inactiveOpacity.doubleValue
        if sender === fontMode {
            // The two modes have different units; never reuse the previous slider value.
            c.fontSize = fontMode.indexOfSelectedItem == 0 ? .fixed(36)
                : .relativeToHeight(fraction: 0.058, minimum: 40, maximum: 58)
        } else if sender === fontSize {
            if fontMode.indexOfSelectedItem == 0 { c.fontSize = .fixed(fontSize.doubleValue) }
            else {
                var minimum: CGFloat = 40, maximum: CGFloat = 58
                if case .relativeToHeight(_, let savedMin, let savedMax) = c.fontSize {
                    minimum = savedMin; maximum = savedMax
                }
                c.fontSize = .relativeToHeight(fraction: fontSize.doubleValue, minimum: minimum, maximum: maximum)
            }
        }
        lyricsController.setConfiguration(c, for: surface)
        refresh()
    }
    @objc private func reset() { lyricsController.resetConfiguration(for: surface); refresh() }
}
