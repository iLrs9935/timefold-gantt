import Foundation

extension ModelChecks {
    static func checkTextPlans() throws {
        let reference = date("2026-11-12")
        let result = TextPlanParser.parse("明天下午报销，预计1-2天\n下周一整理检测报告，持续三天，进度30%", reference: reference)
        try expect(result.issues.isEmpty && result.drafts.count == 2, "解析多行任务")
        let first = result.drafts[0]
        try expect(first.task.title == "报销" && first.task.start == date("2026-11-13") && first.task.end == date("2026-11-14"), "相对日期与时长范围")
        try expect(first.task.notes.contains("下午") && first.warnings.contains { $0.contains("上限") }, "时段保留与范围提示")
        let second = result.drafts[1].task
        try expect(second.title == "整理检测报告" && second.start == date("2026-11-16") && second.end == date("2026-11-18") && second.progress == 0.3, "下周与中文时长及进度")
        print("✓ 中文文字排期：相对日期、时长、时段、进度")

        let original = TextPlanParser.parse("16、8号下午做资料1天\n17、9号下午报销1-2天、整理正在做的检测报告1天\n17、9号上午对账项目材料1-2天\n18、9号上午完成收据1天", reference: reference)
        try expect(original.issues.isEmpty && original.drafts.count == 5, "编号与顿号拆分，不应把编号当日期")
        try expect(original.drafts[2].task.title == "整理正在做的检测报告" && original.drafts[2].task.start == date("2026-11-09") && original.drafts[2].task.notes.contains("下午"), "同一行任务沿用日期和时段")
        try expect(original.drafts[4].task.title == "完成收据" && original.drafts[4].task.progress == 0, "任务名称中的“完成”不代表已经完成")
        let heading = TextPlanParser.parse("明天下午：\n报销两天\n整理报告一天", reference: reference)
        try expect(heading.drafts.count == 2 && heading.drafts.allSatisfy { $0.task.start == date("2026-11-13") }, "日期标题应用于后续任务")
        let note = TextPlanParser.parse("明天在职培训1天，备注：携带资料、发票", reference: reference)
        try expect(note.drafts.count == 1 && note.drafts[0].task.title == "在职培训" && note.drafts[0].task.notes.contains("携带资料、发票"), "保留标题和备注中的词语及顿号")
        print("✓ 中文文字排期：原始案例、编号、多项和日期标题")

        let dates = TextPlanParser.parse("12月31日至1月2日测试\n11月30日至2日交接\n十一月二十日核对材料两天\n2028-02-29登记1天\n本月底完成收据半天\n下个月5号会议1天\n三天后做资料一天半", reference: reference)
        try expect(dates.issues.isEmpty && dates.drafts.count == 7, "绝对日期、中文日期和时长")
        try expect(dates.drafts[0].task.end == date("2027-01-02") && dates.drafts[0].task.duration == 3, "跨年范围包含结束当天")
        try expect(dates.drafts[1].task.end == date("2026-12-02") && !dates.drafts[1].warnings.isEmpty, "省略月份的跨月安排应提示")
        try expect(dates.drafts[2].task.start == date("2026-11-20") && dates.drafts[2].task.duration == 2, "中文月份和日期")
        try expect(dates.drafts[3].task.start == date("2028-02-29"), "闰日")
        try expect(dates.drafts[4].task.start == date("2026-11-30") && dates.drafts[4].task.duration == 1, "月底与半天取整")
        try expect(dates.drafts[5].task.start == date("2026-12-05"), "下个月")
        try expect(dates.drafts[6].task.start == date("2026-11-15") && dates.drafts[6].task.duration == 2, "天数之后与一天半")
        let workdays = TextPlanParser.parse("明天处理报告3个工作日", reference: reference)
        try expect(workdays.drafts.first?.task.end == date("2026-11-17"), "工作日应跳过周末")
        let emoji = TextPlanParser.parse("明天修复🧪报告两天，颜色紫色", reference: reference)
        try expect(emoji.drafts.first?.task.title == "修复🧪报告" && emoji.drafts.first?.task.tint == .lavender, "Unicode 文字范围与颜色")
        let monthRange = TextPlanParser.parse("下个月15号到下个月18号测试", reference: reference)
        try expect(monthRange.drafts.first?.task.start == date("2026-12-15") && monthRange.drafts.first?.task.end == date("2026-12-18"), "范围内重复的“下个月”应参照今天")
        let partial = TextPlanParser.parse("明天做资料1天，已完成一半\n明天做报告1天，进度百分之三十\n明天整理资料1天，已经完成60%", reference: reference)
        try expect(partial.drafts.map { $0.task.progress } == [0.5, 0.3, 0.6], "部分完成不能误标为全部完成")
        print("✓ 中文文字排期：跨月、跨年、闰年、工作日和取整")

        for input in ["2026-02-30登记1天", "明天到今天处理报告", "明天报销0天", "明天报销-1天", "明天报销3-1天", "明天报销，进度130%", "明天报销，进度1000%", "明天报销，进度-3%", "999999999999999999999月1日做事", "明天做事999999999999999999999天"] {
            let invalid = TextPlanParser.parse(input, reference: reference)
            try expect(invalid.drafts.isEmpty && !invalid.issues.isEmpty, "无效表达不得悄悄变成有效任务：\(input)")
        }
        let missing = TextPlanParser.parse("整理资料", reference: reference)
        try expect(missing.drafts.first?.task.start == reference && missing.drafts.first?.task.duration == 1 && missing.drafts[0].warnings.count == 2, "缺少日期或时长时须明确提示默认值")
        let durationOnly = TextPlanParser.parse("整理资料持续三日", reference: reference)
        try expect(durationOnly.drafts.first?.task.start == reference && durationOnly.drafts.first?.task.duration == 3, "明确持续时间中的“日”不应误作月内日期")
        let tooMany = TextPlanParser.parse(Array(repeating: "明天报销一天", count: 201).joined(separator: "\n"), reference: reference)
        try expect(tooMany.drafts.count == 200 && !tooMany.issues.isEmpty, "限制批量输入并报告未解析内容")
        try expect(!TextPlanParser.parse(String(repeating: "字", count: 20_001), reference: reference).issues.isEmpty, "输入长度限制")
        print("✓ 中文文字排期：无效日期、范围、超长输入和默认值提示")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "Timefold.TextChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let url = directory.appendingPathComponent("project.json")
        let store = ProjectStore(fileURL: url, defaults: defaults)
        let before = store.project
        var preview = TextPlanParser.parse("明天报销两天", reference: reference)
        preview.drafts[0].task.title = "仅修改预览"
        try expect(store.project == before && (try ProjectStore.read(from: url)) == before, "解析和修改预览不得写入项目")
        try expect(store.save(result.drafts.map(\.task)), "批量添加应保存成功")
        try expect(store.project.tasks.count == before.tasks.count + 2 && (try ProjectStore.read(from: url)).tasks == store.project.tasks, "保留原有任务并保存新增任务")
        try expect(store.save(result.drafts.map(\.task)) && store.project.tasks.count == before.tasks.count + 2, "重复提交不得重复新增相同任务")
        store.undo()
        try expect(store.project == before && (try ProjectStore.read(from: url)) == before, "一次撤销应恢复整批添加前的数据")
        print("✓ 文字排期批量保存、重复提交与整批撤销")
    }
}
