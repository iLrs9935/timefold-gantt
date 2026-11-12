import AppKit
import SwiftUI

enum Palette {
    static let accent = Color(hex: 0x39866F)
    static let text = adaptive(0x263C35, 0xE7EEE9)
    static let muted = adaptive(0x8A9690, 0x899F93)
    static let surface = adaptive(0xFAFBF7, 0x202C28)
    static let inset = adaptive(0xF0F3ED, 0x263530)
    static let line = adaptive(0xE6EBE2, 0x35443D)
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

struct WidgetActions {
    var hide: () -> Void = {}
    var pin: (Bool) -> Void = { _ in }
    var resize: (NSSize) -> Void = { _ in }
    var shortcut: (GlobalShortcut) -> Void = { _ in }
    var quit: () -> Void = { NSApp.terminate(nil) }
}

struct WidgetView: View {
    @ObservedObject var store: ProjectStore
    var actions = WidgetActions()
    @State private var editing: GanttTask?
    @State private var textPlanShown = false
    @State private var renameShown = false
    @State private var newPlanShown = false
    @State private var newPlanName = ""
    @State private var projectName = ""
    @State private var helpShown = false
    @State private var widgetWidth: CGFloat = 808
    @State private var selection = TaskSelection()
    private var labelWidth: CGFloat { widgetWidth < 700 ? 176 : 216 }
    private var rowHeight: CGFloat { widgetWidth < 700 ? 49 : 55 }
    private var visibleIDs: [UUID] { store.visibleTasks.map(\.id) }
    private var allSelected: Bool { !visibleIDs.isEmpty && selection.ids.isSuperset(of: visibleIDs) }
    private var selectedComplete: Bool {
        !selection.ids.isEmpty && store.project.tasks.filter { selection.ids.contains($0.id) }.allSatisfy(\.isComplete)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            projectHeader
            navigation
            gantt
            footer
        }
        .background(Palette.surface.opacity(0.97))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(store.dark ? 0.08 : 0.8), lineWidth: 1))
        .padding(8)
        .overlay(alignment: .bottomTrailing) {
            WindowResizeGrip().frame(width: 24, height: 24).padding(.trailing, 14).padding(.bottom, 12)
        }
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { widgetWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { widgetWidth = $0 }
            }
        }
        .foregroundStyle(Palette.text)
        .font(.system(size: 12))
        .preferredColorScheme(store.dark ? .dark : .light)
        .onExitCommand(perform: actions.hide)
        .sheet(item: $editing) { task in
            TaskEditor(task: task, isNew: !store.project.tasks.contains { $0.id == task.id },
                       onSave: { store.save($0) }, onDelete: { store.delete(task.id) })
        }
        .sheet(isPresented: $textPlanShown) {
            TextPlanEditor { tasks in
                if store.save(tasks) {
                    if let first = tasks.min(by: { $0.start < $1.start }) { store.reveal(first) }
                    return nil
                }
                return store.saveError ?? "暂时无法添加任务，请检查任务文件。"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newGanttTask)) { _ in addTask() }
        .onReceive(NotificationCenter.default.publisher(for: .parseGanttText)) { _ in openTextPlan() }
        .onReceive(NotificationCenter.default.publisher(for: .undoGanttEdit)) { _ in store.undo() }
        .onReceive(NotificationCenter.default.publisher(for: .selectAllGanttTasks)) { _ in selection.selectAll(visibleIDs) }
        .onReceive(NotificationCenter.default.publisher(for: .deleteGanttSelection)) { _ in deleteSelected() }
        .onChange(of: store.activePlanID) { _ in selection.clear() }
        .onChange(of: visibleIDs) { selection.retain(Set($0)) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Trigger fresh date labels after sleep or a date change.
            store.objectWillChange.send()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Palette.accent)
                Image(systemName: "chart.bar.xaxis").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            }.frame(width: 31, height: 31)
            VStack(alignment: .leading, spacing: 1) {
                Text("时序").font(.system(size: 14, weight: .semibold))
                Text("A LITTLE ROOM FOR BIG PLANS").font(.system(size: 8, weight: .medium, design: .rounded))
                    .tracking(1.1).foregroundStyle(Palette.muted)
            }
            WindowDragArea(showGrip: true).frame(minWidth: 20, maxWidth: .infinity).frame(height: 31)
                .help("拖动这里移动小组件")
            Menu { sizeOptions } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                    .frame(width: 27, height: 27).contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("窗口大小").help("调整窗口大小；也可拖动右下角")
            IconButton(symbol: store.pinned ? "pin.fill" : "pin", help: store.pinned ? "取消置顶" : "始终置顶", active: store.pinned) {
                store.pinned.toggle()
                actions.pin(store.pinned)
            }
            Menu {
                Button("新建任务", action: addTask).keyboardShortcut("n")
                Button("文字排期…", action: openTextPlan).keyboardShortcut("n", modifiers: [.command, .shift])
                Button("撤销上次修改", action: store.undo).disabled(!store.canUndo)
                Divider()
                Toggle("始终置顶", isOn: Binding(get: { store.pinned }, set: { store.pinned = $0; actions.pin($0) }))
                Toggle("深色外观", isOn: $store.dark)
                Toggle("隐藏已完成任务", isOn: $store.hideCompleted)
                Menu("窗口大小") { sizeOptions }
                Menu("呼出快捷键") {
                    Picker("呼出快捷键", selection: Binding(get: { store.shortcut }, set: { actions.shortcut($0) })) {
                        ForEach(GlobalShortcut.allCases) { shortcut in Text(shortcut.display).tag(shortcut) }
                    }.pickerStyle(.inline)
                }
                Divider()
                Button("导出任务…", action: store.exportJSON)
                Button("导入任务…", action: store.importJSON)
                Button("打开数据文件夹") { NSWorkspace.shared.open(store.fileURL.deletingLastPathComponent()) }
                if store.project.isExample { Button("清空示例，开始我的项目", action: store.clearExample) }
                Divider()
                Button("使用说明") { helpShown = true }
                Button("收起到菜单栏", action: actions.hide)
                Button("退出时序", action: actions.quit).keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium))
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("设置与更多操作")
            .popover(isPresented: $helpShown) {
                VStack(alignment: .leading, spacing: 13) {
                    Text("给计划一点空间").font(.system(size: 16, weight: .semibold))
                    Text("拖动顶部圆点区移动小组件。\n拖动右下角手柄，自由调整窗口大小。\n拖动任务条调整日期，两端调整时长。\n单击选择；⌘点击多选；Shift点击连续选择。\n双击任务名称、日期、进度或任务条编辑。\n双击任务列表下方的空白处创建新任务。\n全选后，可在底部批量完成或删除任务。")
                        .lineSpacing(6).foregroundStyle(Palette.muted)
                    if store.shortcut != .disabled {
                        Text("\(store.shortcut.display) 全局呼出 / 收起").font(.system(size: 11, weight: .medium))
                    }
                    Text("⌘A 全选    ⌘N 新任务    ⌘Z 撤销").font(.system(size: 11, design: .monospaced))
                }.padding(24).frame(width: 330)
            }
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 19)
        .background(alignment: .top) { WindowDragArea() }
    }

    private var projectHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(store.plans) { plan in
                            Button { store.switchPlan(plan.id) } label: {
                                if plan.id == store.activePlanID { Label(plan.project.name, systemImage: "checkmark") }
                                else { Text(plan.project.name) }
                            }
                        }
                        Divider()
                        Button("新建计划…") { newPlanName = ""; newPlanShown = true }
                        Button("重命名当前计划…", action: openProjectRename)
                        Button("删除当前计划", role: .destructive) { store.deleteCurrentPlan() }
                        if !store.deletedPlans.isEmpty {
                            Button("恢复最近删除的计划") { store.restoreDeletedPlan() }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Text(store.project.name).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        }.padding(.vertical, 3).contentShape(Rectangle())
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("切换计划").help("点击名称切换、新建、重命名或删除计划")
                    if store.project.isExample {
                        Text("示例").font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.accent)
                            .padding(.horizontal, 6).padding(.vertical, 3).background(Palette.accent.opacity(0.08), in: Capsule())
                    }
                }
                .popover(isPresented: $newPlanShown) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("新建计划").font(.headline)
                        TextField("例如：工作、学习、个人项目", text: $newPlanName).textFieldStyle(.roundedBorder)
                            .onSubmit { createPlan() }
                        HStack { Spacer(); Button("创建", action: createPlan).disabled(newPlanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    }.padding(20).frame(width: 280)
                }
                .popover(isPresented: $renameShown) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("项目名称").font(.headline)
                        TextField("输入项目名称", text: $projectName).textFieldStyle(.roundedBorder)
                            .onSubmit { renameProject() }
                        HStack { Spacer(); Button("保存", action: renameProject).keyboardShortcut(.defaultAction) }
                    }.padding(20).frame(width: 280)
                }
                HStack(spacing: 6) {
                    Circle().fill(Palette.accent).frame(width: 5, height: 5)
                    Text(store.project.activeCount > 0 ? "\(store.project.activeCount) 个任务正在推进" : (store.project.tasks.isEmpty ? "从第一个任务开始" : "所有任务已完成"))
                    Text("·")
                    Text(Date(), format: .dateTime.month(.twoDigits).day(.twoDigits))
                }.font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int((store.project.progress * 100).rounded()))").font(.system(size: 27, weight: .light, design: .rounded))
                    Text("%").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.line)
                        Capsule().fill(Palette.accent).frame(width: max(0, geo.size.width * store.project.progress))
                    }
                }.frame(width: 78, height: 3)
                Text("整体进度").font(.system(size: 9)).foregroundStyle(Palette.muted)
            }.padding(.trailing, 17)
            Button(action: openTextPlan) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                    if widgetWidth >= 700 { Text("文字排期") }
                }.font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(Palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(Palette.accent)
            }.buttonStyle(.plain).accessibilityLabel("文字排期").help("输入中文描述，解析并预览任务（⇧⌘N）")
            Button(action: addTask) {
                Label("新任务", systemImage: "plus").font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(.white)
            }.buttonStyle(.plain).help("新建任务（⌘N）")
        }.padding(.horizontal, 24).padding(.bottom, 22)
    }

    private var navigation: some View {
        HStack(spacing: 7) {
            IconButton(symbol: "chevron.left", help: "上一段日期") { store.navigate(-1) }
            Text(Day.range(store.viewStart, days: store.days)).font(.system(size: 11, weight: .medium)).monospacedDigit()
            IconButton(symbol: "chevron.right", help: "下一段日期") { store.navigate(1) }
            Button("今天") { store.today() }.buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.accent).padding(.horizontal, 8).padding(.vertical, 5)
                .background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            Spacer()
            HStack(spacing: 2) {
                ForEach([7, 14, 28], id: \.self) { count in
                    Button { store.days = count } label: {
                        Text(count == 7 ? "1 周" : (count == 14 ? "2 周" : "4 周"))
                            .font(.system(size: 10, weight: .medium)).frame(width: 40, height: 25)
                            .background(store.days == count ? Palette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(store.days == count ? Palette.text : Palette.muted)
                    }.buttonStyle(.plain)
                }
            }.padding(3).background(Palette.inset, in: RoundedRectangle(cornerRadius: 9))
        }.padding(.horizontal, 22).padding(.bottom, 12)
    }

    private var gantt: some View {
        GeometryReader { geo in
            let timelineWidth = max(200, geo.size.width - labelWidth)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    HStack {
                        Button(action: toggleAll) {
                            HStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.muted.opacity(0.6), lineWidth: 1)
                                    if !selection.ids.isEmpty {
                                        RoundedRectangle(cornerRadius: 3).fill(Palette.accent)
                                        Image(systemName: allSelected ? "checkmark" : "minus")
                                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                    }
                                }.frame(width: 13, height: 13)
                                Text(allSelected ? "取消全选" : "全选")
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(visibleIDs.isEmpty)
                            .accessibilityLabel(allSelected ? "取消全选任务" : "全选任务").help("全选当前显示的任务（⌘A）")
                        Spacer(); Text("进度")
                    }
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.muted)
                        .padding(.leading, 14).padding(.trailing, 18).frame(width: labelWidth, height: 49)
                    TimelineHeader(start: store.viewStart, days: store.days).frame(width: timelineWidth, height: 49)
                }.background(Palette.inset.opacity(0.55))
                Rectangle().fill(Palette.line).frame(height: 1)
                if store.visibleTasks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.accent.opacity(0.65))
                        Text(store.project.tasks.isEmpty ? "把想做的事，排进时间里。" : "已完成的任务都藏好了。")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                        Button(store.project.tasks.isEmpty ? "创建第一个任务" : "显示已完成任务") {
                            if store.project.tasks.isEmpty { addTask() } else { store.hideCompleted = false }
                        }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background { emptyTaskArea }
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(store.visibleTasks) { task in
                                HStack(spacing: 0) {
                                    TaskLabel(task: task, toggle: { store.toggle(task) }, select: { select(task, modifiers: $0) }, rangeDrag: { selectRange(task, delta: $0) }, edit: { editing = task })
                                        .frame(width: labelWidth, height: rowHeight)
                                    TimelineRow(task: task, start: store.viewStart, days: store.days,
                                                selected: selection.ids.contains(task.id), select: { select(task, modifiers: $0) },
                                                edit: { editing = task }, commit: { store.save($0) }, reveal: { store.reveal(task) })
                                        .frame(width: timelineWidth, height: rowHeight)
                                }
                                .background(selection.ids.contains(task.id) ? Palette.accent.opacity(0.095) : Color.clear)
                                .contextMenu {
                                    Button("编辑任务") { editing = task }
                                    if selection.ids.contains(task.id), selection.ids.count > 1 {
                                        Button("\(selectedComplete ? "重新打开" : "完成")选中 \(selection.ids.count) 项任务") {
                                            store.setComplete(!selectedComplete, ids: selection.ids)
                                        }
                                        Button("删除选中 \(selection.ids.count) 项任务", role: .destructive, action: deleteSelected)
                                    } else {
                                        Button(task.isComplete ? "重新打开" : "标为完成") { store.toggle(task) }
                                        Button("删除任务", role: .destructive) { store.delete(task.id) }
                                    }
                                    Button("定位到任务日期") { store.reveal(task) }
                                }
                                Rectangle().fill(Palette.line.opacity(0.65)).frame(height: 1)
                            }
                            emptyTaskArea.frame(height: max(40, geo.size.height - 50 - CGFloat(store.visibleTasks.count) * (rowHeight + 1)))
                        }
                    }.scrollIndicators(.hidden)
                }
            }
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 1))
        .padding(.horizontal, 22)
    }

    private var emptyTaskArea: some View {
        TaskPointerArea(label: "双击空白新建任务", select: { _ in selection.clear() }, edit: addTask,
                        help: "双击这里创建新任务，单击取消任务选择")
            .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let error = store.saveError ?? store.shortcutError {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(error).lineLimit(1).help(error)
            } else if !selection.ids.isEmpty {
                Text("已选 \(selection.ids.count) 项").foregroundStyle(Palette.accent)
                Button(selectedComplete ? "重新打开" : "完成") { store.setComplete(!selectedComplete, ids: selection.ids) }
                    .buttonStyle(.plain).foregroundStyle(Palette.accent).padding(.leading, 7)
                Button("删除", role: .destructive, action: deleteSelected)
                    .buttonStyle(.plain).foregroundStyle(Color(hex: 0xC47B65)).padding(.leading, 5)
                Button("取消选择") { selection.clear() }.buttonStyle(.plain).padding(.leading, 5)
            } else {
                Image(systemName: "checkmark.shield").font(.system(size: 10))
                Text("\(store.project.tasks.count) 个任务 · 保存在此 Mac")
            }
            if !store.deletedPlans.isEmpty {
                Button("撤销删除计划") { store.restoreDeletedPlan() }.buttonStyle(.plain).foregroundStyle(Palette.accent)
            }
            if store.canUndo {
                Button("撤销") { store.undo() }.buttonStyle(.plain).foregroundStyle(Palette.accent).padding(.leading, 7)
            }
            Spacer()
            if selection.ids.isEmpty {
                HStack(spacing: 5) { Circle().fill(Palette.accent).frame(width: 4, height: 4); Text("今天") }
            }
            Text(store.shortcut == .disabled ? "拖动排期 · 双击编辑" : "\(store.shortcut.display) 呼出")
                .padding(.leading, 10).help("可在右上角菜单中修改全局呼出快捷键")
        }.font(.system(size: 9)).foregroundStyle(Palette.muted)
            .padding(.leading, 25).padding(.trailing, 47).padding(.vertical, 16)
    }

    private var sizeOptions: some View {
        ForEach(WidgetSizePreset.allCases) { preset in
            Button(preset.title) { actions.resize(preset.size) }
        }
    }

    private func addTask() {
        guard !store.hasUnreadableData, !textPlanShown else { return }
        editing = GanttTask(title: "", start: Day.start(Date()), end: Day.add(2, to: Date()),
                            tint: TaskTint.allCases[store.project.tasks.count % TaskTint.allCases.count])
    }
    private func openTextPlan() {
        guard !store.hasUnreadableData, editing == nil else { return }
        textPlanShown = true
    }
    private func createPlan() {
        guard !newPlanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.createPlan(newPlanName); newPlanShown = false
    }
    private func selectRange(_ task: GanttTask, delta: CGFloat) {
        guard let origin = visibleIDs.firstIndex(of: task.id), !visibleIDs.isEmpty else { return }
        let target = max(0, min(visibleIDs.count - 1, origin + Int((delta / (rowHeight + 1)).rounded())))
        selection.select(visibleIDs[target], ordered: visibleIDs, extending: true)
    }
    private func select(_ task: GanttTask, modifiers: NSEvent.ModifierFlags) {
        selection.select(task.id, ordered: visibleIDs, extending: modifiers.contains(.shift), toggling: modifiers.contains(.command))
    }
    private func toggleAll() {
        if allSelected { selection.clear() } else { selection.selectAll(visibleIDs) }
    }
    private func deleteSelected() {
        guard !selection.ids.isEmpty else { return }
        store.delete(selection.ids)
        selection.clear()
    }
    private func renameProject() { store.rename(projectName); renameShown = false }
    private func openProjectRename() { projectName = store.project.name; renameShown = true }
}

struct TimelineHeader: View {
    var start: Date
    var days: Int
    var body: some View {
        GeometryReader { geometry in
            let cell = geometry.size.width / CGFloat(days)
            HStack(spacing: 0) {
                ForEach(0..<days, id: \.self) { index in
                    let date = Day.add(index, to: start)
                    VStack(spacing: 5) {
                        if cell >= 16 {
                            Text(Day.weekday(date)).font(.system(size: days > 14 ? 7 : 9))
                                .foregroundStyle(Day.isToday(date) ? Palette.accent : Palette.muted)
                        }
                        Text(Day.number(date)).font(.system(size: cell < 22 ? 8 : 11, weight: Day.isToday(date) ? .bold : .medium, design: .rounded))
                            .foregroundStyle(Day.isToday(date) ? Color.white : Palette.text.opacity(Day.isWeekend(date) ? 0.5 : 0.85))
                            .frame(width: min(21, max(9, cell - 2)), height: min(21, max(9, cell - 2)))
                            .background(Day.isToday(date) ? Palette.accent : Color.clear, in: Circle())
                    }.frame(width: cell, height: 49)
                        .background(Day.isWeekend(date) ? Palette.inset.opacity(0.65) : Color.clear)
                }
            }
        }
    }
}

struct TaskLabel: View {
    var task: GanttTask
    var toggle: () -> Void
    var select: (NSEvent.ModifierFlags) -> Void
    var rangeDrag: (CGFloat) -> Void
    var edit: () -> Void
    var body: some View {
        HStack(spacing: 9) {
            Button(action: toggle) {
                ZStack {
                    Circle().strokeBorder(task.isComplete ? task.tint.color : Palette.muted.opacity(0.5), lineWidth: 1)
                    if task.isComplete {
                        Circle().fill(task.tint.color)
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                    }
                }.frame(width: 18, height: 18).frame(width: 24, height: 38).contentShape(Rectangle())
            }.buttonStyle(.plain).help(task.isComplete ? "重新打开任务" : "标为完成")
            HStack(spacing: 3) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        .foregroundStyle(task.isComplete ? Palette.muted : Palette.text)
                    HStack(spacing: 5) {
                        Text("\(Day.short(task.start)) – \(Day.short(task.end))")
                        if task.isOverdue { Text("逾期").foregroundStyle(Color(hex: 0xC47B65)) }
                    }.font(.system(size: 8)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                Text("\(Int((task.progress * 100).rounded()))%").font(.system(size: 10, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.muted).frame(width: 29, alignment: .trailing)
            }
            .overlay { TaskPointerArea(label: "\(task.title)，\(Day.short(task.start)) 至 \(Day.short(task.end))，进度 \(Int(task.progress * 100))%", select: select, edit: edit, rangeDrag: rangeDrag) }
            .help("单击选择，按住拖过多行可多选；双击编辑 \(task.title)")
        }.padding(.leading, 14).padding(.trailing, 17)
    }
}

struct TimelineRow: View {
    var task: GanttTask
    var start: Date
    var days: Int
    var selected: Bool
    var select: (NSEvent.ModifierFlags) -> Void
    var edit: () -> Void
    var commit: (GanttTask) -> Void
    var reveal: () -> Void
    @State private var hovered = false
    @State private var moveDays = 0
    @State private var startDays = 0
    @State private var endDays = 0
    @State private var dragging = false

    private var preview: GanttTask {
        var value = task.shifted(by: moveDays)
        value.start = Day.add(startDays, to: value.start)
        value.end = Day.add(endDays, to: value.end)
        return value
    }
    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CGFloat(days)
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<days, id: \.self) { index in
                        let date = Day.add(index, to: start)
                        Rectangle().fill(Day.isToday(date) ? Palette.accent.opacity(0.065) : (Day.isWeekend(date) ? Palette.inset.opacity(0.6) : Color.clear))
                            .overlay(alignment: .leading) { Rectangle().fill(Palette.line.opacity(0.55)).frame(width: 0.5) }
                    }
                }
                if let span = TimelineSpan.visible(task: preview, start: start, days: days) {
                    let width = max(8, CGFloat(span.count) * cell - 8)
                    bar(width: width, cell: cell, span: span)
                        .offset(x: CGFloat(span.offset) * cell + 4, y: 0)
                } else {
                    Button(action: reveal) {
                        HStack(spacing: 4) {
                            Image(systemName: Day.distance(start, task.end) < 0 ? "arrow.left" : "arrow.right")
                            Text("查看排期")
                        }.font(.system(size: 9)).foregroundStyle(Palette.muted)
                            .padding(.horizontal, 9).padding(.vertical, 7)
                    }.buttonStyle(.plain).padding(.leading, 10)
                }
                let todayIndex = Day.distance(start, Date())
                if todayIndex >= 0 && todayIndex < days {
                    Path { path in
                        let x = (CGFloat(todayIndex) + 0.5) * cell
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }.stroke(Palette.accent.opacity(0.27), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                let span = TimelineSpan.visible(task: task, start: start, days: days)
                let rect = span.map { CGRect(x: CGFloat($0.offset) * cell + 4, y: (geo.size.height - 25) / 2,
                                             width: max(8, CGFloat($0.count) * cell - 8), height: 25) }
                TaskPointerArea(label: "编辑 \(task.title) 的排期", bar: rect,
                                canResizeStart: span.map { !$0.clippedStart } ?? false,
                                canResizeEnd: span.map { !$0.clippedEnd } ?? false,
                                select: select, edit: edit, singleClick: span == nil ? reveal : nil,
                                change: { mode, delta in
                                    dragging = true
                                    let days = Int((delta / cell).rounded())
                                    switch mode {
                                    case .move: moveDays = days
                                    case .start: startDays = min(days, task.duration - 1)
                                    case .end: endDays = max(days, -(task.duration - 1))
                                    }
                                }, finish: finishDrag)
            }
            .frame(height: geo.size.height).clipped()
        }
    }

    private func bar(width: CGFloat, cell: CGFloat, span: TimelineSpan) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6).fill(task.tint.color.opacity(0.17))
            // Progress is intersected with the visible date span, so clipped bars stay accurate.
            let totalWidth = CGFloat(preview.duration) * cell
            let hiddenWidth = CGFloat(max(0, Day.distance(preview.start, start))) * cell
            let fillWidth = max(0, min(width, totalWidth * task.progress - hiddenWidth))
            RoundedRectangle(cornerRadius: 6).fill(task.tint.color.opacity(task.isComplete ? 0.75 : 0.82))
                .frame(width: fillWidth)
            HStack(spacing: 2) {
                if span.clippedStart { Image(systemName: "chevron.left").font(.system(size: 7, weight: .bold)) }
                Spacer(minLength: 0)
                if width > 54 {
                    Text(task.isComplete ? "完成" : "\(preview.duration) 天")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                }
                Spacer(minLength: 0)
                if span.clippedEnd { Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)) }
            }.foregroundStyle(fillWidth > width / 2 + 12 ? Color.white : task.tint.color).padding(.horizontal, 7)
        }
        .frame(width: width, height: 25)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(task.tint.color.opacity(selected || hovered || dragging ? 0.75 : 0.15), lineWidth: 1))
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            if !span.clippedStart && width > 12 { handle() }
        }
        .overlay(alignment: .trailing) {
            if !span.clippedEnd && width > 12 { handle() }
        }
        .allowsHitTesting(false)
        .onHover { hovered = $0 }
        .help("\(task.title)\n\(Day.short(preview.start)) – \(Day.short(preview.end)) · \(Int(task.progress * 100))%\n拖动移动日期；两端调整时长；双击编辑")
        .accessibilityLabel("\(task.title)，\(Day.short(preview.start)) 至 \(Day.short(preview.end))，进度 \(Int(task.progress * 100))%")
    }

    private func handle() -> some View {
        RoundedRectangle(cornerRadius: 1).fill(task.tint.color.opacity(selected || hovered || dragging ? 0.85 : 0.45))
            .frame(width: 2, height: 11).frame(width: 10, height: 25).contentShape(Rectangle())
    }

    private func finishDrag() {
        if moveDays != 0 || startDays != 0 || endDays != 0 { commit(preview) }
        moveDays = 0; startDays = 0; endDays = 0; dragging = false
    }
}

struct IconButton: View {
    var symbol: String
    var help: String
    var active = false
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? Palette.accent : Palette.muted)
                .frame(width: 27, height: 27)
                .background(hover || active ? Palette.inset : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hover = $0 }.help(help)
    }
}

struct WindowDragArea: NSViewRepresentable {
    var showGrip = false
    final class DragView: NSView {
        var showGrip = false
        private var initialOrigin: NSPoint?
        private var initialPoint = NSPoint.zero
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            initialOrigin = window.frame.origin
            initialPoint = window.convertPoint(toScreen: event.locationInWindow)
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let initialOrigin else { return }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            window.setFrameOrigin(NSPoint(x: initialOrigin.x + point.x - initialPoint.x,
                                          y: initialOrigin.y + point.y - initialPoint.y))
        }
        override func mouseUp(with event: NSEvent) { initialOrigin = nil }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func draw(_ dirtyRect: NSRect) {
            guard showGrip else { return }
            NSColor.tertiaryLabelColor.withAlphaComponent(0.6).setFill()
            for x: CGFloat in [-3, 3] {
                for y: CGFloat in [-5, 0, 5] {
                    NSBezierPath(ovalIn: NSRect(x: bounds.midX + x - 1, y: bounds.midY + y - 1, width: 2, height: 2)).fill()
                }
            }
        }
    }
    func makeNSView(context: Context) -> DragView {
        let view = DragView(); view.showGrip = showGrip; return view
    }
    func updateNSView(_ view: DragView, context: Context) { view.showGrip = showGrip; view.needsDisplay = true }
}

extension Notification.Name {
    static let newGanttTask = Notification.Name("Timefold.newTask")
    static let parseGanttText = Notification.Name("Timefold.parseText")
    static let undoGanttEdit = Notification.Name("Timefold.undo")
}
