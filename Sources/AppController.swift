// Copyright (C) 2026 Said Fauzul
// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import Carbon.HIToolbox
import ServiceManagement

let commandNotification = Notification.Name("id.spidolin.command")

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let doc = InkDocument()
    private var overlays: [OverlayWindow] = []
    private var statusItem: NSStatusItem!
    private var drawKeys: [UInt32] = []
    private(set) var drawing = false
    private var hidden = false
    private(set) var cursor = NSCursor.crosshair

    private var tool: Tool = .pen { didSet { settingsChanged() } }
    private var colorIndex = 0 { didSet { settingsChanged() } }
    private var width: CGFloat = 5 { didSet { settingsChanged() } }

    private var color: NSColor { palette[colorIndex].color }

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        doc.onCommittedChange = { [weak self] in self?.overlays.forEach { $0.inkView.committedChanged() } }
        doc.onLiveChange = { [weak self] r in self?.overlays.forEach { $0.inkView.invalidate(global: r) } }

        rebuildOverlays()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildOverlays() }
        }
        DistributedNotificationCenter.default().addObserver(forName: commandNotification, object: nil,
                                                            queue: .main) { [weak self] note in
            let command = note.object as? String
            MainActor.assumeIsolated { self?.run(command: command) }
        }

        setupStatusItem()
        registerGlobalKeys()
        updateCursor()
        showToast("Spidolin is running. Press F9 or ⌃⌥D to draw.")
    }

    private func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0, controller: self) }
        for w in overlays {
            w.ignoresMouseEvents = !drawing
            if !hidden { w.orderFrontRegardless() }
        }
    }

    // MARK: commands (shared by hotkeys, menu and command line)

    func run(command: String?) {
        switch command {
        case "toggle": toggleDrawing()
        case "clear": doc.clear()
        case "undo": doc.undo()
        case "redo": doc.redo()
        case "visibility": toggleVisibility()
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }

    @objc func toggleDrawing() { setDrawing(!drawing) }

    func setDrawing(_ on: Bool) {
        guard on != drawing else { return }
        if on && hidden { toggleVisibility() }
        drawing = on
        if !on { doc.end() }
        overlays.forEach { $0.ignoresMouseEvents = !on }
        if on {
            registerDrawKeys()
            cursor.set()
            showToast("Drawing: \(settingsSummary)  ·  Esc to finish")
        } else {
            drawKeys.forEach { HotKeys.shared.unregister($0) }
            drawKeys = []
            NSCursor.arrow.set()
            showToast("Drawing mode off")
        }
        updateStatusIcon()
    }

    @objc func toggleVisibility() {
        hidden.toggle()
        if hidden {
            setDrawing(false)
            overlays.forEach { $0.orderOut(nil) }
        } else {
            overlays.forEach { $0.orderFrontRegardless() }
        }
        updateStatusIcon()
    }

    @objc func clearAll() { doc.clear() }
    @objc func undo() { doc.undo() }
    @objc func redo() { doc.redo() }

    // MARK: tool state

    func newStroke(eraser: Bool) -> Stroke {
        let t: Tool = eraser ? .eraser : tool
        let w = t == .eraser ? max(24, width * 5) : width
        return Stroke(tool: t, color: color.cgColor, width: w)
    }

    private var settingsSummary: String {
        tool == .eraser ? "\(tool.title) · \(Int(width)) px" : "\(tool.title) · \(palette[colorIndex].name) · \(Int(width)) px"
    }

    private func settingsChanged() {
        UserDefaults.standard.set(tool.rawValue, forKey: "tool")
        UserDefaults.standard.set(colorIndex, forKey: "color")
        UserDefaults.standard.set(Double(width), forKey: "width")
        updateCursor()
        if drawing {
            cursor.set()
            showToast(settingsSummary)
        }
    }

    private func loadSettings() {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "tool"), let t = Tool(rawValue: raw) { tool = t }
        let c = d.integer(forKey: "color")
        if palette.indices.contains(c) { colorIndex = c }
        let w = d.double(forKey: "width")
        if w > 0 { width = CGFloat(w) }
    }

    private func stepWidth(_ delta: Int) {
        let i = widthSteps.firstIndex { $0 >= width } ?? widthSteps.count - 1
        width = widthSteps[min(max(i + delta, 0), widthSteps.count - 1)]
    }

    /// A ring the size of the brush, in the current colour.
    private func updateCursor() {
        if tool.isShape {
            cursor = .crosshair
            return
        }
        let brush = tool == .eraser ? max(24, width * 5) : (tool == .marker ? width * 3 : width)
        let d = min(max(brush, 8), 96) + 4
        let ring = tool == .eraser ? NSColor.gray : color
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { r in
            let circle = NSBezierPath(ovalIn: r.insetBy(dx: 2, dy: 2))
            circle.lineWidth = 3
            NSColor.white.withAlphaComponent(0.85).setStroke()
            circle.stroke()
            circle.lineWidth = 1.5
            ring.setStroke()
            circle.stroke()
            NSColor.black.withAlphaComponent(0.6).setFill()
            NSBezierPath(ovalIn: NSRect(x: r.midX - 1, y: r.midY - 1, width: 2, height: 2)).fill()
            return true
        }
        cursor = NSCursor(image: img, hotSpot: NSPoint(x: d / 2, y: d / 2))
    }

    private func showToast(_ text: String) {
        let mouse = NSEvent.mouseLocation
        let target = overlays.first { $0.frame.contains(mouse) } ?? overlays.first
        target?.inkView.showToast(text)
    }

    // MARK: hotkeys

    /// Gromit-MPX defaults (F9/F8 family) plus ⌃⌥ letters, because F-keys on a
    /// MacBook are media keys unless Fn is held.
    private func registerGlobalKeys() {
        let hk = HotKeys.shared
        let co = controlKey | optionKey
        hk.register(kVK_F9) { [weak self] in self?.toggleDrawing() }
        hk.register(kVK_F9, shiftKey) { [weak self] in self?.doc.clear() }
        hk.register(kVK_F9, controlKey) { [weak self] in self?.toggleVisibility() }
        hk.register(kVK_F9, optionKey) { NSApp.terminate(nil) }
        hk.register(kVK_F8) { [weak self] in self?.doc.undo() }
        hk.register(kVK_F8, shiftKey) { [weak self] in self?.doc.redo() }
        hk.register(kVK_ANSI_D, co) { [weak self] in self?.toggleDrawing() }
        hk.register(kVK_ANSI_C, co) { [weak self] in self?.doc.clear() }
        hk.register(kVK_ANSI_H, co) { [weak self] in self?.toggleVisibility() }
        hk.register(kVK_ANSI_Z, co) { [weak self] in self?.doc.undo() }
        hk.register(kVK_ANSI_Z, co | shiftKey) { [weak self] in self?.doc.redo() }
    }

    /// Plain keys are only grabbed while drawing mode is on.
    private func registerDrawKeys() {
        let hk = HotKeys.shared
        var ids: [UInt32?] = []
        ids.append(hk.register(kVK_Escape) { [weak self] in self?.setDrawing(false) })
        let toolKeys: [(Int, Tool)] = [(kVK_ANSI_P, .pen), (kVK_ANSI_M, .marker), (kVK_ANSI_A, .arrow),
                                       (kVK_ANSI_L, .line), (kVK_ANSI_R, .rect), (kVK_ANSI_O, .ellipse),
                                       (kVK_ANSI_E, .eraser)]
        for (key, t) in toolKeys {
            ids.append(hk.register(key) { [weak self] in self?.tool = t })
        }
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8]
        for (i, key) in digits.enumerated() where i < palette.count {
            ids.append(hk.register(key) { [weak self] in
                self?.colorIndex = i
                if self?.tool == .eraser { self?.tool = .pen }
            })
        }
        ids.append(hk.register(kVK_ANSI_LeftBracket) { [weak self] in self?.stepWidth(-1) })
        ids.append(hk.register(kVK_ANSI_RightBracket) { [weak self] in self?.stepWidth(1) })
        ids.append(hk.register(kVK_ANSI_Z, cmdKey) { [weak self] in self?.doc.undo() })
        ids.append(hk.register(kVK_ANSI_Z, cmdKey | shiftKey) { [weak self] in self?.doc.redo() })
        ids.append(hk.register(kVK_Delete) { [weak self] in self?.doc.clear() })
        drawKeys = ids.compactMap { $0 }
    }

    // MARK: menu bar (Gromit-MPX's tray icon)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let name = drawing ? "pencil.tip.crop.circle.fill" : (hidden ? "eye.slash" : "pencil.tip")
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: "Spidolin") {
            img.isTemplate = true
            button.image = img
            button.title = ""
        } else {
            button.image = nil
            button.title = drawing ? "✎●" : "✎"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        @discardableResult
        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = []) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = self
            menu.addItem(i)
            return i
        }

        item(drawing ? "Stop drawing  (F9 / ⌃⌥D)" : "Start drawing  (F9 / ⌃⌥D)", #selector(toggleDrawing))
        item("Undo  (F8 / ⌃⌥Z)", doc.canUndo ? #selector(undo) : nil)
        item("Redo  (⇧F8 / ⌃⌥⇧Z)", doc.canRedo ? #selector(redo) : nil)
        item("Clear screen  (⇧F9 / ⌃⌥C)", doc.isEmpty ? nil : #selector(clearAll))
        item(hidden ? "Show drawing  (⌃F9 / ⌃⌥H)" : "Hide drawing  (⌃F9 / ⌃⌥H)", #selector(toggleVisibility))
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Tool", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for (i, t) in Tool.allCases.enumerated() {
            let m = item("\(t.title)  (\(t.key))", #selector(pickTool(_:)))
            m.tag = i
            m.state = t == tool ? .on : .off
        }
        menu.addItem(.separator())

        let colors = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for (i, c) in palette.enumerated() {
            let m = NSMenuItem(title: "\(c.name)  (\(i + 1))", action: #selector(pickColor(_:)), keyEquivalent: "")
            m.target = self
            m.tag = i
            m.state = i == colorIndex ? .on : .off
            m.image = swatch(c.color)
            colorMenu.addItem(m)
        }
        colors.submenu = colorMenu
        colors.image = swatch(color)
        menu.addItem(colors)

        let sizes = NSMenuItem(title: "Width: \(Int(width)) px", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (i, w) in widthSteps.enumerated() {
            let m = NSMenuItem(title: "\(Int(w)) px", action: #selector(pickWidth(_:)), keyEquivalent: "")
            m.target = self
            m.tag = i
            m.state = w == width ? .on : .off
            sizeMenu.addItem(m)
        }
        sizes.submenu = sizeMenu
        menu.addItem(sizes)
        menu.addItem(.separator())

        let help = NSMenuItem(title: "While drawing: P M A L R O E = tool, 1–8 = color, [ ] = width,",
                              action: nil, keyEquivalent: "")
        help.isEnabled = false
        menu.addItem(help)
        let help2 = NSMenuItem(title: "right-click = erase, ⇧ = straight line, Esc = finish", action: nil, keyEquivalent: "")
        help2.isEnabled = false
        menu.addItem(help2)
        menu.addItem(.separator())
        let loginItem = item("Launch at login", #selector(toggleLaunchAtLogin))
        switch SMAppService.mainApp.status {
        case .enabled: loginItem.state = .on
        case .requiresApproval:
            loginItem.state = .mixed
            loginItem.title = "Launch at login (needs approval in System Settings)"
        default: loginItem.state = .off
        }
        item("Quit Spidolin  (⌥F9)", #selector(quit), "q")
    }

    private func swatch(_ c: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            c.setFill()
            NSBezierPath(ovalIn: r).fill()
            NSColor.gray.setStroke()
            NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }

    @objc private func pickTool(_ sender: NSMenuItem) { tool = Tool.allCases[sender.tag] }
    @objc private func pickColor(_ sender: NSMenuItem) {
        colorIndex = sender.tag
        if tool == .eraser { tool = .pen }
    }
    @objc private func pickWidth(_ sender: NSMenuItem) { width = widthSteps[sender.tag] }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: launch at login

    /// Registers the app itself as a login item (macOS 13+ ServiceManagement);
    /// the user can also switch it off in System Settings > General > Login Items.
    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
                showToast("Spidolin will no longer launch at login")
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
                if service.status == .requiresApproval {
                    showToast("Allow Spidolin in System Settings > General > Login Items")
                    SMAppService.openSystemSettingsLoginItems()
                } else {
                    showToast("Spidolin will launch at login")
                }
            }
        } catch {
            showToast("Couldn't change the login setting: \(error.localizedDescription)")
        }
    }
}
