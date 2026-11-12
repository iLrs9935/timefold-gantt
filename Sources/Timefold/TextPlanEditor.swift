import SwiftUI

struct TextPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: ([GanttTask]) -> String?
    @State private var input = ""
    @State private var parsedInput = ""
    @State private var result = TextPlanResult()
    @State private var hasParsed = false
    @State private var editingDraft: GanttTask?
    @State private var saveError: String?
    @FocusState private var inputFocused: Bool

    private var tasks: [GanttTask] { result.drafts.filter(\.included).map(\.task) }
    private var stale: Bool { hasParsed && input != parsedInput }
    private var canAdd: Bool {
        hasParsed && !stale && !tasks.isEmpty && tasks.allSatisfy {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.end >= $0.start
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("文字排期", systemImage: "sparkles").font(.system(size: 21, weight: .semibold))
                    Text("把要做的事写下来，确认后一起放进甘特图。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                IconButton(symbol: "xmark", help: "取消文字排期") { dismiss() }
            }
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $input).font(.system(size: 13)).scrollContentBackground(.hidden)
                        .focused($inputFocused).accessibilityLabel("排期描述")
                    if input.isEmpty {
                        Text("明天下午报销，预计两天\n下周一整理检测报告，持续三天，进度30%")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted.opacity(0.75))
                            .padding(.top, 2).padding(.leading, 5).allowsHitTesting(false)
                    }
                }.frame(height: 105).padding(10).background(Palette.inset, in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Text("一行一项，也可用分号、顿号分隔 · 在此 Mac 解析")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("试试示例") {
                        input = "明天下午报销，预计1-2天\n下周一整理检测报告，持续三天，进度30%\n本月底完成收据，半天"
                        parse()
                    }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                    Button(hasParsed ? "重新解析" : "解析文字", action: parse)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if hasParsed {
                HStack {
                    Text("任务预览 · \(result.drafts.count) 项").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("可修改名称，或点“调整”编辑全部信息").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                if stale {
                    Label("文字已修改，请重新解析后再添加。", systemImage: "arrow.clockwise")
                        .font(.system(size: 11)).foregroundStyle(Color(hex: 0xB18843))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($result.drafts) { $draft in previewRow($draft) }
                        ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                            Label(issue, systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11)).foregroundStyle(Color(hex: 0xB18843))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if result.drafts.isEmpty && result.issues.isEmpty {
                            Text("请补上要做的事情，例如“明天整理报告，持续一天”。")
                                .foregroundStyle(Palette.muted).font(.system(size: 12)).padding(.vertical, 20)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 255)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("支持今天、明天、下周几、具体日期、起止范围与持续时长。")
                    Text("上午、下午和原文会保存在备注中；未写日期或时长时，会在预览中提示采用的安排。")
                }.font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            }
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(Color(hex: 0xC47B65))
            }
            HStack {
                Text(hasParsed ? "已勾选 \(tasks.count) 项 · 添加后可整批撤销" : "⌘↩ 解析文字 · 确认前不会保存任务")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("添加 \(tasks.count) 项任务") {
                    guard canAdd else { return }
                    saveError = onAdd(tasks)
                    if saveError == nil { dismiss() }
                }.buttonStyle(.borderedProminent).tint(Palette.accent).disabled(!canAdd)
            }
        }
        .padding(26).frame(width: 620)
        .background(Palette.surface).foregroundStyle(Palette.text).font(.system(size: 12))
        .onAppear { inputFocused = true }
        .sheet(item: $editingDraft) { task in
            TaskEditor(task: task, isNew: false, onSave: { edited in
                if let index = result.drafts.firstIndex(where: { $0.id == edited.id }) {
                    result.drafts[index].task = edited.normalized()
                    result.drafts[index].warnings = ["已手动调整，请以上方信息为准。"]
                }
            }, onDelete: { result.drafts.removeAll { $0.id == task.id } })
        }
    }

    private func previewRow(_ draft: Binding<TextPlanDraft>) -> some View {
        let value = draft.wrappedValue
        let task = value.task
        return HStack(alignment: .top, spacing: 10) {
            Toggle("添加 \(task.title)", isOn: draft.included).labelsHidden().toggleStyle(.checkbox).padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Circle().fill(task.tint.color).frame(width: 7, height: 7)
                    TextField("任务名称", text: draft.task.title).textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium)).accessibilityLabel("预览任务名称")
                    Button("调整") { editingDraft = task }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                        .accessibilityLabel("调整 \(task.title)")
                }
                HStack(spacing: 5) {
                    Text(task.start, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                    Text("–")
                    Text(task.end, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                    Text("· \(task.duration) 天 · \(Int((task.progress * 100).rounded()))%")
                }.font(.system(size: 10)).foregroundStyle(Palette.muted)
                if !value.warnings.isEmpty {
                    Text(value.warnings.joined(separator: "\n"))
                        .font(.system(size: 10)).foregroundStyle(Color(hex: 0xA07C40)).lineSpacing(3)
                }
                Text("原文：\(value.source)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    .lineLimit(2).help(value.source)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.inset.opacity(value.included ? 0.8 : 0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    private func parse() {
        result = TextPlanParser.parse(input)
        parsedInput = input
        hasParsed = true
        saveError = nil
        inputFocused = false
    }
}
