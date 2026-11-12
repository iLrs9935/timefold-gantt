import Foundation
import SwiftUI

enum TaskTint: String, Codable, CaseIterable, Identifiable {
    case mint, blue, peach, lavender, gold
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mint: return "薄荷"
        case .blue: return "湖蓝"
        case .peach: return "珊瑚"
        case .lavender: return "紫藤"
        case .gold: return "麦黄"
        }
    }
    var color: Color {
        switch self {
        case .mint: return Color(hex: 0x4A9D87)
        case .blue: return Color(hex: 0x6099C0)
        case .peach: return Color(hex: 0xD08771)
        case .lavender: return Color(hex: 0x9B86BA)
        case .gold: return Color(hex: 0xB59A53)
        }
    }
}

struct GanttTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var progress: Double = 0
    var tint: TaskTint = .mint
    var notes = ""

    var duration: Int { Day.distance(start, end) + 1 }
    var isComplete: Bool { progress >= 1 }
    var isOverdue: Bool { !isComplete && Day.start(end) < Day.start(Date()) }

    func normalized() -> Self {
        var result = self
        result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.start = Day.start(start)
        result.end = max(result.start, Day.start(end))
        result.progress = min(1, max(0, progress.isFinite ? progress : 0))
        return result
    }

    func shifted(by days: Int) -> Self {
        var result = self
        result.start = Day.add(days, to: start)
        result.end = Day.add(days, to: end)
        return result
    }
}

struct Project: Codable, Equatable {
    var name = "我的项目"
    var tasks: [GanttTask] = []
    var isExample = false
    var progress: Double {
        let total = tasks.reduce(0) { $0 + $1.duration }
        guard total > 0 else { return 0 }
        return tasks.reduce(0) { $0 + $1.progress * Double($1.duration) } / Double(total)
    }
    var activeCount: Int { tasks.filter { !$0.isComplete }.count }

    static func example(today: Date = Date()) -> Project {
        let monday = Day.weekStart(today)
        return Project(name: "产品上线计划", tasks: [
            GanttTask(title: "需求与调研", start: Day.add(-1, to: monday), end: Day.add(2, to: monday), progress: 1, tint: .mint, notes: "梳理需求，确定本次上线的核心范围。"),
            GanttTask(title: "界面设计", start: Day.add(1, to: monday), end: Day.add(5, to: monday), progress: 0.65, tint: .blue),
            GanttTask(title: "功能开发", start: Day.add(3, to: monday), end: Day.add(10, to: monday), progress: 0.3, tint: .lavender),
            GanttTask(title: "测试与打磨", start: Day.add(8, to: monday), end: Day.add(12, to: monday), progress: 0, tint: .peach),
            GanttTask(title: "正式上线", start: Day.add(13, to: monday), end: Day.add(13, to: monday), progress: 0, tint: .gold)
        ], isExample: true)
    }
}

enum Day {
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.firstWeekday = 2
        return cal
    }
    static func start(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    static func add(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: start(date))!
    }
    static func distance(_ from: Date, _ to: Date) -> Int {
        calendar.dateComponents([.day], from: start(from), to: start(to)).day ?? 0
    }
    static func weekStart(_ date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        return add(-((weekday + 5) % 7), to: date)
    }
    static func isWeekend(_ date: Date) -> Bool { calendar.isDateInWeekend(date) }
    static func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }
    static func number(_ date: Date) -> String { String(calendar.component(.day, from: date)) }
    static func weekday(_ date: Date) -> String {
        ["日", "一", "二", "三", "四", "五", "六"][calendar.component(.weekday, from: date) - 1]
    }
    static func short(_ date: Date) -> String {
        "\(calendar.component(.month, from: date)).\(String(format: "%02d", calendar.component(.day, from: date)))"
    }
    static func range(_ start: Date, days: Int) -> String {
        let end = add(days - 1, to: start)
        return "\(calendar.component(.month, from: start)) 月 \(number(start)) 日 — \(calendar.component(.month, from: end)) 月 \(number(end)) 日"
    }
}

struct TimelineSpan: Equatable {
    let offset: Int
    let count: Int
    let clippedStart: Bool
    let clippedEnd: Bool

    static func visible(task: GanttTask, start: Date, days: Int) -> TimelineSpan? {
        let first = Day.distance(start, task.start)
        let last = Day.distance(start, task.end)
        guard last >= 0, first < days else { return nil }
        let lower = max(0, first)
        let upper = min(days - 1, last)
        return Self(offset: lower, count: upper - lower + 1,
                    clippedStart: first < 0, clippedEnd: last >= days)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}
