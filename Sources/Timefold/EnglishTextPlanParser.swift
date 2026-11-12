import Foundation

enum EnglishTextPlanParser {
    private static let number = #"(?:-?\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten|half|an?|zero)"#
    private static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static func accepts(_ text: String) -> Bool {
        text.range(of: #"\b(?:today|tomorrow|tonight|next|this|by|then|days?|weeks?|hours?|minutes?|morning|afternoon|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#, options: [.regularExpression, .caseInsensitive]) != nil ||
        (text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil && text.range(of: #"\p{Han}"#, options: .regularExpression) == nil)
    }
    static func parse(_ input: String, reference: Date) -> TextPlanResult {
        guard input.count <= 20_000 else { return TextPlanResult(issues: ["Text is too long. Please use at most 20,000 characters per batch."]) }
        var sourceMap: [String: String] = [:]
        let lines = input.components(separatedBy: .newlines)
        for line in lines {
            let marker = line.range(of: #"\b(?:notes?|description)\s*:"#, options: [.regularExpression,.caseInsensitive])
            let body = marker.map { String(line[..<$0.lowerBound]) } ?? line
            let note = marker.map { String(line[$0.lowerBound...]) } ?? ""
            var parts = body.components(separatedBy: ";").flatMap {
                $0.replacingOccurrences(of: #",?\s*\b(?:and then|then|after that|finally)\b\s*"#, with: "\u{1E}", options: [.regularExpression, .caseInsensitive]).components(separatedBy: "\u{1E}")
            }
            if !parts.isEmpty { parts[parts.count - 1] += note }
            for part in parts { sourceMap[normalize(part, reference: reference).trimmingCharacters(in: .whitespacesAndNewlines)] = part.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let canonical = lines.map { normalize($0, reference: reference) }.joined(separator: "\n")
        var result = TextPlanParser.parse(canonical, reference: reference, useEnglishAdapter: false)
        for i in result.drafts.indices {
            let source = sourceMap[result.drafts[i].source] ?? input
            result.drafts[i].source = source
            result.drafts[i].warnings = result.drafts[i].warnings.map { english($0) }
            if source.range(of: #"\bnext\s+(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b"#, options: [.regularExpression,.caseInsensitive]) != nil {
                result.drafts[i].warnings.append("Next weekday means the following calendar week. Review the date.")
            }
            let notes = result.drafts[i].task.notes.components(separatedBy: .newlines).filter { !$0.hasPrefix("原文：") }.map { line in
                ["时段：", "估时：", "截止：", "时间：", "排期说明："].contains(where: { line.hasPrefix($0) }) ? english(line) : line
            }
            result.drafts[i].task.notes = (notes + ["Source: \(source)"]).joined(separator: "\n")
        }
        result.issues = result.issues.map { issue in
            let reason = issue.components(separatedBy: "」：").last ?? issue
            let translated = english(reason)
            return "Unable to parse: \(translated)\nSource: \(input)"
        }
        return result
    }
    private static func amount(_ value: String) -> Double {
        Double(value) ?? ["zero":0,"a":1,"an":1,"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10,"half":0.5][value.lowercased()] ?? 0
    }
    private static func numeric(_ value: Double) -> String { String(format: "%.12g", value) }
    private static func iso(_ date: Date) -> String {
        let c = Day.calendar.dateComponents([.year,.month,.day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    private static func replace(_ pattern: String, in text: String, _ transform: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        let ns = text as NSString; var value = text
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let groups = (0..<m.numberOfRanges).map { m.range(at:$0).location == NSNotFound ? "" : ns.substring(with:m.range(at:$0)) }
            value = (value as NSString).replacingCharacters(in:m.range, with:transform(groups))
        }
        return value
    }
    private static func normalize(_ source: String, reference: Date) -> String {
        var text = source
        // Keep notes outside grammar normalization, including dates and sequence words inside them.
        var note = ""
        if let range = text.range(of: #"\b(?:notes?|description)\s*:"#, options: [.regularExpression,.caseInsensitive]) {
            note = "备注：" + text[range.upperBound...]; text = String(text[..<range.lowerBound])
        }
        text = replace(#"\b(start of next month|beginning of next month)\b"#, in:text) { _ in "下月初" }
        text = replace(#"\b(end of next month|end of this month|end of month)\b"#, in:text) { g in g[0].lowercased().contains("next") ? "下月底" : "本月底" }
        text = replace(#"\bday after tomorrow\b"#, in:text) { _ in "后天" }
        text = replace(#"\b(tomorrow|today|tonight)\b"#, in:text) { g in ["tomorrow":"明天","today":"今天","tonight":"今天晚上"][g[1].lowercased()]! }
        text = replace(#"\bin\s+("# + number + #")\s+days?\b"#, in:text) { g in
            let n = amount(g[1]); return n >= 0 && n <= 3650 ? iso(Day.add(Int(n.rounded(.up)),to:reference)) : "9999-99-99"
        }
        let months = ["jan":1,"feb":2,"mar":3,"apr":4,"may":5,"jun":6,"jul":7,"aug":8,"sep":9,"oct":10,"nov":11,"dec":12]
        text = replace(#"\b(?:on\s+)?(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b"#, in:text) { g in
            let year = Int(g[3]) ?? Day.calendar.component(.year,from:reference)
            return String(format:"%04d-%02d-%02d",year,months[String(g[1].lowercased().prefix(3))]!,Int(g[2])!)
        }
        text = replace(#"\b(?:(next|this)\s+)?(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b"#, in:text) { g in
            let index = weekdays.firstIndex(of:g[2].lowercased())!
            var date = Day.add(index + (g[1].lowercased() == "next" ? 7 : 0),to:Day.weekStart(reference))
            if g[1].isEmpty && date < Day.start(reference) { date = Day.add(7,to:date) }
            return iso(date)
        }
        text = replace(#"\b(?:by|before|due(?:\s+by)?)\s+((?:\d{4}-\d{2}-\d{2}|明天|今天|后天|下月初|本月底|下月底))"#, in:text) { g in "截止" + g[1] }
        text = replace(#"\b(?:from|on|starting)\s+(?=\d{4}-|明天|今天|后天)"#, in:text) { _ in "" }
        text = replace(#"\b(?:to|through|until)\s+(?=\d{4}-|明天|今天|后天)"#, in:text) { _ in "到" }
        text = replace(#"\b(?:at\s+the|at|on|in)\s+(?=下月初|本月底|下月底)"#, in:text) { _ in "" }
        text = replace(#"\bnext week\b"#, in:text) { _ in "下周" }
        text = replace(#"\bnext month\b"#, in:text) { _ in "下月初" }
        text = replace(#"\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#, in:text) { g in
            let hour = Int(g[1])!; let minute = Int(g[2]) ?? 0
            if hour < 1 || hour > 12 || minute > 59 { return "25:99" }
            return String(format:"%02d:%02d",hour % 12 + (g[3].lowercased() == "pm" ? 12 : 0),minute)
        }
        text = replace(#"\bat\s+(?=\d{1,2}:\d{2})"#, in:text) { _ in "" }
        text = replace(#"\b(morning|afternoon|evening)\b"#, in:text) { g in ["morning":"早上","afternoon":"下午","evening":"晚上"][g[1].lowercased()]! }
        text = replace(#"\bhalf\s+(?:a\s+)?(day|hour)\b"#, in:text) { g in "0.5" + (g[1].lowercased() == "day" ? "天" : "小时") }
        text = replace(#"\b(one|two|three)\s+and\s+a\s+half\s+(days?|hours?)\b"#, in:text) { g in "\(amount(g[1])+0.5)" + (g[2].lowercased().hasPrefix("day") ? "天" : "小时") }
        text = replace(#"\b(?:for\s+|takes?\s+|duration\s*:\s*)?("# + number + #")(?:\s*(?:-|–|to)\s*("# + number + #"))?\s*(business days?|working days?|days?|weeks?|hours?|minutes?)\b"#, in:text) { g in
            let unit = g[3].lowercased(); let multiplier = unit.hasPrefix("week") ? 7.0 : (unit.hasPrefix("hour") ? 1.0/24 : (unit.hasPrefix("minute") ? 1.0/1440 : 1.0))
            let low = amount(g[1])*multiplier
            let range = g[2].isEmpty ? "" : "-\(numeric(amount(g[2])*multiplier))"
            return "预计\(numeric(low))\(range)" + ((unit.hasPrefix("business") || unit.hasPrefix("working")) ? "个工作日" : "天")
        }
        text = replace(#"\b(?:for|takes?)\s+(?=-?\d+(?:\.\d+)?(?:天|小时))"#, in:text) { _ in "" }
        text = replace(#"\b(?:progress\s*:?|completed)\s*(\d+(?:\.\d+)?)\s*%"#, in:text) { g in "进度\(g[1])%" }
        text = replace(#"(\d+(?:\.\d+)?)\s*%\s*(?:complete|done)\b"#, in:text) { g in "进度\(g[1])%" }
        text = replace(#"\bhalf\s+done\b"#, in:text) { _ in "进度一半" }
        text = replace(#"\b(?:already completed|already done|status:\s*done)\b"#, in:text) { _ in "已完成" }
        text = replace(#"\b(?:and then|then|after that|finally)\b"#, in:text) { _ in "然后" }
        text = replace(#"(天|工作日)\s+and\s+"#, in:text) { g in g[1]+"和" }
        return text + note
    }
    private static func english(_ text: String) -> String {
        var value = EnglishStrings.translate(text)
        for (zh,en) in ["个工作日":" business days", "工作日":" business days", "早上":"morning", "下午":"afternoon", "晚上":"evening", "小时":" hours", "预计":"", "天":" days"] {
            value = value.replacingOccurrences(of:zh,with:en)
        }
        if value.range(of:#"\p{Han}"#,options:.regularExpression) != nil { return "Review the inferred dates and duration before adding." }
        return value.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
    }
}
