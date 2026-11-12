import Foundation

extension ModelChecks {
    static func checkColloquialPlans() throws {
        let reference = date("2026-11-12")
        let spoken = TextPlanParser.parse("明早报销两三天\n今晚20:30开会一个半小时\n下月初整理资料两天\n11.15核对清单1天\n13-15号做检测\n2026.11.16登记一天", reference: reference)
        try expect(spoken.issues.isEmpty && spoken.drafts.count == 6, "口语日期、时长与点号日期")
        try expect(spoken.drafts[0].task.title == "报销" && spoken.drafts[0].task.start == date("2026-11-13") && spoken.drafts[0].task.duration == 3 && spoken.drafts[0].task.notes.contains("早上"), "明早和两三天")
        try expect(spoken.drafts[1].task.title == "开会" && spoken.drafts[1].task.duration == 1 && spoken.drafts[1].task.notes.contains("20:30") && spoken.drafts[1].task.notes.contains("晚上"), "今晚具体时间与小时估时")
        try expect(spoken.drafts[2].task.start == date("2026-12-01"), "下月初")
        try expect(spoken.drafts[3].task.start == date("2026-11-15") && spoken.drafts[4].task.duration == 3 && spoken.drafts[5].task.start == date("2026-11-16"), "简写日期、简写范围和完整点号日期不得误认为编号")
        let clock = TextPlanParser.parse("明早九点开会半天\n明天提出3点修改意见一天", reference: reference)
        try expect(clock.drafts[0].task.title == "开会" && clock.drafts[0].task.notes.contains("9点"), "中文小时")
        try expect(clock.drafts[1].task.title == "提出3点修改意见", "数量词中的点不能当作时刻删除")
        print("✓ 口语排期：明早今晚、两三天、月初、时间和简写日期")

        let deadlines = TextPlanParser.parse("周五前整理报告\n周五前完成清单，预计两天\n下周一前核对账目2个工作日\n周五下午5点前提交报告，预计两天\n明天开始，周六前整理材料\n明天到周六前处理检测报告", reference: reference)
        try expect(deadlines.issues.isEmpty && deadlines.drafts.count == 6, "截止日期解析")
        try expect(deadlines.drafts[0].task.start == reference && deadlines.drafts[0].task.end == date("2026-11-13"), "仅给截止日期时从今天安排")
        try expect(deadlines.drafts[1].task.start == reference && deadlines.drafts[1].task.duration == 2 && deadlines.drafts[1].warnings.contains { $0.contains("倒推") }, "根据截止日和估时倒推开始日")
        try expect(deadlines.drafts[2].task.start == date("2026-11-13") && deadlines.drafts[2].task.end == date("2026-11-16"), "工作日倒推跳过周末")
        try expect(deadlines.drafts[3].task.title == "提交报告" && deadlines.drafts[3].task.notes.contains("下午") && deadlines.drafts[3].task.notes.contains("5点"), "截止日的具体时间不应丢失")
        try expect(deadlines.drafts[4].task.start == date("2026-11-13") && deadlines.drafts[4].task.end == date("2026-11-14"), "开始日期标题与截止日配合")
        try expect(deadlines.drafts[5].task.title == "处理检测报告" && deadlines.drafts[5].task.start == date("2026-11-13"), "起止语句中的连接词不应混进任务名称")
        let impossible = TextPlanParser.parse("明天开始截止今天交报告", reference: reference)
        try expect(impossible.drafts.isEmpty && !impossible.issues.isEmpty, "反向截止日期必须提示")
        let invalidTime = TextPlanParser.parse("明早25:70开会", reference: reference)
        try expect(invalidTime.drafts.isEmpty && !invalidTime.issues.isEmpty, "无效时间不能静默排期")
        print("✓ 截止排期：包含截止日、倒推、工作日与日期冲突")

        let sequence = TextPlanParser.parse("明早报销两三天，然后整理报告一天，最后核对收据半天", reference: reference)
        try expect(sequence.issues.isEmpty && sequence.drafts.count == 3, "一段话拆分连续任务")
        try expect(sequence.drafts.map { $0.task.start } == [date("2026-11-13"), date("2026-11-16"), date("2026-11-17")], "然后和最后应按结束日顺延")
        try expect(sequence.drafts[1].warnings.contains { $0.contains("次日") }, "顺延规则必须出现在预览中")
        let parallel = TextPlanParser.parse("明天报销两天和整理报告一天，核对收据半天", reference: reference)
        try expect(parallel.drafts.count == 3 && parallel.drafts.allSatisfy { $0.task.start == date("2026-11-13") }, "并列任务沿用日期，不应自动串行")
        let notes = TextPlanParser.parse("明天报销一天，说明：带资料，后天还要用；还有发票、收据，然后再归档", reference: reference)
        try expect(notes.drafts.count == 1 && notes.drafts[0].task.notes.contains("后天还要用；还有发票、收据，然后再归档"), "备注中的日期和分隔词不能拆成新任务")
        print("✓ 一句话多任务：并列、顺序、日期继承与完整备注")
    }
}
