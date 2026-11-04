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
        // the day goes on from now, not from the stop's 13:45: only a fixed time is met by standing there
        #expect((p.slots.first?.ready ?? 0) >= now)
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
        // still there at 9:34, twelve minutes after the train's 9:22: at the end of its track, you came on it
        let later = Itinerary(store: store).project(day4, done: [1], now: 9 * 60 + 34, position: yumoto.coordinate)
        #expect(later.riding?.id == romancecar.id)
    }

    @Test func aTrainYouWaitForOnItsPlatformIsNotMissed() throws {
        // about 145 m from the Odakyu pin, inside the station's circle: a minute before the 7:37, and up
        // to its minute of grace after it (a train running a little late), neither is a missed train
        let station = try #require(store.place("st-shinjuku-odakyu"))
        let platform = Coordinate(station.coordinate.lat + 0.0013, station.coordinate.lng)
        #expect(Presence.isAt(platform, station))
        let it = Itinerary(store: store)
        let grace = Double(store.trip.rules.grace.move)
        #expect(grace == 1)
        for now: Double in [7 * 60 + 36, 7 * 60 + 37 + grace] {
            let p = it.project(day4, done: [], now: now, position: platform)
            #expect(p.cursor == 2)
            #expect(p.replan == nil, "\(now): \(String(describing: p.replan))")
            // there now, or there at its time when that is earlier
            #expect(p.slots.first?.ready == min(now, 7 * 60 + 37))
        }
        // a minute past that, standing on the platform is missing it, as anywhere else: it has left
        for now: Double in [7 * 60 + 38 + grace, 7 * 60 + 40, 7 * 60 + 45] {
            #expect(it.project(day4, done: [], now: now, position: platform).replan?.target == 2, "\(now)")
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

    @Test func aConnectionGoneFromItsStationIsMissed() throws {
        let it = Itinerary(store: store)
        // off the Romancecar at Hakone-Yumoto at 9:40, the train marked: the 9:35 bus has left
        let yumoto = try #require(store.place("st-hakone-yumoto"))
        #expect(it.project(day4, done: [0, 1, 2], now: 9 * 60 + 40, position: yumoto.coordinate).replan?.target == 3)
        // at Kintetsu-Nara at 16:05, the 16:00 to Osaka gone
        let nara = try #require(store.place("st-kintetsu-nara"))
        let p = it.project(day10, done: Set(0 ... 15), now: 16 * 60 + 5, position: nara.coordinate)
        #expect(p.cursor == 16)
        #expect(p.replan?.target == 16)
    }

    @Test func aTrainLeftWhileStillInTownIsMissed() throws {
        // Kawaguchiko day: Honchō-dōri lies 3.3 km from Kawaguchiko station and 0.4 km from the Fujikyu
        // line the 16:48 Fuji Excursion takes back to Shinjuku. At 16:55 standing there is not riding it:
        // the day was there before the train
        let day = try #require(store.day("kawaguchiko"))
        let it = Itinerary(store: store)
        let honcho = try #require(store.place("fs-honcho-dori"))
        let p = it.project(day, done: [], now: 16 * 60 + 55, position: honcho.coordinate)
        #expect(p.cursor == 21)
        #expect(p.replan?.target == 21)
        // on the line 0.8 km from Honchō-dōri, a kilometre being near enough to it
        #expect(it.project(day, done: [], now: 16 * 60 + 55, position: Coordinate(35.49094, 138.79633)).cursor == 21)
        // in town along the line, far from every place the day named: at Fuji-Q Highland (km 1.7) at 17:05,
        // and where the line reverses at Fujisan station (km 2.8) at 17:30, the train is long past
        let back = try #require(store.trip.altRides.first { $0.id == "r-kawaguchiko-fujiExcursion-st-kawaguchiko" })
        let track = store.track(of: back)
        let highland = track[6], fujisan = track[9]
        #expect(it.project(day, done: [], now: 17 * 60 + 5, position: highland).replan?.target == 21)
        #expect(it.project(day, done: [], now: 17 * 60 + 30, position: fujisan).replan?.target == 21)
        // ten minutes behind where the timetable has the train is still on it; a second more is not
        let status = try #require(RideTracker(ride: back, store: store).status(at: highland))
        let due = try #require(Itinerary.due(back, km: status.km))
        #expect(abs(due - (16 * 60 + 48 + status.km / back.km * 120)) < 1e-9)
        let edge = due + Itinerary.behindTimetable
        #expect(edge - due == Itinerary.behindTimetable)
        #expect(Itinerary.behindTimetable == 10)
        let on = it.project(day, done: [], now: edge, position: highland)
        #expect(on.cursor == 22)
        #expect(on.riding?.id == back.id)
        #expect(it.project(day, done: [], now: edge + 1.0 / 60, position: highland).cursor == 21)
    }

    @Test func aTrainIsRiddenAKilometreOut() throws {
        let it = Itinerary(store: store)
        // 7:40, on the Odakyu track 1.33 km out of Shinjuku (the nearest place named before it 1.22 km away)
        #expect(it.project(day4, done: [], now: 7 * 60 + 40, position: Coordinate(35.68015, 139.69465)).cursor == 3)
        // 8:30, 0.74 km off the track half way: within a kilometre of it is on its line
        let track = store.track(of: romancecar), mid = track[track.count / 2]
        let off = Coordinate(mid.lat + 0.009, mid.lng)
        let status = try #require(RideTracker(ride: romancecar, store: store).status(at: off))
        #expect(status.offTrackKm > 0.7 && status.offTrackKm < 1)
        #expect(it.project(day4, done: [], now: 8 * 60 + 30, position: off).cursor == 3)
        // its time has come at its own minute (as for a followed ride)
        #expect(it.project(day4, done: [], now: 7 * 60 + 37, position: mid).cursor == 3)
    }

    @Test func onlyTheItemTheDayIsAtIsMetByStandingThere() throws {
        // Kawaguchiko day at 9:55, at the Lawson (item 5) 0.13 km from Kawaguchiko station: inside the
        // station's circle, but the day is at the Lawson, and the 10:00 Fujikyu (item 7) is at risk
        let day = try #require(store.day("kawaguchiko"))
        let lawson = try #require(store.place("fs-lawson-kawaguchiko-ekimae"))
        let p = Itinerary(store: store).project(day, done: Set(0 ... 4), now: 9 * 60 + 55, position: lawson.coordinate)
        #expect(p.cursor == 5)
        #expect(p.replan?.target == 7)
    }

    @Test func aFollowedRideFarFromItsTrackCountsForNothing() throws {
        let it = Itinerary(store: store)
        // followed, but at the hotel in Akihabara at 7:45: the Romancecar is missed, as unfollowed
        let hotel = try #require(store.place("resol-akihabara"))
        let p = it.project(day4, done: [], now: 7 * 60 + 45, position: hotel.coordinate, riding: romancecar)
        #expect(p.riding == nil)
        #expect(p.replan?.target == 2)
        // at 8:00 near km 4 of its track: 1.35 km off it still counts (the timetable's arrival, the track
        // being too far to read the km from); farther than `RideTracker.offTrack` it does not
        let track = store.track(of: romancecar), near = track[track.count / 10]
        let tracker = RideTracker(ride: romancecar, store: store)
        let close = Coordinate(near.lat + 0.016, near.lng), far = Coordinate(near.lat + 0.019, near.lng)
        let closeOff = try #require(tracker.status(at: close)).offTrackKm
        let farOff = try #require(tracker.status(at: far)).offTrackKm
        #expect(closeOff > 1 && closeOff < RideTracker.offTrack)
        #expect(farOff > RideTracker.offTrack && farOff < 1.7)
        let counted = it.project(day4, done: [], now: 8 * 60, position: close, riding: romancecar)
        #expect(counted.riding?.id == romancecar.id)
        #expect(counted.slots.first?.ready == Double(9 * 60 + 22))
        let ignored = it.project(day4, done: [], now: 8 * 60, position: far, riding: romancecar)
        #expect(ignored.cursor == 2)
        #expect(ignored.riding == nil)
    }

    /// The rides whose destination, with its whole circle, does not lie within `RideTracker.offTrack`
    /// of the ride's own track (or whose destination cannot be found).
    func destinationsOffTrack(_ store: TripStore) -> [String] {
        (store.trip.rides + store.trip.altRides).compactMap { ride in
            guard let day = store.day(ride.day),
                  let move = day.items.compactMap(\.move).first(where: { $0.leg.id == ride.legs.last }),
                  let to = store.place(move.leg.to),
                  let status = RideTracker(ride: ride, store: store).status(at: to.coordinate),
                  status.offTrackKm + Presence.radius(of: to) < RideTracker.offTrack
            else { return ride.id }
            return nil
        }
    }

    @Test func everyRideEndsOnItsTrack() throws {
        // what `strays` relies on: standing at a ride's destination is never far from its track
        #expect(destinationsOffTrack(store) == [])
        // and the check bites: Hakone-Yumoto moved two kilometres south is off the Romancecar's track
        let moved = try TripStore.patched { trip in
            var places = try #require(trip["places"] as? [[String: Any]])
            let i = try #require(places.firstIndex { $0["id"] as? String == "st-hakone-yumoto" })
            places[i]["lat"] = try #require(places[i]["lat"] as? Double) - 0.018
            trip["places"] = places
        }
        #expect(destinationsOffTrack(moved).contains(romancecar.id))
    }

    @Test func aRangedRunTimeIsReadAtItsSlowEnd() throws {
        // day 10: the 16:00 Kintetsu from Nara to Namba runs "35–45" minutes. Near Namba, on schedule
        // for 45 and five minutes behind it, you are on that train: by the 35 it would be long gone
        let ride = try #require(store.trip.rides.first { $0.id == "r-10-kintetsu-st-kintetsu-nara" })
        #expect(ride.min == "35–45")
        let tracker = RideTracker(ride: ride, store: store)
        let track = store.track(of: ride)
        let point = try #require(track.first { p in tracker.status(at: p).map { $0.km > 0.8 * ride.km && !$0.arrived } ?? false })
        let status = try #require(tracker.status(at: point))
        let slow = 16 * 60 + status.km / ride.km * 45, quick = 16 * 60 + status.km / ride.km * 35
        let now = slow + 5
        #expect(now - quick > Itinerary.behindTimetable)
        let p = Itinerary(store: store).project(day10, done: Set(0 ... 15), now: now, position: point)
        #expect(p.cursor == 17)
        #expect(p.riding?.id == ride.id)
    }

    // Kawaguchiko day: item 3 is the 7:30 Fuji Excursion from Shinjuku, item 5 the Lawson stop at
    // Kawaguchiko. A point of its track 0.6 km out of Shinjuku, outside the station's circle:
    var upTheLine: Coordinate { Coordinate(35.69546, 139.69976) }

    @Test func aStopAtTheStationDoesNotTakeTheDayPastTheTrainYouWaitFor() throws {
        // the Lawson moved onto Shinjuku station: at 7:35 on the platform, the train is the one you wait
        // for, and a stop after it does not hold the day
        let station = try #require(store.place("st-shinjuku"))
        let patched = try TripStore.patched { trip in
            var places = try #require(trip["places"] as? [[String: Any]])
            let i = try #require(places.firstIndex { $0["id"] as? String == "fs-lawson-kawaguchiko-ekimae" })
            places[i]["lat"] = station.coordinate.lat
            places[i]["lng"] = station.coordinate.lng
            trip["places"] = places
        }
        let day = try #require(patched.day("kawaguchiko"))
        #expect(Itinerary(store: patched).project(day, done: [], now: 7 * 60 + 35, position: station.coordinate).cursor == 3)
    }

    @Test func nearItsStationATrainIsTakenNotRidden() throws {
        let station = try #require(store.place("st-shinjuku"))
        #expect(!Presence.isAt(upTheLine, station))
        #expect(Geo.km(upTheLine, station.coordinate) < 1)
        // on its line, though within a kilometre of its station: taken, so a stop after it may hold the day
        let moved = try TripStore.patched { trip in
            var places = try #require(trip["places"] as? [[String: Any]])
            let i = try #require(places.firstIndex { $0["id"] as? String == "fs-lawson-kawaguchiko-ekimae" })
            places[i]["lat"] = upTheLine.lat
            places[i]["lng"] = upTheLine.lng
            trip["places"] = places
        }
        let day = try #require(moved.day("kawaguchiko"))
        #expect(Itinerary(store: moved).project(day, done: [], now: 7 * 60 + 35, position: upTheLine).cursor == 5)
        // but not ridden: with nothing before the train to stand near, the day is still at it, and late
        let first = try TripStore.patched { trip in
            for id in ["s:resol-akihabara", "m:resol-akihabara>st-akihabara", "m:st-akihabara>st-shinjuku"] {
                trip.removeItem(day: "kawaguchiko", id: id)
            }
        }
        let bare = try #require(first.day("kawaguchiko"))
        let p = Itinerary(store: first).project(bare, done: [], now: 7 * 60 + 35, position: upTheLine)
        #expect(p.cursor == 0)
        #expect(p.riding == nil)
        #expect(p.replan?.target == 0)
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
        // and over the ride followed: the day is at the stop, not just past the train
        let followed = it.project(day4, done: [1], now: 10 * 60 + 20, position: onshi.coordinate, riding: romancecar)
        #expect(followed.cursor == 4)
        #expect(followed.riding == nil)
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
        // at its own minute it is
        #expect(it.project(day4, done: [], now: 7 * 60 + 37, position: nil, riding: romancecar).cursor == 3)
        // a ride with no time counts at once: the Nankai to the airport on day 12, at 8:00
        let day12 = try #require(store.day("12"))
        let nankai = try #require(store.trip.rides.first { $0.id == "r-12-nankai-st-nankai-namba" })
        let airport = it.project(day12, done: [], now: 8 * 60, position: nil, riding: nankai)
        #expect(airport.cursor == 2)
        #expect(airport.riding?.id == nankai.id)
        // marked past it: the marks win
        let past = it.project(day4, done: [4], now: 8 * 60 + 30, position: nil, riding: romancecar)
        #expect(past.cursor == 5)
        #expect(past.riding == nil)
        // another day's ride counts for nothing here
        let ise = try #require(store.trip.rides.first { $0.id == "r-7-shimakaze-st-toba" })
        #expect(it.project(day4, done: [], now: 8 * 60 + 30, position: nil, riding: ise).riding == nil)
        // even one whose leg this day takes too: the Kawaguchiko day's Chūō line to Shinjuku is item 1 here
        let chuo = try #require(store.trip.altRides.first { $0.id == "r-kawaguchiko-chuoSobu-st-akihabara" })
        #expect(chuo.legs.allSatisfy { leg in day4.items[1].move?.leg.id == leg })
        #expect(it.project(day4, done: [], now: 8 * 60 + 30, position: nil, riding: chuo).riding == nil)
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

    @Test func lateCountsInFiveMinuteSteps() {
        // the widget is sent a new snapshot when the step changes, not with every minute
        #expect(Replan.lateStep(nil) == nil)
        #expect([0, 2, 3, 7, 8, 12, 13, 17, 18].map { Replan.lateStep($0) } == [0, 0, 1, 1, 2, 2, 3, 3, 4])
        #expect(Replan.lateStep(12) == Replan.lateStep(10) && Replan.lateStep(13) != Replan.lateStep(12))
    }

    @Test func aFollowedRideHoldsTheBackgroundReplanUntilAnHourPastItsArrival() throws {
        let it = Itinerary(store: store)
        // the Romancecar arrives at 9:22 by the plan: held until 10:22, not after
        let at = { (hm: String) in TripTime.date(self.day4.date, hm)! }
        #expect(it.holdsReschedule(for: romancecar, at: at("8:00")))
        #expect(it.holdsReschedule(for: romancecar, at: at("10:21")))
        #expect(!it.holdsReschedule(for: romancecar, at: at("10:22")))
        #expect(!it.holdsReschedule(for: romancecar, at: at("13:00")))
        // the ropeway, Ōwakudani between its legs: until an hour after its last leg (14:30 by the plan)
        let ropeway = try #require(store.trip.rides.first { $0.id == "r-4-hakoneRopeway-togendai" })
        let end = try #require(PlanEngine(store: store).simulate(day4).first { $0.index == 11 }).end
        #expect(it.holdsReschedule(for: ropeway, at: TripTime.date(day4.date, minutes: end + 59)!))
        #expect(!it.holdsReschedule(for: ropeway, at: TripTime.date(day4.date, minutes: end + 60)!))
        // the way to the airport has no time: its made-up end (before 1:30) holds nothing at 8:00
        let nankai = try #require(store.trip.rides.first { $0.id == "r-12-nankai-st-nankai-namba" })
        #expect(!it.holdsReschedule(for: nankai, at: TripTime.date("2027-10-29", "8:00")!))
        // only on the ride's own day, from half an hour before it leaves (a ride with no time: its day)
        #expect(Itinerary.rideHoldAhead == 30)
        #expect(!it.holdsReschedule(for: romancecar, at: at("7:06")))
        #expect(it.holdsReschedule(for: romancecar, at: at("7:07")))
        #expect(!it.holdsReschedule(for: romancecar, at: TripTime.date("2027-10-19", "8:00")!))
        #expect(!it.holdsReschedule(for: romancecar, at: TripTime.date("2027-10-20", "12:00")!))
        #expect(!it.holdsReschedule(for: nankai, at: TripTime.date("2027-10-28", "20:00")!))
        #expect(!it.holdsReschedule(for: nankai, at: TripTime.date("2027-10-28", "23:59")!))
        #expect(it.holdsReschedule(for: nankai, at: TripTime.date("2027-10-29", "0:00")!))
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

    @Test func onlyTheWayToTheAirportHasNoPlannedTime() {
        // the Today card names the item the day is at, untimed, on such a day only (an evening's walk
        // back to the hotel on any other day is the day's end)
        let it = Itinerary(store: store)
        #expect((store.trip.days + store.trip.altDays).filter { it.isUntimed($0) }.map(\.key) == ["12"])
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

    static let cruise = "r-4-ashiCruise-moto-hakone-port"

    /// The Ashi cruise, a direct ride (its stop before yours is where you board), made `km` long.
    func cruise(km: Double) throws -> RideTracker {
        let patched = try TripStore.patched { trip in
            guard var rides = trip["rides"] as? [[String: Any]],
                  let i = rides.firstIndex(where: { $0["id"] as? String == Self.cruise }),
                  var stations = rides[i]["stations"] as? [[String: Any]], !stations.isEmpty
            else { throw CocoaError(.coderReadCorrupt) }
            stations[stations.count - 1]["km"] = km
            rides[i]["stations"] = stations
            rides[i]["km"] = km
            trip["rides"] = rides
        }
        let ride = try #require(patched.trip.rides.first { $0.id == Self.cruise })
        #expect(ride.km == km)
        return RideTracker(ride: ride, store: patched)
    }

    @Test func aDirectFerryIsNotAlightingAtBoarding() throws {
        let t = RideTracker(ride: store.trip.rides.first { $0.id == "r-4-ashiCruise-moto-hakone-port" }!, store: store)
        #expect(t.status(km: 0).alightSoon == false)
        #expect(t.status(km: 5.7).alightSoon == true)   // the cruise is 5.9 km
        #expect(t.minutesToAlightPrompt(km: 0)! > 0)
        // ready over its last 15 %: from 5.9 - 0.885 = 5.015 km, 34 of its 40 minutes in
        #expect(!t.status(km: 5.01).alightSoon)
        #expect(t.status(km: 5.02).alightSoon)
        #expect(abs(t.tail - 5.015) < 1e-9)
        #expect(t.status(km: t.tail).alightSoon)
        #expect(abs(t.minutesToAlightPrompt(km: 0)! - 5.015 / 5.9 * 40) < 1e-9)
        #expect(t.minutesToAlightPrompt(km: 5.5) == 0)
        // the Toba ferry to Wagu, 6.2 km in 18 minutes: ready from 5.27 km
        let toba = try #require(store.trip.rides.first { $0.id == "r-7-tobaFerry-toba-marine-terminal" })
        let tobaTracker = RideTracker(ride: toba, store: store)
        #expect(!tobaTracker.status(km: 5.2).alightSoon)
        #expect(tobaTracker.status(km: 5.3).alightSoon)
        #expect(abs(tobaTracker.minutesToAlightPrompt(km: 0)! - 5.27 / 6.2 * 18) < 1e-9)
        // a short one: the last 800 m at least (4 km: from 3.2, not 3.4)
        let short = try cruise(km: 4)
        #expect(!short.status(km: 3.19).alightSoon)
        #expect(short.status(km: 3.21).alightSoon)
        #expect(abs(short.minutesToAlightPrompt(km: 0)! - 3.2 / 4 * 40) < 1e-9)
        // and never more than its second half (600 m: from 300 m, not from boarding)
        let tiny = try cruise(km: 0.6)
        #expect(!tiny.status(km: 0).alightSoon)
        #expect(!tiny.status(km: 0.29).alightSoon)
        #expect(tiny.status(km: 0.31).alightSoon)
        #expect(abs(tiny.minutesToAlightPrompt(km: 0)! - 0.3 / 0.6 * 40) < 1e-9)
        // a ride with a station before yours is as it was (the Romancecar gets ready past Iriuda, 86.6 km)
        let romancecar = RideTracker(ride: store.trip.rides.first { $0.id == "r-4-romancecar-st-shinjuku-odakyu" }!, store: store)
        #expect(!romancecar.status(km: 86.2).alightSoon)
        #expect(romancecar.status(km: 86.4).alightSoon)
        #expect(abs(romancecar.minutesToAlightPrompt(km: 0)! - 86.6 / 88.7 * 105) < 1e-9)
    }

    @Test func aDirectRideWithNoResearchedStationGetsReadyAndRingsAlike() throws {
        // the Ashi cruise without its researched station before yours: of two stations, that is still
        // where you board, for "Chuẩn bị xuống" and for the alarm alike
        let patched = try TripStore.patched { trip in
            guard var rides = trip["rides"] as? [[String: Any]],
                  let i = rides.firstIndex(where: { $0["id"] as? String == Self.cruise })
            else { throw CocoaError(.coderReadCorrupt) }
            rides[i]["alight"] = nil
            trip["rides"] = rides
        }
        let ride = try #require(patched.trip.rides.first { $0.id == Self.cruise })
        #expect(ride.alight == nil)
        #expect(ride.stations.count == 2)
        let t = RideTracker(ride: ride, store: patched)
        #expect(!t.status(km: 0).alightSoon)
        #expect(t.status(km: t.tail).alightSoon)
        #expect(abs(t.minutesToAlightPrompt(km: 0)! - t.tail / ride.km * 40) < 1e-9)
    }

    // day 4: the 7:37 Romancecar, 105 minutes for 88.7 km
    var romancecar: Ride { store.trip.rides.first { $0.id == "r-4-romancecar-st-shinjuku-odakyu" }! }
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Minutes the Romancecar's timetable gives from km to its end.
    func timetable(_ km: Double) -> Double { (romancecar.km - km) / romancecar.km * 105 }

    @Test func slowingIntoAStationDoesNotPushTheAlarm() {
        let t0 = Date(timeIntervalSince1970: 0)
        var t = RideTracker(ride: romancecar, store: store)
        t.record(km: 28.0, at: t0); t.record(km: 30.9, at: t0 + 120)   // ~87 km/h over two minutes, slowing into Machida
        let timetable = RideTracker(ride: romancecar, store: store).minutesToAlightPrompt(km: 30.9)!
        #expect(t.minutesToAlightPrompt(km: 30.9, speedKmh: 16)! / timetable < 1.5)   // ~3.2 today
    }

    @Test func theRidesLastMinutesSetItsPace() {
        // two minutes at 60 km/h: the pace, over the 200 km/h of one fix
        var paced = RideTracker(ride: romancecar, store: store)
        paced.record(km: 10, at: t0)
        paced.record(km: 12, at: t0 + 120)
        #expect(abs(paced.minutesLeft(km: 12, speedKmh: 200)! - (romancecar.km - 12) / 60 * 60) < 1e-9)
        // a second short of two minutes is no pace yet: the fix's speed counts
        var early = RideTracker(ride: romancecar, store: store)
        early.record(km: 10, at: t0)
        early.record(km: 12, at: t0 + 119)
        #expect(abs(early.minutesLeft(km: 12, speedKmh: 70)! - (romancecar.km - 12) / 70 * 60) < 1e-9)
        #expect(early.minutesLeft(km: 12) == timetable(12))
        // two minutes at 12 km/h, standing or crawling: the timetable, not the fix's speed
        var crawling = RideTracker(ride: romancecar, store: store)
        crawling.record(km: 10, at: t0)
        crawling.record(km: 10.4, at: t0 + 120)
        #expect(crawling.minutesLeft(km: 10.4, speedKmh: 70) == timetable(10.4))
        // five minutes are kept, to the second: 6 km in 300 s, then the oldest goes
        var kept = RideTracker(ride: romancecar, store: store)
        kept.record(km: 0, at: t0)
        kept.record(km: 1, at: t0 + 60)
        kept.record(km: 6, at: t0 + 300)
        #expect(abs(kept.minutesLeft(km: 6)! - (romancecar.km - 6) / 72 * 60) < 1e-9)
        kept.record(km: 6.05, at: t0 + 301)
        let pace = 5.05 / 241 * 3600
        #expect(abs(kept.minutesLeft(km: 6.05)! - (romancecar.km - 6.05) / pace * 60) < 1e-9)
        // a fresh tracker is the timetable itself (Itinerary projects the day with one)
        let fresh = RideTracker(ride: romancecar, store: store)
        #expect(fresh.minutesLeft(km: 30.9) == timetable(30.9))
        #expect(fresh.minutesLeft(km: 30.9, speedKmh: 15) == timetable(30.9))
    }

    @Test func anETAStaysWithinItsTimetable() throws {
        let fresh = RideTracker(ride: romancecar, store: store)
        // one fix at 300 km/h, or at 16: 0.6 and 1.5 times the timetable at most
        #expect(abs(fresh.minutesLeft(km: 30.9, speedKmh: 300)! - 0.6 * timetable(30.9)) < 1e-9)
        #expect(abs(fresh.minutesLeft(km: 30.9, speedKmh: 16)! - 1.5 * timetable(30.9)) < 1e-9)
        #expect(abs(fresh.minutesLeft(km: 30.9, speedKmh: 80)! - (romancecar.km - 30.9) / 80 * 60) < 1e-9)
        // and a pace the same
        var fast = RideTracker(ride: romancecar, store: store)
        fast.record(km: 20, at: t0)
        fast.record(km: 30, at: t0 + 120)   // 300 km/h
        #expect(abs(fast.minutesLeft(km: 30)! - 0.6 * timetable(30)) < 1e-9)
        var slow = RideTracker(ride: romancecar, store: store)
        slow.record(km: 30, at: t0)
        slow.record(km: 30.6, at: t0 + 120)   // 18 km/h
        #expect(abs(slow.minutesLeft(km: 30.6)! - 1.5 * timetable(30.6)) < 1e-9)
        // a ranged run, "35–45" to Nara: 0.6 times its fast end, 1.5 times its slow end
        let nara = RideTracker(ride: try #require(store.trip.rides.first { $0.id == "r-10-kintetsu-st-kintetsu-nara" }), store: store)
        #expect(nara.minutesLeft(km: 0) == 35)
        #expect(abs(nara.minutesLeft(km: 0, speedKmh: 300)! - 0.6 * 35) < 1e-9)
        #expect(abs(nara.minutesLeft(km: 0, speedKmh: 16)! - 1.5 * 45) < 1e-9)
        // a ride with no stated time has nothing to hold it: the speed alone, as before
        let ropeway = try #require(store.trip.rides.first { $0.id == "r-4-hakoneRopeway-togendai" })
        #expect(ropeway.min == nil)
        let up = RideTracker(ride: ropeway, store: store)
        #expect(abs(up.minutesLeft(km: 0, speedKmh: 20)! - ropeway.km / 20 * 60) < 1e-9)
        #expect(up.minutesLeft(km: 0) == nil)
    }

    @Test func samplesThatMakeNoSenseAreLeftOut() {
        // the same fix again, and one taken before the last (from further on): not a sample
        var repeated = RideTracker(ride: romancecar, store: store)
        repeated.record(km: 10, at: t0)
        repeated.record(km: 10, at: t0)
        repeated.record(km: 20, at: t0 - 60)
        repeated.record(km: 12, at: t0 + 120)
        #expect(abs(repeated.minutesLeft(km: 12)! - (romancecar.km - 12) / 60 * 60) < 1e-9)
        // faster than any train (360 km/h): a GPS jump; 342 km/h still counts
        var jump = RideTracker(ride: romancecar, store: store)
        jump.record(km: 0, at: t0)
        jump.record(km: 12, at: t0 + 120)
        #expect(jump.minutesLeft(km: 12) == timetable(12))
        var shinkansen = RideTracker(ride: romancecar, store: store)
        shinkansen.record(km: 0, at: t0)
        shinkansen.record(km: 11.4, at: t0 + 120)
        #expect(abs(shinkansen.minutesLeft(km: 11.4)! - 0.6 * timetable(11.4)) < 1e-9)
        var edge = RideTracker(ride: romancecar, store: store)
        edge.record(km: 0, at: t0)
        edge.record(km: 14, at: t0 + 144)   // 350 km/h exactly: still a train
        #expect(abs(edge.minutesLeft(km: 14)! - 0.6 * timetable(14)) < 1e-9)
        var landed = RideTracker(ride: romancecar, store: store)
        landed.record(km: 10, at: t0)
        landed.record(km: 20, at: t0 + 60)   // 600 km/h
        landed.record(km: 12, at: t0 + 120)
        #expect(abs(landed.minutesLeft(km: 12)! - (romancecar.km - 12) / 60 * 60) < 1e-9)
        // a fix behind the last is noise or a standstill: it counts where the train was, at its own time
        var back = RideTracker(ride: romancecar, store: store)
        back.record(km: 0, at: t0)
        back.record(km: 10, at: t0 + 200)
        back.record(km: 9, at: t0 + 250)
        back.record(km: 13, at: t0 + 520)   // the first two are gone: 3 km since 250 s
        #expect(abs(back.minutesLeft(km: 13)! - (romancecar.km - 13) / (3.0 / 270 * 3600) * 60) < 1e-9)
    }

    @Test func afterARingOnlyTheTimetablesRingIsLeft() throws {
        let day4 = try #require(store.day("4"))
        let planned = try #require(WakePlanner(store: store).alarm(for: romancecar))
        let machida = try #require(TripTime.date(day4.date, minutes: 8 * 60 + 5))
        // through Machida at ~87 km/h, on time: the pace sits on the 0.6 floor, the alarm at 8:44
        var t = RideTracker(ride: romancecar, store: store)
        t.record(km: 28.0, at: machida - 120)
        t.record(km: 30.9, at: machida)
        let first = t.alarm(km: 30.9, at: machida, notAfter: planned, scheduled: nil, now: machida)
        let early = try #require(first)
        #expect(early < planned - 30 * 60)
        // the timetable's own alarm still to ring counts for nothing: the GPS moves it
        var fresh = RideTracker(ride: romancecar, store: store)
        fresh.record(km: 28.0, at: machida - 120)
        fresh.record(km: 30.9, at: machida)
        #expect(fresh.alarm(km: 30.9, at: machida, notAfter: planned, scheduled: planned, now: machida) == early)
        // 8:44 rings (due at that very second counts): from then on the timetable's 9:18 only, however
        // early the stop before yours reads
        #expect(t.alarm(km: 50, speedKmh: 300, at: early, notAfter: planned, scheduled: early, now: early) == planned)
        let after = early + 60
        #expect(t.alarm(km: 51, speedKmh: 300, at: after, notAfter: planned, scheduled: early, now: after) == planned)
        // set at 9:18 again, then forgotten by the alarms: still 9:18, never earlier again
        #expect(t.alarm(km: 52, speedKmh: 300, at: after + 60, notAfter: planned, scheduled: planned, now: after + 60) == planned)
        #expect(t.alarm(km: 53, speedKmh: 300, at: after + 120, notAfter: planned, scheduled: nil, now: after + 120) == planned)
        // and nothing within the half minute a new alarm needs, nor after
        #expect(t.alarm(km: 80, at: planned - 30, notAfter: planned, scheduled: planned, now: planned - 30) == nil)
        #expect(t.alarm(km: 80, at: planned - 31, notAfter: planned, scheduled: nil, now: planned - 31) == planned)
        // a ride with no timetable alarm (a boat, switched on by hand) rings once
        var boat = RideTracker(ride: try #require(store.trip.rides.first { $0.id == Self.cruise }), store: store)
        let boarding = t0
        let boatAlarm = boat.alarm(km: 0, at: boarding, notAfter: nil, scheduled: nil, now: boarding)
        let ring = try #require(boatAlarm)
        #expect(boat.alarm(km: 1, at: ring + 10, notAfter: nil, scheduled: ring, now: ring + 10) == nil)
        #expect(boat.alarm(km: 0.5, at: ring + 20, notAfter: nil, scheduled: nil, now: ring + 20) == nil)
    }

    @Test func theGPSAlarmIsNeverLaterThanTheTimetables() throws {
        let day4 = try #require(store.day("4"))
        let timetableAlarm = try #require(WakePlanner(store: store).alarm(for: romancecar))
        #expect(timetableAlarm == TripTime.date(day4.date, minutes: 7 * 60 + 37 + 105 - 4))
        // at Machida at 8:05, a fix at 16 km/h: the stop before yours an hour and a half away, at 9:43
        let machida = try #require(TripTime.date(day4.date, minutes: 8 * 60 + 5))
        var t = RideTracker(ride: romancecar, store: store)
        let prompt = try #require(t.minutesToAlightPrompt(km: 30.9, speedKmh: 16))
        let gps = machida + prompt * 60
        #expect(gps > timetableAlarm)
        #expect(t.alarm(km: 30.9, speedKmh: 16, at: machida, notAfter: nil, scheduled: nil, now: machida) == gps)
        #expect(t.alarm(km: 30.9, speedKmh: 16, at: machida, notAfter: timetableAlarm, scheduled: nil, now: machida) == timetableAlarm)
        // a train ahead of the timetable rings ahead of it
        let early = machida + t.minutesToAlightPrompt(km: 30.9, speedKmh: 200)! * 60
        #expect(early < timetableAlarm)
        #expect(t.alarm(km: 30.9, speedKmh: 200, at: machida, notAfter: timetableAlarm, scheduled: nil, now: machida) == early)
        // anchored at the fix, not at the moment it is handled
        #expect(t.alarm(km: 30.9, speedKmh: 200, at: machida, notAfter: timetableAlarm, scheduled: nil, now: machida + 50) == early)
        // late, past the timetable's alarm or within the half minute a new alarm needs: nothing more is asked
        let late = timetableAlarm + 600
        #expect(t.alarm(km: 80, at: late, notAfter: timetableAlarm, scheduled: nil, now: late) == nil)
        #expect(t.alarm(km: 30.9, speedKmh: 16, at: machida, notAfter: timetableAlarm, scheduled: nil, now: timetableAlarm - 30) == nil)
        #expect(t.alarm(km: 30.9, speedKmh: 16, at: machida, notAfter: timetableAlarm, scheduled: nil, now: timetableAlarm - 31) == timetableAlarm)
        // without the timetable's alarm, the same half minute
        #expect(t.alarm(km: 30.9, speedKmh: 16, at: machida, notAfter: nil, scheduled: nil, now: gps - 30) == nil)
        #expect(t.alarm(km: 30.9, speedKmh: 16, at: machida, notAfter: nil, scheduled: nil, now: gps - 31) == gps)
    }

    // MARK: the stop too close for an alarm

    @Test func aStopTooCloseForAnAlarmGetsANotice() throws {
        let planned = try #require(WakePlanner(store: store).alarm(for: romancecar))
        let fresh = RideTracker(ride: romancecar, store: store)
        let at = planned - 600   // 9:08
        // 100 m before Iriuda (the stop before yours, 86.6 km): seconds away; or passed already
        var t = fresh
        #expect(t.wake(km: 86.5, at: at, notAfter: planned, scheduled: nil, now: at) == .notice)
        t = fresh
        #expect(t.wake(km: 87, at: at, notAfter: planned, scheduled: nil, now: at) == .notice)
        // the timetable's 9:18 still set, ten minutes ahead: a notice now, and it rings later
        t = fresh
        #expect(t.wake(km: 86.5, at: at, notAfter: planned, scheduled: planned, now: at) == .notice)
        // an alarm set to ring within two minutes rings for it: nothing more
        t = fresh
        #expect(t.wake(km: 86.5, at: at, notAfter: planned, scheduled: at + 100, now: at) == .nothing)
        t = fresh
        #expect(t.wake(km: 86.5, at: at, notAfter: planned, scheduled: at + 121, now: at) == .notice)
        // one that has rung: no notice, only the timetable's ring still ahead (R-136), also once the
        // alarms have forgotten the one that rang; nothing at all once that has had its time too
        var rung = fresh
        #expect(rung.wake(km: 86.5, at: at, notAfter: planned, scheduled: at - 5, now: at) == .alarm(planned))
        #expect(rung.wake(km: 86.6, at: at + 20, notAfter: planned, scheduled: nil, now: at + 20) == .alarm(planned))
        #expect(rung.wake(km: 87, at: planned + 5, notAfter: planned, scheduled: nil, now: planned + 5) == .nothing)
        var noTimetable = fresh
        #expect(noTimetable.wake(km: 86.5, at: at, notAfter: nil, scheduled: at - 5, now: at) == .nothing)
        // arrived: nothing
        t = fresh
        #expect(t.wake(km: 88.6, at: at, notAfter: planned, scheduled: nil, now: at) == .nothing)
        // less than a minute from now, counted from the fix: a notice, not an alarm 30–60 s away
        let machida = planned - 73 * 60
        let prompt = try #require(fresh.minutesToAlightPrompt(km: 30.9, speedKmh: 200))
        let gps = machida + prompt * 60
        #expect(gps < planned)
        t = fresh
        #expect(t.wake(km: 30.9, speedKmh: 200, at: machida, notAfter: planned, scheduled: nil, now: gps - 45) == .notice)
        t = fresh
        #expect(t.wake(km: 30.9, speedKmh: 200, at: machida, notAfter: planned, scheduled: nil, now: gps - 59) == .notice)
        t = fresh
        #expect(t.wake(km: 30.9, speedKmh: 200, at: machida, notAfter: planned, scheduled: nil, now: gps - 60) == .alarm(gps))
        // further: what `alarm` says, unchanged
        var a = fresh, b = fresh
        let alarm = b.alarm(km: 30.9, speedKmh: 200, at: machida, notAfter: planned, scheduled: nil, now: machida)
        #expect(alarm == gps)
        #expect(a.wake(km: 30.9, speedKmh: 200, at: machida, notAfter: planned, scheduled: nil, now: machida) == .alarm(gps))
        a = fresh
        b = fresh
        #expect(a.wake(km: 30.9, speedKmh: 16, at: machida, notAfter: planned, scheduled: nil, now: machida)
            == b.alarm(km: 30.9, speedKmh: 16, at: machida, notAfter: planned, scheduled: nil, now: machida).map { .alarm($0) } ?? .nothing)
    }

    // MARK: the ride's end

    func jst(_ day: Day, _ h: Int, _ m: Double) throws -> Date {
        try #require(TripTime.date(day.date, minutes: Double(h * 60) + m))
    }

    @Test func aRideIsOverOnceItsTimeIsLongPast() throws {
        let day4 = try #require(store.day("4"))
        let t = RideTracker(ride: romancecar, store: store)
        let boarding = try jst(day4, 7, 30)
        // 9:22 planned, plus half its 105 minutes (more than 30): 10:14:30 on the trip's clock
        let end = try jst(day4, 10, 14.5)
        #expect(t.deadline(followedAt: boarding) == end)
        #expect(t.ending(arrivedAt: nil, followedAt: boarding, tripNow: end - 1, now: t0) == nil)
        #expect(t.ending(arrivedAt: nil, followedAt: boarding, tripNow: end, now: t0) == .overdue)
        // the next train for a missed one, followed at 9:30: its own 105 minutes from then
        let next = try jst(day4, 9, 30)
        #expect(t.deadline(followedAt: next) == next + (105 + 52.5) * 60)
        // followed on another day: not over at once
        let day6 = try #require(store.day("6"))
        let elsewhere = try jst(day6, 10, 0)
        #expect(t.ending(arrivedAt: nil, followedAt: elsewhere, tripNow: elsewhere, now: t0) == nil)
        #expect(t.deadline(followedAt: elsewhere) == elsewhere + (105 + 52.5) * 60)
        // a ranged run at its slow end: 16:00 "35–45" to Nara, 16:45 + 30 (not 16:35 + 30)
        let day10 = try #require(store.day("10"))
        let nara = RideTracker(ride: try #require(store.trip.rides.first { $0.id == "r-10-kintetsu-st-kintetsu-nara" }), store: store)
        #expect(nara.deadline(followedAt: try jst(day10, 15, 55)) == (try jst(day10, 17, 15)))
        // no planned time: from when it is followed, the Yamanote's 7 minutes + 30
        let yamanote = try #require(store.trip.rides.first { $0.id == "r-2-yamanote-st-akihabara" })
        #expect(yamanote.at == nil)
        let day2 = try #require(store.day("2"))
        let followed = try jst(day2, 13, 0)
        #expect(RideTracker(ride: yamanote, store: store).deadline(followedAt: followed) == followed + 37 * 60)
        // no stated time either (the ropeway): 30 minutes
        let ropeway = try #require(store.trip.rides.first { $0.id == "r-4-hakoneRopeway-togendai" })
        #expect(RideTracker(ride: ropeway, store: store).deadline(followedAt: boarding) == boarding + 30 * 60)
    }

    @Test func aRideArrivedClosesNinetySecondsLater() throws {
        let day4 = try #require(store.day("4"))
        let t = RideTracker(ride: romancecar, store: store)
        let boarding = try jst(day4, 7, 30)
        #expect(t.ending(arrivedAt: t0, followedAt: boarding, tripNow: boarding, now: t0 + 89) == nil)
        #expect(t.ending(arrivedAt: t0, followedAt: boarding, tripNow: boarding, now: t0 + 90) == .arrived)
    }

    /// R-138: ten minutes spanned by the fixes themselves, each farther than 3 km from the track.
    @Test func offTheLineCountsOnTheFixesThemselves() throws {
        let day4 = try #require(store.day("4"))
        let followed = try jst(day4, 7, 30)
        func over(_ t: RideTracker) -> RideTracker.Ending? {
            // the clock far on: only the fixes may say it is over (the trip's clock still at boarding)
            t.ending(arrivedAt: nil, followedAt: followed, tripNow: followed, now: t0 + 86_400)
        }
        let fresh = RideTracker(ride: romancecar, store: store)
        var t = fresh
        t.note(offTrackKm: 0.2, at: t0)          // on the train
        t.note(offTrackKm: 3.5, at: t0 + 60)     // got off, away from the line
        // one fix, then silence (a tunnel, a phone in a bag): nothing, however late it is
        #expect(over(t) == nil)
        t.note(offTrackKm: 4, at: t0 + 659)
        #expect(over(t) == nil)
        t.note(offTrackKm: 4, at: t0 + 660)
        #expect(over(t) == .offLine)
        // off, on (3 km exactly is not off), off: the count starts again
        var jitter = fresh
        jitter.note(offTrackKm: 0.2, at: t0)
        jitter.note(offTrackKm: 3.5, at: t0 + 60)
        jitter.note(offTrackKm: 3.0, at: t0 + 300)
        jitter.note(offTrackKm: 3.5, at: t0 + 400)
        jitter.note(offTrackKm: 3.5, at: t0 + 999)
        #expect(over(jitter) == nil)
        jitter.note(offTrackKm: 3.5, at: t0 + 1000)
        #expect(over(jitter) == .offLine)
        // never within 1.5 km of its line (followed from the hotel): never off it
        var hotel = fresh
        hotel.note(offTrackKm: 5, at: t0)
        hotel.note(offTrackKm: 2, at: t0 + 60)
        hotel.note(offTrackKm: 5, at: t0 + 120)
        hotel.note(offTrackKm: 5, at: t0 + 1200)
        #expect(over(hotel) == nil)
        // a fix not after the latest (a repeat, one delivered late) adds nothing
        var late = fresh
        late.note(offTrackKm: 1.4, at: t0)
        late.note(offTrackKm: 4, at: t0 + 60)
        late.note(offTrackKm: 4, at: t0 - 600)
        late.note(offTrackKm: 4, at: t0 + 659)
        #expect(over(late) == nil)
        late.note(offTrackKm: 0.5, at: t0 + 30)   // older: does not reset either
        late.note(offTrackKm: 4, at: t0 + 660)
        #expect(over(late) == .offLine)
    }

    @Test func theLiveActivityCountsOnThePhonesClock() {
        let fix = Date(timeIntervalSinceReferenceDate: 800_000_017)
        // rehearsing a day ahead (37 s off a whole day)
        let offset = -86_400 + 37.0
        let a = RideTracker.arrival(minutesLeft: 12.5, fixedAt: fix, clockOffset: offset)
        #expect(a.live == fix + 750)
        let trip = fix + offset + 750
        #expect(a.shown == Date(timeIntervalSinceReferenceDate: (trip.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60))
        #expect(a.shown < trip && trip.timeIntervalSince(a.shown) < 60)
        let real = RideTracker.arrival(minutesLeft: 12.5, fixedAt: fix, clockOffset: 0)
        #expect(real.live == fix + 750)
        #expect(real.shown == Date(timeIntervalSinceReferenceDate: ((fix + 750).timeIntervalSinceReferenceDate / 60).rounded(.down) * 60))
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

    /// A circle entered offers its item only on its own day: tomorrow's first meal, watched from the
    /// evening before, is not "Đã tới" tonight, and is once the night has passed (registered as
    /// tomorrow's, entered on the day).
    @Test func aFenceOffersItsItemOnlyOnItsDay() throws {
        let day4 = try #require(store.day("4")), day5 = try #require(store.day("5"))
        let fences = FencePlanner(store: store).fences(today: day4, cursor: 0, tomorrow: day5)
        let tomorrows = fences.filter { $0.day == day5.key }
        try #require(!tomorrows.isEmpty)
        for f in tomorrows {
            #expect(f.kind == .food)
            #expect(f.plannedItem(today: day4) == nil, "\(f.id)")
            let id = try #require(f.itemID)
            #expect(f.plannedItem(today: day5) == day5.index(of: id), "\(f.id)")
            #expect(f.plannedItem(today: day5) != nil, "\(f.id)")
        }
        // today's: the food stops and the stations of its departures, by their item
        let todays = fences.filter { $0.day == day4.key }
        let food = try #require(todays.first { $0.kind == .food })
        let station = try #require(todays.first { $0.kind == .station })
        for f in [food, station] {
            let i = try #require(f.plannedItem(today: day4), "\(f.id)")
            #expect(day4.items[i].id == f.itemID)
            #expect(f.plannedItem(today: day5) == nil, "\(f.id)")
            #expect(f.plannedItem(today: nil) == nil, "\(f.id)")
        }
        // a station kept from yesterday, entered today, offers yesterday's train nothing
        let yesterday = try #require(store.day("3"))
        #expect(station.plannedItem(today: yesterday) == nil)
        // no item: a snack, the hotel
        for f in todays where f.kind == .snack || f.kind == .stay {
            #expect(f.plannedItem(today: day4) == nil, "\(f.id)")
        }
        // an item the day no longer has (an update removed it): nothing
        let gone = Fence(placeID: food.placeID, kind: .food, center: food.center, radius: food.radius, day: day4.key, itemID: "s:nowhere")
        #expect(gone.plannedItem(today: day4) == nil)
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

    @Test func theTimetableAlarmOfARide() throws {
        let wake = WakePlanner(store: store)
        let days = store.days()
        let wakes = wake.wakes(days: days, now: try #require(TripTime.midnight(days[0].date)), horizon: 30 * 86400) { _, _ in false }
        #expect(!wakes.isEmpty)
        for w in wakes {
            let ride = try #require(store.trip.rides.first { $0.id == w.rideID })
            #expect(wake.alarm(for: ride) == w.at, "\(w.rideID)")
        }
        // one due exactly now is no longer wanted
        let romancecar = try #require(store.trip.rides.first { $0.id == "r-4-romancecar-st-shinjuku-odakyu" })
        let planned = try #require(wake.alarm(for: romancecar))
        #expect(!wake.wakes(days: days, now: planned) { _, _ in false }.contains { $0.rideID == romancecar.id })
        #expect(wake.wakes(days: days, now: planned - 1) { _, _ in false }.contains { $0.rideID == romancecar.id })
        // none for a boat, a bus, or a ride with no time
        for id in ["r-4-ashiCruise-moto-hakone-port", "r-4-tozanBus-st-hakone-yumoto", "r-5-shinkansen-st-shizuoka"] {
            let ride = try #require(store.trip.rides.first { $0.id == id })
            #expect(wake.alarm(for: ride) == nil, "\(id)")
        }
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
