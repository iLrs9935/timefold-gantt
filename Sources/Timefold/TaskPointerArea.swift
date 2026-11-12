import AppKit
import SwiftUI

enum TaskDragMode { case move, start, end }

/// Keep mouse tracking on a fixed row while the drawn task bar changes position or length.
struct TaskPointerArea: NSViewRepresentable {
    var label: String
    var bar: CGRect? = nil
    var canResizeStart = false
    var canResizeEnd = false
    var select: (NSEvent.ModifierFlags) -> Void
    var edit: () -> Void
    var singleClick: (() -> Void)? = nil
    var change: (TaskDragMode, CGFloat) -> Void = { _, _ in }
    var finish: () -> Void = {}
    var rangeDrag: ((CGFloat) -> Void)? = nil
    var help = "单击选择；⌘点击多选；Shift点击连续选择；双击编辑任务信息"

    final class PointerView: NSView {
        var configuration: TaskPointerArea!
        private var origin: NSPoint?
        private var mode: TaskDragMode = .move
        private var draggable = false
        private var dragging = false
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private func dragMode(at point: NSPoint) -> TaskDragMode {
            guard let bar = configuration.bar else { return .move }
            let handleWidth = min(10, bar.width / 3)
            if configuration.canResizeStart && point.x < bar.minX + handleWidth { return .start }
            if configuration.canResizeEnd && point.x > bar.maxX - handleWidth { return .end }
            return .move
        }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            window.makeFirstResponder(self)
            configuration.select(event.modifierFlags)
            if event.clickCount >= 2 {
                origin = nil
                configuration.edit()
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            draggable = configuration.bar?.insetBy(dx: 0, dy: -4).contains(point) ?? false
            mode = dragMode(at: point)
            origin = window.convertPoint(toScreen: event.locationInWindow)
            dragging = false
        }
        override func mouseDragged(with event: NSEvent) {
            guard let origin, let window else { return }
            if !draggable, let rangeDrag = configuration.rangeDrag {
                let point = window.convertPoint(toScreen: event.locationInWindow)
                if abs(point.y - origin.y) >= 3 { dragging = true; rangeDrag(origin.y - point.y) }
                return
            }
            guard draggable else { return }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            let delta = point.x - origin.x
            guard dragging || abs(delta) >= 3 else { return }
            dragging = true
            configuration.change(mode, delta)
        }
        override func mouseUp(with event: NSEvent) {
            if dragging { configuration.finish() }
            else if event.clickCount == 1 { configuration.singleClick?() }
            origin = nil
            dragging = false
            draggable = false
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 || event.keyCode == 76 { configuration.edit() }
            else if event.keyCode == 51 || event.keyCode == 117 {
                NotificationCenter.default.post(name: .deleteGanttSelection, object: nil)
            } else { super.keyDown(with: event) }
        }
        override func resetCursorRects() {
            guard let bar = configuration.bar else { return }
            addCursorRect(bar.insetBy(dx: 0, dy: -4), cursor: .openHand)
            let width = min(10, bar.width / 3)
            if configuration.canResizeStart {
                addCursorRect(NSRect(x: bar.minX, y: bar.minY - 4, width: width, height: bar.height + 8), cursor: .resizeLeftRight)
            }
            if configuration.canResizeEnd {
                addCursorRect(NSRect(x: bar.maxX - width, y: bar.minY - 4, width: width, height: bar.height + 8), cursor: .resizeLeftRight)
            }
        }
        override func accessibilityPerformPress() -> Bool { configuration.edit(); return true }
    }

    func makeNSView(context: Context) -> PointerView {
        let view = PointerView()
        view.configuration = self
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(label)
        view.setAccessibilityHelp(help)
        return view
    }
    func updateNSView(_ view: PointerView, context: Context) {
        view.configuration = self
        view.setAccessibilityLabel(label)
        view.setAccessibilityHelp(help)
        view.window?.invalidateCursorRects(for: view)
    }
}

extension Notification.Name {
    static let selectAllGanttTasks = Notification.Name("Timefold.selectAllTasks")
    static let deleteGanttSelection = Notification.Name("Timefold.deleteSelection")
}
