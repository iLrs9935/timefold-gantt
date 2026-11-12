import SwiftUI

struct TaskEditor: View {
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
                    Text(isNew ? "新的一步" : "调整计划").font(.system(size: 21, weight: .semibold))
                    Text(isNew ? "给任务定个时间，让计划开始流动。" : "每一个小进展，都算数。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                IconButton(symbol: "xmark", help: "取消") { dismiss() }
            }
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("任务名称")
                TextField("例如：完成第一版设计", text: $task.title)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .padding(12).background(Palette.inset, in: RoundedRectangle(cornerRadius: 9))
                    .focused($titleFocused)
            }
            HStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("开始日期")
                    DatePicker("开始日期", selection: $task.start, displayedComponents: .date).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("结束日期（包含当天）")
                    DatePicker("结束日期", selection: $task.end, in: Day.start(task.start)..., displayedComponents: .date).labelsHidden()
                }
            }
            .onChange(of: task.start) { value in
                if Day.start(task.end) < Day.start(value) { task.end = value }
            }
            HStack(spacing: 8) {
                fieldLabel("持续时长")
                TextField("天数", value: duration, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 50).accessibilityLabel("持续天数")
                Text("天").foregroundStyle(Palette.muted)
                Stepper("持续天数", value: duration, in: 1...3650).labelsHidden()
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    fieldLabel("完成进度"); Spacer()
                    TextField("百分比", value: percent, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).frame(width: 46).accessibilityLabel("进度百分比")
                    Text("%").foregroundStyle(task.tint.color)
                }
                Slider(value: $task.progress, in: 0...1, step: 0.01).tint(task.tint.color)
                    .accessibilityLabel("完成进度")
            }
            HStack(spacing: 12) {
                fieldLabel("任务颜色")
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
                fieldLabel("备注")
                TextField("添加一点背景信息（可选）", text: $task.notes, axis: .vertical)
                    .lineLimit(2...3).textFieldStyle(.plain)
                    .padding(12).background(Palette.inset, in: RoundedRectangle(cornerRadius: 9))
            }
            HStack {
                if !isNew {
                    Button("删除任务", role: .destructive) { onDelete(); dismiss() }
                        .buttonStyle(.plain).foregroundStyle(Color(hex: 0xC47B65))
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "创建任务" : "保存修改") { onSave(task); dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Palette.accent).disabled(!valid)
            }
        }
        .padding(28).frame(width: 430)
        .background(Palette.surface).foregroundStyle(Palette.text)
        .font(.system(size: 12))
        .onAppear { titleFocused = true }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
    }
}
