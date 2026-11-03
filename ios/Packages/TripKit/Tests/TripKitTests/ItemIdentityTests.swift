import Foundation
import Testing
@testable import TripKit

/// Every visit has an id written in the data (src/data/days.ts), and what is recorded about it — done,
/// skipped, a reminder, a geofence, a "Đã tới" — follows that id. Records kept before ids existed name
/// their item the old way and still find it.
@Suite struct ItemIdentityTests {
    let store = Bundle_.store

    var allDays: [Day] { store.trip.days + store.trip.altDays }

    // MARK: Ids in the data

    @Test func everyItemHasAUniqueID() {
        for d in allDays {
            let ids = d.items.map(\.id)
            #expect(Set(ids).count == ids.count, "Day \(d.key)")
            #expect(ids.allSatisfy { !$0.isEmpty }, "Day \(d.key)")
        }
    }

    /// The widget reads the slim plan: it names each item as the app does.
    @Test func theSlimPlanNamesItemsAsTheAppDoes() throws {
        let slim = try TripStore(tripJSON: Bundle_.data("Shared/schedule.json"))
        #expect(slim.trip.days.count + slim.trip.altDays.count == allDays.count)
        for d in slim.trip.days + slim.trip.altDays {
            let full = try #require(store.day(d.key))
            #expect(d.items.map(\.id) == full.items.map(\.id), "day \(d.key)")
        }
    }

    @Test func renamesAreReadFromThePlanAndAreNoneWithoutThem() throws {
        // trip.json carries the key (empty today); the slim plan has none and reads as empty
        let trip = try #require(try JSONSerialization.jsonObject(with: Bundle_.data("JP27/Resources/Trip/trip.json")) as? [String: Any])
        #expect(trip["idRenames"] != nil)
        #expect(store.trip.idRenames.isEmpty)
        let schedule = try #require(try JSONSerialization.jsonObject(with: Bundle_.data("Shared/schedule.json")) as? [String: Any])
        #expect(schedule["idRenames"] == nil)
        let slim = try TripStore(tripJSON: Bundle_.data("Shared/schedule.json"))
        #expect(slim.trip.idRenames.isEmpty)
        let renamed = try TripStore.patched { $0["idRenames"] = ["8": ["s:wargo-gion:hire": "s:wargo-gion:rent"]] }
        #expect(renamed.trip.idRenames == ["8": ["s:wargo-gion:hire": "s:wargo-gion:rent"]])
    }

    // MARK: Identity, index, resolve

    @Test func identitiesNameEachItemOfADayOnce() {
        for day in allDays {
            let ids = day.items.indices.compactMap { day.identity(of: $0) }
            #expect(ids.count == day.items.count)
            #expect(Set(ids).count == ids.count, "day \(day.key)")
            for i in day.items.indices {
                #expect(day.identity(of: i) == day.items[i].id)
                #expect(day.index(of: day.items[i].id) == i)
                #expect(day.resolve(i, identity: day.identity(of: i)) == i)
            }
        }
        let day = store.day("2")!
        #expect(day.identity(of: day.items.count) == nil)
        #expect(day.identity(of: -1) == nil)
        #expect(day.index(of: "s:gone") == nil)
    }

    @Test func aRecordFollowsItsItemWhenThePlanMoves() throws {
        let day = store.day("2")!
        let (i, _) = try #require(day.stops.first { $0.stop.place != nil && $0.index > 1 })
        let id = day.identity(of: i)
        // recorded two items further on than the item now is: found again where it is
        #expect(day.resolve(i + 2, identity: id) == i)
        // recorded at the index another item now has: its own item, not the one at its index
        #expect(day.resolve(i, identity: day.identity(of: i + 1)) == i + 1)
        // an item the plan no longer has: nowhere, whichever way it was named
        #expect(day.resolve(i, identity: "s:gone") == nil)
        #expect(day.resolve(i, identity: "stop:gone") == nil)
        // older records keep their index while the day has it
        #expect(day.resolve(i, identity: nil) == i)
        #expect(day.resolve(day.items.count + 3, identity: nil) == nil)
    }

    @Test func idsSurviveRemovingAnEarlierVisit() throws {
        let was = try #require(store.day("8"))
        let before = try #require(was.index(of: "s:wargo-gion:return"))
        let store = try TripStore.patched { $0.removeItem(day: "8", id: "s:wargo-gion:rent") }
        let d8 = try #require(store.day("8"))
        #expect(d8.items.count == was.items.count - 1)
        let i = try #require(d8.index(of: "s:wargo-gion:return"))
        #expect(i == before - 1)
        #expect(d8.items[i].at == "14:30")
        #expect(d8.index(of: "s:wargo-gion:rent") == nil)
        #expect(d8.resolve(5, identity: "s:wargo-gion:rent") == nil)
        // the return's record, still at its old index, finds it one place earlier
        #expect(d8.resolve(before, identity: "s:wargo-gion:return") == i)
        // named by order, as before, the return took the rent's name: why old records are converted on
        // the plan they were written under
        #expect(d8.legacyIdentity(of: i) == "stop:wargo-gion")
    }

    @Test func idsSurviveRetimingAndEditingAWalk() throws {
        let was = try #require(store.day("2"))
        let walk = try #require(was.index(of: "m:kayaba>nezu-taiyaki"))
        #expect(was.items[walk].move?.leg.via.isEmpty == false)
        let store = try TripStore.patched { trip in
            trip.setStop(day: "2", place: "nezu-shrine", at: "11:20")
            // a waypoint taken out: the exporter's leg id (a hash of the way) changes with it
            trip.editItem(day: "2", at: walk) { item in
                guard var leg = item["leg"] as? [String: Any] else {
                    Issue.record("no leg")
                    return
                }
                leg["via"] = [String]()
                leg["id"] = "walk.kayaba.nezu-taiyaki.edited"
                item["leg"] = leg
            }
        }
        let now = try #require(store.day("2"))
        let nezu = try #require(now.index(of: "s:nezu-shrine"))
        #expect(now.items[nezu].at == "11:20")
        #expect(now.items[walk].move?.leg.via.isEmpty == true)
        #expect(now.items.map(\.id) == was.items.map(\.id))
        #expect(now.resolve(walk, identity: was.identity(of: walk)) == walk)
        // the old names went by the leg, which the edit changed
        #expect(now.legacyIdentity(of: walk) != was.legacyIdentity(of: walk))
        #expect(now.resolve(walk, identity: was.legacyIdentity(of: walk)) == nil)
    }

    // MARK: Records kept before ids

    @Test func legacyRecordsMapToStableIDs() throws {
        let d8 = store.day("8")!
        let i = d8.index(of: "s:wargo-gion:return")!
        #expect(d8.migrate(legacy: "stop:wargo-gion#1", index: i, renames: [:]) == "s:wargo-gion:return")
        #expect(d8.migrate(legacy: "stop:wargo-gion", index: 0, renames: [:]) == "s:wargo-gion:rent")
        let d1 = store.day("1")!
        #expect(d1.migrate(legacy: "stop:resol-akihabara", index: 9, renames: [:]) == "s:resol-akihabara:bags")
        #expect(d1.migrate(legacy: "stop:resol-akihabara#1", index: 0, renames: [:]) == "s:resol-akihabara:checkin")
        // a move by its leg
        let leg = try #require(d8.items[0].move?.leg.id)
        #expect(d8.legacyIdentity(of: 0) == "move:\(leg)")
        #expect(d8.migrate(legacy: "move:\(leg)", index: 7, renames: [:]) == d8.items[0].id)
        // a record from before identities: the item at its index, while the day has one
        #expect(d8.migrate(legacy: nil, index: i, renames: [:]) == "s:wargo-gion:return")
        #expect(d8.migrate(legacy: nil, index: d8.items.count, renames: [:]) == nil)
        #expect(d8.migrate(legacy: nil, index: -1, renames: [:]) == nil)
        // an item the plan no longer has: no id to give it
        #expect(d8.migrate(legacy: "stop:gone", index: i, renames: [:]) == nil)
        #expect(d8.migrate(legacy: "stop:wargo-gion#2", index: i, renames: [:]) == nil)
    }

    /// Every old name of every item of every day finds its item from where it was recorded, from
    /// further on, and from below 0, where `RecordIndexes` sets a row aside (the twin of the pin in
    /// PlanClockTests for the new ids), and converts to the item's id.
    @Test func legacyIdentitiesFindTheirItemEverywhere() {
        for day in allDays {
            let legacy = day.items.indices.compactMap { day.legacyIdentity(of: $0) }
            #expect(legacy.count == day.items.count)
            #expect(Set(legacy).count == legacy.count, "day \(day.key)")
            for i in day.items.indices {
                let old = day.legacyIdentity(of: i)
                for k in [i, i + 2, -1, -9] {
                    #expect(day.resolve(k, identity: old) == i, "day \(day.key): item \(i) recorded at \(k)")
                    #expect(day.migrate(legacy: old, index: k, renames: [:]) == day.items[i].id, "day \(day.key): item \(i)")
                }
            }
        }
        #expect(store.day("8")!.legacyIdentity(of: store.day("8")!.items.count) == nil)
    }

    @Test func aStopWithoutAPlaceWasNamedByItsTitle() throws {
        let store = try TripStore.patched { trip in
            trip.editItem(day: "2", at: 3) { item in
                item["place"] = nil
                item["id"] = "s::breakfast"
            }
        }
        let day = try #require(store.day("2"))
        let title = try #require(day.items[3].stop?.title)
        #expect(day.items[3].id == "s::breakfast")
        #expect(day.legacyIdentity(of: 3) == "stop:\(title)")
        #expect(day.resolve(0, identity: "stop:\(title)") == 3)
        #expect(day.migrate(legacy: "stop:\(title)", index: 0, renames: [:]) == "s::breakfast")
        #expect(day.resolve(0, identity: "s::breakfast") == 3)
    }

    // MARK: Renames

    @Test func renamedIDsFollowTheirRecord() {
        let d8 = store.day("8")!
        #expect(d8.migrate(legacy: "s:x", index: 0, renames: ["s:x": "s:y"]) == "s:y")
        #expect(d8.renamed("s:x", renames: ["s:x": "s:y"]) == "s:y")
        // no entry: the id stays itself, known to the day or not
        #expect(d8.renamed("s:z", renames: ["s:x": "s:y"]) == "s:z")
        #expect(d8.migrate(legacy: "s:z", index: 0, renames: [:]) == "s:z")
        #expect(d8.migrate(legacy: "s:wargo-gion:rent", index: 0, renames: [:]) == "s:wargo-gion:rent")
        // one step: the data writes a → c and b → c
        #expect(d8.renamed("s:a", renames: ["s:a": "s:b", "s:b": "s:c"]) == "s:b")
        // an id the day has is never renamed away
        let away = ["s:wargo-gion:rent": "s:wargo-gion:return"]
        #expect(d8.renamed("s:wargo-gion:rent", renames: away) == "s:wargo-gion:rent")
        #expect(d8.migrate(legacy: "s:wargo-gion:rent", index: 0, renames: away) == "s:wargo-gion:rent")
        // an old name is converted by the plan, not looked up, even where a rename names it
        #expect(d8.renamed("stop:wargo-gion", renames: [:]) == "stop:wargo-gion")
        #expect(d8.renamed("stop:wargo-gion", renames: ["stop:wargo-gion": "s:menzo"]) == "stop:wargo-gion")
        #expect(d8.renamed("move:x", renames: ["move:x": "m:a>b"]) == "move:x")
        #expect(d8.migrate(legacy: "stop:wargo-gion", index: 5, renames: ["stop:wargo-gion": "s:menzo"]) == "s:wargo-gion:rent")
    }

    /// An update that gives a visit another id ships the rename; a record of the old id reaches the visit
    /// through it, and without it finds nothing (it is not moved elsewhere).
    @Test func aRenameInTheDataLeadsARecordToItsVisit() throws {
        #expect(store.day("8")!.items[5].id == "s:wargo-gion:rent")
        let store = try TripStore.patched { trip in
            trip.editItem(day: "8", at: 5) { $0["id"] = "s:wargo-gion:hire" }
            trip["idRenames"] = ["8": ["s:wargo-gion:rent": "s:wargo-gion:hire"]]
        }
        let d8 = try #require(store.day("8"))
        let renames = store.trip.idRenames[d8.key] ?? [:]
        let id = d8.renamed("s:wargo-gion:rent", renames: renames)
        #expect(id == "s:wargo-gion:hire")
        #expect(d8.resolve(12, identity: id) == 5)
        #expect(d8.resolve(5, identity: "s:wargo-gion:rent") == nil)
        #expect(d8.migrate(legacy: "s:wargo-gion:rent", index: 5, renames: renames) == "s:wargo-gion:hire")
        #expect(d8.renamed("s:wargo-gion:return", renames: renames) == "s:wargo-gion:return")
    }

    // MARK: Reading the records

    /// `Day.read` as "identity@index", nil spelled out.
    func read(_ day: Day, _ index: Int, _ identity: String?, renames: [String: String] = [:], converted: Bool) -> String {
        let r = day.read(index, identity: identity, renames: renames, converted: converted)
        return "\(r.identity ?? "nil")@\(r.index.map(String.init) ?? "nil")"
    }

    /// Every kind of identity a stored row may hold, read by a load before the one-time conversion of
    /// the records and after it.
    @Test func aLoadReadsEveryKindOfRecord() throws {
        let d8 = try #require(store.day("8"))
        let rent = try #require(d8.index(of: "s:wargo-gion:rent"))
        let ret = try #require(d8.index(of: "s:wargo-gion:return"))
        for converted in [false, true] {
            // an id: its item, wherever the row sits (its own index, aside below 0, another item's index)
            for at in [ret, -3, rent] {
                #expect(read(d8, at, "s:wargo-gion:return", converted: converted) == "s:wargo-gion:return@\(ret)")
            }
            // an id the plan no longer has: kept, shown nowhere
            #expect(read(d8, rent, "s:gone", converted: converted) == "s:gone@nil")
            // an id an update renamed: the new id, and its item
            let hire = ["s:wargo-gion:hire": "s:wargo-gion:rent"]
            #expect(read(d8, ret, "s:wargo-gion:hire", renames: hire, converted: converted) == "s:wargo-gion:rent@\(rent)")
            #expect(read(d8, ret, "s:wargo-gion:hire", converted: converted) == "s:wargo-gion:hire@nil")
            // no identity: the item at its index, named now; nothing past the day's end
            #expect(read(d8, ret, nil, converted: converted) == "s:wargo-gion:return@\(ret)")
            #expect(read(d8, d8.items.count, nil, converted: converted) == "nil@nil")
            #expect(read(d8, -1, nil, converted: converted) == "nil@nil")
        }
        // an old name, before the conversion: converted on this plan, from wherever it was recorded
        #expect(read(d8, ret, "stop:wargo-gion#1", converted: false) == "s:wargo-gion:return@\(ret)")
        #expect(read(d8, -1, "stop:wargo-gion", converted: false) == "s:wargo-gion:rent@\(rent)")
        #expect(read(d8, ret, "stop:wargo-gion#2", converted: false) == "stop:wargo-gion#2@nil")
        let leg = try #require(d8.items[0].move?.leg.id)
        #expect(read(d8, 4, "move:\(leg)", converted: false) == "\(d8.items[0].id)@0")
        // after it: kept as it is and shown nowhere, even where the old scheme would find an item, and
        // a rename never reaches it
        #expect(read(d8, ret, "stop:wargo-gion#1", converted: true) == "stop:wargo-gion#1@nil")
        #expect(read(d8, rent, "stop:wargo-gion", renames: ["stop:wargo-gion": "s:wargo-gion:rent"], converted: true) == "stop:wargo-gion@nil")
        #expect(read(d8, 0, "move:\(leg)", converted: true) == "move:\(leg)@nil")
    }

    /// Taking a mark or a skip off deletes the rows a load reads as the item, however each is named
    /// and wherever it sits.
    @Test func takingAMarkOffFindsTheItemsOwnRows() throws {
        let d8 = try #require(store.day("8"))
        let rent = try #require(d8.index(of: "s:wargo-gion:rent"))
        let ret = try #require(d8.index(of: "s:wargo-gion:return"))
        try #require(d8.items.indices.contains(ret + 3))
        let rows: [(index: Int, identity: String?)] = [
            (ret, "stop:wargo-gion#1"),  // the return, named the old way, not converted yet
            (-2, "s:wargo-gion:return"),  // the return again, by its id, set aside: two rows of one item
            (rent, "s:wargo-gion:rent"),
            (ret + 1, nil),  // from before identities: the item at its index
            (ret + 2, "s:gone"),  // an item the plan no longer has, on another item's index
            (ret + 3, "stop:wargo-gion#2"),  // an old name this plan never had
        ]
        #expect(d8.records(of: ret, among: rows, renames: [:], converted: false) == [0, 1])
        // once converted, the old name is nobody's: kept, never deleted
        #expect(d8.records(of: ret, among: rows, renames: [:], converted: true) == [1])
        for converted in [false, true] {
            #expect(d8.records(of: rent, among: rows, renames: [:], converted: converted) == [2])
            #expect(d8.records(of: ret + 1, among: rows, renames: [:], converted: converted) == [3])
            #expect(d8.records(of: ret + 2, among: rows, renames: [:], converted: converted).isEmpty)
            #expect(d8.records(of: ret + 3, among: rows, renames: [:], converted: converted).isEmpty)
        }
        // a row of an id an update renamed is the renamed visit's
        let hire: [(index: Int, identity: String?)] = [(ret, "s:wargo-gion:hire")]
        #expect(d8.records(of: rent, among: hire, renames: ["s:wargo-gion:hire": "s:wargo-gion:rent"], converted: true) == [0])
        #expect(d8.records(of: ret, among: hire, renames: ["s:wargo-gion:hire": "s:wargo-gion:rent"], converted: true).isEmpty)
    }

    /// An update took the kimono rental out of day 8: the return and everything after it sit one index
    /// earlier. The load that moves the records failed, so the return's mark still holds its old index,
    /// now the index of the item after it. Marking that item, then taking either mark off, touches only
    /// its own row: the insert is not made an update of the return's row by the store's unique day and
    /// index (R-87), and the delete does not take the row on the index (R-61).
    @Test func aMarkBesideARecordWaitingForItsIndex() throws {
        let was = try #require(store.day("8"))
        let old = try #require(was.index(of: "s:wargo-gion:return"))
        let store = try TripStore.patched { $0.removeItem(day: "8", id: "s:wargo-gion:rent") }
        let d8 = try #require(store.day("8"))
        let ret = try #require(d8.index(of: "s:wargo-gion:return"))
        #expect(ret == old - 1)
        // the item now on the return's old index
        let next = old
        let nextID = try #require(d8.identity(of: next))
        var rows: [(index: Int, identity: String?)] = [(old, "s:wargo-gion:return")]
        #expect(read(d8, old, "s:wargo-gion:return", converted: true) == "s:wargo-gion:return@\(ret)")
        // insert side
        let slot = try #require(RecordIndexes.slots(for: [next], holding: rows.map(\.index)).first)
        #expect(slot != old)
        #expect(slot < 0)
        rows.append((slot, nextID))
        #expect(rows.map { d8.read($0.index, identity: $0.identity, renames: [:], converted: true).index } == [ret, next])
        // delete side; by the stored index it would have been the return's row
        #expect(d8.records(of: next, among: rows, renames: [:], converted: true) == [1])
        #expect(d8.records(of: ret, among: rows, renames: [:], converted: true) == [0])
        #expect(rows.indices.filter { rows[$0].index == next } == [0])
        // the next load that writes puts both on their items' indexes
        let records = rows.map { RecordIndexes.Record(day: "8", index: $0.index, target: d8.read($0.index, identity: $0.identity, renames: [:], converted: true).index) }
        #expect(RecordIndexes.moves(records).home == [0: ret, 1: next])
    }

    // MARK: "Đã tới"

    @Test func legacyArrivedPayloadIsIgnored() {
        #expect(ItemRef.arrived(from: ["day": "8", "index": 12]) == nil)
        #expect(ItemRef.arrived(from: ["day": "8", "item": "s:wargo-gion:return"]) == ItemRef(day: "8", id: "s:wargo-gion:return"))
        #expect(ItemRef.arrived(from: ["day": "8", "index": 12, "item": "s:wargo-gion:return"]) == ItemRef(day: "8", id: "s:wargo-gion:return"))
        #expect(ItemRef.arrived(from: ["item": "s:wargo-gion:return"]) == nil)
        #expect(ItemRef.arrived(from: ["day": 8, "item": "s:wargo-gion:return"]) == nil)
        #expect(ItemRef.arrived(from: ["day": "8", "item": 12]) == nil)
        #expect(ItemRef.arrived(from: [:]) == nil)
    }

    /// The day of a "Đã tới", with the visit or without: one posted before items had ids opens its day.
    @Test func anArrivedPayloadNamesItsDay() {
        #expect(ItemRef.arrivedDay(from: ["day": "8", "index": 12]) == "8")
        #expect(ItemRef.arrivedDay(from: ItemRef(day: "8", id: "s:wargo-gion:return").userInfo) == "8")
        #expect(ItemRef.arrivedDay(from: ["day": 8, "index": 12]) == nil)
        #expect(ItemRef.arrivedDay(from: ["link": "jp27://menu/menzo"]) == nil)
    }

    /// "Đã tới" marks the visit it names, found on the plan as a record finds it: by its id, through
    /// the renames an update shipped. A visit the plan no longer has is found nowhere (the app then
    /// opens its day and marks nothing).
    @Test func anArrivedVisitIsFoundThroughTheRenames() throws {
        let d8 = try #require(store.day("8"))
        let ret = try #require(d8.index(of: "s:wargo-gion:return"))
        // the id the day has
        let hit = try #require(ItemRef(day: "8", id: "s:wargo-gion:return").locate(in: store))
        #expect(hit.day.key == "8" && hit.index == ret)
        // gone, or on a day the plan does not have
        #expect(ItemRef(day: "8", id: "s:gone").locate(in: store) == nil)
        #expect(ItemRef(day: "99", id: "s:wargo-gion:return").locate(in: store) == nil)
        // an update gave the rental another id and shipped the rename
        let renamed = try TripStore.patched { trip in
            trip.editItem(day: "8", at: 5) { $0["id"] = "s:wargo-gion:hire" }
            trip["idRenames"] = ["8": ["s:wargo-gion:rent": "s:wargo-gion:hire"]]
        }
        let found = try #require(ItemRef(day: "8", id: "s:wargo-gion:rent").locate(in: renamed))
        #expect(found.day.key == "8" && found.index == 5)
        #expect(found.day.items[5].id == "s:wargo-gion:hire")
        // the same edit without the rename: found nowhere, never on another visit
        let unrenamed = try TripStore.patched { trip in trip.editItem(day: "8", at: 5) { $0["id"] = "s:wargo-gion:hire" } }
        #expect(ItemRef(day: "8", id: "s:wargo-gion:rent").locate(in: unrenamed) == nil)
        // the renames are the day's own: day 7's map does not reach day 8
        let elsewhere = try TripStore.patched { trip in trip["idRenames"] = ["7": ["s:gone": "s:wargo-gion:return"]] }
        #expect(ItemRef(day: "8", id: "s:gone").locate(in: elsewhere) == nil)
    }

    @Test func theArrivedPayloadRoundTrips() throws {
        let ref = ItemRef(day: "8", id: "s:wargo-gion:return")
        #expect(ref.userInfo == ["day": "8", "item": "s:wargo-gion:return"])
        #expect(ItemRef.arrived(from: ref.userInfo) == ref)
        // beside what else the notification carries
        var info: [AnyHashable: Any] = ["link": "jp27://menu/menzo", "place": "menzo"]
        for (k, v) in ref.userInfo { info[k] = v }
        #expect(ItemRef.arrived(from: info) == ref)
        #expect(try JSONDecoder().decode(ItemRef.self, from: JSONEncoder().encode(ref)) == ref)
    }

    // MARK: Reminders and fences

    @Test func remindersAreKeyedByItemID() throws {
        let planner = ReminderPlanner(store: store)
        let itinerary = Itinerary(store: store)
        var kinds: Set<Reminder.Kind> = []
        var ids: [String] = []
        for day in allDays {
            let waypoints = itinerary.waypoints(day)
            for r in planner.reminders(for: day) {
                ids.append(r.id)
                #expect(r.day == day.key)
                switch r.kind {
                case .departure, .reservation:
                    kinds.insert(r.kind)
                    let prefix = r.kind == .departure ? "dep" : "res"
                    let itemID = try #require(r.itemID, "\(r.id)")
                    let i = try #require(day.index(of: itemID), "\(r.id)")
                    #expect(r.id == "\(prefix)-\(day.key)-\(itemID)")
                    #expect(r.id != "\(prefix)-\(day.key)-\(i)")
                    if r.kind == .departure { #expect(day.items[i].move != nil) } else { #expect(day.items[i].stop != nil) }
                    // the id names the waypoint the reminder is for, not another item of the day
                    let kind: Waypoint.Kind = r.kind == .departure ? .departure : .reservation
                    #expect(waypoints.contains { $0.index == i && $0.kind == kind }, "\(r.id)")
                    #expect(r.booking == nil)
                case .morning, .journal:
                    #expect(r.itemID == nil && r.booking == nil)
                case .booking:
                    Issue.record("a day's reminders hold no booking: \(r.id)")
                }
            }
        }
        #expect(kinds == [.departure, .reservation])
        // ids name notification requests: one per reminder across the trip
        #expect(Set(ids).count == ids.count)
        let bookings = planner.bookings()
        try #require(!bookings.isEmpty)
        for r in bookings {
            let b = try #require(r.booking, "\(r.id)")
            #expect(r.id == "book-\(b)" || r.id == "book-\(b)-eve")
            #expect(store.guide?.bookings.indices.contains(b) == true, "\(r.id)")
            #expect(r.itemID == nil && r.day == nil)
        }
    }

    @Test func fencesCarryTheItemID() throws {
        let planner = FencePlanner(store: store)
        var kinds: Set<Fence.Kind> = []
        func check(_ fences: [Fence]) throws {
            for f in fences {
                kinds.insert(f.kind)
                switch f.kind {
                case .food, .station:
                    let day = try #require(store.day(f.day))
                    let itemID = try #require(f.itemID, "\(f.id)")
                    let i = try #require(day.index(of: itemID), "\(f.id) on day \(f.day)")
                    if f.kind == .food { #expect(day.items[i].stop?.place == f.placeID) } else { #expect(day.items[i].move?.leg.from == f.placeID) }
                case .snack, .stay:
                    #expect(f.itemID == nil, "\(f.id)")
                }
            }
        }
        let d8 = try #require(store.day("8"))
        let morning = planner.fences(today: d8, cursor: 0, tomorrow: store.day("9"))
        #expect(morning.contains { $0.kind == .food && $0.day == "8" && $0.itemID == "s:yorozuya" })
        try check(morning)
        let days = store.days() + store.trip.altDays
        for (k, today) in days.enumerated() {
            let tomorrow = days.indices.contains(k + 1) ? days[k + 1] : nil
            for cursor in [0, today.items.count / 2] {
                try check(planner.fences(today: today, cursor: cursor, tomorrow: tomorrow))
            }
        }
        #expect(kinds == [.food, .snack, .station, .stay])
    }

    @Test func aFenceIsKeptAsJSON() throws {
        let fences = FencePlanner(store: store).fences(today: store.day("4")!, cursor: 0, tomorrow: store.day("5"))
        try #require(fences.contains { $0.itemID != nil })
        let byID = Dictionary(uniqueKeysWithValues: fences.map { ($0.id, $0) })
        let back = try JSONDecoder().decode([String: Fence].self, from: JSONEncoder().encode(byID))
        #expect(back == byID)
        // written without the item (a snack, the hotel), or with a key this build does not read (an
        // index, say; no build wrote fences as JSON before this one: they were a string per circle)
        let bare = #"{"placeID":"owariya","kind":"food","center":{"lat":35.71,"lng":139.79},"radius":150,"day":"2"}"#
        let indexed = #"{"placeID":"owariya","kind":"food","center":{"lat":35.71,"lng":139.79},"radius":150,"day":"2","index":12}"#
        for json in [bare, indexed] {
            let f = try JSONDecoder().decode(Fence.self, from: Data(json.utf8))
            #expect(f.id == "food:owariya" && f.itemID == nil && f.day == "2")
        }
        let new = Fence(placeID: "owariya", kind: .food, center: Coordinate(35.71, 139.79), radius: 150, day: "2", itemID: "s:owariya")
        #expect(new.itemID == "s:owariya")
    }

    /// A fence's id names its region with iOS and its last entry ("fences.entered"): kind and place, as
    /// every build has written it, so a region an earlier build registered is still this build's fence.
    @Test func aFencesIDIsItsKindAndPlace() {
        for kind in [Fence.Kind.food, .snack, .station, .stay] {
            let f = Fence(placeID: "owariya", kind: kind, center: Coordinate(35.71, 139.79), radius: 150, day: "2", itemID: "s:owariya")
            #expect(f.id == "\(kind.rawValue):owariya")
        }
        #expect([Fence.Kind.food, .snack, .station, .stay].map(\.rawValue) == ["food", "snack", "station", "stay"])
    }

    /// What the app keeps of its fences (`fences.v2`) is read entry by entry: one another build wrote
    /// in a shape this one cannot read, or one damaged, is left out, and the rest are kept.
    @Test func theFencesKeptAreReadOneByOne() throws {
        let fences = FencePlanner(store: store).fences(today: store.day("4")!, cursor: 0, tomorrow: store.day("5"))
        try #require(fences.count >= 3)
        let data = try Fence.archive(fences)
        let back = Fence.unarchive(data)
        #expect(back == Dictionary(uniqueKeysWithValues: fences.map { ($0.id, $0) }))
        var raw = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let ids = fences.map(\.id)
        var boat = try #require(raw[ids[0]] as? [String: Any])
        boat["kind"] = "boat"
        raw[ids[0]] = boat
        var torn = try #require(raw[ids[1]] as? [String: Any])
        torn["center"] = nil
        raw[ids[1]] = torn
        raw["food:elsewhere"] = 5
        let kept = Fence.unarchive(try JSONSerialization.data(withJSONObject: raw))
        #expect(Set(kept.keys) == Set(ids.dropFirst(2)))
        for id in ids.dropFirst(2) { #expect(kept[id] == back[id]) }
        // not an object of fences: none
        #expect(Fence.unarchive(Data("not json".utf8)).isEmpty)
        #expect(Fence.unarchive(Data("[]".utf8)).isEmpty)
        #expect(try Fence.unarchive(Fence.archive([])).isEmpty)
        // one id twice: the last, as a region registered twice is
        let a = fences[0]
        let again = Fence(placeID: a.placeID, kind: a.kind, center: a.center, radius: a.radius + 1, day: a.day, itemID: a.itemID)
        #expect(try Fence.unarchive(Fence.archive([a, again])) == [a.id: again])
    }
}
