// Spidolin — on-screen annotation for macOS
// Copyright (C) 2026 Said Fauzul
// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit

enum Tool: String, CaseIterable {
    case pen, marker, arrow, line, rect, ellipse, eraser

    var title: String {
        switch self {
        case .pen: return "Pen"
        case .marker: return "Highlighter"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rect: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .eraser: return "Eraser"
        }
    }

    /// Key that selects the tool while drawing mode is on.
    var key: String {
        switch self {
        case .pen: return "P"
        case .marker: return "M"
        case .arrow: return "A"
        case .line: return "L"
        case .rect: return "R"
        case .ellipse: return "O"
        case .eraser: return "E"
        }
    }

    /// Shapes only keep their first and last point.
    var isShape: Bool { self == .line || self == .rect || self == .ellipse }
}

struct PaletteColor {
    let name: String
    let color: NSColor
}

let palette: [PaletteColor] = [
    PaletteColor(name: "Red", color: NSColor(srgbRed: 0.93, green: 0.20, blue: 0.20, alpha: 1)),
    PaletteColor(name: "Blue", color: NSColor(srgbRed: 0.16, green: 0.45, blue: 0.96, alpha: 1)),
    PaletteColor(name: "Green", color: NSColor(srgbRed: 0.18, green: 0.74, blue: 0.30, alpha: 1)),
    PaletteColor(name: "Yellow", color: NSColor(srgbRed: 1.00, green: 0.84, blue: 0.08, alpha: 1)),
    PaletteColor(name: "Orange", color: NSColor(srgbRed: 1.00, green: 0.55, blue: 0.10, alpha: 1)),
    PaletteColor(name: "Purple", color: NSColor(srgbRed: 0.62, green: 0.32, blue: 0.95, alpha: 1)),
    PaletteColor(name: "White", color: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)),
    PaletteColor(name: "Black", color: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)),
]

let widthSteps: [CGFloat] = [2, 3, 5, 8, 12, 18, 26]

/// One annotation. Points are in global screen coordinates (AppKit, origin at
/// the bottom-left of the primary screen) so a stroke can span several displays.
struct Stroke {
    var tool: Tool
    var color: CGColor
    var width: CGFloat
    /// Pen/marker/arrow drawn with Shift held: a straight segment.
    var straight = false
    var points: [CGPoint] = []
    var pressures: [CGFloat] = []

    var bounds: CGRect {
        guard let f = points.first else { return .null }
        var r = CGRect(origin: f, size: .zero)
        for p in points { r = r.union(CGRect(origin: p, size: .zero)) }
        let pad = width * (tool == .marker ? 2 : 1) + max(16, width * 4)
        return r.insetBy(dx: -pad, dy: -pad)
    }
}

/// Vector document shared by every overlay. Undo works on whole snapshots, so
/// "clear" is undoable too (Gromit-MPX keeps raster snapshots instead).
@MainActor
final class InkDocument {
    private(set) var strokes: [Stroke] = []
    private(set) var current: Stroke?
    private var undoStack: [[Stroke]] = []
    private var redoStack: [[Stroke]] = []
    private var lastLiveBounds = CGRect.null
    private let maxUndo = 100

    var onCommittedChange: (() -> Void)?
    var onLiveChange: ((CGRect) -> Void)?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isEmpty: Bool { strokes.isEmpty }

    func begin(_ stroke: Stroke) {
        current = stroke
        lastLiveBounds = .null
        liveChanged()
    }

    func add(_ p: CGPoint, pressure: CGFloat) {
        guard var s = current else { return }
        if s.tool.isShape || s.straight {
            s.points = [s.points.first ?? p, p]
            s.pressures = [1, 1]
        } else {
            if let last = s.points.last, hypot(last.x - p.x, last.y - p.y) < 0.5 { return }
            s.points.append(p)
            s.pressures.append(pressure)
        }
        current = s
        liveChanged()
    }

    func end() {
        guard let s = current else { return }
        current = nil
        commit(strokes + [s])
    }

    func clear() {
        cancelCurrent()
        guard !strokes.isEmpty else { return }
        commit([])
    }

    func undo() {
        cancelCurrent()
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = prev
        onCommittedChange?()
    }

    func redo() {
        cancelCurrent()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
        onCommittedChange?()
    }

    func cancelCurrent() {
        guard current != nil else { return }
        current = nil
        onLiveChange?(lastLiveBounds)
        lastLiveBounds = .null
    }

    private func commit(_ new: [Stroke]) {
        undoStack.append(strokes)
        if undoStack.count > maxUndo { undoStack.removeFirst() }
        redoStack.removeAll()
        strokes = new
        lastLiveBounds = .null
        onCommittedChange?()
    }

    private func liveChanged() {
        guard let s = current else { return }
        let b = s.bounds
        onLiveChange?(b.union(lastLiveBounds))
        lastLiveBounds = b
    }
}

enum Renderer {
    static func draw(_ s: Stroke, in ctx: CGContext) {
        guard let first = s.points.first, let last = s.points.last else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(s.color)
        ctx.setFillColor(s.color)
        ctx.setLineWidth(s.width)

        switch s.tool {
        case .pen, .arrow:
            if s.pressures.contains(where: { $0 < 0.999 }) {
                strokeWithPressure(s, ctx)
            } else {
                ctx.addPath(smoothPath(s.points))
                ctx.strokePath()
            }
            if s.tool == .arrow { arrowHead(s, ctx) }
        case .marker:
            ctx.setStrokeColor(s.color.copy(alpha: 0.38) ?? s.color)
            ctx.setLineWidth(s.width * 3)
            ctx.addPath(smoothPath(s.points))
            ctx.strokePath()
        case .eraser:
            ctx.setBlendMode(.clear)
            ctx.addPath(smoothPath(s.points))
            ctx.strokePath()
        case .line:
            ctx.move(to: first)
            ctx.addLine(to: last)
            ctx.strokePath()
        case .rect:
            ctx.stroke(rect(first, last))
        case .ellipse:
            ctx.strokeEllipse(in: rect(first, last))
        }
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Quadratic curves through segment midpoints, for a smoother pen line.
    static func smoothPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let f = pts.first else { return path }
        path.move(to: f)
        if pts.count < 3 {
            path.addLine(to: pts.last!)
            return path
        }
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts.last!)
        return path
    }

    private static func strokeWithPressure(_ s: Stroke, _ ctx: CGContext) {
        let pts = s.points
        if pts.count == 1 {
            ctx.move(to: pts[0]); ctx.addLine(to: pts[0]); ctx.strokePath()
            return
        }
        for i in 1..<pts.count {
            let p = (s.pressures[i - 1] + s.pressures[i]) / 2
            ctx.setLineWidth(max(0.5, s.width * max(0.15, p * 1.6)))
            ctx.move(to: pts[i - 1])
            ctx.addLine(to: pts[i])
            ctx.strokePath()
        }
    }

    private static func arrowHead(_ s: Stroke, _ ctx: CGContext) {
        guard s.points.count >= 2, let tip = s.points.last else { return }
        let len = max(14, s.width * 4)
        var base = s.points[0]
        for p in s.points.reversed() where hypot(tip.x - p.x, tip.y - p.y) >= len {
            base = p
            break
        }
        guard hypot(tip.x - base.x, tip.y - base.y) >= 1 else { return }
        let a = atan2(tip.y - base.y, tip.x - base.x)
        let spread = CGFloat.pi / 7
        ctx.move(to: tip)
        ctx.addLine(to: CGPoint(x: tip.x - len * cos(a - spread), y: tip.y - len * sin(a - spread)))
        ctx.addLine(to: CGPoint(x: tip.x - len * cos(a + spread), y: tip.y - len * sin(a + spread)))
        ctx.closePath()
        ctx.fillPath()
    }
}
