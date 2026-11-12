import AppKit
import Combine
import Foundation

struct SavedPlan: Identifiable, Codable, Equatable {
    var id = UUID()
    var project: Project
    var automaticPlaceholder: Bool? = nil
}

private struct PlanLibrary: Codable {
    var name: String
    var tasks: [GanttTask]
    var isExample: Bool
    var plans: [SavedPlan]
    var activePlanID: UUID
    var deletedPlans: [SavedPlan]?
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var project: Project
    @Published private(set) var plans: [SavedPlan] = []
    @Published private(set) var activePlanID = UUID()
    @Published private(set) var deletedPlans: [SavedPlan] = []
    private var lastActionWasPlanDeletion = false
    private var planHistories: [UUID: [Project]] = [:]
    @Published private(set) var saveError: String?
    @Published private(set) var canUndo = false
    @Published var pinned: Bool { didSet { defaults.set(pinned, forKey: "pinned") } }
    @Published var hideCompleted: Bool { didSet { defaults.set(hideCompleted, forKey: "hideCompleted") } }
    @Published var days: Int { didSet { defaults.set(days, forKey: "days") } }
    @Published var dark: Bool { didSet { defaults.set(dark, forKey: "dark") } }
    @Published var shortcut: GlobalShortcut { didSet { defaults.set(shortcut.rawValue, forKey: "shortcut") } }
    @Published var shortcutError: String?
    @Published var viewStart = Day.weekStart(Date())
    private let defaults: UserDefaults
    let fileURL: URL
    private var history: [Project] = []
    private(set) var hasUnreadableData = false

    init(fileURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Timefold", isDirectory: true).appendingPathComponent("project.json")
        pinned = defaults.bool(forKey: "pinned")
        hideCompleted = defaults.bool(forKey: "hideCompleted")
        let savedDays = defaults.integer(forKey: "days")
        days = [7, 14, 28].contains(savedDays) ? savedDays : 14
        dark = defaults.bool(forKey: "dark")
        shortcut = GlobalShortcut(rawValue: defaults.string(forKey: "shortcut") ?? "") ?? .controlOptionG
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            do {
                project = try Self.read(from: self.fileURL)
                let data = try Data(contentsOf: self.fileURL)
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if object?["plans"] != nil {
                    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                    let library = try decoder.decode(PlanLibrary.self, from: data)
                    guard !library.plans.isEmpty, Set(library.plans.map(\.id)).count == library.plans.count,
                          let active = library.plans.first(where: { $0.id == library.activePlanID }),
                          library.plans.allSatisfy({ $0.project.tasks.count <= 10_000 && Set($0.project.tasks.map(\.id)).count == $0.project.tasks.count }) else { throw CocoaError(.fileReadCorruptFile) }
                    deletedPlans = library.deletedPlans ?? []
                    plans = library.plans
                    activePlanID = library.activePlanID
                    project = active.project
                } else { plans = [SavedPlan(id: activePlanID, project: project)] }
            } catch {
                project = Project()
                hasUnreadableData = true
                saveError = L("无法读取任务文件，原文件已保留。请通过菜单检查数据文件。")
            }
        } else {
            project = .example()
            persist()
        }
    }

    func createPlan(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !hasUnreadableData else { return }
        lastActionWasPlanDeletion = false
        planHistories[activePlanID] = history
        let plan = SavedPlan(project: Project(name: name))
        plans.append(plan); activePlanID = plan.id; project = plan.project
        history = []; canUndo = false; today(); persist()
    }
    func switchPlan(_ id: UUID) {
        guard id != activePlanID, !hasUnreadableData, let plan = plans.first(where: { $0.id == id }) else { return }
        planHistories[activePlanID] = history
        lastActionWasPlanDeletion = false
        activePlanID = id; project = plan.project
        history = planHistories[id] ?? []; canUndo = !history.isEmpty
        if let first = project.tasks.first { reveal(first) } else { today() }
        persist()
    }

    func deleteCurrentPlan() {
        guard !hasUnreadableData else { return }
        planHistories[activePlanID] = history
        deletedPlans.append(SavedPlan(id: activePlanID, project: project))
        plans.removeAll { $0.id == activePlanID }
        if plans.isEmpty { plans = [SavedPlan(project: Project(), automaticPlaceholder: true)] }
        activePlanID = plans[0].id; project = plans[0].project
        history = planHistories[activePlanID] ?? []
        lastActionWasPlanDeletion = true; canUndo = true
        today(); persist()
    }
    func restoreDeletedPlan() {
        guard !hasUnreadableData, let plan = deletedPlans.popLast() else { return }
        planHistories[activePlanID] = history
        // Remove only untouched, automatically generated empty plans, including after a restart.
        plans.removeAll { $0.automaticPlaceholder == true && $0.project.tasks.isEmpty }
        plans.append(plan); activePlanID = plan.id; project = plan.project
        history = planHistories[plan.id] ?? []
        lastActionWasPlanDeletion = false; canUndo = !history.isEmpty
        if let first = project.tasks.first { reveal(first) } else { today() }
        persist()
    }

    var visibleTasks: [GanttTask] {
        project.tasks.filter { !hideCompleted || !$0.isComplete }
    }

    func save(_ task: GanttTask) {
        let value = task.normalized()
        guard !value.title.isEmpty else { return }
        mutate {
            if let index = $0.tasks.firstIndex(where: { $0.id == value.id }) {
                $0.tasks[index] = value
            } else {
                $0.tasks.append(value)
            }
            $0.isExample = false
        }
    }

    @discardableResult
    func save(_ tasks: [GanttTask]) -> Bool {
        guard !hasUnreadableData else { return false }
        let values = tasks.map { $0.normalized() }
        guard !values.isEmpty, values.allSatisfy({ !$0.title.isEmpty }) else {
            saveError = L("请补全任务名称后再添加。")
            return false
        }
        var next = project
        for value in values {
            if let index = next.tasks.firstIndex(where: { $0.id == value.id }) { next.tasks[index] = value }
            else { next.tasks.append(value) }
        }
        guard next.tasks.count <= 10_000 else {
            saveError = L("任务总数不能超过 10,000 项，请减少本次添加的任务。")
            return false
        }
        next.isExample = false
        if next == project { persist() } else { mutate { $0 = next } }
        return saveError == nil
    }

    func delete(_ id: UUID) { mutate { $0.tasks.removeAll { $0.id == id }; $0.isExample = false } }
    func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        mutate { $0.tasks.removeAll { ids.contains($0.id) }; $0.isExample = false }
    }
    func setComplete(_ complete: Bool, ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        mutate {
            for index in $0.tasks.indices where ids.contains($0.tasks[index].id) {
                $0.tasks[index].progress = complete ? 1 : 0
            }
            $0.isExample = false
        }
    }
    func toggle(_ task: GanttTask) {
        var value = task
        value.progress = task.isComplete ? 0 : 1
        save(value)
    }
    func rename(_ name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        mutate { $0.name = value; $0.isExample = false }
    }
    func clearExample() {
        guard project.isExample else { return }
        mutate { $0 = Project() }
    }
    func undo() {
        if lastActionWasPlanDeletion { restoreDeletedPlan(); return }
        guard let previous = history.popLast() else { return }
        project = previous
        canUndo = !history.isEmpty
        persist()
    }
    func navigate(_ direction: Int) { viewStart = Day.add(direction * days, to: viewStart) }
    func today() { viewStart = Day.weekStart(Date()) }
    func reveal(_ task: GanttTask) { viewStart = Day.weekStart(task.start) }

    private func mutate(_ change: (inout Project) -> Void) {
        guard !hasUnreadableData else { return }
        var next = project
        change(&next)
        guard next != project else { return }
        if let index = plans.firstIndex(where: { $0.id == activePlanID }) { plans[index].automaticPlaceholder = nil }
        lastActionWasPlanDeletion = false
        history.append(project)
        if history.count > 50 { history.removeFirst() }
        project = next
        canUndo = true
        persist()
    }

    private func persist() {
        guard !hasUnreadableData else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let index = plans.firstIndex(where: { $0.id == activePlanID }) { plans[index].project = project }
            else { plans.append(SavedPlan(id: activePlanID, project: project)) }
            let library = PlanLibrary(name: project.name, tasks: project.tasks, isExample: project.isExample,
                                      plans: plans, activePlanID: activePlanID, deletedPlans: deletedPlans)
            try encoder.encode(library).write(to: fileURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = L("保存失败：\(error.localizedDescription)")
        }
    }

    static func read(from url: URL) throws -> Project {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var project = try decoder.decode(Project.self, from: Data(contentsOf: url))
        guard project.tasks.count <= 10_000 else { throw CocoaError(.fileReadCorruptFile) }
        guard Set(project.tasks.map(\.id)).count == project.tasks.count else { throw CocoaError(.fileReadCorruptFile) }
        project.tasks = project.tasks.map { $0.normalized() }
        return project
    }

    func exportJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(project.name).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(project).write(to: url, options: .atomic)
        } catch { saveError = L("导出失败：\(error.localizedDescription)") }
    }

    func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let loaded = try Self.read(from: url)
            guard !hasUnreadableData else { return }
            mutate { $0 = loaded }
            if let first = loaded.tasks.first { reveal(first) }
        } catch { saveError = L("导入失败：请选择时序导出的有效 JSON 文件。") }
    }
}
