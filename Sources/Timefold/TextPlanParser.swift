import Foundation

struct TextPlanDraft: Identifiable {
    var task: GanttTask
    var source: String
    var warnings: [String]
    var included = true
    var id: UUID { task.id }
}

struct TextPlanResult {
    var drafts: [TextPlanDraft] = []
    var issues: [String] = []
}

/// Offline Chinese scheduling expressions. Uncertain choices remain visible before saving.
enum TextPlanParser {
    private static let digits = #"[0-9零〇一二两三四五六七八九十]+"#
    private static let number = #"(?:-?\d+(?:\.\d+)?|[零〇一二两三四五六七八九十百千]+|半)"#
    private static let datePattern = #"\d{4}[-/]\d{1,2}[-/]\d{1,2}|(?:\d{4}年)?"# + digits + #"月"# + digits + #"[日号]?|\d{1,2}/\d{1,2}|(?:下个月|下月|这个月|本月)?"# + digits + #"[日号]|大后天|后天|明天|今天|今日|明日|前天|昨天|昨日|"# + number + #"天(?:以后|之后|后)|(?:(?:下下|下|本|这)(?:个)?)?(?:周|星期|礼拜)[一二三四五六日天1-7末]|(?:下下|下|本|这)(?:周|星期)|(?:本|下|这)?(?:月底|月末)|(?:本月|下月|下个月)(?:底|末)"#

    private struct Token {
        var match: NSTextCheckingResult
        var text: String
        var ns: NSString
        func group(_ index: Int) -> String {
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : ns.substring(with: range)
        }
    }
    private struct Context { var date: Date; var period: String }
    private enum ParseError: Error { case invalid(String) }

    static func parse(_ input: String, reference: Date = Date()) -> TextPlanResult {
        var result = TextPlanResult()
        guard input.count <= 20_000 else {
            result.issues = ["文字过长，请分成每次不超过 20,000 字的几段。"]
            return result
        }
        let normalized = input.folding(options: .widthInsensitive, locale: Locale(identifier: "zh_CN"))
        // A comma before another explicit date starts a new task; other commas describe the current task.
        let separated = replacing(#"[,，](?=\s*(?:今天|明天|后天|大后天|(?:下下|下|本|这)?(?:周|星期|礼拜)[一二三四五六日天]|\d{1,2}[月日号]))"#, in: normalized, with: "\n")
        var heading: Context?
        var count = 0
        for rawLine in separated.components(separatedBy: CharacterSet(charactersIn: "\n；;")) {
            let line = replacing(#"^\s*(?:[-*•]\s+|\d+[、.．)）]\s*)"#, in: rawLine, with: "")
            // Keep enumeration punctuation inside a note intact.
            let noteStart = first(#"备注\s*[:：]"#, in: line)?.match.range.location
            let body = noteStart.map { (line as NSString).substring(to: $0) } ?? line
            let note = noteStart.map { (line as NSString).substring(from: $0) } ?? ""
            let parts = body.components(separatedBy: "、")
            var context = heading
            for (index, part) in parts.enumerated() {
                let source = (part + (index == parts.count - 1 ? note : "")).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty else { continue }
                count += 1
                guard count <= 200 else { result.issues.append("每次最多解析 200 条，请将剩余文字分批输入。"); return result }
                do {
                    let parsed = try parseTask(source, reference: Day.start(reference), context: context, tintIndex: result.drafts.count)
                    context = parsed.context
                    if let draft = parsed.draft { result.drafts.append(draft) }
                    else { heading = parsed.context }
                } catch ParseError.invalid(let message) {
                    result.issues.append("「\(source)」：\(message)")
                } catch { result.issues.append("「\(source)」：未能识别，请调整文字后重试。") }
            }
        }
        return result
    }

    private static func parseTask(_ source: String, reference: Date, context: Context?, tintIndex: Int) throws -> (draft: TextPlanDraft?, context: Context) {
        var text = source
        var notes: [String] = []
        var warnings: [String] = []
        if let token = first(#"备注\s*[:：]\s*(.*)$"#, in: text) {
            notes.append(token.group(1)); remove(token, from: &text)
        }

        let tokens = matches(datePattern, in: text).filter { token in
            // “持续三日” is a duration; a bare “三日” is a calendar date.
            let prefix = (text as NSString).substring(to: token.match.range.location)
            let isDayOnly = first(#"^"# + digits + #"日$"#, in: token.text) != nil
            return !(isDayOnly && first(#"(?:持续|为期|预计|估计|大约|大概|耗时|用时|需要|共)\s*$"#, in: prefix) != nil)
        }
        let start: Date
        var explicitEnd: Date?
        if let token = tokens.first {
            let leading = (text as NSString).substring(to: token.match.range.location)
            start = try resolveDate(token.text, reference: reference, base: nil)
            var consumed = [token]
            if tokens.count > 1 {
                let next = tokens[1]
                let gap = (text as NSString).substring(with: NSRange(location: NSMaxRange(token.match.range), length: next.match.range.location - NSMaxRange(token.match.range)))
                    .trimmingCharacters(in: .whitespaces)
                if ["至", "到", "-", "—", "–", "~", "～"].contains(gap) {
                    explicitEnd = try resolveDate(next.text, reference: reference, base: start)
                    guard explicitEnd! >= start else { throw ParseError.invalid("结束日期早于开始日期，请写清起止日期。") }
                    if next.text.range(of: #"^[0-9一二三四五六七八九十]+[日号]$"#, options: .regularExpression) != nil,
                       let end = explicitEnd, Day.calendar.component(.month, from: end) != Day.calendar.component(.month, from: start) {
                        warnings.append("结束日期没有写月份，已按跨月安排，请确认。")
                    }
                    if let end = explicitEnd, Day.distance(start, end) > 3650 { throw ParseError.invalid("日期范围超过 3,650 天，请缩短排期。") }
                    text = (text as NSString).replacingCharacters(in: NSRange(location: token.match.range.location, length: NSMaxRange(next.match.range) - token.match.range.location), with: "")
                    consumed.removeAll()
                } else { warnings.append("出现多个日期，暂用第一个作为开始日期，请确认。") }
            }
            for token in consumed.reversed() { remove(token, from: &text) }
            if ["从", "在", "于", "请"].contains(leading.trimmingCharacters(in: .whitespaces)) { text = String(text.dropFirst(leading.count)) }
            if ["下周", "下下周", "本周", "这周", "下星期", "本星期"].contains(token.text) {
                warnings.append("没有指定星期几，按该周周一安排。")
            }
        } else if let context {
            start = context.date
            warnings.append("沿用上一项的日期 \(Day.short(start))。")
        } else {
            start = reference
            warnings.append("没有写开始日期，先安排在今天。")
        }

        var period = tokens.isEmpty ? (context?.period ?? "") : ""
        if let token = first(#"上午|下午|早上|早晨|中午|晚上|傍晚|全天"#, in: text) {
            period = token.text; remove(token, from: &text)
        }
        if !period.isEmpty {
            notes.append("时段：\(period)")
            if period != "全天" { warnings.append("按天显示，\(period)保存在备注中。") }
        }

        var duration = 1
        var workdays = false
        var explicitDuration = false
        let durationPattern = #"(?:预计|估计|大约|大概|持续|耗时|用时|需要|为期|共)?\s*("# + number + #")(?:\s*[-—–~～至到]\s*("# + number + #"))?\s*(个?工作日|天|日|周|星期|小时)(半)?"#
        if let token = first(durationPattern, in: text) {
            let lower = numeric(token.group(1)) ?? 0
            let upper = token.group(2).isEmpty ? lower : (numeric(token.group(2)) ?? 0)
            let amount = upper + (token.group(4).isEmpty ? 0 : 0.5)
            let unit = token.group(3)
            let days = amount * (["周", "星期"].contains(unit) ? 7 : (unit == "小时" ? 1.0 / 24 : 1))
            guard lower > 0, upper >= lower, days > 0, days <= 3650 else {
                throw ParseError.invalid("持续时长无效，请填写 0 到 3,650 天之间的正数。")
            }
            duration = max(1, Int(days.rounded(.up)))
            workdays = unit.contains("工作日")
            explicitDuration = true
            notes.append("估时：\(token.text.trimmingCharacters(in: .whitespaces))")
            if !token.group(2).isEmpty { warnings.append("时长为范围，先按上限 \(duration)\(workdays ? " 个工作日" : " 天")安排。") }
            if days != days.rounded() || unit == "小时" { warnings.append("甘特图按整天显示，估时向上取整，原估时保存在备注中。") }
            remove(token, from: &text)
        } else if explicitEnd == nil { warnings.append("没有写时长，先安排 1 天。") }

        var end = Day.add(duration - 1, to: start)
        if workdays {
            end = start
            var remaining = duration
            while true {
                if !Day.isWeekend(end) { remaining -= 1 }
                if remaining == 0 { break }
                end = Day.add(1, to: end)
            }
            warnings.append("工作日估时已跳过周末，任务条仍显示连续日期。")
        }
        if let explicitEnd {
            if explicitDuration && explicitEnd != end { warnings.append("日期范围与估时不同，已优先采用明确的起止日期。") }
            end = explicitEnd
        }

        var progress = 0.0
        let progressPrefix = #"(?:进度|已经完成|已完成了|已完成|完成了|已做)\s*[为是:：]?\s*"#
        if let token = first(progressPrefix + #"(-?\d+(?:\.\d+)?)\s*[%％]"#, in: text) {
            guard let value = Double(token.group(1)), value.isFinite, (0...100).contains(value) else { throw ParseError.invalid("进度应在 0% 到 100% 之间。") }
            progress = value / 100; remove(token, from: &text)
        } else if let token = first(progressPrefix + #"百分之("# + number + #")"#, in: text) {
            guard let value = numeric(token.group(1)), (0...100).contains(value) else { throw ParseError.invalid("进度应在 0% 到 100% 之间。") }
            progress = value / 100; remove(token, from: &text)
        } else if let token = first(progressPrefix + #"(?:一半|半)"#, in: text) {
            progress = 0.5; remove(token, from: &text)
        } else if let token = first(#"(?:已经完成|已完成|已做完|已结束)(?!了?[0-9一二三四五六七八九十半百零〇两])"#, in: text) {
            progress = 1; remove(token, from: &text)
        }
        var tint = TaskTint.allCases[tintIndex % TaskTint.allCases.count]
        if let token = first(#"(?:颜色\s*[为是:：]?|标为|标成)\s*(薄荷|绿色|绿|湖蓝|蓝色|蓝|珊瑚|红色|红|紫藤|紫色|紫|麦黄|黄色|黄)"#, in: text) {
            let color = token.group(1)
            if ["薄荷", "绿色", "绿"].contains(color) { tint = .mint }
            if ["湖蓝", "蓝色", "蓝"].contains(color) { tint = .blue }
            if ["珊瑚", "红色", "红"].contains(color) { tint = .peach }
            if ["紫藤", "紫色", "紫"].contains(color) { tint = .lavender }
            if ["麦黄", "黄色", "黄"].contains(color) { tint = .gold }
            remove(token, from: &text)
        }
        if source.contains("每周") || source.contains("每天") || source.contains("每月") {
            warnings.append("包含重复安排，本次只创建一次任务；重复要求保留在原文中。")
        }
        let title = cleanTitle(text)
        let newContext = Context(date: start, period: period)
        if title.isEmpty {
            // A date-only heading applies to the following lines, without creating an empty task.
            if !tokens.isEmpty && !explicitDuration && explicitEnd == nil { return (nil, newContext) }
            throw ParseError.invalid("缺少任务名称，请补上要做的事情。")
        }
        if title.count > 300 { throw ParseError.invalid("任务名称过长，请将补充说明放在“备注：”之后。") }
        notes.append("原文：\(source)")
        let task = GanttTask(title: title, start: start, end: end, progress: progress, tint: tint, notes: notes.joined(separator: "\n"))
        return (TextPlanDraft(task: task, source: source, warnings: warnings), newContext)
    }

    private static func resolveDate(_ text: String, reference: Date, base: Date?) throws -> Date {
        let calendar = Day.calendar
        let baseDate = base ?? reference
        var year = calendar.component(.year, from: baseDate)
        var month = calendar.component(.month, from: baseDate)
        let relative = ["前天": -2, "昨天": -1, "昨日": -1, "今天": 0, "今日": 0, "明天": 1, "明日": 1, "后天": 2, "大后天": 3]
        if let offset = relative[text] { return Day.add(offset, to: reference) }
        if let token = first(#"^("# + number + #")天(?:以后|之后|后)$"#, in: text), let count = numeric(token.group(1)), count >= 0, count <= 3650 {
            return Day.add(Int(count.rounded(.up)), to: reference)
        }
        if text.contains("周") || text.contains("星期") || text.contains("礼拜") {
            let offset = text.hasPrefix("下下") ? 14 : (text.hasPrefix("下") ? 7 : 0)
            let weekday = text.last.map(String.init) ?? "一"
            let day = ["一": 0, "1": 0, "二": 1, "2": 1, "三": 2, "3": 2, "四": 3, "4": 3, "五": 4, "5": 4, "六": 5, "6": 5, "末": 5, "日": 6, "天": 6, "7": 6][weekday] ?? 0
            let plain = !["下", "本", "这"].contains(where: { text.hasPrefix($0) })
            var date = Day.add(offset + day, to: Day.weekStart(plain ? baseDate : reference))
            if base != nil && plain && date < baseDate { date = Day.add(7, to: date) }
            return date
        }
        if text.contains("月底") || text.contains("月末") || text.hasSuffix("月末") || text.hasSuffix("月底") || text.hasSuffix("个月底") {
            let firstDay = try checkedDate(year: year, month: month, day: 1, source: text)
            let offset = text.hasPrefix("下") ? 2 : 1
            return Day.add(-1, to: calendar.date(byAdding: .month, value: offset, to: firstDay)!)
        }
        if let token = first(#"^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$"#, in: text) {
            return try checkedDate(year: Int(token.group(1))!, month: Int(token.group(2))!, day: Int(token.group(3))!, source: text)
        }
        if let token = first(#"^(?:(\d{4})年)?("# + digits + #")月("# + digits + #")[日号]?$"#, in: text) {
            let explicitYear = !token.group(1).isEmpty
            if explicitYear { year = Int(token.group(1))! }
            let targetMonth = integer(token.group(2)) ?? 0
            if base != nil && !explicitYear && targetMonth < month { year += 1 }
            return try checkedDate(year: year, month: targetMonth, day: integer(token.group(3)) ?? 0, source: text)
        }
        if let token = first(#"^(\d{1,2})/(\d{1,2})$"#, in: text) {
            let targetMonth = Int(token.group(1))!
            if base != nil && targetMonth < month { year += 1 }
            return try checkedDate(year: year, month: targetMonth, day: Int(token.group(2))!, source: text)
        }
        if let token = first(#"^(下个月|下月|这个月|本月)?("# + digits + #")[日号]$"#, in: text) {
            if !token.group(1).isEmpty {
                year = calendar.component(.year, from: reference)
                month = calendar.component(.month, from: reference)
            }
            if token.group(1).hasPrefix("下") { month += 1; if month > 12 { month = 1; year += 1 } }
            let day = integer(token.group(2)) ?? 0
            if base != nil && token.group(1).isEmpty && day < calendar.component(.day, from: baseDate) {
                month += 1; if month > 12 { month = 1; year += 1 }
            }
            return try checkedDate(year: year, month: month, day: day, source: text)
        }
        throw ParseError.invalid("无法确定日期“\(text)”，请改成例如“11月15日”。")
    }

    private static func checkedDate(year: Int, month: Int, day: Int, source: String) throws -> Date {
        let calendar = Day.calendar
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: date) == year, calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day else {
            throw ParseError.invalid("日期“\(source)”不存在，请检查月份和天数。")
        }
        return Day.start(date)
    }

    private static func numeric(_ value: String) -> Double? {
        if value == "半" { return 0.5 }
        if let number = Double(value) { return number.isFinite ? number : nil }
        guard value.count <= 16 else { return nil }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
        var total = 0, current = 0
        for char in value {
            if let digit = digits[char] { current = current * 10 + digit }
            else if let unit = units[char] { total += max(1, current) * unit; current = 0 }
            else { return nil }
        }
        return value.isEmpty ? nil : Double(total + current)
    }

    private static func integer(_ text: String) -> Int? {
        guard let value = numeric(text), value >= 0, value <= 9999, value == value.rounded() else { return nil }
        return Int(value)
    }

    private static func cleanTitle(_ value: String) -> String {
        var text = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,：:。.!！-—~～")))
        text = replacing(#"^(?:(?:请帮我|帮我|请安排|我想要|我想|我要|开始|起)\s*[,，:：]?\s*)+"#, in: text, with: "")
        text = replacing(#"(?:\s*[,，:：]?\s*(?:预计|估计|大约|大概|持续|耗时|用时|需要|为期|共|用|开始|起|完成进度|进度))+$"#, in: text, with: "")
        text = replacing(#"\s*[,，]\s*"#, in: text, with: "，")
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,：:。.!！-—~～")))
    }
    private static func matches(_ pattern: String, in text: String) -> [Token] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { Token(match: $0, text: ns.substring(with: $0.range), ns: ns) }
    }
    private static func first(_ pattern: String, in text: String) -> Token? { matches(pattern, in: text).first }
    private static func remove(_ token: Token, from text: inout String) { text = (text as NSString).replacingCharacters(in: token.match.range, with: "") }
    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
}
