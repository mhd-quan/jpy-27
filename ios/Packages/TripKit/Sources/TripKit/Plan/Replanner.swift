import Foundation

/// "Trễ 12 phút cho Ginza Line 16:15 — bỏ Umezono thì kịp": the first departure or reservation the
/// rest of today will miss, and the smallest set of stops to drop to make it.
public struct Replan: Sendable, Hashable {
    /// item index of the departure or reservation at risk
    public let target: Int
    /// minutes late, keeping every stop
    public let lateBy: Int
    /// stop indices to drop, in plan order; empty when nothing helps
    public let drop: [Int]
    /// minutes to spare once they are dropped (negative: still late)
    public let spare: Int

    public var works: Bool { !drop.isEmpty && spare >= 0 }

    /// Minutes late in five-minute steps, the nearest one (12 → 2, 13 → 3): the widget's snapshot
    /// counts as changed when the step does, not with every minute the projection moves.
    public static func lateStep(_ minutes: Int?) -> Int? {
        minutes.map { Int((Double($0) / 5).rounded()) }
    }
}

extension PlanEngine {
    /// Stops the replanner may drop: sights, food without a reservation, shops — never a hotel,
    /// a station, a reservation or a luggage errand.
    public func droppable(_ day: Day, from: Int, before target: Int, skips: Set<Int> = []) -> [Int] {
        (from ..< target).filter { i in
            guard case .stop(let s) = day.items[i], !skips.contains(i), let p = store.place(s.place) else { return false }
            if store.reserved.contains(p.id) || p.kind == .stay || p.kind == .station { return false }
            if s.isErrand { return false }
            return dwell(day, i, s) > 0
        }
    }

    /// The first fixed time ahead that the projection misses by more than its grace: a minute for a
    /// departure, two for a booking (`PlanRules.grace`, as the plan check counts them).
    public func firstMiss(_ day: Day, _ o: Options) -> (slot: Slot, lateBy: Double)? {
        let grace = store.trip.rules.grace
        for slot in simulate(day, o) where slot.hard && !slot.skipped {
            let allowed = Double(day.items[slot.index].move != nil ? grace.move : grace.stop)
            if let spare = slot.spare, spare < -allowed { return (slot, -spare) }
        }
        return nil
    }

    public func replan(_ day: Day, _ o: Options) -> Replan? {
        guard let (miss, lateBy) = firstMiss(day, o) else { return nil }
        let target = miss.index
        let candidates = droppable(day, from: o.from, before: target, skips: o.skips)

        func spare(dropping set: [Int]) -> Double {
            var opts = o
            opts.skips.formUnion(set)
            let slot = simulate(day, opts).first { $0.index == target }
            return slot?.spare ?? -.infinity
        }
        // cost of a drop: an optional stop is cheap, a long visit is dear
        func cost(_ set: [Int]) -> Double {
            set.reduce(0) { total, i in
                guard case .stop(let s) = day.items[i] else { return total }
                return total + (s.isOptional ? 10 : 30) + Double(dwell(day, i, s))
            }
        }

        var best: (set: [Int], spare: Double)?
        // `stride`, not `1 ... n`: with nothing left to drop (you are already at the departure,
        // or every stop before it is fixed) the closed range would be 1...0 and trap
        for size in stride(from: 1, through: min(3, candidates.count), by: 1) {
            for set in Self.combinations(candidates, size) {
                let s = spare(dropping: set)
                guard s >= 0 else { continue }
                if best == nil || cost(set) < cost(best!.set) { best = (set, s) }
            }
            if best != nil { break }
        }
        if let best {
            return Replan(target: target, lateBy: Int(lateBy.rounded(.up)), drop: best.set, spare: Int(best.spare.rounded(.down)))
        }
        // nothing makes it: say how far off it stays even with every droppable stop gone
        let all = spare(dropping: candidates)
        return Replan(target: target, lateBy: Int(lateBy.rounded(.up)), drop: [], spare: all.isFinite ? Int(all.rounded(.down)) : -Int(lateBy))
    }

    static func combinations<T>(_ items: [T], _ k: Int) -> [[T]] {
        guard k > 0 else { return [[]] }
        guard items.count >= k else { return [] }
        if k == items.count { return [items] }
        var out: [[T]] = []
        for (i, x) in items.enumerated() {
            for rest in combinations(Array(items[(i + 1)...]), k - 1) { out.append([x] + rest) }
        }
        return out
    }
}
