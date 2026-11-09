import SwiftUI
import TripKit

// Dùng khi mất sóng: what is ready for no signal, item by item, and the map areas one level down.

// MARK: - Offline

/// Where one area is, as its row says it.
private enum AreaStatus: Equatable {
    case checking, idle, stale, complete, preparing
    case downloading(Double), waiting(Double), paused(Double)
    /// downloading, and MapLibre's last error, while it tries again
    case failing(Double, String)
    /// its pack could not be made: why, and "Thử lại"
    case failed(String)
}

/// What is ready for no signal, item by item (`OfflineReadiness`), each with its state and, while it is missing, its
/// own download. Downloads belong to the app (`Downloads`), so this page only shows where they are: leave it, use
/// the rest of the app, come back, and it shows the truth. The map areas are one level down (`OfflineMapsPage`).
struct OfflinePage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// the translation pack's download, whose system prompt comes up over this page
    @State private var translator = TalkTranslator()

    var body: some View {
        let downloads = model.downloads
        let readiness = downloads.readiness
        let states = readiness.states
        SettingsPage(title: "Dùng khi mất sóng") {
            if downloads.busy || downloads.ended != nil {
                Section {
                    JobRow(downloads: downloads)
                }
            }
            Section {
                ForEach(ReadyItem.allCases, id: \.self) { item in
                    row(item, states[item])
                }
            } header: {
                Text("Sẵn sàng khi mất sóng")
            } footer: {
                Text("Vẫn tải khi rời trang hay rời app; dừng được từ màn hình khoá.")
            }
        }
        // the one host of the translation pack's prompt: the page itself, never a row (a section's modifier goes to
        // each of its rows, and a row scrolled away can be torn down with its task)
        .talkTranslation(translator)
        .onAppear { model.offline.configure(store: model.store) }
        // what is read from the disk and the system, again on each change that can move it, never on a progress tick
        .task { await readiness.refresh() }
        .onChange(of: downloads.busy) { _, busy in
            if !busy { Task { await readiness.refresh() } }
        }
        .onChange(of: translator.needsDownload) { Task { await readiness.refresh() } }
        .onChange(of: translator.unsupported) { Task { await readiness.refresh() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await readiness.refresh() } }
        }
    }

    @ViewBuilder private func row(_ item: ReadyItem, _ state: ReadyState?) -> some View {
        let downloads = model.downloads
        let online = model.network.raw
        switch item {
        case .maps:
            // the areas, each with its own download, one level down
            NavigationLink(value: SettingsRoute.offlineMaps) {
                ReadyRow(title: Self.title(item), detail: mapsDetail(state), state: state)
            }
        case .photos:
            PhotosRow(photos: downloads.photos, online: online, download: { downloads.downloadPhotos() })
        case .translation:
            // iOS asks before it downloads (its own prompt, over this page)
            let download = ReadyRow.Action(online: online, run: { translator.download() })
            ReadyRow(title: Self.title(item), detail: Self.detail(item, state), state: state,
                     action: Self.fetchable(state) ? download : nil)
        case .speech:
            let install = ReadyRow.Action(online: online, run: { Task { await downloads.readiness.installSpeech() } })
            ReadyRow(title: Self.title(item), detail: Self.detail(item, state), state: state,
                     action: Self.fetchable(state) ? install : nil)
        case .forecasts:
            ReadyRow(title: Self.title(item), detail: forecastsDetail(state), state: state)
        case .dayMaps, .fuji:
            // drawn ahead by "Tải tất cả" (Task 6)
            ReadyRow(title: Self.title(item), detail: Self.detail(item, state), state: state)
        }
    }

    /// The row's name.
    static func title(_ item: ReadyItem) -> String {
        switch item {
        case .maps: "Bản đồ"
        case .dayMaps: "Ảnh bản đồ các ngày"
        case .photos: "Ảnh quán, khách sạn"
        case .fuji: "Ảnh địa hình Fuji"
        case .forecasts: "Dự báo mây"
        case .translation: "Gói dịch Nhật–Việt"
        case .speech: "Gói nghe tiếng Nhật"
        }
    }

    /// "Sẵn sàng", "3/11 vùng", "Chưa tải", "Đang tải 42%", "Chờ có mạng", or the reason given.
    static func detail(_ item: ReadyItem, _ state: ReadyState?) -> String {
        guard let state else { return "Đang kiểm tra…" }
        switch state {
        case .ready: return Readiness.ready
        case .missing(let done?, let total?):
            switch item {
            case .maps: return "\(done)/\(total) vùng"
            case .dayMaps: return "\(done)/\(total) ngày"
            case .photos, .fuji: return "\(done)/\(total) ảnh"
            case .forecasts: return "Chưa mới · \(done)/\(total) nơi"
            case .translation, .speech: return "Chưa tải"
            }
        case .missing: return "Chưa tải"
        // a download the system runs by itself does not say how far it is
        case .working(let p): return p > 0 ? "Đang tải \(Int(p * 100))%" : "Đang tải"
        case .waitingForNetwork: return "Chờ có mạng"
        case .failed(let why), .unsupported(let why), .needsSetup(let why): return why
        }
    }

    /// Missing, or failed: there is something to download.
    static func fetchable(_ state: ReadyState?) -> Bool {
        switch state {
        case .missing?, .failed?: true
        case nil, .ready?, .working?, .waitingForNetwork?, .unsupported?, .needsSetup?: false
        }
    }

    /// with the areas' size on disk, when there is any
    private func mapsDetail(_ state: ReadyState?) -> String {
        let bytes = model.offline.totalBytes
        let head = Self.detail(.maps, state)
        guard bytes > 0 else { return head }
        return head + " · " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// with the oldest forecast's time, in Japan ("cập nhật 9:05"), and its day when that is not today
    private func forecastsDetail(_ state: ReadyState?) -> String {
        let head = Self.detail(.forecasts, state)
        guard state != nil, let oldest = model.downloads.readiness.oldestForecast else { return head }
        var when = "cập nhật \(TripTime.clock(oldest))"
        let day = TripTime.isoDate(of: oldest)
        if day != TripTime.isoDate(of: Date()) { when += " ngày \(Fmt.shortDate(day))" }
        return head + " · " + when
    }
}

/// One item of the readiness list: its name, its state in words, and its download while there is one to start.
private struct ReadyRow: View {
    /// a download to start, off without a network
    struct Action {
        let online: Bool
        let run: () -> Void
    }

    let title: String
    let detail: String
    let state: ReadyState?
    var action: Action? = nil
    @State private var started = 0

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            trailing
        }
        .sensoryFeedback(.start, trigger: started)
    }

    @ViewBuilder private var trailing: some View {
        if let action {
            Button("Tải") {
                started += 1
                action.run()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!action.online)
        } else {
            switch state {
            case nil, .working?:
                ProgressView()
            case .ready?:
                ProgressRing(value: 1, mode: .done)
            case .missing?, .waitingForNetwork?, .failed?, .unsupported?, .needsSetup?:
                EmptyView()
            }
        }
    }

    private var warning: Bool {
        if case .failed? = state { return true }
        return false
    }
}

/// The map areas, each with its own download: "Toàn tuyến" first, then every region.
struct OfflineMapsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let offline = model.offline
        let downloads = model.downloads
        SettingsPage(title: "Bản đồ offline") {
            Section {
                if !offline.stale.isEmpty {
                    Label("Nguồn bản đồ đã đổi, nên \(offline.stale.count) vùng đã tải không còn dùng được khi mất sóng. Tải lại khi có Wi‑Fi.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if offline.ready {
                    ForEach(offline.areas) { area in
                        AreaRow(
                            name: area.name,
                            status: status(area.id),
                            bytes: offline.bytes[area.id],
                            download: { downloads.download(area) },
                            pause: { offline.pause(area.id) },
                            remove: { offline.remove(area) })
                    }
                    if !offline.missing.isEmpty {
                        Button("Tải tất cả bản đồ") { downloads.downloadAllMaps() }
                    }
                    if offline.totalBytes > 0 {
                        LabeledContent("Đã tải") {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(offline.totalBytes), countStyle: .file)).monospacedDigit()
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Đang đọc các vùng đã tải…").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { offline.configure(store: model.store) }
    }

    private func status(_ id: String) -> AreaStatus {
        let o = model.offline
        let p = o.progress[id] ?? 0
        switch o.phases[id] {
        case nil: return .idle
        // asked for, its pack not read yet (or not asked how far it is)
        case .requested?: return .checking
        case .creating?: return .preparing
        case .downloading?: return model.network.raw ? .downloading(p) : .waiting(p)
        case .waitingForNetwork?:
            if model.network.raw, let problem = o.problems[id] { return .failing(p, problem) }
            return .waiting(p)
        case .paused?: return .paused(p)
        case .complete?: return .complete
        case .stale?: return .stale
        case .failed(let reason)?: return .failed(reason)
        }
    }
}

/// The download under way, as one line ("Bản đồ 3/10 vùng · Ảnh 120/180 · 42%"), and once it is over, how
/// it ended: "Xong" only when everything is there, else what is missing ("Bản đồ 8/10 vùng · 2 lỗi"), or
/// "Đã dừng".
private struct JobRow: View {
    let downloads: Downloads

    var body: some View {
        HStack(spacing: 12) {
            if downloads.busy {
                ProgressView()
                Text(downloads.progressLine)
            } else if let ended = downloads.ended {
                Image(systemName: ended.success ? "checkmark.circle.fill" : ended.paused ? "pause.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ended.success ? Color.green : ended.paused ? Color.secondary : Color.orange)
                Text(ended.subtitle)
            }
        }
        .font(.footnote)
        .monospacedDigit()
        .contentTransition(.numericText())
    }
}

private struct AreaRow: View {
    let name: String
    let status: AreaStatus
    let bytes: UInt64?
    let download: () -> Void
    let pause: () -> Void
    let remove: () -> Void
    /// on the row: a download starts, or stops
    @State private var started = 0
    @State private var stopped = 0

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            trailing
        }
        .sensoryFeedback(.start, trigger: started)
        .sensoryFeedback(.stop, trigger: stopped)
        .swipeActions(edge: .trailing) {
            if hasData {
                Button("Xoá", systemImage: "trash", role: .destructive, action: remove)
            }
        }
        .contextMenu {
            if hasData {
                Button("Xoá", systemImage: "trash", role: .destructive, action: remove)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var trailing: some View {
        switch status {
        case .checking:
            ProgressView()
        case .failed:
            Button("Thử lại") {
                started += 1
                download()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .idle, .stale:
            Button(status == .stale ? "Tải lại" : "Tải") {
                started += 1
                download()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .complete:
            ProgressRing(value: 1, mode: .done)
        case .preparing, .downloading, .waiting, .failing:
            // as in the App Store: the ring is the stop button
            Button {
                stopped += 1
                pause()
            } label: {
                ProgressRing(value: running, mode: .running)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tạm dừng tải \(name)")
        case .paused(let p):
            Button {
                started += 1
                download()
            } label: {
                ProgressRing(value: p, mode: .paused)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tải tiếp \(name)")
        }
    }

    /// how far a running download is (its pack being made: nothing yet)
    private var running: Double {
        switch status {
        case .downloading(let p), .waiting(let p), .failing(let p, _): p
        case .checking, .idle, .stale, .complete, .preparing, .paused, .failed: 0
        }
    }

    private var size: String? {
        guard let bytes, bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var detail: String {
        func with(_ head: String, _ p: Double) -> String {
            ([head, "\(Int(p * 100))%"] + [size].compactMap { $0 }).joined(separator: " · ")
        }
        switch status {
        case .checking: return "Đang kiểm tra…"
        case .preparing: return "Đang chuẩn bị…"
        case .idle: return "Chưa tải"
        case .stale: return "Tải từ nguồn cũ, cần tải lại"
        case .complete: return ["Đã tải", size].compactMap { $0 }.joined(separator: " · ")
        case .downloading(let p): return with("Đang tải", p)
        case .waiting(let p): return with("Chờ có mạng", p)
        case .paused(let p): return with("Tạm dừng", p)
        case .failing(let p, let problem): return with(problem, p)
        case .failed(let reason): return reason
        }
    }

    private var warning: Bool {
        switch status {
        case .failing, .failed, .stale: true
        case .checking, .idle, .complete, .preparing, .downloading, .waiting, .paused: false
        }
    }

    /// something to remove: a pack, or a request (one that failed is dropped with any older pack)
    private var hasData: Bool {
        switch status {
        case .idle, .checking: false
        default: true
        }
    }
}

/// The trip's remote photos: how many are on disk, the download under way, what failed.
private struct PhotosRow: View {
    let photos: OfflinePhotos
    let online: Bool
    let download: () -> Void
    @State private var started = 0
    @State private var stopped = 0

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(OfflinePage.title(.photos))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(photos.failed > 0 && !photos.running ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            if !photos.counted {
                ProgressView()
            } else if photos.running {
                Button {
                    stopped += 1
                    photos.pause()
                } label: {
                    ProgressRing(value: photos.fraction, mode: .running)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tạm dừng tải ảnh")
            } else if photos.complete {
                ProgressRing(value: 1, mode: .done)
            } else if photos.saved > 0 {
                Button {
                    started += 1
                    download()
                } label: {
                    ProgressRing(value: photos.fraction, mode: .paused)
                }
                .buttonStyle(.plain)
                .disabled(!online)
                .accessibilityLabel(photos.failed > 0 ? "Thử tải lại ảnh lỗi" : "Tải tiếp ảnh")
            } else {
                Button("Tải") {
                    started += 1
                    download()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!online)
            }
        }
        .sensoryFeedback(.start, trigger: started)
        .sensoryFeedback(.stop, trigger: stopped)
    }

    private var detail: String {
        guard photos.counted else { return "Đang đếm ảnh đã lưu…" }
        if photos.running {
            return "Đang tải · \(photos.saved)/\(photos.total) ảnh" + (photos.failed > 0 ? " · \(photos.failed) lỗi" : "")
        }
        if photos.complete { return "Đã lưu đủ \(photos.total) ảnh" }
        var line = "\(photos.saved)/\(photos.total) ảnh đã lưu"
        if photos.failed > 0 { line += " · \(photos.failed) ảnh chưa tải được" }
        if !online { line += " · cần mạng" }
        return line
    }
}