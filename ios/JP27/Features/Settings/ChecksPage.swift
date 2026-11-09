import SwiftUI
import TripKit
import UserNotifications

// Hỗ trợ › Kiểm tra (spec 2.3): eight checks run on a tap, each ok, a warning or an error with one short line, kept
// for the main page and the exported log, and written to the log.

/// A run of the checks as kept (`UserDefaults` "checks.last"): when, on the real clock, and the results in order.
nonisolated struct CheckRunStored: Codable, Sendable {
    let at: Date
    let results: [CheckResult]
}

/// The checks, one run at a time, for the whole app: leaving the page while a run goes on keeps its result, and the
/// main page's "Kiểm tra" follows the last one.
@Observable final class CheckRun {
    static let shared = CheckRun()
    private static let key = "checks.last"
    /// the forecast server, asked at its bare URL: any answer is an answer (`CheckReport.network`)
    private nonisolated static let forecastURL = URL(string: "https://api.open-meteo.com/v1/forecast")!

    private(set) var running = false
    /// the last run, nil until one ran (or when what was kept cannot be read: it is run again)
    private(set) var last: CheckRunStored? = CheckRun.load()

    /// "Ổn", "1 lỗi · 2 cảnh báo" or "Chưa chạy"
    var summary: String {
        last.map { CheckReport.summary($0.results) } ?? "Chưa chạy"
    }

    /// The last run as its JSON (keys sorted, the time in ISO 8601), for the exported log's `info.json`.
    var lastJSON: String? {
        guard let last, let data = try? Self.encoder.encode(last) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs the eight checks: what is read from the system first (the notification permission, the readiness list),
    /// the disk walk and the two servers at once and off the main thread, the rest here. Kept, then each result written
    /// to the log at its level.
    func run(model: AppModel) async {
        guard !running else { return }
        running = true
        defer { running = false }
        AppLog.info(.check, "Chạy kiểm tra")
        await model.notifications.refreshStatus()
        await model.downloads.readiness.refresh()
        // read here: what an `async let` evaluates runs in its child task, off the main actor
        let packBytes = Int64(clamping: model.offline.totalBytes)
        let online = model.network.raw
        let template = OfflineMaps.mapBuild.template
        async let storage = Self.storage(packBytes: packBytes)
        async let network = Self.network(online: online, template: template)
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests().count

        let downloads = model.downloads
        var results = [
            permissions(model),
            CheckReport.offline(downloads.readiness.states, mapsStale: !model.offline.stale.isEmpty,
                                downloading: downloads.busy ? downloads.fraction : nil),
            records(model),
            reminders(model, pending: pending),
            sync(model),
            CheckReport.clock(rehearsing: model.rehearsing),
        ]
        results.append(await storage)
        results.append(await network)
        let run = CheckRunStored(at: Date(), results: CheckReport.ordered(results))
        last = run
        if let data = try? Self.encoder.encode(run) { UserDefaults.standard.set(data, forKey: Self.key) }
        for r in run.results { Self.log(r) }
        AppLog.info(.check, "Kiểm tra xong", ["summary": CheckReport.summary(run.results)])
    }

    // MARK: The checks read here

    /// "4/5 đã bật · tắt: Ảnh", as the Quyền page counts them
    private func permissions(_ model: AppModel) -> CheckResult {
        let p = PermissionStates(model)
        let named: [(String, PermissionRow.State)] = [
            ("Vị trí", p.location), ("Thông báo", p.notifications), ("Báo thức", p.alarms), ("Ảnh", p.photos), ("Live Activities", p.live),
        ]
        let off = named.filter { !$0.1.isOn }.map(\.0)
        var line = "\(p.on)/\(p.all.count) đã bật"
        if !off.isEmpty { line += " · tắt: " + off.joined(separator: ", ") }
        return CheckResult(id: .permissions, level: off.isEmpty ? .ok : .warning, line: line)
    }

    /// The records opened, no save failing now, no pretend failure on (the full story of a failed opening is in Cần xem).
    private func records(_ model: AppModel) -> CheckResult {
        if Records.problem != nil { return CheckResult(id: .records, level: .error, line: "Sổ ghi chép mở lỗi") }
        if let issue = model.saveIssue { return CheckResult(id: .records, level: .warning, line: "Lỗi lưu đang treo: \(issue.what)") }
        if Records.pretending { return CheckResult(id: .records, level: .warning, line: "Đang giả lỗi lưu") }
        return CheckResult(id: .records, level: .ok, line: "Mở bình thường")
    }

    /// "12 nhắc đang chờ · đặt lại 3 lần"; the last alarm error is an error.
    private func reminders(_ model: AppModel, pending: Int) -> CheckResult {
        if let error = model.alarms.lastError {
            return CheckResult(id: .reminders, level: .error, line: "Lỗi báo thức: \(error)")
        }
        return CheckResult(id: .reminders, level: .ok, line: "\(pending) nhắc đang chờ · đặt lại \(model.reschedules) lần")
    }

    /// The last sync, by its time only: the stamp also holds the other phone's name, which never goes in a line.
    private func sync(_ model: AppModel) -> CheckResult {
        let sync = model.ledgerSync
        guard let at = sync.lastSync?.at else {
            return CheckResult(id: .sync, level: .warning, line: "Chưa đồng bộ lần nào")
        }
        return CheckResult(id: .sync, level: .ok, line: "Đã đồng bộ \(LedgerSync.when(at))" + (sync.enabled ? "" : " · đồng bộ đang tắt"))
    }

    // MARK: Off the main thread

    /// Free space for what matters to the user (`volumeAvailableCapacityForImportantUsage`), and what the app keeps:
    /// Application Support and Caches, each walked once. MapLibre's database is in Application Support, so the map
    /// packs are counted there and only named apart (`packBytes`, as Dùng khi mất sóng's "Đã tải"), never added.
    @concurrent nonisolated static func space() async -> (free: Int64?, app: Int64) {
        let free = try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        return (free, folderBytes(URL.applicationSupportDirectory) + folderBytes(URL.cachesDirectory))
    }

    @concurrent private nonisolated static func storage(packBytes: Int64) async -> CheckResult {
        let (free, app) = await space()
        var line = "app dùng \(bytes(app))"
        if packBytes > 0 { line += ", trong đó bản đồ \(bytes(packBytes))" }
        guard let free else {
            return CheckResult(id: .storage, level: .warning, line: "Không đọc được chỗ trống · " + line)
        }
        return CheckResult(id: .storage, level: CheckReport.storage(freeBytes: free), line: "Trống \(bytes(free)) · " + line)
    }

    /// Bytes of the regular files under `folder`, hidden ones too (MapLibre's `.mapbox`); a file that cannot be read is
    /// skipped, not the walk. Synchronous: the enumerator cannot be iterated in an async function.
    private nonisolated static func folderBytes(_ folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walk {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private nonisolated static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    /// No network: nothing is asked. Else the tile build the map reads (its first tile) and the forecast server, at
    /// once, each with 10 s in all.
    @concurrent private nonisolated static func network(online: Bool, template: String) async -> CheckResult {
        guard online else { return CheckReport.network(online: false, tiles: nil, forecast: nil) }
        async let forecast = ask(forecastURL)
        var tiles: CheckReport.Answer?
        if let url = firstTile(template) { tiles = await ask(url) }
        return CheckReport.network(online: true, tiles: tiles, forecast: await forecast)
    }

    /// The build's tile 0/0/0, as the launch's check asks it (`OfflineMaps.checkPinnedTiles`); nil for a template that
    /// is not an https URL with `{z}/{x}/{y}` (the "pinned" stand-in, a template of another shape).
    private nonisolated static func firstTile(_ template: String) -> URL? {
        let path = template.replacingOccurrences(of: "{z}/{x}/{y}", with: "0/0/0")
        guard !path.contains("{"), !path.contains("}"), let url = URL(string: path), url.scheme == "https", url.host() != nil else { return nil }
        return url
    }

    /// A HEAD: the status when the server asked answered, `elsewhere` when another host did (a login page the request
    /// was sent on to), `none` with no answer at all.
    @concurrent private nonisolated static func ask(_ url: URL) async -> CheckReport.Answer {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await probe.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .none }
            guard http.url?.host() == url.host() else { return .elsewhere }
            return .status(http.statusCode)
        } catch {
            return .none
        }
    }

    /// Asks what the server says now: nothing cached, 10 s for the whole request, no waiting for a network to come.
    private nonisolated static let probe: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.timeoutIntervalForResource = 10
        c.waitsForConnectivity = false
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    // MARK: Kept

    private nonisolated static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private nonisolated static func load() -> CheckRunStored? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(CheckRunStored.self, from: data)
    }

    private static func log(_ r: CheckResult) {
        let fields = ["id": r.id.rawValue, "line": r.line]
        switch r.level {
        case .ok: AppLog.info(.check, "Kết quả kiểm tra", fields)
        case .warning: AppLog.warning(.check, "Kết quả kiểm tra", fields)
        case .error: AppLog.error(.check, "Kết quả kiểm tra", fields)
        }
    }

    /// "14:03 ngày 9/11", on the phone's clock
    static func when(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute, .day, .month], from: date)
        return "\(c.hour ?? 0):\(String(format: "%02d", c.minute ?? 0)) ngày \(c.day ?? 0)/\(c.month ?? 0)"
    }
}

/// Settings › Hỗ trợ › Kiểm tra.
struct ChecksPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let run = CheckRun.shared
        Section {
            Button {
                Task { await run.run(model: model) }
            } label: {
                HStack {
                    Text(run.running ? "Đang kiểm tra…" : "Chạy kiểm tra")
                    Spacer()
                    if run.running { ProgressView() }
                }
            }
            .disabled(run.running)
        }
        if let last = run.last {
            Section {
                ForEach(last.results, id: \.id) { CheckRow(result: $0) }
            } footer: {
                Text("Lần gần nhất: \(CheckRun.when(last.at)).")
            }
        }
    }
}

/// One check: ✓, ! or ✕ in its colour, its name, its line.
private struct CheckRow: View {
    let result: CheckResult

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.name(result.id))
                Text(result.line).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            switch result.level {
            case .ok: SettingsIcon(symbol: "checkmark", tint: .green)
            case .warning: SettingsIcon(symbol: "exclamationmark", tint: .orange)
            case .error: SettingsIcon(symbol: "xmark", tint: .red)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(result.level == .ok ? "Ổn" : result.level == .warning ? "Cảnh báo" : "Lỗi"))
    }

    private static func name(_ id: CheckID) -> String {
        switch id {
        case .permissions: "Quyền"
        case .offline: "Dùng khi mất sóng"
        case .storage: "Bộ nhớ"
        case .records: "Sổ ghi chép"
        case .reminders: "Nhắc giờ và báo thức"
        case .sync: "Đồng bộ"
        case .network: "Mạng"
        case .clock: "Đồng hồ"
        }
    }
}
