import Foundation

/// What a record of a plan item (a stop done, a stop dropped) holds on to besides its index, so an
/// update that edits the plan never moves the mark onto the item that now sits at that index: the
/// item's id, written in the data (`DayItem.id`).
///
/// Records kept before items had ids named them by the old scheme (`legacyIdentity(of:)`: "stop:" or
/// "move:"), which names a place the day comes back to by its order of visits. Those still find their
/// item, the way they always did, until each is converted once (`read`, `migrate`) on the plan it was
/// written under; one that found no item then is shown nowhere after.
extension Day {
    /// The id of item `index`; nil when the day has no such item.
    public func identity(of index: Int) -> String? {
        items.indices.contains(index) ? items[index].id : nil
    }

    /// Where the item with id `id` is in the day; nil when the plan no longer has it.
    public func index(of id: String) -> Int? {
        items.firstIndex { $0.id == id }
    }

    /// Where an item recorded at `index` as `identity` is now: the item with that id, wherever it is,
    /// else nowhere (the plan no longer has it). A record from before identities were kept (`identity`
    /// nil) keeps its index while the day still has one. An old-scheme identity finds its item as it
    /// always did: at its index if that item has the name, else the nearest item that has it.
    public func resolve(_ index: Int, identity: String?) -> Int? {
        guard let identity else { return items.indices.contains(index) ? index : nil }
        if Self.isLegacy(identity) { return legacyResolve(index, identity: identity) }
        if items.indices.contains(index), items[index].id == identity { return index }
        return self.index(of: identity)
    }

    /// The id a record of `id` follows now: the day's renames (`Trip.idRenames[key]`) map an id an
    /// update changed to the one the visit has now. One step, as the data writes them; an id the day
    /// still has is never renamed away, and an old-scheme identity is never looked up (the plan
    /// converts it, `migrate`).
    public func renamed(_ id: String, renames: [String: String]) -> String {
        guard !Self.isLegacy(id), index(of: id) == nil, let to = renames[id] else { return id }
        return to
    }

    /// The id a record should carry, converted once from what it holds: an id goes through the renames;
    /// an old-scheme identity becomes the id of the item it finds on this plan (nil when the plan no
    /// longer has it); no identity at all names the item at `index`, while the day has one.
    public func migrate(legacy: String?, index: Int, renames: [String: String]) -> String? {
        guard let legacy else { return identity(of: index) }
        guard Self.isLegacy(legacy) else { return renamed(legacy, renames: renames) }
        return legacyResolve(index, identity: legacy).map { items[$0].id }
    }

    // MARK: Reading the records

    /// A stored record of this day, `index` and `identity` as its row holds them, read the way every
    /// load of the records reads it: the identity the row holds from now on, and the index of its item
    /// now (nil: the record is kept, and shown nowhere).
    ///
    /// - No identity (a row from builds that kept none): the item at its index, named now.
    /// - An id: through the day's renames (`renamed`, on every load), then that item, wherever it is.
    /// - An old-scheme identity, while the records are not `converted`: converted on this plan
    ///   (`migrate`) to its item's id; one this plan does not find keeps its identity.
    /// - An old-scheme identity once they are: shown nowhere. It did not find its item on the plan it
    ///   was written under, and a later plan must not give it one.
    public func read(_ index: Int, identity: String?, renames: [String: String], converted: Bool) -> (identity: String?, index: Int?) {
        guard let identity else {
            let id = self.identity(of: index)
            return (id, id == nil ? nil : index)
        }
        guard Self.isLegacy(identity) else {
            let id = renamed(identity, renames: renames)
            return (id, resolve(index, identity: id))
        }
        guard !converted, let i = legacyResolve(index, identity: identity) else { return (identity, nil) }
        return (items[i].id, i)
    }

    /// The stored records of item `index`, by their position in `stored` (each row's index and
    /// identity): the rows a load reads as that item (`read`), whatever index each holds. What taking
    /// the item's mark or its skip off deletes, and never a row of another item that still holds the
    /// index because the write that would have moved it failed.
    public func records(of index: Int, among stored: [(index: Int, identity: String?)], renames: [String: String], converted: Bool) -> [Int] {
        stored.indices.filter { read(stored[$0].index, identity: stored[$0].identity, renames: renames, converted: converted).index == index }
    }

    // MARK: The old scheme

    /// The name the app gave item `index` before items had ids: the leg's id for a move, the place
    /// (else the title) for a stop, and for a place the day comes back to, which visit ("#1" the second).
    func legacyIdentity(of index: Int) -> String? {
        guard items.indices.contains(index) else { return nil }
        let base = Self.legacyBase(items[index])
        let before = items[..<index].lazy.filter { Self.legacyBase($0) == base }.count
        return before == 0 ? base : "\(base)#\(before)"
    }

    /// Where an old-scheme record is on this plan: still at its index, else the nearest item with
    /// that name, else nowhere.
    private func legacyResolve(_ index: Int, identity: String) -> Int? {
        if legacyIdentity(of: index) == identity { return index }
        return items.indices
            .filter { legacyIdentity(of: $0) == identity }
            .min { abs($0 - index) < abs($1 - index) }
    }

    private static func legacyBase(_ item: DayItem) -> String {
        switch item {
        case .move(let m): "move:\(m.leg.id)"
        case .stop(let s): s.place.map { "stop:\($0)" } ?? "stop:\(s.title)"
        }
    }

    /// An identity written before item ids: "stop:…" or "move:…". An id starts "s:" or "m:", so the
    /// two never meet.
    private static func isLegacy(_ identity: String) -> Bool {
        identity.hasPrefix("stop:") || identity.hasPrefix("move:")
    }
}
