import Foundation
import MultipeerConnectivity
import NearbyInteraction
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
/// Third-party apps cannot send by AirDrop on their own, nor take in an AirDrop without the share
/// sheet and an accept on the other side: hence this, and the CSV only as a fallback.
@Observable final class LedgerSync: NSObject {
    /// the one the app runs, for the records' helpers to nudge
    static weak var shared: LedgerSync?

    struct Partner: Codable, Hashable, Identifiable {
        var install: String
        var name: String
        var id: String { install }
    }

    struct Stamp: Codable, Equatable {
        var name: String
        var at: Date
    }

    /// on while the travellers want the phones to sync; asking for local network and nearby
    /// devices waits until they turn it on
    private(set) var enabled: Bool
    /// this phone's name on the other phone
    private(set) var name: String
    private(set) var paired: [Partner]
    /// a paired phone connected now
    private(set) var nearby: Partner?
    /// a phone near by with the app open, not yet said yes to
    private(set) var asking: Partner?
    /// metres to the nearby phone, when both have UWB
    private(set) var distance: Float?
    private(set) var lastSync: Stamp?
    /// rows folded as copies of the other phone's since the app opened
    private(set) var folded = 0
    /// both phones need UWB for the touch; this one has it
    var supportsTouch: Bool { NISession.deviceCapabilities.supportsPreciseDistanceMeasurement }

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var link: SyncLink?
    @ObservationIgnored private var events: AsyncStream<SyncLink.Event>.Continuation?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var saves: (any NSObjectProtocol)?
    /// connected peer → who it said it is
    @ObservationIgnored private var peers: [Int: Partner] = [:]
    /// what was last sent to each peer, so an unchanged ledger is not sent again
    @ObservationIgnored private var sent: [Int: LedgerState] = [:]
    @ObservationIgnored private var sessions: [Int: NISession] = [:]
    @ObservationIgnored private var closeness: [Int: Float] = [:]
    @ObservationIgnored private var lastTouch = Date.distantPast
    @ObservationIgnored private var declined: Set<String> = []

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

    /// Foreground: look for the other phone, if syncing is on.
    func activate(context: ModelContext) {
        self.context = context
        if saves == nil {
            // every save of the records may be a change to the ledger; unchanged ledgers are not sent
            saves = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.ledgerChanged() }
            }
        }
        if enabled { begin() }
    }

    /// Background: the link does not survive it; it starts again in the foreground.
    func deactivate() {
        end()
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        Shared.defaults.set(on, forKey: Key.enabled)
        on ? begin() : end()
    }

    func rename(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != name else { return }
        name = clean
        Shared.defaults.set(clean, forKey: Key.name)
        // the name is the link's: start it again under the new one
        if link != nil { end(); begin() }
    }

    // MARK: - Pairing

    /// Yes to the phone asking: share with it from now on.
    func accept() {
        guard let p = asking else { return }
        pair(p)
    }

    /// Not now: not asked again until the app opens again.
    func decline() {
        guard let p = asking else { return }
        declined.insert(p.install)
        asking = nil
    }

    func unpair(_ p: Partner) {
        paired.removeAll { $0.install == p.install }
        savePaired()
        if nearby?.install == p.install { nearby = nil; distance = nil }
    }

    private func pair(_ p: Partner) {
        if let i = paired.firstIndex(where: { $0.install == p.install }) {
            paired[i].name = p.name
        } else {
            paired.append(p)
        }
        savePaired()
        if asking?.install == p.install { asking = nil }
        for (key, peer) in peers where peer.install == p.install {
            nearby = peer
            distance = closeness[key]
            push(to: key, force: true)
        }
    }

    private func isPaired(_ install: String) -> Bool {
        paired.contains { $0.install == install }
    }

    private func savePaired() {
        Shared.defaults.set(try? JSONEncoder().encode(paired), forKey: Key.paired)
    }

    // MARK: - The link

    private func begin() {
        guard link == nil, context != nil else { return }
        let (stream, continuation) = AsyncStream.makeStream(of: SyncLink.Event.self)
        events = continuation
        // one queue for everything the link reports, so a peer's hello is always handled before its ledger
        listener = Task { [weak self] in
            for await event in stream { self?.handle(event) }
        }
        let link = SyncLink(peer: peerID(), install: SpendLedgerFile.installID) { continuation.yield($0) }
        self.link = link
        link.start()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self?.pushAll()
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
        sent = [:]
        closeness = [:]
        nearby = nil
        asking = nil
        distance = nil
    }

    /// The same peer identity every launch, as MultipeerConnectivity asks, until the name changes.
    private func peerID() -> MCPeerID {
        // at most 63 bytes of UTF-8
        var display = ""
        for c in name where (display + String(c)).utf8.count <= 60 { display.append(c) }
        if display.isEmpty { display = "iPhone" }
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

    private func handle(_ event: SyncLink.Event) {
        switch event {
        case .connected(let key):
            var token: Data?
            if supportsTouch {
                let s = NISession()
                s.delegate = self
                s.delegateQueue = .main
                sessions[key] = s
                token = s.discoveryToken.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
            }
            send(.hello(install: SpendLedgerFile.installID, name: name, token: token), to: key)
        case .disconnected(let key):
            let gone = peers.removeValue(forKey: key)
            sessions.removeValue(forKey: key)?.invalidate()
            sent[key] = nil
            closeness[key] = nil
            if let gone, nearby?.install == gone.install, !peers.values.contains(where: { $0.install == gone.install }) {
                nearby = nil
                distance = nil
            }
            if let gone, asking?.install == gone.install { asking = nil }
        case .received(let key, let data):
            guard let message = try? JSONDecoder().decode(SyncMessage.self, from: data) else { return }
            receive(message, from: key)
        }
    }

    private func receive(_ message: SyncMessage, from key: Int) {
        switch message {
        case .hello(let install, let name, let token):
            let peer = Partner(install: install, name: name)
            peers[key] = peer
            if let token, let s = sessions[key],
               let t = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: token) {
                s.run(NINearbyPeerConfiguration(peerToken: t))
            }
            if isPaired(install) {
                pair(peer)
            } else if !declined.contains(install) {
                asking = peer
            }
        case .state(let remote):
            guard let peer = peers[key], isPaired(peer.install), let context else { return }
            let (merged, changes) = Ledger.merge(remote, into: context)
            folded += changes.folded.count
            stamp(peer.name)
            // what it lacked goes back; then both hold the same
            if merged != remote { send(.state(merged), to: key) }
            sent[key] = merged
        case .touched:
            guard let peer = peers[key] else { return }
            if isPaired(peer.install) {
                felt()
                push(to: key, force: true)
            } else if let d = closeness[key], d < 0.3 {
                // the touch is the yes, on this side too, when this side measured it as well
                felt()
                pair(peer)
            }
        }
    }

    private func stamp(_ peer: String) {
        let s = Stamp(name: peer, at: Date())
        lastSync = s
        Shared.defaults.set(try? JSONEncoder().encode(s), forKey: Key.last)
    }

    /// Something in the records was saved: send the ledger if it changed, a moment later so a burst
    /// of saves goes as one.
    func ledgerChanged() {
        guard link != nil else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.pushAll()
        }
    }

    private func pushAll() {
        for (key, peer) in peers where isPaired(peer.install) { push(to: key) }
    }

    private func push(to key: Int, force: Bool = false) {
        guard let context else { return }
        let state = Ledger.state(context)
        if !force, sent[key] == state { return }
        send(.state(state), to: key)
        sent[key] = state
    }

    private func send(_ message: SyncMessage, to key: Int) {
        guard let link, let data = try? JSONEncoder().encode(message) else { return }
        link.send(data, to: key)
    }

    // MARK: - The touch

    private func measured(_ session: ObjectIdentifier, _ metres: Float?) {
        guard let key = sessions.first(where: { ObjectIdentifier($0.value) == session })?.key else { return }
        closeness[key] = metres
        if let peer = peers[key], nearby?.install == peer.install { distance = metres }
        guard let metres, metres < Self.touch, Date().timeIntervalSince(lastTouch) > 4, let peer = peers[key] else { return }
        lastTouch = Date()
        felt()
        send(.touched, to: key)
        if isPaired(peer.install) {
            push(to: key, force: true)
        } else {
            pair(peer)
        }
    }

    private func felt() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Status

    /// One quiet line for the Spend tab: "Đã đồng bộ với Lan lúc 21:04".
    var status: String {
        guard enabled else { return "Đồng bộ với máy kia đang tắt" }
        if let nearby {
            if let lastSync, lastSync.name == nearby.name { return "\(nearby.name) ở gần · đã đồng bộ \(Self.when(lastSync.at))" }
            return "\(nearby.name) ở gần · đang đồng bộ"
        }
        if let lastSync { return "Đã đồng bộ với \(lastSync.name) \(Self.when(lastSync.at))" }
        if let first = paired.first { return "Chờ \(first.name) mở JP27 ở gần" }
        return "Chờ máy kia mở JP27 ở gần"
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

/// What the phones say to each other, as JSON.
nonisolated enum SyncMessage: Codable {
    /// who this is; the UWB token, when it has UWB
    case hello(install: String, name: String, token: Data?)
    /// the whole ledger
    case state(LedgerState)
    /// the phones touched
    case touched
}

/// MultipeerConnectivity, kept off the main actor: its callbacks come on its own queues, and leave
/// here only as plain values, in order, through `onEvent`. Each phone advertises and browses; of
/// two phones, the one with the greater install id invites, so they open one session, not two.
/// Invitations are accepted from any phone running the app: nothing is shared before the
/// travellers say yes (`LedgerSync.pair`), and the session is encrypted.
nonisolated final class SyncLink: NSObject, @unchecked Sendable, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    enum Event: Sendable {
        case connected(Int)
        case disconnected(Int)
        case received(Int, Data)
    }

    /// `_jp27-sync._tcp` and `_udp` in NSBonjourServices
    static let service = "jp27-sync"

    private let me: MCPeerID
    private let install: String
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let onEvent: @Sendable (Event) -> Void

    init(peer: MCPeerID, install: String, onEvent: @escaping @Sendable (Event) -> Void) {
        me = peer
        self.install = install
        self.onEvent = onEvent
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["install": install], serviceType: Self.service)
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

    /// A peer is its `MCPeerID.hash`: the same for the same peer whichever object reports it.
    func send(_ data: Data, to key: Int) {
        let to = session.connectedPeers.filter { $0.hash == key }
        guard !to.isEmpty else { return }
        try? session.send(data, toPeers: to, with: .reliable)
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
        onEvent(.received(peerID.hash, data))
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}

    // MARK: MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }

    // MARK: MCNearbyServiceBrowserDelegate

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard peerID != me, !session.connectedPeers.contains(peerID) else { return }
        // the greater install id invites; the other waits for it
        if let theirs = info?["install"], theirs >= install { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
