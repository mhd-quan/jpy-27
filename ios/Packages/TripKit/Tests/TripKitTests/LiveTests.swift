import Foundation
import Testing
@testable import TripKit

@Suite struct ReplanTests {
    let store = Bundle_.store
    var day2: Day { store.day("2")! }

    @Test func onTimeNeedsNothing() {
        // 14:50 at Sumida as planned, Umezono still ahead: Ginza Line 16:15 is reachable
        let o = PlanEngine.Options.live(from: 15, now: 14 * 60 + 50)
        #expect(PlanEngine(store: store).replan(day2, o) == nil)
    }

    @Test func lateDropsTheOptionalSweetShop() throws {
        // 15:40 and still at Sumida: keeping Umezono misses the 16:15 train
        let o = PlanEngine.Options.live(from: 15, now: 15 * 60 + 40)
        let r = try #require(PlanEngine(store: store).replan(day2, o))
        #expect(r.target == 19)
        #expect(r.lateBy > 0)
        #expect(r.works)
        #expect(r.drop.contains(17), "drops Umezono, got \(r.drop)")
    }

    @Test func mergedWalkIsShorterThanTheDetour() {
        let engine = PlanEngine(store: store)
        let keep = engine.simulate(day2, .live(from: 16, now: 900))
        let drop = engine.simulate(day2, .live(from: 16, now: 900, skips: [17]))
        let k = keep.first { $0.index == 19 }!.ready
        let d = drop.first { $0.index == 19 }!.ready
        #expect(d < k - 15)
    }

    @Test func waypointsLeaveBeforeTheTrain() throws {
        let points = Itinerary(store: store).waypoints(day2)
        let ginza = try #require(points.first { $0.index == 19 })
        #expect(ginza.kind == .departure)
        // leave Umezono with the walk to the station and three minutes in hand, not earlier
        let walk = try #require(day2.items[18].move?.leg.walk)
        #expect(ginza.setOff == Double(16 * 60 + 15 - walk.min) - Itinerary.margin)
        #expect(points.contains { $0.placeID == "owariya" })
    }

    @Test func phaseAcrossTheTrip() {
        let it = Itinerary(store: store)
        let days = store.days()
        if case .before(let n, _) = it.phase(at: TripTime.date("2027-10-10", "12:00")!, days: days) { #expect(n == 8) } else { Issue.record("before") }
        if case .during(let d) = it.phase(at: TripTime.date("2027-10-19", "1:30")!, days: days) { #expect(d.key == "2") } else { Issue.record("during") }
        if case .after = it.phase(at: TripTime.date("2027-10-30", "9:00")!, days: days) {} else { Issue.record("after") }
    }

    @Test func alternativeReplacesItsDay() {
        let days = store.days(choosing: ["kawaguchiko"])
        #expect(days[2].key == "kawaguchiko")
        #expect(days.count == 12)
    }
}

@Suite struct RideTests {
    let store = Bundle_.store

    @Test func romancecarAtOdawara() throws {
        let ride = try #require(store.trip.rides.first { $0.id == "r-4-romancecar-st-shinjuku-odakyu" })
        let tracker = RideTracker(ride: ride, store: store)
        let odawara = try #require(store.place("st-odawara"))
        let s = try #require(tracker.status(at: odawara.coordinate))
        #expect(s.offTrackKm < 0.5)
        #expect(ride.stations[s.previous!].en == "Odawara")
        #expect(ride.stations[s.nextStop!].en == "Hakone-Yumoto")
        #expect(!s.alightSoon)
        #expect(tracker.status(km: 87).alightSoon)
        #expect(tracker.status(km: 88.6).arrived)
    }

    @Test func fujiSideOnTheRomancecar() throws {
        let ride = try #require(store.trip.rides.first { $0.id == "r-4-romancecar-st-shinjuku-odakyu" })
        let tracker = RideTracker(ride: ride, store: store)
        let sides = stride(from: 0.0, through: ride.km, by: 1).compactMap { tracker.status(km: $0).fujiSide }
        #expect(sides.contains(.right))
        #expect(tracker.minutesLeft(km: ride.km / 2)! > 40)
    }
}

@Suite struct MenuTests {
    let store = Bundle_.store

    @Test func foldsScriptsAndWidths() {
        #expect(JapaneseText.fold("カツ丼") == JapaneseText.fold("かつ丼"))
        #expect(JapaneseText.fold("天ぷら　そば（２人前）") == JapaneseText.fold("天ぷらそば(2人前)"))
        #expect(JapaneseText.price(in: "天ぷらそば ……… ２，０００円") == 2000)
        #expect(JapaneseText.price(in: "¥1,500 (税込)") == 1500)
    }

    @Test func scannedLinesFindResearchedDishes() throws {
        let m = MenuMatcher(store: store, placeID: "owariya")
        let hits = m.match(lines: ["お品書き", "天 ぷ ら そ ば　２，０００円", "天せいろ 1,500円", "ビール 700円"])
        let names = hits.map(\.candidate.item.ja)
        #expect(names.contains("天ぷらそば"))
        #expect(names.contains("天せいろ"))
        #expect(hits.first { $0.candidate.item.ja == "天ぷらそば" }?.printedYen == 2000)
        #expect(!names.contains { $0.contains("ビール") } || hits.count >= 2)
    }

    @Test func heardLinesFindReplies() throws {
        let scenarios = try #require(store.guide?.phrases.scenarios)
        let heard = try #require(scenarios.flatMap(\.hear).first)
        let hit = try #require(HeardMatcher(scenarios: scenarios).best(for: heard.ja))
        #expect(hit.heard.ja == heard.ja)
    }
}

@Suite struct MoneyAndPlacesTests {
    let store = Bundle_.store

    @Test func priceRanges() {
        #expect(Spend.range("¥1.400–1.700")! == (1400, 1700))
        #expect(Spend.range("khoảng ¥2.000")! == (2000, 2000))
    }

    @Test func cashPlanCountsCashOnlyPlaces() {
        let days = store.days()
        let plan = CashPlan(store: store, days: days, from: 0, cursor: 0, horizon: 12)
        #expect(plan.certain > 0)
        #expect(plan.possible >= plan.certain)
        #expect(plan.shortfall(onHand: 1_000_000) == 0)
    }

    @Test func budgetRowsFollowTheBudget() throws {
        let status = BudgetStatus(budget: try #require(store.guide?.budget), spent: [.food: 12_000])
        #expect(status.rows.first { $0.category == .food }?.planned == 172_000)
        #expect(status.spent == 12_000)
        #expect(status.planned == store.guide!.budget.total)
    }

    @Test func fujiFromOnshiPark() {
        let s = FujiSight.from(Coordinate(35.19632, 139.02596), altitude: 769)
        #expect(abs(s.km - 32.7) < 0.3)
        #expect(abs(s.bearing - 304) < 1.5)
        #expect(s.elevation > 4 && s.elevation < 6)
        #expect(s.compass == "Tây Bắc")
    }

    @Test func nearbyStartsWithWhatIsClosest() throws {
        let day = store.day("2")!
        let sensoji = try #require(store.place("sensoji"))
        let list = Nearby.around(sensoji.coordinate, day: day, store: store)
        #expect(list.first?.place.id == "sensoji")
        #expect(list.map(\.km) == list.map(\.km).sorted())
    }

    @Test func formats() {
        #expect(Fmt.yen(1500) == "¥1.500")
        #expect(Fmt.yen(172_000) == "¥172.000")
        #expect(Fmt.km(0.85) == "850 m")
        #expect(Fmt.km(1.24) == "1,2 km")
        #expect(Fmt.duration(100) == "1 giờ 40")
        #expect(Fmt.vndMillions(100_000, rate: 175) == "17,5 triệu")
        #expect(TripTime.clock(16 * 60 + 5) == "16:05")
    }
}

@Suite struct TrackingTests {
    let store = Bundle_.store

    @Test func remindersForHakoneDay() throws {
        let day = store.day("4")!
        let list = ReminderPlanner(store: store).reminders(for: day)
        let romance = try #require(list.first { $0.kind == .departure })
        #expect(romance.level == .timeSensitive)
        #expect(romance.body.contains("Romancecar"))
        #expect(romance.fire < TripTime.date(day.date, "7:37")!)
        #expect(list.contains { $0.kind == .journal })
        let ids = list.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func bookingReminders() {
        let b = ReminderPlanner(store: store).bookings()
        #expect(b.count == 2 * (store.guide?.bookings.filter { $0.at != nil }.count ?? 0))
    }

    @Test func fencesStayUnderTheLimit() {
        let days = store.days()
        for (k, d) in days.enumerated() {
            let f = FencePlanner(store: store).fences(today: d, cursor: 0, tomorrow: days.indices.contains(k + 1) ? days[k + 1] : nil)
            #expect(f.count <= 20)
            #expect(Set(f.map(\.placeID)).count == f.count)
        }
        let f2 = FencePlanner(store: store).fences(today: days[1], cursor: 0, tomorrow: days[2])
        #expect(f2.contains { $0.placeID == "owariya" && $0.kind == .food })
        #expect(f2.contains { $0.kind == .station })
    }

    @Test func journalMarksVisitedLateAndSkipped() throws {
        let day = store.day("2")!
        let kayaba = try #require(store.place("kayaba"))
        let tamai = try #require(store.place("tamai"))
        let visits = [
            VisitRecord(arrival: TripTime.date(day.date, "8:42")!, departure: TripTime.date(day.date, "9:20")!, coordinate: kayaba.coordinate),
            VisitRecord(arrival: TripTime.date(day.date, "18:05")!, departure: TripTime.date(day.date, "19:30")!, coordinate: tamai.coordinate),
        ]
        let j = Journal(store: store, day: day, visits: visits, marked: [:], now: TripTime.date(day.date, "22:00")!)
        let k = try #require(j.entries.first { $0.place.id == "kayaba" })
        #expect(k.status == .visited(arrival: visits[0].arrival, departure: visits[0].departure, late: 12))
        #expect(j.entries.first { $0.place.id == "umezono" }?.status == .skipped)
        #expect(j.visited == 2)
    }

    @Test func paceLearnsSlowWalkers() {
        var pace = PaceModel()
        pace.add(planned: 20, actual: 25)
        pace.add(planned: 30, actual: 36)
        #expect(pace.factor < 1)
        #expect(pace.factor > 0.75)
        let w = WalkStats(km: 1, up: 0, down: 0, walkMin: 15, min: 17)
        #expect(w.minutes(pace: pace.factor) > 17)
        #expect(w.minutes(pace: 1) == 17)
    }
}

@Suite struct GeoTests {
    @Test func polylineRoundTrip() {
        let pts = [Coordinate(35.69674, 139.77393), Coordinate(35.69657, 139.77519), Coordinate(35.0, 135.5)]
        let back = Polyline.decode(Polyline.encode(pts))
        #expect(back.count == 3)
        for (a, b) in zip(pts, back) { #expect(abs(a.lat - b.lat) < 1e-5 && abs(a.lng - b.lng) < 1e-5) }
    }

    @Test func projectionAlongALine() throws {
        let line = [Coordinate(35, 139), Coordinate(35, 139.1)]
        let p = try #require(Geo.project(Coordinate(35.001, 139.05), on: line))
        #expect(abs(p.kmAlong - Geo.km(line[0], line[1]) / 2) < 0.05)
        #expect(p.offKm < 0.12)
        #expect(abs(p.heading - 90) < 1)
    }
}
