import Foundation
import Observation
import Speech
import Translation
import TripKit

/// What is ready for no signal, item by item (`ReadyItem`), for the offline page's list and Settings' summary
/// (`Readiness`). Owned by `Downloads` (`downloads.readiness`).
///
/// Two kinds of item:
/// - **live**: the maps and the photos, read from `OfflineMaps` and `OfflinePhotos` each time `states` is read. No
///   disk, no writes; a download's progress moves them through observation alone.
/// - **read**: the day maps, the Fuji pictures, the forecasts and the two language packs, read from the disk and the
///   system by `refresh()`, one run at a time (`Coalescer`), each file check off the main thread. Counting never
///   draws, decodes or keeps a picture, and counts only what is on disk (`MapSnapshots.isOnDisk`,
///   `FujiTerrainPictures.isOnDisk`): a picture a page drew with no signal is held only in memory, which a launch with
///   no signal does not find.
///
/// `refresh()` is asked for on discrete changes only (the page or Settings opening, a download ending, the app coming
/// back, a pack installed), never on a progress tick.
@Observable final class OfflineReadiness {
    private let maps: OfflineMaps
    private let photos: OfflinePhotos

    /// the read items, as the last refresh found them
    private var read: [ReadyItem: ReadyState] = [:]
    /// a refresh has ended: until then Settings says nothing of what it cannot back
    private(set) var checked = false
    /// the oldest of the forecasts counted, when any is kept ("cập nhật 9:05")
    private(set) var oldestForecast: Date?
    /// how far the speech pack asked for here is, while `installSpeech` runs
    private var speechFraction: Double?
    /// why the last install of the speech pack failed: said until the next one, or until the pack is there
    private var speechError: String?
    /// `installSpeech` is running, from its first line to its last
    @ObservationIgnored private var installing = false
    @ObservationIgnored private lazy var refresher = Coalescer { [weak self] in await self?.readAll() }
    /// each item's state as last logged, by kind ("ready", "missing", …): the log hears of a change of kind only
    @ObservationIgnored private var logged: [ReadyItem: String] = [:]

    /// Made inside `Downloads`, itself made inside `AppModel.shared`: nothing here reads `AppModel.shared` until later.
    init(maps: OfflineMaps, photos: OfflinePhotos) {
        self.maps = maps
        self.photos = photos
    }

    /// Every item that can be told now: the read ones as the last refresh found them, the live ones as they are. An
    /// item missing from it has not been read yet (`Readiness` counts it as not ready).
    var states: [ReadyItem: ReadyState] {
        var s = read
        s[.maps] = mapsState
        s[.photos] = photosState
        if let speechFraction { s[.speech] = online ? .working(speechFraction) : .waitingForNetwork }
        return s
    }

    private var online: Bool { AppModel.shared.network.raw }

    /// Every area, "Toàn tuyến" among them, complete for the build the map reads. Nothing until MapLibre has read its
    /// packs and the areas are known (no areas would read as all complete).
    private var mapsState: ReadyState? {
        guard maps.ready, !maps.areas.isEmpty else { return nil }
        let ids = Set(maps.areas.map(\.id))
        let done = maps.complete.intersection(ids).count
        if done == ids.count { return .ready }
        if ids.contains(where: { maps.phases[$0]?.isUnderWay == true }) {
            return online ? .working(maps.fraction(of: ids)) : .waitingForNetwork
        }
        return .missing(done: done, total: ids.count)
    }

    /// Every remote photo on disk. Nothing until they are counted.
    private var photosState: ReadyState? {
        guard photos.counted else { return nil }
        if photos.running { return online ? .working(photos.fraction) : .waitingForNetwork }
        if photos.complete { return .ready }
        return .missing(done: photos.saved, total: photos.total)
    }

    // MARK: Reading

    /// Reads the day maps, the Fuji pictures, the forecasts and the language packs again: now, or once more after the
    /// run going on (which may not have seen the change that asks for this one).
    func refresh() async {
        await refresher.flush()
    }

    private func readAll() async {
        let model = AppModel.shared
        var next = read
        next[.dayMaps] = await dayMaps(model)
        next[.fuji] = await fuji(model)
        let forecasts = await forecasts(model)
        next[.forecasts] = forecasts.state
        next[.translation] = await Self.translationState()
        next[.speech] = speechState(await Self.speechReading())
        if next != read { read = next }
        if forecasts.oldest != oldestForecast { oldestForecast = forecasts.oldest }
        if !checked { checked = true }
        log(states)
    }

    /// Every day, the alternative ones with them (one may be swapped in with no signal), with its map's picture on disk
    /// at the page size the home measured last.
    private func dayMaps(_ model: AppModel) async -> ReadyState {
        guard let page = Prefetch.lastPage else { return .needsSetup("Mở trang Hôm nay một lần") }
        let store = model.store
        var seen = Set<String>()
        let days = (store.trip.days + store.trip.altDays).filter { seen.insert($0.key).inserted }
        var done = 0
        for day in days {
            // nil: the page's light or dark cannot be told yet (its photograph's colour is not read), so not ready
            guard let request = await Prefetch.dayMapRequest(day, photo: HomePicks.photo(for: day, store: store), model: model, page: page)
            else { continue }
            if await MapSnapshots.shared.isOnDisk(request) { done += 1 }
        }
        return done == days.count ? .ready : .missing(done: done, total: days.count)
    }

    /// Every area hero and viewpoint card, light and dark (R-600), at the sizes kept; or which page to open first.
    private func fuji(_ model: AppModel) async -> ReadyState {
        switch FujiTerrainPictures.wanted(guide: model.guide.fuji, store: model.store) {
        case .needs(let slot):
            return .needsSetup(slot.setup)
        case .pictures(let requests):
            var done = 0
            for request in requests {
                if await FujiTerrainPictures.shared.isOnDisk(request) { done += 1 }
            }
            return done == requests.count ? .ready : .missing(done: done, total: requests.count)
        }
    }

    /// The summit's forecast and every viewpoint's, fresh by the real clock (never the rehearsal's: they are stamped
    /// with it), and the oldest of them.
    private func forecasts(_ model: AppModel) async -> (state: ReadyState, oldest: Date?) {
        let keys = ["summit"] + model.guide.fuji.spots.map(\.id)
        var fetched: [Date?] = []
        for key in keys { fetched.append(await model.forecasts.fetched(key)) }
        return (Readiness.forecasts(fetched: fetched, now: Date()), fetched.compactMap { $0 }.min())
    }

    /// The Japanese–Vietnamese pack, as the Talk pages ask it (`TalkTranslator`). Read and judged in one place off the
    /// main actor: `LanguageAvailability` is not Sendable, and only the answer leaves.
    @concurrent private nonisolated static func translationState() async -> ReadyState {
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: "ja"), to: Locale.Language(identifier: "vi"))
        if status == .installed { return .ready }
        if status == .unsupported { return .unsupported("Máy này chưa dịch được Nhật sang Việt") }
        return .missing(done: nil, total: nil)
    }

    /// The Japanese speech pack, for the transcriber the listener runs (`TalkListener.transcriber`).
    private nonisolated enum SpeechReading: Sendable {
        case unsupported, installed, downloading, supported
    }

    /// Asked in one place off the main actor: `AssetInventory.Status` is not Sendable, so only this answer leaves.
    @concurrent private nonisolated static func speechReading() async -> SpeechReading {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP")) else { return .unsupported }
        let status = await AssetInventory.status(forModules: [TalkListener.transcriber(locale: locale)])
        if status == .installed { return .installed }
        if status == .downloading { return .downloading }
        if status == .supported { return .supported }
        return .unsupported
    }

    private func speechState(_ reading: SpeechReading) -> ReadyState {
        switch reading {
        case .unsupported:
            return .unsupported("Máy này chưa nghe được tiếng Nhật")
        case .installed:
            speechError = nil
            return .ready
        case .downloading:
            // the system downloads it (asked by the listener, or trying again by itself after a failed attempt):
            // how far is not told
            speechError = nil
            return online ? .working(0) : .waitingForNetwork
        case .supported:
            return speechError.map { .failed($0) } ?? .missing(done: nil, total: nil)
        }
    }

    // MARK: The speech pack

    /// Downloads and installs the Japanese speech pack for the listener's transcriber, its progress followed about
    /// once a second; a failure is said on the row (`failed`) until the next try. A second tap while one runs does
    /// nothing.
    func installSpeech() async {
        // set before the first wait, so a second tap during the locale check finds it; cleared on every way out
        guard !installing else { return }
        installing = true
        defer { installing = false }
        speechError = nil
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP")) else {
            read[.speech] = .unsupported("Máy này chưa nghe được tiếng Nhật")
            return
        }
        speechFraction = 0
        AppLog.info(.offline, "Tải gói nghe tiếng Nhật", ["status": "start"])
        do {
            // nil: already installed
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [TalkListener.transcriber(locale: locale)]) {
                let progress = request.progress
                let follow = Task { [weak self] in
                    while !Task.isCancelled {
                        let now = progress.fractionCompleted
                        if let self, self.speechFraction != nil, self.speechFraction != now { self.speechFraction = now }
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
                defer { follow.cancel() }
                try await request.downloadAndInstall()
            }
            AppLog.info(.offline, "Tải gói nghe tiếng Nhật", ["status": "installed"])
        } catch {
            speechError = error.localizedDescription
            AppLog.warning(.offline, "Không tải được gói nghe tiếng Nhật", ["error": error.localizedDescription])
        }
        speechFraction = nil
        await refresh()
    }

    // MARK: The log

    /// One line per item whose kind of state changed since it was last logged: a fraction or a count moving is no change.
    private func log(_ states: [ReadyItem: ReadyState]) {
        for item in ReadyItem.allCases {
            guard let state = states[item] else { continue }
            let kind = Self.kind(state)
            guard logged[item] != kind else { continue }
            logged[item] = kind
            var fields = ["item": item.rawValue, "state": kind]
            if case .missing(let done, let total) = state {
                if let done { fields["done"] = "\(done)" }
                if let total { fields["total"] = "\(total)" }
            }
            if case .failed(let why) = state { fields["error"] = why }
            AppLog.info(.offline, "Sẵn sàng khi mất sóng", fields)
        }
    }

    private static func kind(_ state: ReadyState) -> String {
        switch state {
        case .ready: "ready"
        case .missing: "missing"
        case .working: "working"
        case .waitingForNetwork: "waiting"
        case .failed: "failed"
        case .unsupported: "unsupported"
        case .needsSetup: "setup"
        }
    }
}
