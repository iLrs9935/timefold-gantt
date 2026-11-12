import Foundation

struct TaskSelection {
    private(set) var ids: Set<UUID> = []
    private(set) var anchor: UUID?

    mutating func select(_ id: UUID, ordered: [UUID], extending: Bool = false, toggling: Bool = false) {
        guard ordered.contains(id) else { return }
        if extending, let anchor, let first = ordered.firstIndex(of: anchor), let last = ordered.firstIndex(of: id) {
            let range = Set(ordered[min(first, last)...max(first, last)])
            ids = toggling ? ids.union(range) : range
        } else {
            if toggling {
                if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            } else { ids = [id] }
            anchor = id
        }
    }
    mutating func selectAll(_ ordered: [UUID]) { ids = Set(ordered); anchor = ordered.first }
    mutating func clear() { ids.removeAll(); anchor = nil }
    mutating func retain(_ valid: Set<UUID>) {
        ids.formIntersection(valid)
        if let anchor, !valid.contains(anchor) { self.anchor = nil }
    }
}
