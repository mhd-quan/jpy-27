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
        // an old name is converted by the plan, not looked up
        #expect(d8.renamed("stop:wargo-gion", renames: [:]) == "stop:wargo-gion")
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
        var kinds: Set<Reminder.Kind> = []
        var ids: [String] = []
        for day in allDays {
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
                    // read by the app until it reads the id
                    #expect(r.index == i)
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
            #expect(r.index == b)
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
                    let i = try #require(f.index, "\(f.id)")
                    #expect(f.itemID == day.items[i].id, "\(f.id) on day \(f.day)")
                    if f.kind == .food { #expect(day.items[i].stop?.place == f.placeID) } else { #expect(day.items[i].move?.leg.from == f.placeID) }
                case .snack, .stay:
                    #expect(f.itemID == nil && f.index == nil, "\(f.id)")
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
        // written without the item (a snack, the hotel) or by a build that knew only the index
        let bare = #"{"placeID":"owariya","kind":"food","center":{"lat":35.71,"lng":139.79},"radius":150,"day":"2"}"#
        let f = try JSONDecoder().decode(Fence.self, from: Data(bare.utf8))
        #expect(f.id == "food:owariya" && f.itemID == nil && f.index == nil)
        // the app's call shape, and the new one
        let old = Fence(placeID: "owariya", kind: .food, center: Coordinate(35.71, 139.79), radius: 150, day: "2", index: 12)
        #expect(old.index == 12 && old.itemID == nil)
        let new = Fence(placeID: "owariya", kind: .food, center: Coordinate(35.71, 139.79), radius: 150, day: "2", itemID: "s:owariya")
        #expect(new.itemID == "s:owariya" && new.index == nil && new.id == old.id)
    }
}
