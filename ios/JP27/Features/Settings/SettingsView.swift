import SwiftUI
import TripKit

/// Laid out like the system's Settings: the trip at the top, then what needs a look (only when something
/// does), then the trip's own switches, how the app looks and reads, what it may use and keep, the offline
/// downloads, and help. Each row carries its current value; most open a page one level down
/// (`SettingsRoute`), so the first screen reads as a summary instead of a wall of controls.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Appearance.key) private var appearance: Appearance = .system
    @AppStorage(MapPacer.glassKey) private var glass = true
    @AppStorage(MapPacer.reliefKey) private var relief = false
    @AppStorage(SpeechPace.key) private var pace: SpeechPace = .normal
    /// AlarmKit and ActivityKit permissions are read, not observed: read again each time this page shows
    @State private var permissionTick = 0
    /// what the log takes on disk (`AppLog.usage`), read each time this page shows
    @State private var logBytes: Int?

    var body: some View {
        @Bindable var model = model
        let _ = permissionTick
        let permissions = PermissionStates(model)
        NavigationStack {
            Form {
                SettingsHeader()
                attention(permissions)
                TripSection()
                Section {
                    NavigationLink(value: SettingsRoute.appearance) {
                        SettingsLabel(title: "Giao diện", symbol: "circle.lefthalf.filled", tint: .blue, value: appearance.label)
                    }
                    NavigationLink(value: SettingsRoute.map) {
                        SettingsLabel(title: "Bản đồ", symbol: "map.fill", tint: .teal,
                                      value: MapOptionsSection.summary(glass: glass, relief: relief))
                    }
                    Picker(selection: $pace) {
                        ForEach(SpeechPace.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label {
                            Text("Đọc tiếng Nhật")
                        } icon: {
                            SettingsIcon(symbol: "speaker.wave.2.fill", tint: .pink)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: pace) { _, p in AppLog.info(.settings, "Đọc tiếng Nhật", ["value": p.rawValue]) }
                    Toggle(isOn: $model.keepAwakeOnRide) {
                        Label {
                            Text("Giữ màn hình sáng khi đi tàu")
                        } icon: {
                            SettingsIcon(symbol: "sun.max.fill", tint: .orange)
                        }
                    }
                } header: {
                    Text("Trải nghiệm")
                } footer: {
                    Text("Đọc tiếng Nhật: tốc độ của nút đọc. Giữ sáng: chỉ khi đang theo dõi chuyến.")
                }
                Section("Riêng tư") {
                    NavigationLink(value: SettingsRoute.permissions) {
                        SettingsLabel(title: "Quyền", symbol: "hand.raised.fill", tint: .blue,
                                      value: "\(permissions.on)/\(permissions.all.count) đã bật")
                    }
                    NavigationLink(value: SettingsRoute.journal) {
                        SettingsLabel(title: "Nhật ký vị trí", symbol: "book.pages.fill", tint: .indigo,
                                      value: model.journalEnabled ? "Bật" : "Tắt")
                    }
                }
                Section {
                    NavigationLink(value: SettingsRoute.offline) {
                        SettingsLabel(title: "Dùng khi mất sóng", symbol: "arrow.down.circle.fill", tint: .blue, value: offlineValue)
                    }
                }
                Section {
                    NavigationLink(value: SettingsRoute.checks) {
                        SettingsLabel(title: "Kiểm tra", symbol: "checkmark.seal.fill", tint: .green, value: CheckRun.shared.summary)
                    }
                    NavigationLink(value: SettingsRoute.log) {
                        SettingsLabel(title: "Log", symbol: "doc.text.fill", tint: .gray,
                                      value: logBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) })
                    }
                    NavigationLink(value: SettingsRoute.metrics) {
                        SettingsLabel(title: "Số đo", symbol: "chart.bar.xaxis", tint: .indigo)
                    }
                    NavigationLink(value: SettingsRoute.sources) {
                        SettingsLabel(title: "Nguồn và ghi công", symbol: "books.vertical.fill", tint: .brown)
                    }
                    NavigationLink(value: SettingsRoute.developer) {
                        SettingsLabel(title: "Nhà phát triển", symbol: "hammer.fill", tint: .gray)
                    }
                } header: {
                    Text("Hỗ trợ")
                } footer: {
                    Text("JP27 \(Self.version) (\(Self.build)) · Dữ liệu nghiên cứu ngày \(model.store.trip.meta.researched).")
                }
            }
            .navigationDestination(for: SettingsRoute.self) { SettingsDestination(route: $0) }
            .progressiveEdges()
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseButton() }
            .onAppear {
                permissionTick += 1
                if model.offline.areas.isEmpty { model.offline.configure(store: model.store) }
                Task { logBytes = await AppLog.usage() }
            }
            // the notification permission as it is now, for the Quyền value and "Cần xem"
            .task { await model.notifications.refreshStatus() }
            // what is ready for no signal, for "Dùng khi mất sóng" and "Cần xem"
            .task { await model.downloads.readiness.refresh() }
        }
    }

    /// Cần xem: only what needs a look now, each row leading to where it is put right. A pretend failure of Nhà
    /// phát triển first, as a red band that turns it off; then the records that failed to open, with their file to
    /// send for rescue.
    @ViewBuilder private func attention(_ permissions: PermissionStates) -> some View {
        let pretending = Records.pretending
        let problem = Records.problem
        let stale = !model.offline.stale.isEmpty
        let alarm = model.alarms.lastError
        // stale maps have their own row, which says more
        let unready = !stale && offlineUnready
        if pretending || problem != nil || permissions.off > 0 || stale || alarm != nil || unready {
            Section("Cần xem") {
                if pretending {
                    PretendBand()
                }
                if let problem {
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
                }
                if permissions.off > 0 {
                    NavigationLink(value: SettingsRoute.permissions) {
                        SettingsLabel(title: "\(permissions.off) quyền đang tắt", symbol: "hand.raised.fill", tint: .red)
                    }
                }
                if stale {
                    NavigationLink(value: SettingsRoute.offline) {
                        SettingsLabel(title: "Bản đồ offline cần tải lại", symbol: "arrow.down.circle.fill", tint: .orange)
                    }
                }
                if unready {
                    NavigationLink(value: SettingsRoute.offline) {
                        SettingsLabel(title: "Chưa sẵn sàng khi mất sóng", symbol: "arrow.down.circle.fill", tint: .orange)
                    }
                }
                if let alarm {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lỗi báo thức gần nhất")
                            Text(alarm).font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        SettingsIcon(symbol: "alarm.fill", tint: .red)
                    }
                }
            }
        }
    }

    /// "Sẵn sàng", "Thiếu 2 mục", "Đang tải 42%" or "Cần tải lại" (`Readiness.summary`); nothing until what is ready
    /// has been read once, unless a download or stale maps already tell
    private var offlineValue: String? {
        let downloads = model.downloads
        let stale = !model.offline.stale.isEmpty
        guard downloads.readiness.checked || downloads.busy || stale else { return nil }
        return Readiness.summary(downloads.readiness.states, mapsStale: stale, downloading: downloads.busy ? downloads.fraction : nil)
    }

    /// Not all ready for no signal, from 14 days before the trip to its end by the real clock (never the rehearsal's:
    /// the trip itself is what it gets ready for).
    private var offlineUnready: Bool {
        let meta = model.store.trip.meta
        guard model.downloads.readiness.checked, let value = offlineValue, value != Readiness.ready else { return false }
        return Readiness.watching(now: Date(), start: meta.start, end: meta.end)
    }

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
}

/// The page each `SettingsRoute` opens.
private struct SettingsDestination: View {
    let route: SettingsRoute

    var body: some View {
        switch route {
        case .alternatives: SettingsPage(title: "Ngày thay thế") { AlternativesSection() }
        case .pace: SettingsPage(title: "Đi bộ") { PaceSection() }
        case .rehearsal: SettingsPage(title: "Chạy thử") { RehearsalSection() }
        case .appearance: SettingsPage(title: "Giao diện") { AppearanceSection() }
        case .map: SettingsPage(title: "Bản đồ") { MapOptionsSection() }
        case .permissions: SettingsPage(title: "Quyền") { PermissionsSection() }
        case .journal: SettingsPage(title: "Nhật ký vị trí") { JournalSection() }
        case .offline: OfflinePage()
        case .offlineMaps: OfflineMapsPage()
        case .checks: SettingsPage(title: "Kiểm tra") { ChecksPage() }
        case .log: LogPage()
        case .metrics: SettingsPage(title: "Số đo") { MetricsSection() }
        case .sources: SettingsPage(title: "Nguồn") { SourcesSection() }
        case .developer: SettingsPage(title: "Nhà phát triển") { DeveloperSection() }
        }
    }
}

/// "Đang giả lỗi lưu": a pretend failure of Nhà phát triển is on (saves or ledger reads), in the system's red, with
/// its "Tắt" that turns both off at once.
private struct PretendBand: View {
    var body: some View {
        HStack {
            Label {
                Text("Đang giả lỗi lưu").fontWeight(.semibold)
            } icon: {
                Image(systemName: "xmark.octagon.fill")
            }
            Spacer()
            Button("Tắt") {
                Records.failSaves = .off
                Records.failReads = false
                AppLog.info(.dev, "Tắt giả lỗi")
            }
            .buttonStyle(.borderless)
            .fontWeight(.semibold)
        }
        .foregroundStyle(.white)
        .tint(.white)
        .listRowBackground(Color.red)
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

// MARK: - Trip

/// The trip's own switches, each summarised by its value and opened on a page.
private struct TripSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let alts = model.store.trip.altDays
        Section("Chuyến đi") {
            if !alts.isEmpty {
                let on = alts.filter { model.alternatives.contains($0.key) }.count
                NavigationLink(value: SettingsRoute.alternatives) {
                    SettingsLabel(title: "Ngày thay thế", symbol: "arrow.triangle.swap", tint: .orange,
                                  value: on == 0 ? "Theo lịch gốc" : "\(on) ngày đổi")
                }
            }
            NavigationLink(value: SettingsRoute.pace) {
                SettingsLabel(title: "Tốc độ đi bộ", symbol: "figure.walk", tint: .green,
                              value: "\(Fmt.decimal(3.9 * model.pace.factor, digits: 1)) km/h")
            }
            NavigationLink(value: SettingsRoute.rehearsal) {
                SettingsLabel(title: "Chạy thử", symbol: "clock.arrow.circlepath", tint: .purple,
                              value: model.rehearsing ? "Đang chạy" : "Tắt")
            }
        }
    }
}
