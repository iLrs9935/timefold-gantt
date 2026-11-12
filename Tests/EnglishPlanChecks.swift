import Foundation
extension ModelChecks {
    static func checkEnglishPlans() throws {
        let reference = date("2026-11-12")
        let result = TextPlanParser.parse("File expenses tomorrow afternoon for 2-3 days, then draft report for one day\nSubmit checklist by Friday at 5pm for two days\nCheck receipts at the start of next month for half a day", reference: reference)
        try expect(result.issues.isEmpty && result.drafts.count == 4, "English compound tasks")
        try expect(result.drafts.map { $0.task.title } == ["File expenses", "draft report", "Submit checklist", "Check receipts"], "English titles must not retain grammar tokens")
        try expect(result.drafts[0].task.start == date("2026-11-13") && result.drafts[0].task.end == date("2026-11-15"), "English duration range")
        try expect(result.drafts[1].task.start == date("2026-11-16"), "English then sequence")
        try expect(result.drafts[2].task.start == reference && result.drafts[2].task.end == date("2026-11-13") && result.drafts[2].task.notes.contains("17:00"), "English deadline and PM time")
        try expect(result.drafts[3].task.start == date("2026-12-01") && result.drafts[3].task.duration == 1, "English next month and half day")
        try expect(result.drafts.flatMap(\.warnings).allSatisfy { $0.range(of: #"\p{Han}"#, options: .regularExpression) == nil }, "English warnings")
        let dates = TextPlanParser.parse("Test next Monday for three business days\nShip on November 20, 2026 for a day\nStudy tomorrow for one and a half days\nReview in three days for two hours, 50% complete", reference: reference)
        try expect(dates.issues.isEmpty && dates.drafts.count == 4, "English dates and durations")
        try expect(dates.drafts[0].task.start == date("2026-11-16") && dates.drafts[0].task.end == date("2026-11-18"), "English weekday and business days")
        try expect(dates.drafts[1].task.start == date("2026-11-20"), "English named month")
        try expect(dates.drafts[2].task.title == "Study" && dates.drafts[2].task.duration == 2, "One and a half days")
        try expect(dates.drafts[3].task.start == date("2026-11-15") && dates.drafts[3].task.progress == 0.5, "Relative date and percentage")
        for text in ["Ship on February 30, 2026 for one day", "Meet tomorrow at 13pm", "Draft tomorrow for zero days"] {
            let invalid = TextPlanParser.parse(text, reference: reference)
            try expect(invalid.drafts.isEmpty && !invalid.issues.isEmpty, "Invalid English input: \(text)")
        }
        let notes = TextPlanParser.parse("Draft tomorrow for a day, Notes: 保留这句话，then call tomorrow; keep receipts", reference: reference)
        try expect(notes.drafts.count == 1 && notes.drafts[0].task.notes.contains("保留这句话，then call tomorrow; keep receipts"), "English notes stay intact, including Chinese text")
        let multiline = TextPlanParser.parse("Draft tomorrow for a day, Notes: call tomorrow; keep receipts\nTest next Monday for 2 business days", reference: reference)
        try expect(multiline.issues.isEmpty && multiline.drafts.count == 2 && multiline.drafts[1].task.title == "Test" && multiline.drafts[1].source == "Test next Monday for 2 business days", "A note must not swallow the next line's English grammar or source")
        let fractional = TextPlanParser.parse("明天研究预计1.5天", reference: reference)
        try expect(fractional.issues.isEmpty && fractional.drafts.first?.task.duration == 2, "Decimal estimates are durations, not month/day dates")
        let oldLanguage = AppLanguage.shared.code
        AppLanguage.shared.code = "en"
        try expect(L("删除当前计划") == "Delete current plan" && L("已选 3 项") == "3 selected", "Static and dynamic English localization")
        try expect(Day.weekday(reference) == "Th" && L("1 天") == "1 day", "English weekdays and singular day")
        AppLanguage.shared.code = oldLanguage
        print("✓ English text scheduling, validation, notes and localization")
    }
}
