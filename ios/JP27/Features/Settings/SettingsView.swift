import CoreLocation
import Photos
import SwiftUI
import TripKit
import UIKit
import WeatherKit

/// Laid out like the system's Settings: who the app is for at the top, then what is changed most
/// (how it looks, what it may use), then the trip's own switches, each a row with its current value
/// that opens a page, so the first screen reads as a summary instead of a wall of controls.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                SettingsHeader()
                AppearanceSection()
                PermissionsSection()
                TripSection()
                if let problem = Records.problem {
                    Section {
                        Label {
                            Text(problem).font(.subheadline)
                        } icon: {
                            SettingsIcon(symbol: "exclamationmark.triangle.fill", tint: .red)
                        }
                        if let file = Records.unreadable {
                            ShareLink(item: file) {
                                Label("Gửi file sổ cũ để cứu dữ liệu", systemImage: "square.and.arrow.up")
                            }
                        }
                    } header: {
                        Text("Sổ ghi chép")
                    }
                }
                Section {
                    NavigationLink {
                        SettingsPage(title: "Dùng khi mất sóng") { OfflineSection() }
                    } label: {
                        SettingsLabel(title: "Dùng khi mất sóng", symbol: "arrow.down.circle.fill", tint: .blue, value: offlineValue)
                    }
                    NavigationLink {
                        SettingsPage(title: "Nguồn") { SourcesSection() }
                    } label: {
                        SettingsLabel(title: "Nguồn và ghi công", symbol: "books.vertical.fill", tint: .brown)
                    }
                } footer: {
                    Text("Dữ liệu nghiên cứu ngày \(model.store.trip.meta.researched).")
                }
                DiagnosticsSection()
            }
            .progressiveEdges()
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseButton() }
            .onAppear {
                if model.offline.areas.isEmpty { model.offline.configure(store: model.store) }
            }
        }
    }

    /// "Đang tải 42%", "4/10 vùng · 182 MB", or "Chưa tải"
    private var offlineValue: String {
        let offline = model.offline
        if model.downloads.busy { return "Đang tải \(Int(model.downloads.fraction * 100))%" }
        if !offline.stale.isEmpty { return "Cần tải lại" }
        guard offline.totalBytes > 0 else { return "Chưa tải" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(offline.totalBytes), countStyle: .file)
        return "\(offline.complete.count)/\(offline.areas.count) vùng · \(size)"
    }
}

// MARK: - Diagnostics

/// What the map really draws, measured on the phone: for a jerky map, numbers instead of guesses.
/// And what the alarms last ran into.
private struct DiagnosticsSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(MapPacer.readingsKey) private var readings = false
    @AppStorage(MapPacer.glassKey) private var glass = true
    @AppStorage(MapPacer.reliefKey) private var relief = false
    #if DEBUG
    /// what AlarmKit listed, the last time it was asked
    @State private var systemAlarms: String?
    #endif

    var body: some View {
        Section {
            Toggle(isOn: $readings) {
                Label {
                    Text("Đo khung hình bản đồ")
                } icon: {
                    SettingsIcon(symbol: "speedometer", tint: .gray)
                }
            }
            if readings {
                Toggle(isOn: $glass) {
                    Label {
                        Text("Kính trên bản đồ")
                    } icon: {
                        SettingsIcon(symbol: "rectangle.on.rectangle", tint: .teal)
                    }
                }
                Toggle(isOn: $relief) {
                    Label {
                        Text("Bóng địa hình")
                    } icon: {
                        SettingsIcon(symbol: "mountain.2", tint: .brown)
                    }
                }
            }
            if let problem = model.alarms.lastError {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lỗi báo thức gần nhất")
                        Text(problem).font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    SettingsIcon(symbol: "exclamationmark.triangle.fill", tint: .red)
                }
            }
            #if DEBUG
            testAlarm(minutes: 2)
            testAlarm(minutes: 5)
            Button {
                systemAlarms = model.alarms.systemAlarmsSummary()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Báo thức trong hệ thống")
                        if let systemAlarms {
                            Text(systemAlarms).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    SettingsIcon(symbol: "list.bullet", tint: .gray)
                }
            }
            #endif
        } header: {
            Text("Chẩn đoán")
        } footer: {
            Text(readings
                ? "Ở góc bản đồ: mỗi khung main thread mất bao lâu, chia ra CPU tự làm và thời gian ngồi chờ GPU trả khung; GPU bận đến đâu; bản đồ giữ main thread bao nhiêu phần trăm. Tắt Kính trên bản đồ để thấy phần kính tốn. Bóng địa hình bật lại lớp đổ bóng núi mà bản đồ của app đã bỏ (nó bắt main thread chờ GPU cho từng mảnh địa hình đã tải, mỗi khung): bật lên rồi lướt bản đồ một lúc để so số chờ."
                : "Hiện ở góc bản đồ thời gian của từng khung hình, để biết bản đồ giật vì đâu.")
        }
    }

    #if DEBUG
    /// A real alarm for a ride that does not exist, set the way a followed ride sets one (asks for
    /// permission, replaces only once set), for the device checks in
    /// docs/superpowers/checklists/2026-11-device-phase1-3.md. Two lengths on the same ride: the
    /// second moves the first by more than two minutes, so it is a replacement.
    private func testAlarm(minutes: Double) -> some View {
        Button {
            Task { await model.alarms.alight(rideID: "debug.wake", station: "Ga thử", at: Date().addingTimeInterval(minutes * 60)) }
        } label: {
            Label {
                Text("Báo thức thử sau \(Int(minutes)) phút")
            } icon: {
                SettingsIcon(symbol: "alarm", tint: .orange)
            }
        }
    }
    #endif
}

// MARK: - Building blocks

/// The coloured tile in front of a settings row, as in the system's Settings.
private struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(tint.gradient, in: .rect(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A row that opens a page: tile, title, and the current value on the trailing side.
private struct SettingsLabel: View {
    let title: String
    let symbol: String
    let tint: Color
    var value: String?

    var body: some View {
        LabeledContent {
            if let value {
                Text(value).monospacedDigit().lineLimit(1)
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                SettingsIcon(symbol: symbol, tint: tint)
            }
        }
    }
}

/// A page one level down: its own form, and the close button still at the far right.
private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .progressiveEdges()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseButton() }
    }
}

// MARK: - Header

/// The trip itself, the way the system's Settings opens on your account: the mark, the dates,
/// the cities in order.
private struct SettingsHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let trip = model.store.trip
        let meta = trip.meta
        Section {
            HStack(spacing: 14) {
                HinomaruMark(size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(meta.title)
                        .font(.system(size: 24, weight: .black).width(.expanded))
                    Text("\(Fmt.shortDate(meta.start)) – \(Fmt.shortDate(meta.end)) · \(meta.nights) đêm · \(meta.people) người")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(trip.chapters.map(\.kanji).joined(separator: " → "))
                        .font(.mincho(14, bold: false, relativeTo: .footnote))
                        .foregroundStyle(.secondary)
                        .environment(\.locale, Locale(identifier: "ja"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Appearance

/// Automatic, light or dark, picked from three small screens, as in Display & Brightness.
private struct AppearanceSection: View {
    @AppStorage(Appearance.key) private var appearance: Appearance = .system

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Appearance.allCases) { a in
                    Button {
                        appearance = a
                    } label: {
                        AppearanceChoice(appearance: a, on: appearance == a)
                    }
                    // a row holding several buttons: without a plain style the whole row is one tap
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            .sensoryFeedback(.pick, trigger: appearance)
        } header: {
            Text("Giao diện")
        } footer: {
            Text("Tự động đổi sáng, tối theo iPhone, cả bản đồ.")
        }
    }
}

private struct AppearanceChoice: View {
    let appearance: Appearance
    let on: Bool

    var body: some View {
        VStack(spacing: 10) {
            thumb
                .frame(width: 60, height: 100)
                .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
            Text(appearance.label)
                .font(.subheadline)
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(on ? AnyShapeStyle(Palette.sun) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appearance.label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var thumb: some View {
        switch appearance {
        case .light:
            AppearanceThumb().environment(\.colorScheme, .light)
        case .dark:
            AppearanceThumb().environment(\.colorScheme, .dark)
        case .system:
            ZStack {
                AppearanceThumb().environment(\.colorScheme, .light)
                AppearanceThumb().environment(\.colorScheme, .dark)
                    .mask(LowerRightHalf())
            }
        }
    }
}

/// A screen of the app in miniature: paper, the red disc, a title, two cards.
private struct AppearanceThumb: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        shape
            .fill(Palette.paper)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    Circle().fill(Palette.sun).frame(width: 12, height: 12)
                    Capsule().fill(.primary.opacity(0.8)).frame(width: 32, height: 4)
                    Capsule().fill(.secondary.opacity(0.6)).frame(width: 22, height: 3)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.card).frame(height: 24)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.card).frame(height: 16)
                }
                .padding(8)
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
    }
}

private nonisolated struct LowerRightHalf: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - Trip

/// The trip's own switches, each summarised by its value and opened on a page.
private struct TripSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let alts = model.store.trip.altDays
        Section("Chuyến đi") {
            if !alts.isEmpty {
                let on = alts.filter { model.alternatives.contains($0.key) }.count
                NavigationLink {
                    SettingsPage(title: "Ngày thay thế") { AlternativesSection() }
                } label: {
                    SettingsLabel(title: "Ngày thay thế", symbol: "arrow.triangle.swap", tint: .orange,
                                  value: on == 0 ? "Theo lịch gốc" : "\(on) ngày đổi")
                }
            }
            NavigationLink {
                SettingsPage(title: "Đi bộ") { PaceSection() }
            } label: {
                SettingsLabel(title: "Tốc độ đi bộ", symbol: "figure.walk", tint: .green,
                              value: "\(Fmt.decimal(3.9 * model.pace.factor, digits: 1)) km/h")
            }
            NavigationLink {
                SettingsPage(title: "Chạy thử") { RehearsalSection() }
            } label: {
                SettingsLabel(title: "Chạy thử", symbol: "clock.arrow.circlepath", tint: .purple,
                              value: model.clockOffset == 0 ? "Tắt" : "Đang chạy")
            }
        }
    }
}

// MARK: - Permissions

private struct PermissionsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    /// AlarmKit and ActivityKit states are read, not observed: bump to re-read after a request
    @State private var tick = 0

    var body: some View {
        Section("Quyền") {
            location
            PermissionRow(
                title: "Thông báo", detail: "Nhắc giờ tàu, xe, đặt bàn", symbol: "bell.badge.fill", tint: .red,
                state: model.notifications.authorized ? .on : .off,
                action: { Task { await model.notifications.requestAuthorization(); await model.notifications.refreshStatus(); if !model.notifications.authorized { openSettings() } } })
            PermissionRow(
                title: "Báo thức", detail: "Đánh thức trước ga cần xuống", symbol: "alarm.fill", tint: .orange,
                state: alarmsState,
                action: { Task { if !(await model.alarms.requestAuthorization()) { openSettings() }; tick += 1 } })
            PermissionRow(
                title: "Ảnh", detail: "Gắn ảnh vào nhật ký mỗi tối", symbol: "photo.on.rectangle.angled", tint: .indigo,
                state: photosState,
                action: {
                    if model.photos.status == .notDetermined {
                        Task { await model.photos.request() }
                    } else {
                        openSettings()
                    }
                })
            PermissionRow(
                title: "Live Activities", detail: "Ga kế, lúc xuống, Fuji bên nào", symbol: "dot.radiowaves.left.and.right", tint: .teal,
                state: liveState,
                action: openSettings)
        }
        .task { await model.notifications.refreshStatus() }
    }

    private var location: some View {
        let status = model.location.authorization
        let state: PermissionRow.State = switch status {
        case .authorizedAlways: .on
        case .authorizedWhenInUse: .partial("Khi dùng app")
        case .notDetermined: .ask
        default: .off
        }
        return PermissionRow(
            title: "Vị trí luôn bật", detail: "Món nên gọi khi tới quán, ga trên tàu, nhật ký", symbol: "location.fill", tint: .blue,
            state: state,
            action: {
                switch status {
                case .notDetermined: model.location.requestWhenInUse()
                case .authorizedWhenInUse: model.location.requestAlways()
                default: openSettings()
                }
            })
    }

    private var alarmsState: PermissionRow.State {
        _ = tick
        return model.alarms.authorized ? .on : .ask
    }

    private var liveState: PermissionRow.State {
        _ = tick
        return model.live.isAvailable ? .on : .off
    }

    private var photosState: PermissionRow.State {
        switch model.photos.status {
        case .authorized: .on
        case .limited: .partial("Một phần")
        case .notDetermined: .ask
        default: .off
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

private struct PermissionRow: View {
    enum State: Equatable {
        case on, off, ask
        case partial(String)
    }

    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let state: State
    let action: () -> Void
    /// iOS's prompt or Settings opened; on the row, as the button leaves once access is given
    /// (spelled out: `State` here is the row's own)
    @SwiftUI.State private var asked = 0

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            switch state {
            case .on:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Đã bật")
            case .partial(let text):
                Button(text, action: ask)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            case .ask:
                Button("Cho phép", action: ask)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            case .off:
                Button("Mở Cài đặt", action: ask)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .sensoryFeedback(.press, trigger: asked)
        .accessibilityElement(children: .combine)
    }

    private func ask() {
        asked += 1
        action()
    }
}

// MARK: - Offline

/// Where one area is, as its row says it.
private enum AreaStatus: Equatable {
    case checking, idle, stale, complete
    case downloading(Double), waiting(Double), paused(Double)
    case failing(Double, String)
}

/// Downloads belong to the app (`Downloads`), so this page only shows where they are: leave it,
/// use the rest of the app, come back, and it shows the truth.
private struct OfflineSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let offline = model.offline
        let downloads = model.downloads
        Group {
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
                    if offline.areas.contains(where: { !offline.complete.contains($0.id) && !offline.wanted.contains($0.id) }) {
                        Button("Tải tất cả bản đồ") { downloads.downloadAllMaps() }
                    }
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Đang đọc các vùng đã tải…").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Bản đồ")
            } footer: {
                if offline.totalBytes > 0 {
                    Text("Đã tải \(ByteCountFormatter.string(fromByteCount: Int64(offline.totalBytes), countStyle: .file)). Vuốt trái một vùng để xoá.")
                }
            }
            Section {
                PhotosRow(photos: downloads.photos, online: model.network.online, download: { downloads.downloadPhotos() })
            } header: {
                Text("Ảnh")
            } footer: {
                Text("Vẫn tải khi bạn chuyển sang phần khác của app. Bấm tải rồi rời app thì iOS hiện tiến độ trên màn hình khoá và Dynamic Island, tải tiếp đến khi xong; dừng được ngay từ đó.")
            }
        }
        .onAppear { offline.configure(store: model.store) }
    }

    private func status(_ id: String) -> AreaStatus {
        let o = model.offline
        if o.checking.contains(id) { return .checking }
        if o.complete.contains(id) { return .complete }
        if o.stale.contains(id), !o.wanted.contains(id) { return .stale }
        let p = o.progress[id] ?? 0
        if o.wanted.contains(id) || o.running.contains(id) {
            if !model.network.online { return .waiting(p) }
            if let problem = o.problems[id] { return .failing(p, problem) }
            return .downloading(p)
        }
        if let problem = o.problems[id] { return .failing(p, problem) }
        return o.progress[id] == nil ? .idle : .paused(p)
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
        case .idle, .stale:
            Button(status == .stale ? "Tải lại" : "Tải") {
                started += 1
                download()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .complete:
            ProgressRing(value: 1, mode: .done)
        case .downloading(let p), .waiting(let p), .failing(let p, _):
            // as in the App Store: the ring is the stop button
            Button {
                stopped += 1
                pause()
            } label: {
                ProgressRing(value: p, mode: .running)
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
        case .idle: return "Chưa tải"
        case .stale: return "Tải từ nguồn cũ, cần tải lại"
        case .complete: return ["Đã tải", size].compactMap { $0 }.joined(separator: " · ")
        case .downloading(let p): return with("Đang tải", p)
        case .waiting(let p): return with("Chờ có mạng", p)
        case .paused(let p): return with("Tạm dừng", p)
        case .failing(let p, let problem): return with(problem, p)
        }
    }

    private var warning: Bool {
        if case .failing = status { return true }
        return status == .stale
    }

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
                Text("Ảnh quán ăn và khách sạn")
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

/// A download's ring: filling while it runs (a square in it: tap to stop), an arrow while paused
/// (tap to go on), a tick when done. As in the App Store and Podcasts.
private struct ProgressRing: View {
    enum Mode { case running, paused, done }
    let value: Double
    let mode: Mode

    var body: some View {
        ZStack {
            Circle().stroke(.fill.tertiary, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(mode == .done ? Color.green : .accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            switch mode {
            case .running:
                RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 8, height: 8)
            case .paused:
                Image(systemName: "arrow.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.accentColor)
            case .done:
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
            }
        }
        .frame(width: 26, height: 26)
        // a bigger target than the ring, as a button needs
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.25), value: value)
        .accessibilityValue(Text("\(Int(value * 100))%"))
    }
}

// MARK: - Alternative days

private struct AlternativesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let alts = model.store.trip.altDays
        if !alts.isEmpty {
            Section {
                ForEach(alts) { alt in
                    Toggle(isOn: binding(alt.key)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alt.title)
                            Text("Thay ngày \(alt.replaces ?? alt.n) · \(Fmt.shortDate(alt.date))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Lịch trình")
            } footer: {
                Text("Nhắc giờ, geofence và widget đi theo lựa chọn này.")
            }
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { model.alternatives.contains(key) },
            set: { on in
                if on { model.alternatives.insert(key) } else { model.alternatives.remove(key) }
            })
    }
}

// MARK: - Rehearsal clock

private struct RehearsalSection: View {
    @Environment(AppModel.self) private var model
    @State private var picked = Date()
    @State private var seeded = false

    private var range: ClosedRange<Date> {
        let first = model.store.trip.days.first.flatMap { TripTime.midnight($0.date) } ?? Date()
        let last = model.store.trip.days.last.flatMap { TripTime.midnight($0.date) } ?? Date()
        return first.addingTimeInterval(-86400) ... last.addingTimeInterval(2 * 86400)
    }

    var body: some View {
        Section {
            DatePicker("Thời điểm", selection: $picked, in: range)
                .environment(\.timeZone, TripTime.zone)
            Button("Chạy thử từ thời điểm này") {
                model.clockOffset = picked.timeIntervalSince(Date())
            }
            if model.clockOffset != 0 {
                LabeledContent("Đồng hồ chuyến đi") {
                    Text(clockLabel(model.now)).monospacedDigit()
                }
                Button("Về giờ thật", role: .destructive) {
                    model.clockOffset = 0
                    picked = clampedNow
                }
            }
        } header: {
            Text("Chạy thử")
        } footer: {
            Text("Giờ Nhật. Thông báo, widget và Live Activity chạy theo đồng hồ này. Những gì ghi trong lúc chạy thử (điểm đã đi, điểm bỏ, khoản chi, đồ đã mua) nằm ở một sổ riêng, không sang máy kia, và bị xoá khi về giờ thật.")
        }
        .onAppear {
            guard !seeded else { return }
            seeded = true
            picked = clampedNow
        }
    }

    private var clampedNow: Date {
        let now = model.now
        return min(max(now, range.lowerBound), range.upperBound)
    }

    private func clockLabel(_ d: Date) -> String {
        let c = TripTime.calendar.dateComponents([.day, .month], from: d)
        return "\(c.day ?? 0)/\(c.month ?? 0) · \(TripTime.clock(d))"
    }
}

// MARK: - Walking pace

private struct PaceSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pace = model.pace
        Section {
            LabeledContent("Tốc độ đi bộ") {
                Text("\(Fmt.decimal(3.9 * pace.factor, digits: 1)) km/h").monospacedDigit()
            }
            Text(summary(pace))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Đi bộ")
        }
    }

    private func summary(_ pace: PaceModel) -> String {
        guard pace.minutes >= 1 else { return "Chưa đo. Giờ đi bộ đang tính theo 3,9 km/h trên đường bằng, chậm hơn khi lên dốc." }
        let delta = Int(((pace.factor - 1) * 100).rounded())
        let base = "Đo từ \(Int(pace.minutes.rounded())) phút đi bộ."
        if abs(delta) < 2 { return "Đúng như mô hình. " + base }
        return (delta > 0 ? "Nhanh hơn mô hình \(delta)%. " : "Chậm hơn mô hình \(-delta)%. ") + base
    }
}

// MARK: - Sources

private struct SourcesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("Nghiên cứu", value: model.store.trip.meta.researched)
            source("Bản đồ: OpenFreeMap", "https://openfreemap.org")
            source("© OpenStreetMap", "https://www.openstreetmap.org/copyright")
            source("Ảnh: Wikimedia Commons", "https://commons.wikimedia.org")
            source("Quán ăn: Tabelog", "https://tabelog.com/en/")
            Link(destination: model.forecasts.attribution?.legalPageURL ?? URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!) {
                Label("Dự báo:  Weather", systemImage: "cloud.sun")
            }
            // the fallback when the build has no WeatherKit entitlement; CC BY 4.0 asks for the credit
            source("Dự báo: Open-Meteo", "https://open-meteo.com/")
        } header: {
            Text("Nguồn")
        }
    }

    private func source(_ title: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label(title, systemImage: "arrow.up.right.square")
        }
    }
}
