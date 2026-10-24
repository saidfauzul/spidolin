// Copyright (C) 2026 Said Fauzul
// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit

/// Transparent, borderless panel covering one display. It never activates the
/// app, so the presented application keeps keyboard focus while you draw.
final class OverlayWindow: NSPanel {
    let inkView: InkView

    init(screen: NSScreen, controller: AppController) {
        inkView = InkView(frame: NSRect(origin: .zero, size: screen.frame.size), controller: controller)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        contentView = inkView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class InkView: NSView {
    private unowned let controller: AppController
    private var cache: CGImage?
    private var cacheValid = false
    private var toast: String?
    private var toastTimer: Timer?
    private var eraserStroke = false

    init(frame: NSRect, controller: AppController) {
        self.controller = controller
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Global screen origin of this view's bottom-left corner.
    private var origin: CGPoint { window?.frame.origin ?? .zero }

    // MARK: document updates

    func committedChanged() {
        cacheValid = false
        needsDisplay = true
    }

    func invalidate(global r: CGRect) {
        guard !r.isNull else { return }
        let local = r.offsetBy(dx: -origin.x, dy: -origin.y).intersection(bounds)
        if !local.isNull, !local.isEmpty { setNeedsDisplay(local) }
    }

    func showToast(_ text: String) {
        toast = text
        needsDisplay = true
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.toast = nil
                self?.needsDisplay = true
            }
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        committedChanged()
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)

        if !cacheValid {
            cache = renderCache()
            cacheValid = true
        }

        ctx.saveGState()
        ctx.beginTransparencyLayer(in: dirtyRect, auxiliaryInfo: nil)
        if let cache { ctx.draw(cache, in: bounds) }
        if let cur = controller.doc.current {
            ctx.translateBy(x: -origin.x, y: -origin.y)
            Renderer.draw(cur, in: ctx)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        if let toast { drawToast(toast) }
    }

    /// Committed strokes are rasterised once per change; only the live stroke
    /// is re-rendered while the mouse moves.
    private func renderCache() -> CGImage? {
        let strokes = controller.doc.strokes
        guard !strokes.isEmpty else { return nil }
        let scale = window?.backingScaleFactor ?? 2
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -origin.x, y: -origin.y)
        let visible = CGRect(origin: origin, size: bounds.size)
        for s in strokes where s.tool == .eraser || s.bounds.intersects(visible) {
            Renderer.draw(s, in: ctx)
        }
        return ctx.makeImage()
    }

    private func drawToast(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let box = NSRect(x: (bounds.width - size.width) / 2 - 16, y: bounds.height - size.height - 70,
                         width: size.width + 32, height: size.height + 14)
        NSColor(white: 0, alpha: 0.72).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        str.draw(at: NSPoint(x: box.minX + 16, y: box.minY + 7))
    }

    // MARK: mouse

    private func globalPoint(_ e: NSEvent) -> CGPoint {
        let p = e.locationInWindow
        return CGPoint(x: p.x + origin.x, y: p.y + origin.y)
    }

    private func pressure(_ e: NSEvent) -> CGFloat {
        e.subtype == .tabletPoint ? CGFloat(max(e.pressure, 0.05)) : 1
    }

    private func beginStroke(_ e: NSEvent, eraser: Bool) {
        var stroke = controller.newStroke(eraser: eraser)
        stroke.straight = e.modifierFlags.contains(.shift) && !eraser
        stroke.points = [globalPoint(e)]
        stroke.pressures = [pressure(e)]
        controller.doc.begin(stroke)
    }

    override func mouseDown(with e: NSEvent) { beginStroke(e, eraser: false) }
    override func rightMouseDown(with e: NSEvent) { beginStroke(e, eraser: true) }
    override func mouseDragged(with e: NSEvent) { controller.doc.add(globalPoint(e), pressure: pressure(e)) }
    override func rightMouseDragged(with e: NSEvent) { controller.doc.add(globalPoint(e), pressure: pressure(e)) }
    override func mouseUp(with e: NSEvent) { controller.doc.end() }
    override func rightMouseUp(with e: NSEvent) { controller.doc.end() }

    // MARK: cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) { controller.cursor.set() }
    override func mouseMoved(with event: NSEvent) { controller.cursor.set() }
}
