import Foundation
import Testing
@testable import TripKit

@Suite struct LedgerSyncSessionTests {
    let t0 = Date(timeIntervalSince1970: 0)
    let a = LedgerDigest("a"), b = LedgerDigest("b")

    @Test func notSyncedUntilAcked() {
        var s = LedgerSyncSession()
        s.didSend(a, at: t0)
        #expect(!s.isSynced(current: a))
        s.peerHas(a)
        #expect(s.isSynced(current: a))
    }

    @Test func unsentStateIsAlwaysDue() { #expect(LedgerSyncSession().needsSend(current: a, now: t0)) }

    @Test func sentButUnackedIsResentAfter15Seconds() {
        var s = LedgerSyncSession(); s.didSend(a, at: t0)
        #expect(!s.needsSend(current: a, now: t0 + 14))
        #expect(s.needsSend(current: a, now: t0 + 15))
    }

    @Test func ackOfAnOlderStateDoesNotCoverTheCurrentOne() {
        var s = LedgerSyncSession(); s.didSend(a, at: t0); s.peerHas(a)
        #expect(!s.isSynced(current: b)); #expect(s.needsSend(current: b, now: t0))
    }

    @Test func nackKeepsItDueAndSaysWhy() {
        var s = LedgerSyncSession(); s.didSend(a, at: t0)
        s.peerFailed(a, reason: "disk full")
        // due at once, not 15 seconds after the send: the other phone said it did not write it
        #expect(s.needsSend(current: a, now: t0 + 1))
        #expect(s.lastFailure == "disk full")
        #expect(s.standing(current: a) == .failed("disk full"))
    }

    @Test func disconnectForgetsUnackedSend() {
        var s = LedgerSyncSession(); s.didSend(a, at: t0)
        s.disconnected()
        #expect(s.needsSend(current: a, now: t0 + 1))
    }

    @Test func pausedSessionNeitherSendsNorAcks() {
        var s = LedgerSyncSession(); s.paused = true
        #expect(!s.needsSend(current: a, now: t0))
        let written = s.received("x", failure: nil)
        #expect(written == nil)
        let refused = s.received("x", failure: "disk full")
        #expect(refused == nil)
        #expect(!s.isSynced(current: LedgerDigest("x")))
    }

    // MARK: What the peer holds

    /// Every ledger the peer is known to hold counts, not only the last one heard of: with one slot, a phone that
    /// heard "I hold yours" and then the peer's own ledger forgets the first, and the two resend for ever.
    @Test func everyLedgerThePeerHoldsCounts() {
        var s = LedgerSyncSession()
        s.peerHas(a)
        s.peerHas(b)
        #expect(s.isSynced(current: a) && s.isSynced(current: b))
        #expect(!s.needsSend(current: a, now: t0) && !s.needsSend(current: b, now: t0))
    }

    @Test func aNackForAnOlderLedgerLeavesTheNewerSendAlone() {
        var s = LedgerSyncSession()
        s.didSend(a, at: t0)
        s.didSend(b, at: t0 + 1)
        s.peerFailed(a, reason: "disk full")
        #expect(!s.needsSend(current: b, now: t0 + 2), "b is on its way")
        #expect(s.lastFailure == "disk full")
    }

    /// A nack takes back an ack of the same ledger: a row the other phone refused as dated too far ahead of its
    /// clock may be one it takes now, and writing it failed. Without this, the sender would think it held and
    /// never send it again, and the other phone would say it could not write for ever.
    @Test func aNackTakesBackAnAckOfTheSameLedger() {
        var s = LedgerSyncSession()
        s.didSend(a, at: t0)
        s.peerHas(a)
        s.peerFailed(a, reason: "disk full")
        #expect(!s.isSynced(current: a))
        #expect(s.needsSend(current: a, now: t0 + 1))
        #expect(s.standing(current: a) == .failed("disk full"))
    }

    @Test func aFailureOnAnOlderLedgerIsPastOnceTheCurrentOneIsHeld() {
        var s = LedgerSyncSession()
        s.peerHas(b)
        s.peerFailed(a, reason: "disk full")
        #expect(s.standing(current: b) == .synced)
        #expect(s.standing(current: a) == .failed("disk full"))
    }

    @Test func anAckClearsTheFailure() {
        var s = LedgerSyncSession()
        s.didSend(a, at: t0)
        s.peerFailed(a, reason: "disk full")
        s.didSend(a, at: t0 + 15)
        s.peerHas(a)
        #expect(s.lastFailure == nil)
        #expect(s.standing(current: a) == .synced)
    }

    /// Their own ledger, which they hold, or a late ack of an older one of this phone's, says nothing of the one
    /// they could not write: "X chưa lưu được" stays, not a flicker to "sending" until the next heartbeat.
    @Test func aLedgerHeldThatIsNeitherTheFailedNorTheCurrentOneLeavesTheFailure() {
        var s = LedgerSyncSession()
        s.didSend(b, at: t0)
        s.didSend(a, at: t0 + 1)
        s.peerFailed(a, reason: "disk full")
        _ = s.received("theirs", failure: nil, current: a)
        #expect(s.lastFailure == "disk full")
        #expect(s.standing(current: a) == .failed("disk full"))
        s.peerHas(b, current: a)
        #expect(s.standing(current: a) == .failed("disk full"))
    }

    /// Once they hold this phone's ledger as it is now, the failure of an older one is past, also for the ledgers
    /// after it.
    @Test func theCurrentLedgerHeldClearsTheFailure() {
        var s = LedgerSyncSession()
        s.didSend(a, at: t0)
        s.peerFailed(a, reason: "disk full")
        s.didSend(b, at: t0 + 15)
        s.peerHas(b, current: b)
        #expect(s.lastFailure == nil)
        #expect(s.standing(current: LedgerDigest("c")) == .sending)
        // their own ledger, the same as this phone's now
        var t = LedgerSyncSession()
        t.peerFailed(a, reason: "disk full")
        _ = t.received("c", failure: nil, current: LedgerDigest("c"))
        #expect(t.lastFailure == nil)
    }

    @Test func theOtherPhonesReasonIsCut() {
        var s = LedgerSyncSession()
        s.peerFailed(a, reason: String(repeating: "é", count: 500))
        #expect(s.lastFailure?.count == LedgerSyncSession.longestReason)
        #expect(LedgerSyncSession.longestReason == 200)
    }

    /// A clock set back (by hand, or by the network after drifting) does not hold a resend until it catches up.
    @Test func aClockSetBackDoesNotHoldTheResend() {
        var s = LedgerSyncSession()
        s.didSend(a, at: t0 + 3600)
        #expect(s.needsSend(current: a, now: t0))
    }

    @Test func disconnectedForgetsWhatThePeerHeld() {
        var s = LedgerSyncSession()
        s.peerHas(a)
        s.peerFailed(b, reason: "disk full")
        _ = s.received("c", failure: "disk full")
        s.disconnected()
        #expect(!s.isSynced(current: a))
        #expect(s.lastFailure == nil)
        #expect(s.standing(current: a) == .sending)
    }

    // MARK: A ledger received

    @Test func aLedgerWrittenIsAckedAndHeld() {
        var s = LedgerSyncSession()
        let answer = s.received("x", failure: nil)
        #expect(answer == .ack(digest: "x"))
        #expect(s.isSynced(current: LedgerDigest("x")), "a phone sends only what it has stored")
        #expect(s.standing(current: LedgerDigest("x")) == .synced)
    }

    @Test func aLedgerNotWrittenIsNackedAndSaysWhyHere() {
        var s = LedgerSyncSession()
        let refused = s.received("x", failure: "disk full")
        #expect(refused == .nack(digest: "x", reason: "disk full"))
        #expect(!s.isSynced(current: LedgerDigest("x")))
        #expect(s.standing(current: LedgerDigest("x")) == .unsaved("disk full"))
        // the next one written clears it
        let written = s.received("y", failure: nil)
        #expect(written == .ack(digest: "y"))
        #expect(s.standing(current: LedgerDigest("y")) == .synced)
    }

    @Test func aLedgerWithoutADigestIsNotAcked() {
        var s = LedgerSyncSession()
        let written = s.received(nil, failure: nil)
        #expect(written == nil)
        let refused = s.received(nil, failure: "disk full")
        #expect(refused == nil)
        #expect(s.standing(current: a) == .unsaved("disk full"))
    }

    /// Whether this phone's ledger goes back is `LedgerMerge.reply`'s call, and it is not sent twice.
    @Test func answersOnlyWithWhatTheOtherWouldGainAndNotTwice() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func row(_ n: Int) -> LedgerRecord {
            LedgerRecord(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, yen: 900,
                         category: "food", method: "cash", at: now, origin: "a")
        }
        let theirs = LedgerState(records: [row(1)])
        let mine = LedgerState(records: [row(1), row(2)])
        var s = LedgerSyncSession()
        #expect(!s.answers(theirs, with: theirs, digest: a, now: now), "nothing to gain")
        #expect(s.answers(theirs, with: mine, digest: b, now: now))
        s.didSend(b, at: now)
        #expect(!s.answers(theirs, with: mine, digest: b, now: now + 1), "already on its way")
        #expect(s.answers(theirs, with: mine, digest: b, now: now + 15))
        s.peerHas(b)
        #expect(!s.answers(theirs, with: mine, digest: b, now: now + 30), "it holds it")
    }

    // MARK: A build before acknowledgements

    @Test func theVersionSaysWhetherThePeerAcks() {
        #expect(LedgerSyncSession.version == 2)
        #expect(LedgerSyncSession().acks)
        #expect(LedgerSyncSession(peerVersion: 2).acks)
        #expect(LedgerSyncSession(peerVersion: 3).acks)
        #expect(!LedgerSyncSession(peerVersion: nil).acks)
        #expect(!LedgerSyncSession(peerVersion: 1).acks)
    }

    /// A phone that never acks gets each ledger once (not every 15 seconds while they are near), is never
    /// acked, and is never "synced": what it holds cannot be known.
    @Test func anOlderBuildGetsEachLedgerOnceAndIsNeverSynced() {
        var s = LedgerSyncSession(peerVersion: nil)
        #expect(s.standing(current: a) == .sending)
        s.didSend(a, at: t0)
        #expect(!s.needsSend(current: a, now: t0 + 3600))
        #expect(s.needsSend(current: b, now: t0 + 1))
        #expect(s.standing(current: a) == .unconfirmed)
        #expect(s.standing(current: b) == .sending)
        let written = s.received("x", failure: nil)
        #expect(written == nil)
        #expect(!s.isSynced(current: LedgerDigest("x")))
        let refused = s.received(nil, failure: "disk full")
        #expect(refused == nil)
        #expect(s.standing(current: a) == .unsaved("disk full"))
    }

    // MARK: Standing

    @Test func notSyncedWhileTheLedgerIsUnknown() {
        var s = LedgerSyncSession()
        s.peerHas(a)
        #expect(s.standing(current: nil) == .sending)
        #expect(s.standing(current: a) == .synced)
    }

    @Test func thisPhonesFailureComesBeforeTheirs() {
        var s = LedgerSyncSession()
        s.peerFailed(a, reason: "theirs")
        _ = s.received("x", failure: "mine")
        #expect(s.standing(current: a) == .unsaved("mine"))
    }

    /// With several phones near, the line speaks of the worst, the first of equals; "synced" only when all are.
    @Test func severalPhonesShowTheWorst() {
        typealias S = LedgerSyncSession.Standing
        let order: [S] = [.unsaved("u"), .failed("f"), .unconfirmed, .sending, .synced]
        for (i, worse) in order.enumerated() {
            for better in order[i...] {
                for list in [[("lan", better), ("minh", worse)], [("minh", worse), ("lan", better)]] {
                    let w = S.worst(list, by: \.1)
                    #expect(w?.standing == worse)
                    if worse == better {
                        #expect(w?.item.0 == list[0].0, "the first of equals")
                    } else {
                        #expect(w?.item.0 == "minh")
                    }
                }
            }
        }
        #expect(S.worst([("lan", S.synced), ("minh", .synced)], by: \.1)?.standing == .synced)
        #expect(S.worst([(String, S)](), by: \.1) == nil)
    }
}

// MARK: - Two phones

/// Two phones syncing by `LedgerSyncSession`'s decisions. The test plays the radio and the disks only: it carries
/// `SyncPayload`s each way in order, writes merges, works out digests, and asks the session at the points
/// `LedgerSync` does: a push (`needsSend`), a ledger in (`received`, then `answers`), an ack, a nack, a stamp
/// (`standing == .synced`).
struct TwoPhones {
    struct Phone {
        var ledger: LedgerState
        var now: Date
        var session = LedgerSyncSession()
        /// put in front of every digest: the two phones work out different digests for one ledger
        var salt = ""
        /// how many of the other phone's ledgers fail to be written before one is
        var failing = 0
        /// a build before acknowledgements (b444f14): no digest, no ack, sends a ledger only when it changed,
        /// and counts what it merged as sent
        var old = false
        var oldSent: LedgerState?
        /// times "Đã đồng bộ" was stamped
        var stamps = 0
        var nacks = 0

        var current: LedgerDigest {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return LedgerDigest(salt + String(decoding: (try? encoder.encode(ledger)) ?? Data(), as: UTF8.self))
        }
    }

    var phones: [Phone]
    /// what is on its way to each phone, in order
    var inbox: [[SyncPayload]] = [[], []]
    /// messages handed to the radio
    var sent = 0
    /// how many of the next sends the radio refuses
    var refusals = 0
    /// "Đã đồng bộ" stamped while the other phone lacks a row of this one's that it would take (`holds`)
    var falseStamps: [String] = []
    /// ledgers sent back as an answer though the other phone would gain nothing from them (`LedgerMerge.reply`)
    var needlessAnswers = 0

    init(_ a: Phone, _ b: Phone) {
        phones = [a, b]
        // each knows from the other's greeting whether it acks
        phones[0].session = LedgerSyncSession(peerVersion: b.old ? nil : LedgerSyncSession.version)
        phones[1].session = LedgerSyncSession(peerVersion: a.old ? nil : LedgerSyncSession.version)
    }

    var busy: Bool { !inbox[0].isEmpty || !inbox[1].isEmpty }

    func standing(_ i: Int) -> LedgerSyncSession.Standing { phones[i].session.standing(current: phones[i].current) }

    /// Hands a message to the radio; false when it refused it.
    mutating func radio(_ from: Int, _ m: SyncPayload) -> Bool {
        sent += 1
        if refusals > 0 { refusals -= 1; return false }
        inbox[1 - from].append(m)
        return true
    }

    /// The connection dropped and came back: what was on its way is lost, each side starts a new session, and
    /// both send at once.
    mutating func reconnect() {
        inbox = [[], []]
        phones[0].session = LedgerSyncSession(peerVersion: phones[1].old ? nil : LedgerSyncSession.version)
        phones[1].session = LedgerSyncSession(peerVersion: phones[0].old ? nil : LedgerSyncSession.version)
        phones[0].oldSent = nil
        phones[1].oldSent = nil
        push(0, force: true)
        push(1, force: true)
    }

    /// The connection opened, or the phones touched (`force`), or the heartbeat.
    mutating func push(_ i: Int, force: Bool = false) {
        let p = phones[i]
        if p.old {
            guard force || p.oldSent != p.ledger else { return }
            // that build took a send the radio refused for sent
            _ = radio(i, .state(p.ledger, digest: nil))
            phones[i].oldSent = p.ledger
            return
        }
        let d = p.current
        guard force || p.session.needsSend(current: d, now: p.now) else { return }
        if radio(i, .state(p.ledger, digest: d.value)) { phones[i].session.didSend(d, at: p.now) }
    }

    mutating func deliver(_ i: Int) {
        switch inbox[i].removeFirst() {
        case .state(let remote, let digest):
            let now = phones[i].now
            let before = phones[i].ledger
            let merged = LedgerMerge.merge(phones[i].ledger, LedgerMerge.screened(remote, now: now).state)
            var failure: String?
            // as `Ledger.apply`: a merge that changes nothing writes nothing, so it cannot fail
            if merged != phones[i].ledger, phones[i].failing > 0 {
                phones[i].failing -= 1
                failure = "disk full"
            } else {
                phones[i].ledger = merged
            }
            if phones[i].old {
                guard failure == nil else { return }
                if let back = LedgerMerge.reply(local: phones[i].ledger, remote: remote, now: now) {
                    _ = radio(i, .state(back, digest: nil))
                }
                phones[i].oldSent = phones[i].ledger
                return
            }
            // as `LedgerSync`: this phone's digest is known only while the merge changed nothing
            let current = phones[i].ledger == before ? phones[i].current : nil
            if let receipt = phones[i].session.received(digest, failure: failure, current: current) { _ = radio(i, receipt) }
            guard failure == nil else { return }
            let mine = phones[i].ledger, d = phones[i].current
            if phones[i].session.answers(remote, with: mine, digest: d, now: now) {
                if LedgerMerge.reply(local: mine, remote: remote, now: now) == nil { needlessAnswers += 1 }
                if radio(i, .state(mine, digest: d.value)) { phones[i].session.didSend(d, at: now) }
            }
            stamp(i)
        case .ack(let d):
            guard !phones[i].old else { return }
            phones[i].session.peerHas(LedgerDigest(d), current: phones[i].current)
            stamp(i)
        case .nack(let d, let reason):
            guard !phones[i].old else { return }
            phones[i].nacks += 1
            phones[i].session.peerFailed(LedgerDigest(d), reason: reason)
        case .intro, .touched:
            break
        }
    }

    /// Delivers everything on its way, the heartbeat still.
    mutating func drain() {
        while busy { deliver(inbox[1].isEmpty ? 0 : 1) }
    }

    /// "Đã đồng bộ", checked against the truth: the other phone holds every row of this one's it would take.
    mutating func stamp(_ i: Int) {
        guard standing(i) == .synced else { return }
        phones[i].stamps += 1
        if !holds(1 - i, i) { falseStamps.append("phone \(i) stamped while phone \(1 - i) lacks a row it would take") }
    }

    /// Phone `j` gains nothing from phone `i`'s ledger that it would take, by its clock set back by `setBack`:
    /// the clocks run on while the phones talk, and a row dated ahead that `j` refused when it screened may be
    /// one it takes by now.
    func holds(_ j: Int, _ i: Int, setBack: TimeInterval = 20_000) -> Bool {
        let other = phones[j]
        return LedgerMerge.merge(other.ledger, LedgerMerge.screened(phones[i].ledger, now: other.now - setBack).state) == other.ledger
    }

    /// The heartbeat, 15 seconds on.
    mutating func tick() {
        for i in 0..<2 { phones[i].now += 15 }
        push(0)
        push(1)
    }

    mutating func edit(_ i: Int, _ r: LedgerRecord) {
        phones[i].ledger = LedgerMerge.merge(phones[i].ledger, LedgerState(records: [r]))
        push(i)
    }

    /// Both connect; then messages are delivered in order, the heartbeat beating whenever nothing is on its
    /// way. True once three heartbeats in a row sent nothing, within `steps`.
    mutating func connectAndSettle(steps: Int = 200) -> Bool {
        push(0, force: true)
        push(1, force: true)
        return settle(steps: steps)
    }

    mutating func settle(steps: Int = 200) -> Bool {
        var quiet = 0
        for _ in 0..<steps {
            if !inbox[1].isEmpty {
                deliver(1)
            } else if !inbox[0].isEmpty {
                deliver(0)
            } else {
                let before = sent
                tick()
                quiet = sent == before && !busy ? quiet + 1 : 0
                if quiet == 3 { return true }
            }
        }
        return false
    }
}

@Suite struct LedgerSyncProtocolTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    func row(_ n: Int, yen: Int = 900, at: Date? = nil, lat: Double? = nil, origin: String = "a") -> LedgerRecord {
        LedgerRecord(id: id(n), yen: yen, category: "food", method: "cash", at: at ?? now, lat: lat, origin: origin)
    }

    func phone(_ rows: [LedgerRecord], tombstones: [LedgerTombstone] = []) -> TwoPhones.Phone {
        TwoPhones.Phone(ledger: LedgerState(records: rows, tombstones: tombstones), now: now)
    }

    @Test func twoLedgersBecomeOneAndBothSaySynced() {
        var p = TwoPhones(phone([row(1)]), phone([row(2, origin: "b")]))
        let quiet = p.connectAndSettle()
        #expect(quiet)
        #expect(p.phones[0].ledger == p.phones[1].ledger)
        #expect(p.phones[0].ledger.records.map(\.id) == [id(1), id(2)])
        #expect(p.standing(0) == .synced && p.standing(1) == .synced)
        #expect(p.phones[0].stamps > 0 && p.phones[1].stamps > 0)
        #expect(p.sent <= 8)
    }

    /// A row the other phone refuses (past the keypad's cap, written before every way in was checked): each
    /// keeps its own, both say synced (the refusal is counted where it happens), and they stop.
    @Test func aRowTheOtherRefusesStopsAndBothSaySynced() {
        for refused in [row(9, yen: 12_000_000), row(9, at: now.addingTimeInterval(2 * 86400))] {
            var p = TwoPhones(phone([row(1), refused]), phone([row(1)]))
            let quiet = p.connectAndSettle()
            #expect(quiet)
            #expect(p.sent <= 4)
            #expect(p.phones[0].ledger.records == [row(1), refused])
            #expect(p.phones[1].ledger.records == [row(1)])
            #expect(p.standing(0) == .synced && p.standing(1) == .synced)
        }
    }

    /// The same row with the same write time on both, other coordinates: `LedgerMerge.merge` keeps its first
    /// argument on such a tie, so each phone keeps its own. The sync does not depend on it: both say synced, and
    /// they stop.
    @Test func aTieStopsAndBothSaySynced() {
        var p = TwoPhones(phone([row(1, lat: 1)]), phone([row(1, lat: 2)]))
        let quiet = p.connectAndSettle()
        #expect(quiet)
        #expect(p.sent <= 4)
        #expect(p.phones[0].ledger.records.map(\.lat) == [1])
        #expect(p.phones[1].ledger.records.map(\.lat) == [2])
        #expect(p.standing(0) == .synced && p.standing(1) == .synced)
    }

    /// Two phones that work out different digests for one ledger (say, another iOS writes the JSON otherwise):
    /// one more ledger goes over, then they stop, both synced.
    @Test func digestsThatDifferAcrossPhonesCostOneLedgerNotALoop() {
        var same = TwoPhones(phone([row(1)]), phone([row(1)]))
        same.push(0, force: true)
        let sameQuiet = same.settle()
        #expect(sameQuiet)
        #expect(same.sent == 2, "the ledger and its ack")
        var salted = TwoPhones(phone([row(1)]), phone([row(1)]))
        salted.phones[1].salt = "b:"
        salted.push(0, force: true)
        let saltedQuiet = salted.settle()
        #expect(saltedQuiet)
        #expect(salted.sent == 4, "the ledger and its ack, each way")
        #expect(salted.standing(0) == .synced && salted.standing(1) == .synced)
    }

    /// The other phone cannot write (a full disk; "Giả lỗi lưu"): this one says so, sends again at each
    /// heartbeat, and both say synced once a write works, with nothing edited in between.
    @Test func aWriteThatFailsIsSentAgainUntilItWorks() {
        var p = TwoPhones(phone([row(1), row(2)]), phone([row(1)]))
        p.phones[1].failing = 2
        p.push(0, force: true)
        p.deliver(1)
        #expect(p.standing(1) == .unsaved("disk full"))
        p.deliver(0)
        #expect(p.standing(0) == .failed("disk full"))
        #expect(p.phones[0].session.needsSend(current: p.phones[0].current, now: p.phones[0].now))
        p.tick()
        p.drain()
        #expect(p.phones[0].nacks == 2)
        #expect(p.phones[1].ledger.records == [row(1)], "nothing of it written")
        #expect(p.phones[0].stamps == 0 && p.phones[1].stamps == 0)
        p.tick()
        p.deliver(1)
        #expect(p.standing(1) == .synced)
        p.drain()
        #expect(p.standing(0) == .synced)
        let quiet = p.settle()
        #expect(quiet)
        #expect(p.phones[1].ledger == p.phones[0].ledger)
    }

    /// A send the radio refused is not taken for sent: the next heartbeat sends it.
    @Test func aSendTheRadioRefusedGoesAtTheNextHeartbeat() {
        var p = TwoPhones(phone([row(1), row(2)]), phone([row(1)]))
        p.refusals = 1
        p.push(0, force: true)
        #expect(!p.busy)
        #expect(p.standing(0) == .sending)
        p.tick()
        #expect(p.busy)
        let quiet = p.settle()
        #expect(quiet)
        #expect(p.phones[1].ledger == p.phones[0].ledger)
        #expect(p.standing(0) == .synced && p.standing(1) == .synced)
    }

    /// An ack that never came: the ledger goes again 15 seconds on, and once acked, never again.
    @Test func anAckThatNeverCameIsCoveredByASecondSend() {
        var p = TwoPhones(phone([row(1), row(2)]), phone([row(1)]))
        p.push(0, force: true)
        p.refusals = 1  // the ack
        p.deliver(1)
        #expect(!p.busy)
        #expect(p.standing(0) == .sending)
        p.tick()
        #expect(p.inbox[1].count == 1, "sent again")
        let quiet = p.settle()
        #expect(quiet)
        #expect(p.standing(0) == .synced && p.standing(1) == .synced)
    }

    /// A build before acknowledgements: the ledgers still meet, this phone never says synced, and it sends each
    /// ledger once, not every heartbeat.
    @Test func anOlderBuildIsNeverSyncedAndNotFlooded() {
        var old = phone([row(2, origin: "b")])
        old.old = true
        var p = TwoPhones(phone([row(1)]), old)
        let quiet = p.connectAndSettle()
        #expect(quiet)
        #expect(p.phones[0].ledger == p.phones[1].ledger)
        #expect(p.standing(0) == .unconfirmed)
        #expect(p.phones[0].stamps == 0)
        let sent = p.sent
        for _ in 0..<20 { p.tick() }
        #expect(p.sent == sent)
        p.edit(0, row(3))
        let settledAgain = p.settle()
        #expect(settledAgain)
        #expect(p.phones[1].ledger.records.map(\.id) == [id(1), id(2), id(3)])
        #expect(p.sent == sent + 1, "the edit, once")
    }

    // MARK: Fuzz

    func randomState(_ g: inout SplitMix) -> LedgerState {
        let offsets: [TimeInterval] = [0, 60, 120, 3 * 86400, -3600, 86400 + 10, 2 * 86400, 120]
        var rows: [UUID: LedgerRecord] = [:]
        var tombs: [LedgerTombstone] = []
        for n in 1...4 {
            switch Int.random(in: 0..<5, using: &g) {
            case 0: continue
            case 1, 2:
                let yen = [900, 1500, 12_000_000, 0].randomElement(using: &g)!
                let note = Bool.random(using: &g) && Bool.random(using: &g) ? String(repeating: "x", count: 501) : ""
                let at = now.addingTimeInterval(offsets.randomElement(using: &g)!)
                let edited: Date? = Bool.random(using: &g) ? now.addingTimeInterval(offsets.randomElement(using: &g)!) : nil
                rows[id(n)] = LedgerRecord(id: id(n), yen: yen, category: "food", method: "cash", note: note, at: at, updatedAt: edited,
                                           origin: Bool.random(using: &g) ? "a" : "b")
            case 3:
                // a tie: same write, other coordinates
                rows[id(n)] = row(n, lat: Bool.random(using: &g) ? 1 : 2)
            default:
                let bad = LedgerRecord(id: id(n), yen: 12_000_000, category: "food", method: "cash", at: now, origin: "a")
                tombs.append(LedgerTombstone(id: id(n), at: now.addingTimeInterval(offsets.randomElement(using: &g)!),
                                             duplicateOf: Bool.random(using: &g) ? id(9) : nil, record: Bool.random(using: &g) ? bad : nil))
            }
        }
        let kept = Bool.random(using: &g) ? [LedgerMerge.pairKey(id(1), id(2))] : []
        // a ledger as a phone would hold it: merged with itself
        return LedgerMerge.merge(LedgerState(records: Array(rows.values), tombstones: tombs, kept: kept), .empty)
    }

    /// Two phones with random ledgers (rows one refuses, ties, deletions), clocks up to four days apart, digests
    /// that differ across phones, writes that fail, sends the radio refuses, acks still on their way when a
    /// heartbeat beats, edits along the way, and sometimes a build before acknowledgements: they always go quiet,
    /// and then both say synced (or, beside an older build, "unconfirmed", never synced).
    @Test func twoPhonesAlwaysGoQuietAndSaySynced() {
        var g = SplitMix(seed: 15)
        for run in 0..<1000 {
            let skews: [TimeInterval] = [0, 0, 2 * 86400, -2 * 86400, 86400 + 30, -(86400 + 30)]
            var a = TwoPhones.Phone(ledger: randomState(&g), now: now.addingTimeInterval(skews.randomElement(using: &g)!))
            var b = TwoPhones.Phone(ledger: randomState(&g), now: now.addingTimeInterval(skews.randomElement(using: &g)!))
            if Int.random(in: 0..<4, using: &g) == 0 { b.salt = "b:" }
            if run % 5 == 0 {
                b.old = true
            } else {
                a.failing = Int.random(in: 0..<2, using: &g)
                b.failing = Int.random(in: 0..<3, using: &g)
            }
            var p = TwoPhones(a, b)
            p.refusals = Int.random(in: 0..<3, using: &g)
            var edits = Int.random(in: 0..<3, using: &g)
            p.push(0, force: true)
            p.push(1, force: true)
            var quiet = 0
            var steps = 0
            while quiet < 3, steps < 400 {
                steps += 1
                let ready = (0..<2).filter { !p.inbox[$0].isEmpty }
                let late = !ready.isEmpty && Int.random(in: 0..<40, using: &g) == 0
                if !ready.isEmpty, !late {
                    p.deliver(ready.randomElement(using: &g)!)
                } else if ready.isEmpty, edits > 0, Bool.random(using: &g) {
                    edits -= 1
                    let i = Int.random(in: 0..<2, using: &g)
                    p.edit(i, LedgerRecord(id: id(100 + edits), yen: 700, category: "food", method: "cash", at: p.phones[i].now,
                                           origin: i == 0 ? "a" : "b"))
                    quiet = 0
                } else {
                    let before = p.sent
                    p.tick()
                    quiet = ready.isEmpty && edits == 0 && p.sent == before && !p.busy ? quiet + 1 : 0
                }
            }
            guard quiet == 3 else {
                Issue.record("run \(run) never went quiet: \(p.sent) messages")
                return
            }
            if b.old {
                #expect(p.standing(0) == .unconfirmed, "run \(run)")
                #expect(p.phones[0].stamps == 0, "run \(run)")
            } else if p.standing(0) != .synced || p.standing(1) != .synced {
                Issue.record("run \(run) quiet but \(p.standing(0)) / \(p.standing(1))")
                return
            }
        }
    }

    /// The 1.5 review's shape: edits whenever, messages on their way or not; a reconnect or none, losing what
    /// was on its way; an older build (every fifth run) whose writes fail too; sends the radio refuses. At every
    /// stamp, the truth: the other phone lacks no row of this one's that it would take (`TwoPhones.holds`). An
    /// answer goes only when the other phone would gain something (`LedgerMerge.reply`). They always go quiet,
    /// and then both say synced, and are (beside an older build, never synced).
    @Test(arguments: [UInt64(15), 16, 17, 99, 1234])
    func editsInFlightReconnectsAndTheTruth(seed: UInt64) {
        var g = SplitMix(seed: seed)
        var problems: [String] = []
        for run in 0..<600 {
            let skews: [TimeInterval] = [0, 0, 2 * 86400, -2 * 86400, 86400 + 30, -(86400 + 30)]
            var a = TwoPhones.Phone(ledger: randomState(&g), now: now.addingTimeInterval(skews.randomElement(using: &g)!))
            var b = TwoPhones.Phone(ledger: randomState(&g), now: now.addingTimeInterval(skews.randomElement(using: &g)!))
            if Int.random(in: 0..<4, using: &g) == 0 { b.salt = "b:" }
            if run % 5 == 0 { b.old = true }
            a.failing = Int.random(in: 0..<2, using: &g)
            b.failing = Int.random(in: 0..<3, using: &g)
            var p = TwoPhones(a, b)
            p.refusals = Int.random(in: 0..<3, using: &g)
            var edits = Int.random(in: 0..<5, using: &g)
            var reconnects = Int.random(in: 0..<2, using: &g)
            p.push(0, force: true)
            p.push(1, force: true)
            var quiet = 0
            var steps = 0
            while quiet < 3, steps < 600 {
                steps += 1
                let ready = (0..<2).filter { !p.inbox[$0].isEmpty }
                let roll = Int.random(in: 0..<20, using: &g)
                if edits > 0, roll == 0 {
                    // an edit, whether or not messages are on their way
                    edits -= 1
                    let i = Int.random(in: 0..<2, using: &g)
                    p.edit(i, LedgerRecord(id: id(100 + edits), yen: 700, category: "food", method: "cash", at: p.phones[i].now,
                                           origin: i == 0 ? "a" : "b"))
                    quiet = 0
                } else if reconnects > 0, roll == 1 {
                    reconnects -= 1
                    p.reconnect()
                    quiet = 0
                } else if !ready.isEmpty, roll > 2 {
                    p.deliver(ready.randomElement(using: &g)!)
                } else {
                    let before = p.sent
                    p.tick()
                    quiet = ready.isEmpty && edits == 0 && reconnects == 0 && p.sent == before && !p.busy ? quiet + 1 : 0
                }
            }
            problems += p.falseStamps.map { "run \(run): \($0)" }
            if p.needlessAnswers > 0 { problems.append("run \(run): \(p.needlessAnswers) answer(s) the other would gain nothing from") }
            guard quiet == 3 else {
                problems.append("run \(run) never went quiet: \(p.sent) messages")
                continue
            }
            if b.old {
                if p.standing(0) == .synced { problems.append("run \(run): synced beside an older build") }
            } else if p.standing(0) != .synced || p.standing(1) != .synced {
                problems.append("run \(run) quiet but \(p.standing(0)) / \(p.standing(1))")
            } else if !p.holds(1, 0) || !p.holds(0, 1) {
                problems.append("run \(run) quiet and synced, but a phone lacks a row it would take")
            }
        }
        let found = problems.count
        #expect(found == 0, "seed \(seed), first: \(problems.prefix(3))")
    }

    /// The reply rule alone (`LedgerMerge.reply`, R-53): each side answers a ledger with its own only when the
    /// other would gain something it vouches for; random ledgers and clocks, from either side: always stops.
    @Test func repliesAlwaysStop() {
        var g = SplitMix(seed: 42)
        var worst = 0
        for _ in 0..<4000 {
            var sides = [randomState(&g), randomState(&g)]
            let skews: [TimeInterval] = [0, 2 * 86400, -2 * 86400, 86400 + 30, -(86400 + 30), 3 * 86400]
            var nows = [now.addingTimeInterval(skews.randomElement(using: &g)!), now.addingTimeInterval(skews.randomElement(using: &g)!)]
            let steps: [TimeInterval] = [0, 3600, 6 * 3600]
            let step = steps.randomElement(using: &g)!
            var to = Bool.random(using: &g) ? 1 : 0
            var message: LedgerState? = sides[1 - to]
            var messages = 0
            while let m = message, messages < 50 {
                messages += 1
                sides[to] = LedgerMerge.merge(sides[to], LedgerMerge.screened(m, now: nows[to]).state)
                message = LedgerMerge.reply(local: sides[to], remote: m, now: nows[to])
                nows[0] += step
                nows[1] += step
                to = 1 - to
            }
            worst = max(worst, messages)
        }
        #expect(worst <= 3)
    }
}
