import AppKit
import SwiftUI

enum WidgetSizePreset: String, CaseIterable, Identifiable {
    case compact, standard, spacious
    var id: String { rawValue }
    var size: NSSize {
        switch self {
        case .compact: return NSSize(width: 640, height: 460)
        case .standard: return NSSize(width: 808, height: 598)
        case .spacious: return NSSize(width: 1040, height: 740)
        }
    }
    var title: String {
        let name = self == .compact ? L("紧凑") : (self == .standard ? L("标准") : L("宽敞"))
        return "\(name) · \(Int(size.width)) × \(Int(size.height))"
    }
}

enum WidgetSizing {
    static let minimum = NSSize(width: 560, height: 380)
    static let maximum = NSSize(width: 1600, height: 1100)

    /// Anchor the upper-left corner, constrain the result to the current display.
    static func frame(from original: NSRect, size: NSSize, visible: NSRect) -> NSRect {
        let width = min(maximum.width, visible.width, max(minimum.width, size.width))
        let height = min(maximum.height, visible.height, max(minimum.height, size.height))
        let x = max(visible.minX, min(original.minX, visible.maxX - width))
        let top = min(visible.maxY, max(original.maxY, visible.minY + height))
        return NSRect(x: x, y: top - height, width: width, height: height)
    }
}

struct WindowResizeGrip: NSViewRepresentable {
    final class GripView: NSView {
        private var initialFrame: NSRect?
        private var initialPoint = NSPoint.zero
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.withAlphaComponent(0.65).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.4
            path.lineCapStyle = .round
            for length: CGFloat in [4, 8, 12] {
                path.move(to: NSPoint(x: bounds.maxX - 4 - length, y: 4))
                path.line(to: NSPoint(x: bounds.maxX - 4, y: 4 + length))
            }
            path.stroke()
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            initialFrame = window.frame
            initialPoint = window.convertPoint(toScreen: event.locationInWindow)
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let initialFrame, let screen = window.screen ?? NSScreen.main else { return }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            let size = NSSize(width: initialFrame.width + point.x - initialPoint.x,
                              height: initialFrame.height - (point.y - initialPoint.y))
            window.setFrame(WidgetSizing.frame(from: initialFrame, size: size, visible: screen.visibleFrame), display: true)
        }
        override func mouseUp(with event: NSEvent) { initialFrame = nil }
    }
    func makeNSView(context: Context) -> NSView {
        let view = GripView()
        view.toolTip = L("拖动调整小组件大小")
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel(L("拖动调整小组件大小"))
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
