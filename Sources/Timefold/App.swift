import AppKit
import Carbon
import SwiftUI

@main
struct TimefoldMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, attachedSheet == nil, NSApp.keyWindow === self {
            orderOut(nil)
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: WidgetWindow!
    private var statusItem: NSStatusItem!
    private var store: ProjectStore!
    private var refreshTimer: Timer?
    private var globalHotKey: GlobalHotKey?
    private var frameName = "Timefold.mainWidget"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let previewMode = CommandLine.arguments.contains("--preview")
        if previewMode {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Timefold-preview-\(ProcessInfo.processInfo.processIdentifier).json")
            store = ProjectStore(fileURL: url, defaults: UserDefaults(suiteName: "Timefold.Preview")!)
        } else {
            store = ProjectStore()
        }
        NotificationCenter.default.addObserver(forName: .timefoldLanguageChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.installMenu()
                self?.window?.title = L("时序 · 桌面甘特图")
            }
        }
        installMenu()
        createWindow(previewMode: previewMode)
        createStatusItem()
        if !previewMode {
            globalHotKey = GlobalHotKey { [weak self] in
                Task { @MainActor in self?.toggleWidget() }
            }
            changeShortcut(store.shortcut)
        }
        showWidget()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.objectWillChange.send() }
        }
    }

    private func createWindow(previewMode: Bool) {
        frameName = previewMode ? "Timefold.preview" : "Timefold.mainWidget"
        let size = NSSize(width: 808, height: 598)
        window = WidgetWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.title = L("时序 · 桌面甘特图")
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = WidgetSizing.minimum
        window.maxSize = WidgetSizing.maximum
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = store.pinned ? .floating : .normal
        window.delegate = self
        let actions = WidgetActions(hide: { [weak self] in self?.hideWidget() },
                                    pin: { [weak self] pinned in self?.window.level = pinned ? .floating : .normal },
                                    resize: { [weak self] size in self?.resizeWidget(to: size) },
                                    shortcut: { [weak self] value in self?.changeShortcut(value) })
        let host = NSHostingView(rootView: WidgetView(store: store, actions: actions))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        if !window.setFrameUsingName(frameName) {
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                window.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 36, y: frame.maxY - size.height - 50))
            } else { window.center() }
        }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) { window.center() }
        window.setFrameAutosaveName(frameName)
        window.isExcludedFromWindowsMenu = true
    }

    private func resizeWidget(to size: NSSize) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let frame = WidgetSizing.frame(from: window.frame, size: size, visible: screen.visibleFrame)
        window.setFrame(frame, display: true, animate: true)
        window.saveFrame(usingName: frameName)
    }

    private func changeShortcut(_ shortcut: GlobalShortcut) {
        guard let globalHotKey else { return }
        let status = globalHotKey.register(shortcut)
        if status == noErr {
            store.shortcut = shortcut
            store.shortcutError = nil
            statusItem.button?.toolTip = L("时序 · \(shortcut == .disabled ? L("点击呼出") : shortcut.display + L(" 呼出 / 收起"))")
        } else {
            store.shortcutError = status == eventHotKeyExistsErr
                ? L("\(shortcut.display) 已被占用，请在菜单中换一个快捷键。")
                : L("无法注册快捷键（\(status)），请在菜单中重新选择。")
        }
    }

    private func installMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("显示时序"), action: #selector(showWidget), keyEquivalent: "1").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("退出时序"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        bar.addItem(appItem)

        let fileItem = NSMenuItem(title: L("文件"), action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: L("文件"))
        fileMenu.addItem(withTitle: L("新建任务"), action: #selector(newTask), keyEquivalent: "n").target = self
        let textPlanItem = fileMenu.addItem(withTitle: L("文字排期…"), action: #selector(parseTextPlan), keyEquivalent: "n")
        textPlanItem.keyEquivalentModifierMask = [.command, .shift]
        textPlanItem.target = self
        fileItem.submenu = fileMenu
        bar.addItem(fileItem)

        let editItem = NSMenuItem(title: L("编辑"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: L("编辑"))
        editMenu.addItem(withTitle: L("撤销任务修改"), action: #selector(undoTask), keyEquivalent: "z").target = self
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("全选"), action: #selector(selectAll(_:)), keyEquivalent: "a").target = self
        editMenu.addItem(withTitle: L("删除选中任务"), action: #selector(deleteSelection), keyEquivalent: "").target = self
        editItem.submenu = editMenu
        bar.addItem(editItem)
        NSApp.mainMenu = bar
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: L("时序甘特图"))
            button.toolTip = L("时序 · 桌面甘特图（右键打开菜单）")
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: window.isVisible ? L("收起小组件") : L("显示小组件"), action: #selector(toggleWidget), keyEquivalent: "").target = self
            menu.addItem(withTitle: L("新建任务"), action: #selector(newTask), keyEquivalent: "").target = self
            let pin = menu.addItem(withTitle: L("始终置顶"), action: #selector(togglePin), keyEquivalent: "")
            pin.target = self
            pin.state = store.pinned ? .on : .off
            let shortcutItem = NSMenuItem(title: L("呼出快捷键"), action: nil, keyEquivalent: "")
            let shortcutMenu = NSMenu()
            for shortcut in GlobalShortcut.allCases {
                let item = shortcutMenu.addItem(withTitle: shortcut.display, action: #selector(selectShortcut(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = shortcut.rawValue
                item.state = store.shortcut == shortcut ? .on : .off
            }
            shortcutItem.submenu = shortcutMenu
            menu.addItem(shortcutItem)
            let sizeItem = NSMenuItem(title: L("窗口大小"), action: nil, keyEquivalent: "")
            let sizeMenu = NSMenu()
            for preset in WidgetSizePreset.allCases {
                let item = sizeMenu.addItem(withTitle: preset.title, action: #selector(selectSize(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = preset.rawValue
            }
            sizeItem.submenu = sizeMenu
            menu.addItem(sizeItem)
            menu.addItem(.separator())
            menu.addItem(withTitle: L("退出时序"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            if let button = statusItem.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
            }
        } else { toggleWidget() }
    }

    @objc private func toggleWidget() {
        if window.isVisible && NSApp.isActive { hideWidget() }
        else { showWidget() }
    }
    @objc private func selectShortcut(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let shortcut = GlobalShortcut(rawValue: raw) else { return }
        changeShortcut(shortcut)
    }
    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = WidgetSizePreset(rawValue: raw) else { return }
        resizeWidget(to: preset.size)
    }
    @objc func showWidget() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    @objc private func hideWidget() { window.orderOut(nil) }
    @objc private func newTask() {
        showWidget()
        NotificationCenter.default.post(name: .newGanttTask, object: nil)
    }
    @objc private func undoTask() {
        if let field = NSApp.keyWindow?.firstResponder as? NSTextView, field.isEditable { field.undoManager?.undo() }
        else if window.attachedSheet == nil { store.undo() }
    }
    @objc private func parseTextPlan() {
        guard window.attachedSheet == nil else { return }
        showWidget()
        NotificationCenter.default.post(name: .parseGanttText, object: nil)
    }
    @objc private func selectAll(_ sender: Any?) {
        if let field = NSApp.keyWindow?.firstResponder as? NSTextView, field.isEditable { field.selectAll(sender) }
        else if window.attachedSheet == nil {
            NotificationCenter.default.post(name: .selectAllGanttTasks, object: nil)
        }
    }
    @objc private func deleteSelection() {
        guard window.attachedSheet == nil else { return }
        NotificationCenter.default.post(name: .deleteGanttSelection, object: nil)
    }
    @objc private func togglePin() {
        store.pinned.toggle()
        window.level = store.pinned ? .floating : .normal
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { hideWidget(); return false }
    func windowDidResize(_ notification: Notification) { window.saveFrame(usingName: frameName) }
    func windowDidMove(_ notification: Notification) { window.saveFrame(usingName: frameName) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWidget(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        globalHotKey = nil
    }
}
