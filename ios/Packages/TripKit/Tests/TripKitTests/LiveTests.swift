import Foundation
import Testing
@testable import TripKit

@Suite struct ReplanTests {
    let store = Bundle_.store
    var day2: Day { store.day("2")! }
    var day4: Day { store.day("4")! }
    var day10: Day { store.day("10")! }

    @Test func onTimeNeedsNothing() {
        // 10:00 at Tōdai-ji as planned: Kasuga Taisha fits before the 12:30 table at AWA
        let o = PlanEngine.Options.live(from: 8, now: 10 * 60)
        #expect(PlanEngine(store: store).replan(day10, o) == nil)
    }

    @Test func lateDropsTheOptionalShrine() throws {
        // 11:20 and still at Tōdai-ji: keeping Kasuga Taisha misses the booked lunch
        let o = PlanEngine.Options.live(from: 8, now: 11 * 60 + 20)
        let r = try #require(PlanEngine(store: store).replan(day10, o))
        #expect(r.target == 11)
        #expect(r.lateBy > 0)
        #expect(r.works)
        #expect(r.drop.contains(9), "drops Kasuga Taisha, got \(r.drop)")
    }

    @Test func atTheDepartureWithNothingLeftToDrop() throws {
        // 7:40, a quarter of an hour from Shinjuku, the Romancecar 7:37 itself next: no stop before
        // it left to drop. A replan with no candidates trapped on `1 ... 0`.
        let o = PlanEngine.Options.live(from: 2, now: 7 * 60 + 40, toReach: 16)
        let r = try #require(PlanEngine(store: store).replan(day4, o))
        #expect(r.target == 2)
        #expect(r.drop.isEmpty)
        #expect(!r.works)
    }

    @Test func localTrainsAndAnUnbookedShinkansenAreNotDepartures() throws {
        let engine = PlanEngine(store: store)
        let day5 = try #require(store.day("5"))
        // JR Tōkaidō Odawara → Shimizu at 9:27 is an example time: three local trains an hour
        guard case .move(let local) = day5.items[3] else { Issue.record("day 5 item 3 is a ride"); return }
        #expect(local.leg.line == "tokaido")
        #expect(!engine.isHard(day5.items[3]))
        #expect(!engine.isHard(day5.items[7]))
        // the Shinkansen to Nagoya waits half its interval in a live projection, like any frequent line
        guard case .move(let bullet) = day5.items[8] else { Issue.record("day 5 item 8 is a ride"); return }
        #expect(engine.frequentWait(bullet.leg) == 10)
        // the Kintetsu to Ise at 15:50 is still the departure the afternoon is held to
        #expect(engine.isHard(day5.items[10]))
    }

    @Test func aMetroWithATimeIsNotADeparture() throws {
        let engine = PlanEngine(store: store)
        // the Ginza Line runs every few minutes; the Romancecar is a reserved seat
        #expect(!engine.isHard(day2.items[19]))
        #expect(engine.isHard(day4.items[2]))
        // late at Sumida, nothing on day 2 is worth dropping a stop for: the next train comes
        #expect(engine.replan(day2, .live(from: 15, now: 15 * 60 + 40)) == nil)
        // a live projection takes the next train, waiting half the interval, not the planned one
        let slot = try #require(engine.simulate(day2, .live(from: 19, now: 16 * 60)).first { $0.index == 19 })
        #expect(slot.begin == 16 * 60)
        #expect(slot.end == Double(16 * 60 + 15) + 1.5)
        // and no Time Sensitive "leave now" for it
        let reminders = ReminderPlanner(store: store).reminders(for: day2)
        #expect(!reminders.contains { $0.kind == .departure })
    }

    @Test func standingAtAStopHoldsTheDayThere() throws {
        let it = Itinerary(store: store)
        let sensoji = try #require(store.place("sensoji"))
        let now = Double(16 * 60 + 5)
        // by the clock alone the day is at the station; you are still in Sensō-ji
        #expect(it.cursor(day2, done: [], now: now) >= 18)
        #expect(it.cursor(day2, done: [], now: now, position: sensoji.coordinate) == 14)
        let p = it.project(day2, done: [], now: now, position: sensoji.coordinate)
        #expect(p.cursor == 14)
        // late by the plan, but nothing ahead will not wait: no stop to give up
        #expect(p.replan == nil, "replan: \(String(describing: p.replan))")
    }

    @Test func aMorningStopPassedAtNightDoesNotRewindTheDay() throws {
        let it = Itinerary(store: store)
        let kayaba = try #require(store.place("kayaba"))
        let clock = it.cursor(day2, done: [], now: 20 * 60)
        #expect(it.cursor(day2, done: [], now: 20 * 60, position: kayaba.coordinate) == clock)
    }

    @Test func farFromEveryStopTheClockDecides() {
        let it = Itinerary(store: store)
        // about a kilometre north of Asakusa station, near none of the day's stops
        let away = Coordinate(35.7205, 139.7975)
        let now = Double(16 * 60 + 5)
        #expect(it.cursor(day2, done: [], now: now, position: away) == it.cursor(day2, done: [], now: now))
        // and the replan from there does not trap either
        _ = it.project(day2, done: [], now: now, position: away)
    }

    // MARK: A train being ridden, or gone

    // day 4: item 2 is the 7:37 Romancecar, ride r-4-romancecar-st-shinjuku-odakyu (105 min, 88.7 km)
    var romancecar: Ride { store.trip.rides.first { $0.id == "r-4-romancecar-st-shinjuku-odakyu" }! }

    @Test func aTrainBeingRiddenIsNotLate() {
        let day4 = store.day("4")!, track = store.track(of: romancecar)
        let mid = track[track.count / 2]
        #expect(Itinerary(store: store).project(day4, done: [], now: 510, position: mid).replan == nil)
    }

    @Test func aTakenTrainDoesNotHoldTheCursor() {
        let r = Itinerary(store: store).project(store.day("4")!, done: [1], now: 630, position: store.place("onshi-hakone-park")!.coordinate)
        #expect(r.cursor >= 3); #expect(r.replan?.target != 2)
    }

    @Test func alightedBeforeTheRideIsMarked() throws {
        // off the Romancecar at Hakone-Yumoto at 9:25, the Chūō line marked and the Romancecar not yet:
        // the day is past the train, and the 9:35 bus is in reach
        let yumoto = try #require(store.place("st-hakone-yumoto"))
        let p = Itinerary(store: store).project(day4, done: [1], now: 9 * 60 + 25, position: yumoto.coordinate)
        #expect(p.cursor == 3)
        #expect(p.replan == nil, "\(String(describing: p.replan))")
    }

    @Test func aTrainYouWaitForOnItsPlatformIsNotMissed() throws {
        // about 145 m from the Odakyu pin, inside the station's circle: a minute before the 7:37, and three
        // minutes after it (a train running late), neither is a missed train
        let station = try #require(store.place("st-shinjuku-odakyu"))
        let platform = Coordinate(station.coordinate.lat + 0.0013, station.coordinate.lng)
        #expect(Presence.isAt(platform, station))
        let it = Itinerary(store: store)
        for now: Double in [7 * 60 + 36, 7 * 60 + 40] {
            let p = it.project(day4, done: [], now: now, position: platform)
            #expect(p.cursor == 2)
            #expect(p.replan == nil, "\(now): \(String(describing: p.replan))")
        }
        // 400 m away, outside the circle, the same minute before it: still on the way, and late
        let street = Coordinate(station.coordinate.lat + 0.0036, station.coordinate.lng)
        #expect(!Presence.isAt(street, station))
        #expect(it.project(day4, done: [], now: 7 * 60 + 36, position: street).replan?.target == 2)
    }

    @Test func aBookedTableYouSitAtIsNotLate() throws {
        // seated at AWA (day 10, booked for 12:30) at 12:34, before anything after it is marked
        let awa = try #require(store.place("awa"))
        let it = Itinerary(store: store)
        let p = it.project(day10, done: Set(0 ... 10), now: 12 * 60 + 34, position: awa.coordinate)
        #expect(p.cursor == 11)
        #expect(p.replan == nil, "\(String(describing: p.replan))")
        // 400 m away at the same minute: late for it
        let away = Coordinate(awa.coordinate.lat + 0.0036, awa.coordinate.lng)
        #expect(it.project(day10, done: Set(0 ... 10), now: 12 * 60 + 34, position: away).replan?.target == 11)
    }

    @Test func aTrainLeftWhileStillInTownIsMissed() throws {
        // Kawaguchiko day: Honchō-dōri lies 3.3 km from Kawaguchiko station and 0.4 km from the Fujikyu
        // line the 16:48 Fuji Excursion takes back to Shinjuku. At 16:55 standing there is not riding it:
        // the day was there before the train
        let day = try #require(store.day("kawaguchiko"))
        let honcho = try #require(store.place("fs-honcho-dori"))
        let p = Itinerary(store: store).project(day, done: [], now: 16 * 60 + 55, position: honcho.coordinate)
        #expect(p.cursor == 21)
        #expect(p.replan?.target == 21)
    }

    @Test func theRideYouAreOnSetsTheClock() throws {
        let it = Itinerary(store: store)
        let track = store.track(of: romancecar), mid = track[track.count / 2]
        let tracker = RideTracker(ride: romancecar, store: store)
        let status = try #require(tracker.status(at: mid))
        let left = try #require(tracker.minutesLeft(km: status.km))
        // on time at 8:30, half way: the day goes on from the bus, at the train's timetable arrival, not
        // at the earlier one its pace alone would give
        let paced: Double = 8 * 60 + 30 + left
        #expect(paced < 9 * 60 + 22)
        let onTime = it.project(day4, done: [], now: 8 * 60 + 30, position: mid)
        #expect(onTime.cursor == 3)
        #expect(onTime.riding?.id == romancecar.id)
        #expect(onTime.slots.first?.ready == Double(9 * 60 + 22))
        // still half way at 9:30, followed: it arrives the rest of the way later, and the 9:35 bus is gone
        let late = it.project(day4, done: [], now: 9 * 60 + 30, position: mid, riding: romancecar)
        #expect(late.cursor == 3)
        let bus = try #require(late.slots.first)
        let due: Double = 9 * 60 + 30 + left
        #expect(abs(bus.ready - due) < 1e-9)
        #expect(late.replan?.target == 3)
        // a stop that holds you wins over the ride (off the bus at Onshi Park before it was marked)
        let onshi = try #require(store.place("onshi-hakone-park"))
        let off = it.project(day4, done: [1], now: 10 * 60 + 20, position: onshi.coordinate)
        #expect(off.cursor == 4)
        #expect(off.riding == nil)
    }

    @Test func aFollowedRideStartsTheDayAfterIt() throws {
        let it = Itinerary(store: store)
        // on the Romancecar at 8:30 with no position: the day goes on from the bus, at the train's arrival
        let p = it.project(day4, done: [], now: 8 * 60 + 30, position: nil, riding: romancecar)
        #expect(p.cursor == 3)
        #expect(p.riding?.id == romancecar.id)
        #expect(p.slots.first?.ready == Double(9 * 60 + 22))
        #expect(p.replan == nil)
        // without it, the clock alone has you at the train, late for it: no position, no inference
        #expect(it.project(day4, done: [], now: 8 * 60 + 30, position: nil).cursor == 2)
        // followed from the platform at 7:20: not under way yet, the day is still at the train
        let early = it.project(day4, done: [], now: 7 * 60 + 20, position: nil, riding: romancecar)
        #expect(early.cursor == 2)
        #expect(early.riding == nil)
        // marked past it: the marks win
        let past = it.project(day4, done: [4], now: 8 * 60 + 30, position: nil, riding: romancecar)
        #expect(past.cursor == 5)
        #expect(past.riding == nil)
        // another day's ride counts for nothing here
        let ise = try #require(store.trip.rides.first { $0.id == "r-7-shimakaze-st-toba" })
        #expect(it.project(day4, done: [], now: 8 * 60 + 30, position: nil, riding: ise).riding == nil)
        // the ropeway has Ōwakudani between its legs: following it never skips the stop
        let ropeway = try #require(store.trip.rides.first { $0.id == "r-4-hakoneRopeway-togendai" })
        let up = it.project(day4, done: Set(0 ... 8), now: 13 * 60 + 15, position: nil, riding: ropeway)
        #expect(up.cursor == 9)
        #expect(up.riding == nil)
    }

    @Test func oversleptTheTrainIsMissedNotTaken() throws {
        // guard: at the hotel in Akihabara at 7:45, eight km from Shinjuku and off the Odakyu line, the
        // Romancecar is missed, not taken
        let hotel = try #require(store.place("resol-akihabara"))
        let p = Itinerary(store: store).project(day4, done: [], now: 7 * 60 + 45, position: hotel.coordinate)
        #expect(p.cursor == 2)
        #expect(p.replan?.target == 2)
    }

    // MARK: A day without times

    @Test func theClockMovesTheCursorOnlyOnATimedDay() {
        let it = Itinerary(store: store), engine = PlanEngine(store: store)
        let all = store.trip.days + store.trip.altDays
        // the one day in the data with no time at all: the way to the airport
        #expect(all.filter { $0.items.first?.at == nil }.map(\.key) == ["12"])
        for day in all {
            let slots = engine.simulate(day)
            for half in 10 ... 47 {
                let now = Double(half * 30)
                let cursor = it.cursor(day, done: [], now: now)
                if day.items.first?.at != nil {
                    // every half hour from 5:00 to 23:30, with nothing marked and no position: the plan's clock
                    #expect(cursor == (slots.first { $0.end > now }?.index ?? day.items.count), "day \(day.key) at \(TripTime.clock(now))")
                } else {
                    // its made-up times end before 1:30: it stays at its first item, until a mark moves it
                    #expect(cursor == 0, "day \(day.key) at \(TripTime.clock(now))")
                    #expect(it.cursor(day, done: [0], now: now) == 1)
                }
            }
        }
    }

    @Test func anUntimedDayFollowsWhereYouStand() throws {
        // day 12 with KIX made a sight (a station never holds the day): standing there at 8:00 holds the
        // day there, although the plan's made-up times left it before 1:30
        let patched = try TripStore.patched { trip in
            var places = try #require(trip["places"] as? [[String: Any]])
            let i = try #require(places.firstIndex { $0["id"] as? String == "kix" })
            places[i]["kind"] = "sight"
            trip["places"] = places
        }
        let kix = try #require(patched.place("kix"))
        let day12 = try #require(patched.day("12"))
        #expect(Itinerary(store: patched).cursor(day12, done: [], now: 8 * 60, position: kix.coordinate) == 2)
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
        let day7 = try #require(store.day("7"))
        let points = Itinerary(store: store).waypoints(day7)
        let shimakaze = try #require(points.first { $0.index == 13 })
        #expect(shimakaze.kind == .departure)
        // leave Sazanami with the walk to the station and three minutes in hand, not earlier
        let walk = try #require(day7.items[12].move?.leg.walk)
        #expect(shimakaze.setOff == Double(15 * 60 + 20 - walk.min) - Itinerary.margin)
        #expect(points.contains { $0.placeID == "sazanami-toba" })
        // the subway that evening is no departure to leave for
        #expect(!points.contains { $0.index == 15 })
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

    @Test func sameDishInOtherCharactersMatchesByReading() {
        // a stand-in for the system's dictionary, which Linux does not have
        let words = ["天麩羅": "tenpura", "天ぷら": "tenpura", "蕎麦": "soba", "そば": "soba",
                     "牛丼": "gyuudon", "弁当": "bentou", "持ち帰り": "mochikaeri"]
        let reading = Reading { s in
            words.sorted { $0.key.count > $1.key.count }.reduce(s) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
        }
        #expect(JapaneseText.similarity("天ぷら蕎麦", "天ぷらそば") < 0.55)
        #expect(JapaneseText.similarity("天ぷら蕎麦", "天ぷらそば", reading: reading) == 1)
        #expect(JapaneseText.similarity("天麩羅そば", "天ぷらそば", reading: reading) == 1)
        // the bowl's name inside a takeaway box's line is not the bowl
        #expect(JapaneseText.similarity("持ち帰り 牛丼弁当", "牛丼") < 0.55)
        #expect(JapaneseText.similarity("持ち帰り 牛丼弁当", "牛丼", reading: reading) < 0.55)
        // a dish named inside a longer line still is the dish
        #expect(JapaneseText.similarity("名物 天ぷらそば", "天ぷらそば") >= 0.55)

        let soba = MenuMatcher.Candidate(placeID: "x", item: MenuItem(ja: "天ぷらそば", romaji: nil, vi: "Soba tempura", yen: 2000, yenNote: nil, pick: .signature, note: nil))
        let beef = MenuMatcher.Candidate(placeID: "x", item: MenuItem(ja: "牛丼", romaji: nil, vi: "Cơm bò", yen: 500, yenNote: nil, pick: .popular, note: nil))
        let hits = MenuMatcher(candidates: [soba, beef], reading: reading)
            .match(lines: ["天麩羅そば ２，０００円", "持ち帰り 牛丼弁当 650円"])
        #expect(hits.map(\.candidate.item.ja) == ["天ぷらそば"])
        #expect(hits.first?.printedYen == 2000)
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

    @Test func anUntimedDayIsNotOverAtNight() {
        let day12 = store.day("12")!
        #expect(Itinerary(store: store).cursor(day12, done: [], now: 480) == 0)
        let morning = ReminderPlanner(store: store).reminders(for: day12).first { $0.kind == .morning }
        #expect(morning.map { $0.fire >= TripTime.midnight("2027-10-29")! } ?? true)
    }

    @Test func theMorningReminderOnlyOnATimedDay() throws {
        let planner = ReminderPlanner(store: store), engine = PlanEngine(store: store)
        for day in store.trip.days + store.trip.altDays {
            let mornings = planner.reminders(for: day).filter { $0.kind == .morning }
            let midnight = try #require(TripTime.midnight(day.date))
            if day.items.first?.at != nil {
                // half an hour before the day begins, as it always was
                let start = try #require(engine.simulate(day).first).begin
                #expect(mornings.map(\.fire) == [TripTime.date(day.date, minutes: start - 30)], "day \(day.key)")
                #expect(mornings.map(\.id) == ["morning-\(day.key)"])
            } else {
                // a day with no time (12) has nothing to wake you for the night before
                #expect(mornings.allSatisfy { $0.fire >= midnight }, "day \(day.key): \(mornings.map(\.fire))")
            }
        }
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
        // day 2's only timed ride is the Ginza Line: no station to be warned at
        #expect(!f2.contains { $0.kind == .station })
        let f4 = FencePlanner(store: store).fences(today: days[3], cursor: 0, tomorrow: days[4])
        #expect(f4.contains { $0.placeID == "st-shinjuku-odakyu" && $0.kind == .station })
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

    @Test func oneStayReportedTwiceIsOneVisit() throws {
        let day = store.day("2")!
        let sensoji = try #require(store.place("sensoji"))
        let arrive = try #require(TripTime.date(day.date, "13:50"))
        let leave = try #require(TripTime.date(day.date, "14:40"))
        // iOS: once on arrival (no departure yet), once on leaving (both times), a few metres apart
        let visits = [
            VisitRecord(arrival: arrive, departure: nil, coordinate: sensoji.coordinate),
            VisitRecord(arrival: arrive.addingTimeInterval(30), departure: leave, coordinate: Coordinate(sensoji.coordinate.lat + 0.0002, sensoji.coordinate.lng)),
        ]
        #expect(VisitRecord.merged(visits).count == 1)
        #expect(VisitRecord.merged(visits).first?.departure == leave)
        let j = Journal(store: store, day: day, visits: visits, marked: [:], now: TripTime.date(day.date, "22:00")!)
        let e = try #require(j.entries.first { $0.place.id == "sensoji" })
        if case .visited(_, let departure, _) = e.status { #expect(departure == leave) } else { Issue.record("not visited: \(e.status)") }
        #expect(j.extras.isEmpty)
    }

    @Test func fencesAreWideEnoughForACity() {
        let days = store.days()
        let f = FencePlanner(store: store).fences(today: days[1], cursor: 0, tomorrow: days[2])
        #expect(!f.isEmpty)
        #expect(f.allSatisfy { $0.radius >= 150 })
    }

    @Test func oneStayMarksTheStopItIsAt() throws {
        let it = Itinerary(store: store)
        let day6 = try #require(store.day("6"))
        let akafuku = try #require(store.place("akafuku"))
        let fukusuke = try #require(store.place("fukusuke"))
        // Fukusuke (9) comes first in the plan and is 51 m away; a stay at Akafuku is Akafuku's
        #expect(Geo.km(akafuku.coordinate, fukusuke.coordinate) < 0.15)
        #expect(it.stop(at: akafuku.coordinate, in: day6, done: []) == 12)
        // reported again on leaving, with Akafuku marked: still Akafuku, so nothing new is marked
        #expect(it.stop(at: akafuku.coordinate, in: day6, done: [12]) == 12)
        #expect(it.stop(at: fukusuke.coordinate, in: day6, done: [12]) == 9)
        // far from every stop: none
        #expect(it.stop(at: Coordinate(34.5, 136.5), in: day6, done: []) == nil)
    }

    @Test func aPlaceVisitedTwiceTakesItsVisitsInOrder() throws {
        let it = Itinerary(store: store)
        let day8 = try #require(store.day("8"))
        let wargo = try #require(store.place("wargo-gion"))
        #expect(it.stop(at: wargo.coordinate, in: day8, done: []) == 5)
        #expect(it.stop(at: wargo.coordinate, in: day8, done: [5]) == 12)
    }

    @Test func theJournalGivesEachStayToOneStop() throws {
        let day6 = try #require(store.day("6"))
        let akafuku = try #require(store.place("akafuku"))
        let noon = try #require(TripTime.date(day6.date, minutes: 12 * 60))
        let stay = VisitRecord(arrival: noon, departure: noon.addingTimeInterval(1800), coordinate: akafuku.coordinate)
        let journal = Journal(store: store, day: day6, visits: [stay], marked: [:], now: noon.addingTimeInterval(4 * 3600))
        let visited = journal.entries.filter { if case .visited = $0.status { true } else { false } }.map(\.index)
        #expect(visited == [12])
    }

    @Test func oneDefinitionOfBeingThere() throws {
        let sensoji = try #require(store.place("sensoji"))
        let owariya = try #require(store.place("owariya"))
        #expect(Presence.radius(of: sensoji) == 0.25)
        #expect(Presence.radius(of: owariya) == 0.15)
        #expect(FencePlanner.radius(owariya) == 150)
    }

    @Test func wakeAlarmsOnlyOnLongTrainRides() throws {
        let wake = WakePlanner(store: store)
        let worth = Set((store.trip.days.flatMap { store.rides(on: $0) }).filter(wake.isWorthAnAlarm).map(\.id))
        #expect(worth == ["r-4-romancecar-st-shinjuku-odakyu", "r-5-tokaido-st-odawara", "r-5-kintetsu-st-kintetsu-nagoya",
                          "r-7-shimakaze-st-toba", "r-10-kintetsu-st-kintetsu-nara"], "\(worth.sorted())")
        // the pirate ship, the Toba ferry, buses: never
        #expect(!worth.contains { $0.contains("Cruise") || $0.contains("Ferry") || $0.contains("Bus") })
        #expect(TripTime.statedMaxMinutes("55–80") == 80)
        #expect(TripTime.statedMaxMinutes("1 giờ 40") == 100)
        #expect(TripTime.statedMaxMinutes("20–25, đổi tàu") == 25)
    }

    @Test func tomorrowsEarlyTrainIsSetTheEveningBefore() throws {
        let wake = WakePlanner(store: store)
        let days = store.days()
        let evening = try #require(TripTime.date(days[2].date, minutes: 21 * 60))
        let wakes = wake.wakes(days: days, now: evening) { _, _ in false }
        let romancecar = try #require(wakes.first { $0.rideID == "r-4-romancecar-st-shinjuku-odakyu" })
        // 7:37 plus 105 minutes, four before
        #expect(romancecar.at == TripTime.date(days[3].date, minutes: 7 * 60 + 37 + 105 - 4))
        #expect(!romancecar.station.isEmpty)
        // a ride already taken wants no alarm
        let taken = wake.wakes(days: days, now: evening) { day, _ in day.key == "4" }
        #expect(!taken.contains { $0.rideID == romancecar.rideID })
    }

    @Test func oneSlowLegDoesNotDecideThePace() {
        var pace = PaceModel()
        // a 15-minute walk that took 22 (a crowd, a photo): the model still counts for more
        pace.add(planned: 15, actual: 22)
        #expect(pace.factor > 0.85)
        #expect(pace.factor < 1)
    }

    @Test func templePhrasesOnlyAtTemplesAndShrines() throws {
        for id in ["uji-bridge", "toshijima-wagu", "toshijima-toshi", "hanamikoji", "ishibe-koji", "hozenji", "fs-shimoyoshida-station", "kashikojima"] {
            #expect(!TripStore.isSacred(try #require(store.place(id))), "\(id)")
        }
        for id in ["sensoji", "meiji-jingu", "nezu-shrine", "adashino", "kiyomizudera", "fs-fujisan-hongu-sengen-taisha"] {
            #expect(TripStore.isSacred(try #require(store.place(id))), "\(id)")
        }
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
