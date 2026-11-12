import Foundation
import AppKit

enum CheckFailure: Error { case failed(String) }

@main @MainActor
struct ModelChecks {
    static func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: value)!
    }
    static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure.failed(message) }
    }

    static func main() throws {
        let task = GanttTask(title: "跨周任务", start: date("2026-10-03"), end: date("2026-10-09"))
        try expect(task.duration == 7, "结束日期必须包含当天")
        try expect(TimelineSpan.visible(task: task, start: date("2026-10-05"), days: 3) ==
                   TimelineSpan(offset: 0, count: 3, clippedStart: true, clippedEnd: true), "双端裁剪")
        try expect(TimelineSpan.visible(task: task, start: date("2026-10-10"), days: 7) == nil, "已过去的任务")
        try expect(TimelineSpan.visible(task: task, start: date("2026-09-20"), days: 7) == nil, "未来的任务")
        print("✓ 日期区间与裁剪")

        let crossing = GanttTask(title: "上线", start: date("2026-10-30"), end: date("2026-11-02"))
        let shifted = crossing.shifted(by: 4)
        try expect(shifted.start == date("2026-11-03") && shifted.end == date("2026-11-06"), "跨月移动")
        try expect(shifted.duration == crossing.duration, "移动必须保留任务时长")
        try expect(Day.weekStart(date("2026-10-11")) == date("2026-10-05"), "周日归属本周")
        print("✓ 跨月移动与周边界")

        let invalid = GanttTask(title: "  开发  ", start: date("2026-10-08"), end: date("2026-10-03"), progress: 2).normalized()
        try expect(invalid.title == "开发" && invalid.duration == 1 && invalid.progress == 1, "导入数据归一化")
        print("✓ 异常日期和进度处理")

        let project = Project(tasks: [
            GanttTask(title: "长任务", start: date("2026-10-01"), end: date("2026-10-09"), progress: 0.5),
            GanttTask(title: "短任务", start: date("2026-10-10"), end: date("2026-10-10"), progress: 1)
        ])
        try expect(abs(project.progress - 0.55) < 0.0001, "按时长加权的整体进度")
        print("✓ 整体进度")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "Timefold.Checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let url = directory.appendingPathComponent("project.json")
        let store = ProjectStore(fileURL: url, defaults: defaults)
        store.shortcut = .commandOptionG
        store.clearExample()
        let saved = GanttTask(title: "真实任务", start: date("2026-10-08"), end: date("2026-10-10"), progress: 0.35)
        store.save(saved)
        let diskProject = try ProjectStore.read(from: url)
        try expect(store.saveError == nil && diskProject.tasks == [saved], "任务保存及 JSON 往返")
        store.delete(saved.id)
        try expect(store.project.tasks.isEmpty, "删除任务")
        store.undo()
        try expect(store.project.tasks == [saved], "撤销删除")
        let reopened = ProjectStore(fileURL: url, defaults: defaults)
        try expect(reopened.project == store.project, "重新打开恢复数据")
        try expect(reopened.shortcut == .commandOptionG, "快捷键选择必须记住")
        print("✓ 本地保存、撤销、重新打开")

        let taskIDs = (0..<5).map { _ in UUID() }
        var selection = TaskSelection()
        selection.select(taskIDs[1], ordered: taskIDs)
        selection.select(taskIDs[3], ordered: taskIDs, extending: true)
        try expect(selection.ids == Set(taskIDs[1...3]), "Shift 必须选择锚点到目标的连续任务")
        selection.select(taskIDs[2], ordered: taskIDs, toggling: true)
        try expect(selection.ids == Set([taskIDs[1], taskIDs[3]]), "Command 点击应取消单项选择")
        selection.select(taskIDs[0], ordered: taskIDs, extending: true, toggling: true)
        try expect(selection.ids == Set(taskIDs[0...3]), "Command Shift 应追加连续任务")
        selection.selectAll(taskIDs)
        try expect(selection.ids.count == 5, "全选应包括滚动区域内全部任务")
        selection.retain(Set(taskIDs.suffix(2)))
        try expect(selection.ids == Set(taskIDs.suffix(2)) && selection.anchor == nil, "隐藏或移除任务必须清理选择与锚点")
        selection.clear()
        try expect(selection.ids.isEmpty, "取消全选")
        print("✓ 全选、多选、连续选择及隐藏任务")

        let second = GanttTask(title: "第二项", start: date("2026-10-09"), end: date("2026-10-09"), progress: 0.17)
        let untouched = GanttTask(title: "未选择", start: date("2026-10-10"), end: date("2026-10-12"), progress: 0.43)
        store.save(second); store.save(untouched)
        let originalTasks = store.project.tasks
        let batchIDs: Set<UUID> = [saved.id, second.id]
        store.setComplete(true, ids: batchIDs)
        try expect(store.project.tasks.filter { batchIDs.contains($0.id) }.allSatisfy(\.isComplete), "批量完成")
        try expect(store.project.tasks.first { $0.id == untouched.id } == untouched, "批量操作不得修改未选任务")
        store.undo()
        try expect(store.project.tasks == originalTasks, "一次撤销应恢复整批原有进度")
        store.delete(batchIDs)
        try expect(store.project.tasks == [untouched], "批量删除仅删除选中项")
        store.undo()
        try expect(store.project.tasks == originalTasks && (try ProjectStore.read(from: url)).tasks == originalTasks, "批量删除一次撤销并恢复保存")
        print("✓ 批量完成、批量删除与整批撤销")

        let corruptURL = directory.appendingPathComponent("corrupt.json")
        let original = Data("corrupt data".utf8)
        try original.write(to: corruptURL)
        let corrupt = ProjectStore(fileURL: corruptURL, defaults: defaults)
        corrupt.rename("新项目")
        let preserved = try Data(contentsOf: corruptURL)
        try expect(corrupt.saveError != nil && preserved == original, "损坏文件必须保留")
        print("✓ 损坏数据保护")

        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let originalFrame = NSRect(x: 800, y: 240, width: 640, height: 460)
        let smallFrame = WidgetSizing.frame(from: originalFrame, size: NSSize(width: 10, height: 10), visible: screen)
        try expect(smallFrame.size == WidgetSizing.minimum && smallFrame.maxY == originalFrame.maxY, "缩小应保持顶部并限制最小尺寸")
        let largeFrame = WidgetSizing.frame(from: originalFrame, size: NSSize(width: 3000, height: 3000), visible: screen)
        try expect(screen.contains(largeFrame) && largeFrame.size == screen.size, "大窗口不能超出屏幕")
        let negativeScreen = NSRect(x: -1920, y: 200, width: 1920, height: 1080)
        let movedFrame = WidgetSizing.frame(from: originalFrame, size: WidgetSizePreset.standard.size, visible: negativeScreen)
        try expect(negativeScreen.contains(movedFrame), "外接屏负坐标约束")
        print("✓ 自由缩放、屏幕边界与外接屏")
        try checkTextPlans()
        print("全部 14 组检查通过。")
    }
}
