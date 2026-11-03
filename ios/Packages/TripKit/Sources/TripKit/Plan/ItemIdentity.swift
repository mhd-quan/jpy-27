import Foundation

/// What a record of a plan item (a stop done, a stop dropped) holds on to besides its index, so an
/// update that edits the plan never moves the mark onto the item that now sits at that index.
extension Day {
    /// A name for item `index` that survives an edit of the plan around it: the leg's id for a move,
    /// the place (else the title) for a stop, and for a place the day comes back to, which visit.
    public func identity(of index: Int) -> String? {
        guard items.indices.contains(index) else { return nil }
        let base = Self.identityBase(items[index])
        let before = items[..<index].lazy.filter { Self.identityBase($0) == base }.count
        return before == 0 ? base : "\(base)#\(before)"
    }

    private static func identityBase(_ item: DayItem) -> String {
        switch item {
        case .move(let m): "move:\(m.leg.id)"
        case .stop(let s): s.place.map { "stop:\($0)" } ?? "stop:\(s.title)"
        }
    }

    /// Where an item recorded at `index` as `identity` is now: still there, else the nearest item
    /// with that identity, else nowhere (the plan no longer has it). A record from before identities
    /// were kept (`identity` nil) keeps its index while the day still has one.
    public func resolve(_ index: Int, identity: String?) -> Int? {
        guard let identity else { return items.indices.contains(index) ? index : nil }
        if self.identity(of: index) == identity { return index }
        return items.indices
            .filter { self.identity(of: $0) == identity }
            .min { abs($0 - index) < abs($1 - index) }
    }
}
