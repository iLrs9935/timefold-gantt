import SwiftUI

struct TaskEditor: View {
    @ObservedObject private var appLanguage = AppLanguage.shared
    @Environment(\.dismiss) private var dismiss
    @State var task: GanttTask
    var isNew: Bool
    var onSave: (GanttTask) -> Void
    var onDelete: () -> Void
    @FocusState private var titleFocused: Bool
    private var valid: Bool {
        !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Day.start(task.end) >= Day.start(task.start)
    }
    private var duration: Binding<Int> {
        Binding(get: { task.duration }, set: { task.end = Day.add(max(1, min(3650, $0)) - 1, to: task.start) })
    }
    private var percent: Binding<Int> {
        Binding(get: { Int((task.progress * 100).rounded()) }, set: { task.progress = Double(max(0, min(100, $0))) / 100 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isNew ? L("新的一步") : L("调整计划")).font(.system(size: 21, weight: .semibold))
                    Text(isNew ? L("给任务定个时间，让计划开始流动。") : L("每一个小进展，都算数。"))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                IconButton(symbol: "xmark", help: L("取消")) { dismiss() }
            }
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel(L("任务名称"))
                TextField(L("例如：完成第一版设计"), text: $task.title)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .padding(12).background(Palette.inset, in: RoundedRectangle(cornerRadius: 9))
                    .focused($titleFocused)
            }
            HStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel(L("开始日期"))
                    DatePicker(L("开始日期"), selection: $task.start, displayedComponents: .date).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel(L("结束日期（包含当天）"))
                    DatePicker(L("结束日期"), selection: $task.end, in: Day.start(task.start)..., displayedComponents: .date).labelsHidden()
                }
            }
            .onChange(of: task.start) { value in
                if Day.start(task.end) < Day.start(value) { task.end = value }
            }
            HStack(spacing: 8) {
                fieldLabel(L("持续时长"))
                TextField(L("天数"), value: duration, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 50).accessibilityLabel(L("持续天数"))
                Text(L("天")).foregroundStyle(Palette.muted)
                Stepper(L("持续天数"), value: duration, in: 1...3650).labelsHidden()
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    fieldLabel(L("完成进度")); Spacer()
                    TextField(L("百分比"), value: percent, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).frame(width: 46).accessibilityLabel(L("进度百分比"))
                    Text("%").foregroundStyle(task.tint.color)
                }
                Slider(value: $task.progress, in: 0...1, step: 0.01).tint(task.tint.color)
                    .accessibilityLabel(L("完成进度"))
            }
            HStack(spacing: 12) {
                fieldLabel(L("任务颜色"))
                ForEach(TaskTint.allCases) { tint in
                    Button { task.tint = tint } label: {
                        Circle().fill(tint.color).frame(width: 23, height: 23)
                            .overlay {
                                if task.tint == tint { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                            }
                            .padding(3).overlay(Circle().strokeBorder(task.tint == tint ? tint.color.opacity(0.5) : .clear, lineWidth: 1))
                    }.buttonStyle(.plain).help(tint.title).accessibilityLabel(tint.title)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel(L("备注"))
                TextField(L("添加一点背景信息（可选）"), text: $task.notes, axis: .vertical)
                    .lineLimit(2...3).textFieldStyle(.plain)
                    .padding(12).background(Palette.inset, in: RoundedRectangle(cornerRadius: 9))
            }
            HStack {
                if !isNew {
                    Button(L("删除任务"), role: .destructive) { onDelete(); dismiss() }
                        .buttonStyle(.plain).foregroundStyle(Color(hex: 0xC47B65))
                }
                Spacer()
                Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? L("创建任务") : L("保存修改")) { onSave(task); dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Palette.accent).disabled(!valid)
            }
        }
        .padding(28).frame(width: 430)
        .background(Palette.surface).foregroundStyle(Palette.text)
        .environment(\.locale, appLanguage.locale)
        .font(.system(size: 12))
        .onAppear { titleFocused = true }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
    }
}
