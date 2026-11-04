import Foundation

/// A short name for one whole ledger, the same on both phones for the same ledger: the app works it out (a hash
/// of the ledger as JSON with sorted keys); here it is only compared.
public struct LedgerDigest: Codable, Sendable, Hashable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }
}

/// What one phone knows of the sync with one other phone over one connection, and the decisions made from it.
/// No clock inside: the time is passed in.
///
/// A ledger counts as synced only once the other phone has written it: it says so with an ack, or by sending
/// its own ledger, which it sends only once stored. Until then the ledger is sent again at each heartbeat
/// `resendAfter` on; after a nack it is due at once, and sent at the next heartbeat. The ledgers the other phone is
/// known to hold are kept as a set, not one slot: two phones may stay different on a row one of them refuses
/// (`LedgerMerge.reply`), or on a merge tie, or work out different digests for one ledger; with one slot, hearing
/// "I hold yours" and then their own ledger would forget the first, and the two would resend to each other for
/// ever. A phone sends a given ledger at most once per `resendAfter` until it is held, so with nothing new written
/// the two always go quiet.
///
/// A build from before acknowledgements never acks: it is sent each ledger once (as before), and it is never
/// counted as synced, since what it holds cannot be known.
public struct LedgerSyncSession: Sendable {
    /// The version of the sync this build speaks, said in its greeting: from 2 on, every ledger received is
    /// acknowledged once written (`.ack`) or refused with the reason (`.nack`).
    public static let version = 2
    /// The longest reason from the other phone that is kept, in characters.
    public static let longestReason = 200

    /// whether the other phone acknowledges (its greeting said version 2 or later)
    public let acks: Bool
    /// during a rehearsal: nothing is sent, nothing acknowledged
    public var paused = false
    /// why the other phone could not write the last ledger it said it could not (its nack); cleared once it
    /// holds that ledger, or this phone's as it is now (`peerHas`)
    public var lastFailure: String? { failure?.reason }
    /// why this phone could not write the other's last ledger; cleared by the next one written
    public private(set) var unsaved: String?

    /// the ledgers the other phone is known to hold, this connection
    private var held: Set<LedgerDigest> = []
    /// the last ledger handed to the radio, and when
    private var sent: Sent?
    /// the last ledger the other phone could not write (its nack), and why
    private var failure: Failure?

    private struct Sent: Sendable {
        var digest: LedgerDigest
        var at: Date
    }

    private struct Failure: Sendable {
        var digest: LedgerDigest
        var reason: String
    }

    /// `peerVersion`: the version in the other phone's greeting (nil from a build before acknowledgements).
    public init(peerVersion: Int? = LedgerSyncSession.version) {
        acks = (peerVersion ?? 1) >= 2
    }

    /// The radio took this ledger for the other phone (call it only then: a send it refused is not one).
    public mutating func didSend(_ d: LedgerDigest, at: Date) {
        sent = Sent(digest: d, at: at)
    }

    /// The other phone holds this ledger: it acked it, or sent it as its own. Its failure to write one of this
    /// phone's (`lastFailure`) is past once it holds that ledger, or this phone's as it is now (`current`, nil when
    /// not known); a ledger of its own or a late ack of an older one says nothing of it, and "X chưa lưu được"
    /// stays rather than flicker to "sending" until the next heartbeat.
    public mutating func peerHas(_ d: LedgerDigest, current: LedgerDigest? = nil) {
        held.insert(d)
        guard let failure else { return }
        if failure.digest == d || current.map(held.contains) == true { self.failure = nil }
    }

    /// The other phone could not write this ledger (its nack): it is due again at once (sent at the next
    /// heartbeat), and `lastFailure` says why. It takes back an earlier ack of the same ledger: a row it refused
    /// then, dated too far ahead of its clock, may be one it takes now, and that write is what failed. A nack for
    /// an older ledger leaves a newer one on its way alone.
    public mutating func peerFailed(_ d: LedgerDigest, reason: String) {
        failure = Failure(digest: d, reason: Self.clipped(reason))
        held.remove(d)
        if sent?.digest == d { sent = nil }
    }

    /// The connection ended: what was known of it goes with it.
    public mutating func disconnected() {
        held = []
        sent = nil
        failure = nil
        unsaved = nil
    }

    /// Whether to send this phone's ledger now (the heartbeat; the connection's first send and a touch send
    /// regardless): not while paused, not when the other phone holds it, and not while it is on its way, that is
    /// sent less than `resendAfter` ago and neither acked nor nacked. A build that never acks gets each ledger
    /// once. A send dated after `now` (the clock was set back) does not hold the next one.
    public func needsSend(current: LedgerDigest, now: Date, resendAfter: TimeInterval = 15) -> Bool {
        guard !paused, !held.contains(current) else { return false }
        guard let sent, sent.digest == current else { return true }
        guard acks else { return false }
        let age = now.timeIntervalSince(sent.at)
        return age < 0 || age >= resendAfter
    }

    /// The other phone holds this phone's ledger as it is now.
    public func isSynced(current: LedgerDigest) -> Bool {
        held.contains(current)
    }

    /// A ledger came from the other phone with its `digest` (nil from a build before acknowledgements), and this
    /// phone wrote it (`failure` nil) or could not (`failure`, why). Returns what goes back at once: `.ack` when
    /// written, `.nack` with the reason when not; nothing while paused, to a build that never acks, or for a
    /// ledger that came without a digest. A ledger written is one the other phone holds: it sends only what it
    /// has stored (`peerHas`, with this phone's `current` ledger when known).
    public mutating func received(_ digest: String?, failure: String?, current: LedgerDigest? = nil) -> SyncPayload? {
        guard !paused else { return nil }
        unsaved = failure.map(Self.clipped)
        guard acks, let digest else { return nil }
        guard let failure else {
            peerHas(LedgerDigest(digest), current: current)
            return .ack(digest: digest)
        }
        return .nack(digest: digest, reason: Self.clipped(failure))
    }

    /// Whether this phone's ledger (`mine`, as written now, with its `digest`) goes back after `remote` came in
    /// and was merged: only when the other phone would gain something this phone vouches for
    /// (`LedgerMerge.reply`, by this phone's `now`, the one it screened `remote` by), and it is not already on
    /// its way or held there (`needsSend`).
    public func answers(_ remote: LedgerState, with mine: LedgerState, digest: LedgerDigest, now: Date) -> Bool {
        LedgerMerge.reply(local: mine, remote: remote, now: now) != nil && needsSend(current: digest, now: now)
    }

    /// Where the sync with this phone stands, for this phone's ledger as it is now (nil while its digest is not
    /// worked out yet). `.synced`, and only that, is when "Đã đồng bộ" may be stamped: the other phone holds
    /// this ledger, and this phone wrote the other's last one. A nack for an older ledger is past once the other
    /// phone holds this one.
    public func standing(current: LedgerDigest?) -> Standing {
        if let unsaved { return .unsaved(unsaved) }
        let holds = current.map(held.contains) ?? false
        if let lastFailure, !holds { return .failed(lastFailure) }
        guard let current else { return .sending }
        guard acks else { return sent?.digest == current ? .unconfirmed : .sending }
        return holds ? .synced : .sending
    }

    /// Where the sync with one phone stands, worst first.
    public enum Standing: Sendable, Hashable {
        /// this phone could not write the other's last ledger, and why
        case unsaved(String)
        /// the other phone could not write this one's (its nack), and why
        case failed(String)
        /// a build before acknowledgements has been sent this ledger; whether it holds it cannot be known
        case unconfirmed
        /// this ledger is not known to be on the other phone yet
        case sending
        /// the other phone holds this ledger, and this phone wrote the other's last one
        case synced

        /// Of several phones connected at once, the one the status speaks of: the worst standing (in the order
        /// above), the first of equals; nil for none. So "synced" only when every one is.
        public static func worst<T>(_ items: [T], by standing: (T) -> Standing) -> (item: T, standing: Standing)? {
            var worst: (item: T, standing: Standing)?
            for item in items {
                let s = standing(item)
                if let w = worst, w.standing.rank <= s.rank { continue }
                worst = (item, s)
            }
            return worst
        }

        private var rank: Int {
            switch self {
            case .unsaved: 0
            case .failed: 1
            case .unconfirmed: 2
            case .sending: 3
            case .synced: 4
            }
        }
    }

    private static func clipped(_ reason: String) -> String {
        String(reason.prefix(longestReason))
    }
}
