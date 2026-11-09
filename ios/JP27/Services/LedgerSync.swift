import CryptoKit
import Foundation
import MultipeerConnectivity
import NearbyInteraction
import os
import Security
import SwiftData
import TripKit
import UIKit

/// The two phones' ledgers kept as one, with no server and no internet.
///
/// While both phones have the app open near each other they find each other over peer-to-peer
/// Wi-Fi (MultipeerConnectivity, the link AirDrop uses) and each sends the other its whole ledger:
/// expenses, deletions, pairs kept apart. Each merges what it gets by `LedgerMerge`'s rules and sends
/// back what the other lacked, so a couple of messages leave both phones with the same ledger. After
/// that, every change on either phone goes across within a second or two.
///
/// Phones with a UWB chip (iPhone 11 and later) also measure the distance between them
/// (NearbyInteraction): bring the tops of the two phones together and they sync at once, with a tap
/// felt on both. The first time two phones meet, nothing is shared until each says yes, by the
/// button or by that touch. A phone said yes to is remembered and synced with from then on.
///
/// Who is who rests on keys, not on what a phone says it is. Each install has a key pair kept in
/// its Keychain (`SyncIdentity`); saying yes pins the other phone's public key, after the
/// travellers check that both screens show the same six digits (or touch the phones together,
/// which only the two phones in hand can do). Every message after the greeting is signed (HMAC) with
/// a key only the two phones can work out, fresh for each connection, so another phone running the
/// app can neither read the ledger nor write to it, even knowing the other's install id; nothing
/// identifying is advertised to phones near by; invitations are taken only from phones already
/// paired, or while the sync page is open to pair; and rows the keypad could not have written (an
/// amount past its cap, a note too long, a date far in the future) are not believed
/// (`LedgerMerge.screened`; how many is `rejected`).
///
/// Third-party apps cannot send by AirDrop on their own, nor take in an AirDrop without the share
/// sheet and an accept on the other side: hence this, and the CSV only as a fallback.
///
/// "Đã đồng bộ" means the other phone has written this one's ledger as it is now, and this one wrote
/// the other's last. What to send and when, and what to answer, is decided by TripKit's
/// `LedgerSyncSession`, one per connection; this class merges, works out digests, signs and sends:
/// 1. A sends `.state(S_A, d_A)`, `d_A` its digest (`LedgerDigest`: a hash of the ledger as sorted
///    JSON, the same on both phones). Only once the radio takes it does the session note it as sent;
///    a send the radio refuses is not one, and the heartbeat sends it.
/// 2. B screens it (`LedgerMerge.screened`) and merges it into its records. Written: B answers
///    `.ack(d_A)`, notes that A holds `S_A` (a phone sends only what it has stored), and sends its own
///    ledger back when A would gain something from it (`LedgerMerge.reply`) and it is not already on its
///    way. Not written: `.nack(d_A, reason)`, nothing stamped, and this line says so.
/// 3. A, on `.ack`, notes that B holds `S_A`; on B's ledger, does as B did in 2; on `.nack`, says why
///    and sends again at the next heartbeat.
/// 4. "Đã đồng bộ lúc …" is stamped (`lastSync`) only when the session says `.synced`.
/// 5. Every 15 s the heartbeat sends this phone's ledger to each phone that is not known to hold it
///    and has not had it within the last 15 s. A connection's first send, and a touch, send at once.
/// A build from before acknowledgements (its greeting has no `v`) is sent each ledger once and never
/// counted as synced: "Đã gửi cho Lan · chờ máy kia cập nhật app để xác nhận". During a rehearsal
/// nothing is sent or acknowledged: the link is down.
@Observable final class LedgerSync: NSObject {
    /// the one the app runs, for the records' helpers to nudge
    static weak var shared: LedgerSync?

    struct Partner: Codable, Hashable, Identifiable {
        /// the other install, which names who logged each row; learnt once paired ("" until then)
        var install: String
        var name: String
        /// its public key, pinned when the travellers said yes: only that phone can sign as it. Nil on
        /// a phone paired before messages were signed: such a phone is asked about again.
        var key: Data?
        var id: String { key?.base64EncodedString() ?? install }
    }

    struct Stamp: Codable, Equatable {
        var name: String
        var at: Date
    }

    /// on while the travellers want the phones to sync; asking for local network and nearby
    /// devices waits until they turn it on
    private(set) var enabled: Bool
    /// off while a rehearsal runs: its records are not the trip's, and stay on this phone
    private(set) var paused = false
    /// this phone's name on the other phone
    private(set) var name: String
    private(set) var paired: [Partner]
    /// a paired phone connected now
    private(set) var nearby: Partner?
    /// a phone near by with the app open, not yet said yes to
    private(set) var asking: Partner?
    /// the six digits both phones show for `asking`; the same on both only if no one is in between
    private(set) var askingCode: String?
    /// metres to the nearby phone, when both have UWB
    private(set) var distance: Float?
    private(set) var lastSync: Stamp?
    /// rows of the paired phone's last ledger that this phone left out (`LedgerMerge.screened`):
    /// replaced by each ledger received, not kept across launches
    private(set) var rejected = 0
    /// the paired phone that ledger came from
    private(set) var rejectedFrom: String?
    /// both phones need UWB for the touch; this one has it
    var supportsTouch: Bool { NISession.deviceCapabilities.supportsPreciseDistanceMeasurement }

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var link: SyncLink?
    @ObservationIgnored private var events: AsyncStream<SyncLink.Event>.Continuation?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var saves: (any NSObjectProtocol)?
    /// the sync page is on screen: phones not yet paired may connect, to be asked about
    @ObservationIgnored private var pairing = false
    /// connected peers that have said who they are, each with its sync session (observed: `standing`
    /// reads them)
    private var peers: [Int: Peer] = [:]
    /// this side's random number for each connection, sent in its greeting
    @ObservationIgnored private var nonces: [Int: Data] = [:]
    /// this phone's ledger as last read from the records, with its digest; dropped when an expense is
    /// saved (observed: `standing` reads the digest)
    private var cached: Snapshot?
    /// bumped whenever `cached` is dropped, so a digest worked out across a save is not kept
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var sessions: [Int: NISession] = [:]
    @ObservationIgnored private var closeness: [Int: Float] = [:]
    @ObservationIgnored private var lastTouch = Date.distantPast
    /// keys said "not now" to, until the app opens again
    @ObservationIgnored private var declined: Set<Data> = []

    /// A phone on the other end of a connection, as its greeting said, and the key the two share.
    private struct Peer {
        var name: String
        var key: Data
        var install: String?
        var secret: SymmetricKey
        /// the number of the last message sent to it, and of the last one taken from it
        var out: UInt64 = 0
        var heard: UInt64 = 0
        /// what this connection knows of the sync, and its decisions
        var session: LedgerSyncSession
    }

    /// The ledger as read from the records, and the digest of exactly that value.
    private struct Snapshot {
        let state: LedgerState
        let digest: LedgerDigest
    }

    private enum Key {
        static let enabled = "sync.enabled"
        static let name = "sync.name"
        static let paired = "sync.paired"
        static let last = "sync.last"
        static let peer = "sync.peer"
        static let peerName = "sync.peerName"
    }

    /// Phones this close count as touching.
    static let touch: Float = 0.12

    override init() {
        let d = Shared.defaults
        enabled = d.bool(forKey: Key.enabled)
        name = d.string(forKey: Key.name) ?? UIDevice.current.name
        paired = d.data(forKey: Key.paired).flatMap { try? JSONDecoder().decode([Partner].self, from: $0) } ?? []
        lastSync = d.data(forKey: Key.last).flatMap { try? JSONDecoder().decode(Stamp.self, from: $0) }
        super.init()
        Self.shared = self
    }

    // MARK: - Lifecycle

    /// Foreground, or the records swapped for a rehearsal's: look for the other phone, if syncing is
    /// on and no rehearsal runs.
    func activate(context: ModelContext) {
        if self.context !== context {
            self.context = context
            changed()
        }
        if saves == nil {
            // only a save that touches expenses or their deletions can change the ledger; a point of
            // the walk trace or a stop marked done cannot, and the ledger is not read again for them
            saves = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
                let ledger = LedgerSync.touchesLedger(note.userInfo)
                MainActor.assumeIsolated { if ledger { self?.ledgerChanged() } }
            }
        }
        if enabled, !paused { begin() }
    }

    /// Background: the link does not survive it; it starts again in the foreground.
    func deactivate() {
        end()
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        Shared.defaults.set(on, forKey: Key.enabled)
        on && !paused ? begin() : end()
    }

    /// A rehearsal starts (or ends; `activate` then starts the link again).
    func setPaused(_ on: Bool) {
        guard on != paused else { return }
        paused = on
        AppLog.info(.sync, "Đồng bộ tạm dừng khi chạy thử", ["paused": "\(on)"])
        for k in peers.keys { peers[k]?.session.paused = on }
        if on { end() }
    }

    /// The sync page opened or closed: while it is open, phones not paired yet may connect. Opening
    /// it with no phone connected starts the link again, so a phone turned away a moment ago is found
    /// and invited afresh.
    func setPairing(_ open: Bool) {
        guard open != pairing else { return }
        pairing = open
        admit()
        if open, link != nil, peers.isEmpty { end(); begin() }
    }

    func rename(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != name else { return }
        name = clean
        Shared.defaults.set(clean, forKey: Key.name)
        // the name is in the greeting: start the link again under the new one
        if link != nil { end(); begin() }
    }

    // MARK: - Pairing

    /// Yes to the phone asking: share with it from now on.
    func accept() {
        guard let key = asking?.key else { return }
        pair(key)
    }

    /// Not now: not asked again until the app opens again.
    func decline() {
        guard let key = asking?.key else { return }
        declined.insert(key)
        asking = nil
        askingCode = nil
    }

    func unpair(_ p: Partner) {
        AppLog.info(.sync, "Bỏ ghép máy", ["peer": Self.peerTag(p.key)])
        paired.removeAll { $0.id == p.id }
        savePaired()
        if nearby?.id == p.id { nearby = nil; distance = nil }
    }

    /// Pins the key of a phone connected now: from here on it is this phone's partner.
    private func pair(_ key: Data) {
        guard let peer = peers.values.first(where: { $0.key == key }) else { return }
        AppLog.info(.sync, "Ghép máy", ["peer": Self.peerTag(key)])
        if let i = paired.firstIndex(where: { $0.key == key }) {
            paired[i].name = peer.name
        } else {
            // a phone paired before messages were signed, or that reinstalled: one entry, the new key
            paired.removeAll { $0.key == nil && peer.install != nil && $0.install == peer.install }
            paired.append(Partner(install: peer.install ?? "", name: peer.name, key: key))
        }
        savePaired()
        if asking?.key == key { asking = nil; askingCode = nil }
        for (k, p) in peers where p.key == key { connected(k) }
    }

    /// The partner a connected peer's key belongs to.
    private func partner(_ peer: Peer) -> Partner? {
        paired.first { $0.key == peer.key }
    }

    /// A paired phone connected: say which install this is, then send the ledger.
    private func connected(_ k: Int) {
        guard let peer = peers[k], let p = partner(peer) else { return }
        AppLog.info(.sync, "Kết nối máy kia", ["peer": Self.peerTag(peer.key)])
        nearby = p
        distance = closeness[k]
        seal(.intro(install: SpendLedgerFile.installID), to: k)
        // the ledger follows once its digest is worked out; nothing waits for it
        Task { await push(to: k, force: true) }
    }

    /// The other phone in the log: the first 8 hex digits of its key's fingerprint (`SyncIdentity.fingerprint`),
    /// never its name. "none" for a phone paired before messages were signed.
    private static func peerTag(_ key: Data?) -> String {
        guard let key else { return "none" }
        return String(SyncIdentity.fingerprint(key).map { String(format: "%02x", $0) }.joined().prefix(8))
    }

    private func savePaired() {
        Shared.defaults.set(try? JSONEncoder().encode(paired), forKey: Key.paired)
        admit()
    }

    /// Tells the link whose invitations to take: paired phones' keys, and anyone while pairing.
    private func admit() {
        link?.admit(open: pairing, prints: Set(paired.compactMap { $0.key.map(SyncIdentity.fingerprint) }))
    }

    // MARK: - The link

    private func begin() {
        guard link == nil, context != nil, enabled, !paused else { return }
        let (stream, continuation) = AsyncStream.makeStream(of: SyncLink.Event.self)
        events = continuation
        // one queue for everything the link reports, handled one at a time and to the end (a ledger's
        // digest is awaited), so a peer's greeting is always handled before its ledger, and its ledger
        // before its next message
        listener = Task { [weak self] in
            for await event in stream { await self?.handle(event) }
        }
        let link = SyncLink(peer: peerID(), fingerprint: SyncIdentity.fingerprint(SyncIdentity.publicKey)) { continuation.yield($0) }
        self.link = link
        admit()
        link.start()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await self?.pushAll()
            }
        }
    }

    private func end() {
        link?.stop()
        link = nil
        events?.finish()
        events = nil
        listener?.cancel()
        heartbeat?.cancel()
        debounce?.cancel()
        listener = nil
        heartbeat = nil
        for s in sessions.values { s.invalidate() }
        sessions = [:]
        peers = [:]
        nonces = [:]
        closeness = [:]
        nearby = nil
        asking = nil
        askingCode = nil
        distance = nil
    }

    /// The same peer identity every launch, as MultipeerConnectivity asks. Phones near by see only
    /// "JP27": the name the travellers chose goes in the greeting, to a connected phone.
    private func peerID() -> MCPeerID {
        let display = "JP27"
        let d = Shared.defaults
        if d.string(forKey: Key.peerName) == display, let data = d.data(forKey: Key.peer),
           let id = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            return id
        }
        let id = MCPeerID(displayName: display)
        d.set(try? NSKeyedArchiver.archivedData(withRootObject: id, requiringSecureCoding: true), forKey: Key.peer)
        d.set(display, forKey: Key.peerName)
        return id
    }

    private func handle(_ event: SyncLink.Event) async {
        switch event {
        case .connected(let k):
            greet(k)
        case .disconnected(let k):
            // its sync session goes with it: what the other phone held, and what was on its way
            let gone = peers.removeValue(forKey: k)
            if let gone { AppLog.info(.sync, "Mất kết nối máy kia", ["peer": Self.peerTag(gone.key)]) }
            nonces[k] = nil
            sessions.removeValue(forKey: k)?.invalidate()
            closeness[k] = nil
            if let gone, nearby?.key == gone.key, !peers.values.contains(where: { $0.key == gone.key }) {
                nearby = nil
                distance = nil
            }
            if let gone, asking?.key == gone.key { asking = nil; askingCode = nil }
        case .received(let k, let data):
            guard let message = try? JSONDecoder().decode(SyncMessage.self, from: data) else { return }
            await receive(message, from: k)
        }
    }

    /// This side's greeting on a new connection: the name, the public key, a random number for this
    /// connection, and the UWB token when the phone has UWB.
    private func greet(_ k: Int) {
        guard nonces[k] == nil else { return }
        let nonce = SyncIdentity.random(32)
        nonces[k] = nonce
        var token: Data?
        if supportsTouch {
            let s = NISession()
            s.delegate = self
            s.delegateQueue = .main
            sessions[k] = s
            token = s.discoveryToken.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
        }
        send(.hello(name: name, key: SyncIdentity.publicKey, nonce: nonce, token: token, v: LedgerSyncSession.version), to: k)
    }

    private func receive(_ message: SyncMessage, from k: Int) async {
        switch message {
        case .hello(let name, let key, let nonce, let token, let v):
            // their greeting can come before the link tells this side it connected
            if nonces[k] == nil { greet(k) }
            guard peers[k] == nil, let mine = nonces[k], nonce.count == 32, key != SyncIdentity.publicKey,
                  let secret = SyncIdentity.secret(with: key, nonces: mine, nonce)
            else { return }
            // a greeting with no version is a build before acknowledgements: it is never counted as synced
            var session = LedgerSyncSession(peerVersion: v)
            session.paused = paused
            let peer = Peer(name: String(name.prefix(60)), key: key, secret: secret, session: session)
            peers[k] = peer
            if let token, let s = sessions[k],
               let t = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: token) {
                s.run(NINearbyPeerConfiguration(peerToken: t))
            }
            if partner(peer) != nil {
                connected(k)
            } else if !declined.contains(key) {
                AppLog.info(.sync, "Máy chưa ghép xin kết nối", ["peer": Self.peerTag(key)])
                asking = Partner(install: "", name: peer.name, key: key)
                askingCode = SyncIdentity.code(with: key)
            }
        case .sealed(let n, let body, let mac):
            // signed by the phone the greeting came from, in this connection, and not seen before
            guard var peer = peers[k], n > peer.heard, SyncIdentity.isValid(mac, n, body, peer.secret),
                  let payload = try? JSONDecoder().decode(SyncPayload.self, from: body)
            else { return }
            peer.heard = n
            peers[k] = peer
            await open(payload, from: k)
        }
    }

    private func open(_ payload: SyncPayload, from k: Int) async {
        guard let peer = peers[k] else { return }
        switch payload {
        case .intro(let install):
            peers[k]?.install = install
            if let i = paired.firstIndex(where: { $0.key == peer.key }), paired[i].install != install {
                paired[i].install = install
                savePaired()
                if nearby?.key == peer.key { nearby = paired[i] }
            }
        case .state(let remote, let digest):
            guard let p = partner(peer), let context, !paused else { return }
            let now = Date()
            let (clean, left) = LedgerMerge.screened(remote, now: now)
            rejected = left.count
            rejectedFrom = p.name
            var failure: String?
            do {
                let changes = try Ledger.merge(clean, into: context).changes
                // dropped here too: a merge that changed only the pairs kept apart posts no save
                if !changes.isEmpty { changed() }
                // counts only: never a row's note or place name, never the phone's name
                let fields = ["peer": Self.peerTag(peer.key), "rows": "\(remote.records.count)", "rejected": "\(left.count)", "changed": "\(changes.upserts.count + changes.deletions.count)"]
                if left.isEmpty { AppLog.info(.sync, "Nhận sổ chi", fields) } else { AppLog.warning(.sync, "Nhận sổ chi", fields) }
            } catch {
                // not written, so not synced: nothing stamped, the records as they were; the other
                // phone is told why (`.nack`) and sends it again at its next heartbeat
                let reason = error.localizedDescription
                failure = reason
                AppLog.error(.sync, "Không lưu được sổ chi máy kia gửi", ["peer": Self.peerTag(peer.key), "error": reason])
            }
            // their ledger, held there, ends a failure of theirs only when it is this phone's as it is now
            // (`cached`: dropped by a merge that changed something)
            if let receipt = peers[k]?.session.received(digest, failure: failure, current: cached?.digest) { seal(receipt, to: k) }
            guard failure == nil else { return }
            // this phone's ledger as now written goes back when the other would gain something from it
            // (`LedgerMerge.reply`) and it is not already on its way; a row one phone refuses stays
            // where it is (counted in `rejected`)
            guard let mine = await snapshot(), !paused, let session = peers[k]?.session else { return }
            if session.answers(remote, with: mine.state, digest: mine.digest, now: now) { sendLedger(mine, to: k) }
            confirm(k)
        case .ack(let digest):
            guard partner(peer) != nil else { return }
            // this phone's ledger as it is now, worked out first if a save dropped it: the ack ends a
            // failure of theirs when they hold it (`peerHas(current:)`), and it is stamped against it, or
            // an ack landing in that moment would never stamp
            _ = await snapshot()
            AppLog.info(.sync, "Máy kia đã lưu sổ chi", ["peer": Self.peerTag(peer.key)])
            peers[k]?.session.peerHas(LedgerDigest(digest), current: cached?.digest)
            confirm(k)
        case .nack(let digest, let reason):
            guard partner(peer) != nil else { return }
            // sent again at the next heartbeat, not from here: a write that keeps failing costs one
            // ledger every 15 s, not a loop
            peers[k]?.session.peerFailed(LedgerDigest(digest), reason: reason)
            // the other phone's `localizedDescription` of its failed write, nothing else (`.state` above), cut short
            AppLog.error(.sync, "Máy kia không lưu được sổ chi", ["peer": Self.peerTag(peer.key), "error": String(reason.prefix(200))])
        case .touched:
            AppLog.info(.sync, "Chạm hai máy", ["peer": Self.peerTag(peer.key)])
            if partner(peer) != nil {
                felt()
                await push(to: k, force: true)
            } else if let d = closeness[k], d < 0.3 {
                // the touch is the yes, on this side too, when this side measured it as well
                felt()
                pair(peer.key)
            }
        }
    }

    /// Stamps "Đã đồng bộ" when the session with this peer says synced: it holds this phone's ledger
    /// as it is now, and this phone wrote its last one.
    private func confirm(_ k: Int) {
        guard let peer = peers[k], let p = partner(peer),
              peer.session.standing(current: cached?.digest) == .synced
        else { return }
        stamp(p.name)
    }

    private func stamp(_ peer: String) {
        let s = Stamp(name: peer, at: Date())
        lastSync = s
        Shared.defaults.set(try? JSONEncoder().encode(s), forKey: Key.last)
    }

    /// Something in the ledger was saved: send it if it changed, a moment later so a burst of saves
    /// goes as one.
    func ledgerChanged() {
        changed()
        guard link != nil else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.pushAll()
        }
    }

    /// The ledger read before is out of date.
    private func changed() {
        cached = nil
        generation += 1
    }

    /// Whether a save may have changed the ledger: it inserted, changed or deleted an expense or a
    /// deletion record. A save that does not say what it touched counts as one that may have.
    nonisolated static func touchesLedger(_ info: [AnyHashable: Any]?) -> Bool {
        let keys = [ModelContext.NotificationKey.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        var told = false
        for key in keys {
            guard let ids = info?[key.rawValue] as? [PersistentIdentifier] else { continue }
            told = true
            if ids.contains(where: { $0.entityName == "Expense" || $0.entityName == "ExpenseTombstone" }) { return true }
        }
        return !told
    }

    /// The heartbeat, or a burst of saves settled: each paired phone that needs it gets the ledger.
    private func pushAll() async {
        for (k, peer) in peers where partner(peer) != nil { await push(to: k) }
    }

    /// Sends this phone's ledger to one peer when its session says so, or regardless (`force`: the
    /// connection's first send, a touch).
    private func push(to k: Int, force: Bool = false) async {
        guard !paused, let mine = await snapshot(), !paused, let session = peers[k]?.session else { return }
        guard force || session.needsSend(current: mine.digest, now: Date()) else { return }
        sendLedger(mine, to: k)
    }

    /// The ledger and its digest, from one snapshot; noted as sent only once the radio took it.
    private func sendLedger(_ mine: Snapshot, to k: Int) {
        if seal(.state(mine.state, digest: mine.digest.value), to: k) {
            if let peer = peers[k] { AppLog.info(.sync, "Gửi sổ chi", ["peer": Self.peerTag(peer.key), "rows": "\(mine.state.records.count)"]) }
            peers[k]?.session.didSend(mine.digest, at: Date())
        }
    }

    /// This phone's ledger and its digest, read from the records only when an expense changed since
    /// the last read. The digest is worked out off the main actor; one finished after a save is used
    /// for what it was taken from, not kept. Nil when the records could not be read: no digest, so
    /// nothing is sent, answered or stamped (an empty ledger read in its place would be acked and
    /// stamped synced though no row went).
    private func snapshot() async -> Snapshot? {
        if let cached { return cached }
        guard let context else { return nil }
        let state: LedgerState
        do {
            state = try Ledger.state(context)
        } catch {
            AppLog.error(.sync, "Không đọc được sổ chi", ["error": error.localizedDescription])
            return nil
        }
        let taken = generation
        guard let digest = await Self.digest(state) else {
            AppLog.error(.sync, "Không tính được dấu sổ chi")
            return nil
        }
        let s = Snapshot(state: state, digest: digest)
        if taken == generation { cached = s }
        return s
    }

    /// SHA-256 of the ledger as JSON with sorted keys (its rows already in id order), in hex: the same
    /// ledger gives the same digest on either phone. It encodes the whole ledger, so not on main.
    @concurrent private nonisolated static func digest(_ state: LedgerState) async -> LedgerDigest? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(state) else { return nil }
        return LedgerDigest(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    /// Signs a message for one peer, numbered so it cannot be played again; false when it did not go.
    @discardableResult
    private func seal(_ payload: SyncPayload, to k: Int) -> Bool {
        guard var peer = peers[k], let body = try? JSONEncoder().encode(payload) else { return false }
        peer.out += 1
        peers[k] = peer
        return send(.sealed(n: peer.out, body: body, mac: SyncIdentity.mac(peer.out, body, peer.secret)), to: k)
    }

    /// False when the radio did not take it.
    @discardableResult
    private func send(_ message: SyncMessage, to k: Int) -> Bool {
        guard let link, let data = try? JSONEncoder().encode(message) else { return false }
        return link.send(data, to: k)
    }

    // MARK: - The touch

    private func measured(_ session: ObjectIdentifier, _ metres: Float?) {
        guard let k = sessions.first(where: { ObjectIdentifier($0.value) == session })?.key else { return }
        closeness[k] = metres
        if let peer = peers[k], nearby?.key == peer.key { distance = metres }
        // close enough that a touch may follow (the same 30 cm the pairing reads as measured on this side):
        // the haptic of the touch is readied, a few seconds each time
        if let metres, metres < 0.3 { Haptic.prepare(.done) }
        guard let metres, metres < Self.touch, Date().timeIntervalSince(lastTouch) > 4, let peer = peers[k] else { return }
        lastTouch = Date()
        AppLog.info(.sync, "Chạm hai máy", ["peer": Self.peerTag(peer.key)])
        felt()
        seal(.touched, to: k)
        if partner(peer) != nil {
            Task { await push(to: k, force: true) }
        } else {
            pair(peer.key)
        }
    }

    private func felt() {
        Haptic.done()
    }

    // MARK: - Status

    /// Where the sync stands, for the line on the Spend tab and the sync page.
    enum Status: Equatable {
        /// syncing is turned off
        case off
        /// a rehearsal runs
        case paused
        /// no paired phone near, and none synced with yet
        case waiting(name: String?)
        /// a paired phone near; this phone's ledger as it is now is not known to be on it yet
        case sending(name: String)
        /// when a paired phone last held this phone's ledger as it was, this phone having written its last
        case synced(name: String, at: Date)
        /// a build before acknowledgements was sent this ledger; whether it holds it cannot be known
        case unconfirmed(name: String)
        /// the paired phone could not write this one's ledger (its nack), and why
        case failed(name: String, reason: String)
        /// this phone could not write the paired phone's ledger, and why
        case unsaved(name: String, reason: String)

        var text: String {
            switch self {
            case .off: "Đồng bộ với máy kia đang tắt"
            case .paused: "Đồng bộ tạm dừng trong lúc chạy thử"
            case .waiting(let name): "Chờ \(name ?? "máy kia") mở JP27 ở gần"
            case .sending(let name): "\(name) ở gần · đang đồng bộ"
            case .synced(let name, let at): "Đã đồng bộ với \(name) \(LedgerSync.when(at))"
            case .unconfirmed(let name): "Đã gửi cho \(name) · chờ máy kia cập nhật app để xác nhận"
            case .failed(let name, let reason): "\(name) chưa lưu được: \(reason)"
            case .unsaved(let name, let reason): "Chưa lưu được sổ chi của \(name): \(reason)"
            }
        }

        /// a write that failed, on either phone
        var isProblem: Bool {
            switch self {
            case .failed, .unsaved: true
            default: false
            }
        }
    }

    /// Where the sync stands. With paired phones connected, the worst of them, named
    /// (`LedgerSyncSession.Standing.worst`), so "đã đồng bộ" only when every one is synced; away from
    /// them, the last sync, or who to wait for.
    var standing: Status {
        guard enabled else { return .off }
        if paused { return .paused }
        let current = cached?.digest
        let near = paired.compactMap { p in
            peers.values.first { $0.key == p.key }.map { (name: p.name, standing: $0.session.standing(current: current)) }
        }
        if let worst = LedgerSyncSession.Standing.worst(near, by: { $0.standing }) {
            let name = worst.item.name
            switch worst.standing {
            case .unsaved(let reason): return .unsaved(name: name, reason: reason)
            case .failed(let reason): return .failed(name: name, reason: reason)
            case .unconfirmed: return .unconfirmed(name: name)
            case .sending: return .sending(name: name)
            case .synced:
                // stamped as it became synced
                guard let lastSync else { return .sending(name: name) }
                return .synced(name: lastSync.name, at: lastSync.at)
            }
        }
        if let lastSync { return .synced(name: lastSync.name, at: lastSync.at) }
        return .waiting(name: paired.first?.name)
    }

    /// One quiet line for the Spend tab: "Đã đồng bộ với Lan lúc 21:04", ending with how many rows
    /// of the paired phone's last ledger were not taken: " · không nhận 1 khoản".
    var status: String {
        let s = standing
        guard rejected > 0, s != .off, s != .paused else { return s.text }
        return "\(s.text) · không nhận \(rejected) khoản"
    }

    /// "lúc 21:04", or "lúc 21:04 ngày 19/10" on another day (Japan time, as the trip reads).
    static func when(_ date: Date) -> String {
        let clock = TripTime.clock(date)
        let day = TripTime.isoDate(of: date)
        guard day != TripTime.isoDate(of: Date()) else { return "lúc \(clock)" }
        let p = day.split(separator: "-")
        guard p.count == 3, let d = Int(p[2]), let m = Int(p[1]) else { return "lúc \(clock)" }
        return "lúc \(clock) ngày \(d)/\(m)"
    }
}

// MARK: - Keys

/// This install's key pair for the sync. The private half is made on the phone the first time it is
/// needed, kept in the Keychain for this device only, and never leaves it.
enum SyncIdentity {
    private static let service = "tech.delphyra.jp27.sync"
    private static let account = "identity"

    static let key: Curve25519.KeyAgreement.PrivateKey = stored() ?? made()

    static var publicKey: Data { key.publicKey.rawRepresentation }

    /// A short name for a public key, sent with invitations so a paired phone knows who invites.
    static func fingerprint(_ publicKey: Data) -> Data {
        Data(SHA256.hash(data: publicKey).prefix(16))
    }

    static func random(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// The key the two ends of one connection share: from the two key pairs, which only the two
    /// phones can do, and the two random numbers of this connection, so a message recorded on one
    /// connection is worth nothing on the next.
    static func secret(with theirs: Data, nonces a: Data, _ b: Data) -> SymmetricKey? {
        guard let other = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirs),
              let shared = try? key.sharedSecretFromKeyAgreement(with: other)
        else { return nil }
        return shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: sorted(a, b),
                                              sharedInfo: Data("jp27 ledger sync 1".utf8) + sorted(publicKey, theirs),
                                              outputByteCount: 32)
    }

    static func mac(_ n: UInt64, _ body: Data, _ secret: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: signed(n, body), using: secret))
    }

    /// Checked in constant time.
    static func isValid(_ mac: Data, _ n: UInt64, _ body: Data, _ secret: SymmetricKey) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: signed(n, body), using: secret)
    }

    /// Six digits for a pair of phones, "482 913": both phones show the same only if each holds
    /// the other's real key, so a phone in between, passing on keys of its own, shows up as a
    /// difference.
    static func code(with theirs: Data) -> String {
        let digest = SHA256.hash(data: Data("jp27 pair".utf8) + sorted(publicKey, theirs))
        let n = digest.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) } % 1_000_000
        let s = String(format: "%06u", n)
        return "\(s.prefix(3)) \(s.suffix(3))"
    }

    private static func signed(_ n: UInt64, _ body: Data) -> Data {
        withUnsafeBytes(of: n.bigEndian) { Data($0) } + body
    }

    /// Two values in one order whichever phone puts them together.
    private static func sorted(_ a: Data, _ b: Data) -> Data {
        a.lexicographicallyPrecedes(b) ? a + b : b + a
    }

    private static func stored() -> Curve25519.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    /// A new key pair, saved. Should the Keychain refuse it, the key lives until the app quits and
    /// the other phone is asked about again next time.
    private static func made() -> Curve25519.KeyAgreement.PrivateKey {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(item as CFDictionary)
        var add = item
        add[kSecValueData as String] = key.rawRepresentation
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        return key
    }
}

// MARK: - Nearby Interaction

extension LedgerSync: NISessionDelegate {
    // delivered on the main queue (`delegateQueue = .main`)
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        let id = ObjectIdentifier(session)
        let metres = nearbyObjects.first?.distance
        MainActor.assumeIsolated { measured(id, metres) }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        let id = ObjectIdentifier(session)
        MainActor.assumeIsolated { measured(id, nil) }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        if let config = session.configuration { session.run(config) }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: any Error) {
        let id = ObjectIdentifier(session)
        MainActor.assumeIsolated {
            // permission refused, or the session ended: the phones still sync, without the touch
            if let key = sessions.first(where: { ObjectIdentifier($0.value) == id })?.key {
                sessions[key] = nil
                closeness[key] = nil
            }
        }
    }
}

// MARK: - Messages

// What the phones say to each other (`SyncMessage`, `SyncPayload`) is in TripKit (`SyncWire.swift`),
// where tests pin the shapes that this build and the one before acknowledgements both read.

/// MultipeerConnectivity, kept off the main actor: its callbacks come on its own queues, and leave
/// here only as plain values, in order, through `onEvent`. Each phone advertises and browses; of
/// two phones, the one with the greater random number (new each time the link starts) invites, so
/// they open one session, not two. Phones near by see the service, "JP27" and that number, nothing
/// that stays the same from one day to the next. An invitation carries the inviter's key
/// fingerprint and is taken only from a paired phone, or from any while this phone's sync page is
/// open to pair (`admit`). The session is encrypted; who is who is settled above it, by keys.
nonisolated final class SyncLink: NSObject, @unchecked Sendable, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    enum Event: Sendable {
        case connected(Int)
        case disconnected(Int)
        case received(Int, Data)
    }

    struct Admission: Sendable {
        var open = false
        var prints: Set<Data> = []
    }

    /// `_jp27-sync._tcp` and `_udp` in NSBonjourServices
    static let service = "jp27-sync"

    private let me: MCPeerID
    /// this phone's key fingerprint, sent with its invitations
    private let fingerprint: Data
    private let draw: String
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let onEvent: @Sendable (Event) -> Void
    private let admission = OSAllocatedUnfairLock(initialState: Admission())

    init(peer: MCPeerID, fingerprint: Data, onEvent: @escaping @Sendable (Event) -> Void) {
        me = peer
        self.fingerprint = fingerprint
        draw = UUID().uuidString
        self.onEvent = onEvent
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["n": draw], serviceType: Self.service)
        browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.service)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    /// Whose invitations to take: the fingerprints of paired phones, and anyone while `open`.
    func admit(open: Bool, prints: Set<Data>) {
        admission.withLock { $0 = Admission(open: open, prints: prints) }
    }

    /// A peer is its `MCPeerID.hash`: the same for the same peer whichever object reports it.
    /// True once the session took it for delivery: not that the peer has it (that is its ack).
    func send(_ data: Data, to key: Int) -> Bool {
        let to = session.connectedPeers.filter { $0.hash == key }
        guard !to.isEmpty else { return false }
        do {
            try session.send(data, toPeers: to, with: .reliable)
            return true
        } catch {
            let reason = error.localizedDescription
            AppLog.error(.sync, "Không gửi được sổ chi", ["error": reason])
            return false
        }
    }

    // MARK: MCSessionDelegate

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected: onEvent(.connected(peerID.hash))
        case .notConnected: onEvent(.disconnected(peerID.hash))
        default: break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // a whole ledger is a few hundred kilobytes at most; anything far larger is not one
        guard data.count < 8_000_000 else { return }
        onEvent(.received(peerID.hash, data))
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}

    // MARK: MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let take = admission.withLock { a in a.open || context.map { a.prints.contains($0) } == true }
        invitationHandler(take, take ? session : nil)
    }

    // MARK: MCNearbyServiceBrowserDelegate

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard peerID != me, !session.connectedPeers.contains(peerID) else { return }
        // the greater number invites; the other waits for it
        if let theirs = info?["n"], theirs >= draw { return }
        browser.invitePeer(peerID, to: session, withContext: fingerprint, timeout: 20)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
