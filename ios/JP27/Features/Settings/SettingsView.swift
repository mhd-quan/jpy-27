import CoreLocation
import Photos
import SwiftUI
import TripKit
import UIKit
import WeatherKit

/// Permissions, offline data, the alternative days, the rehearsal clock and sources.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                PermissionsSection()
                OfflineSection()
                AlternativesSection()
                RehearsalSection()
                PaceSection()
                SourcesSection()
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseButton() }
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
                title: "Thông báo", detail: "Nhắc giờ tàu, xe, đặt bàn",
                state: model.notifications.authorized ? .on : .off,
                action: { Task { await model.notifications.requestAuthorization(); await model.notifications.refreshStatus(); if !model.notifications.authorized { openSettings() } } })
            PermissionRow(
                title: "Báo thức", detail: "Đánh thức trước ga cần xuống",
                state: alarmsState,
                action: { Task { if !(await model.alarms.requestAuthorization()) { openSettings() }; tick += 1 } })
            PermissionRow(
                title: "Ảnh", detail: "Gắn ảnh vào nhật ký mỗi tối",
                state: photosState,
                action: {
                    if model.photos.status == .notDetermined {
                        Task { await model.photos.request() }
                    } else {
                        openSettings()
                    }
                })
            PermissionRow(
                title: "Live Activities", detail: "Ga kế, lúc xuống, Fuji bên nào",
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
            title: "Vị trí luôn bật", detail: "Món nên gọi khi tới quán, ga trên tàu, nhật ký",
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
    let state: State
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
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
                Button(text, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            case .ask:
                Button("Cho phép", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            case .off:
                Button("Mở Cài đặt", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Offline

@Observable private final class PrefetchProgress {
    var value: Double?
    var done: Int?
}

private struct OfflineSection: View {
    @Environment(AppModel.self) private var model
    @State private var prefetch = PrefetchProgress()

    private var remotePhotos: [Photo] {
        let places = model.store.trip.places.flatMap(\.images)
        let stays = model.guide.stays.flatMap { s -> [Photo] in
            guard let around = s.around else { return [] }
            return around.photos + around.walks.flatMap { $0.highlights.flatMap(\.images) }
        }
        var seen = Set<String>()
        return (places + stays).filter { !$0.isBundled && seen.insert($0.src).inserted }
    }

    var body: some View {
        let offline = model.offline
        Section {
            ForEach(offline.areas) { area in
                AreaRow(
                    name: area.name,
                    progress: offline.progress[area.id],
                    bytes: offline.bytes[area.id],
                    complete: offline.complete.contains(area.id),
                    download: { offline.download(area) },
                    remove: { offline.remove(area) })
            }
            if offline.areas.contains(where: { !offline.complete.contains($0.id) }) {
                Button("Tải tất cả bản đồ") { offline.downloadAll() }
            }
            photosRow
        } header: {
            Text("Dùng khi mất sóng")
        } footer: {
            if offline.totalBytes > 0 {
                Text("Bản đồ đã tải: \(ByteCountFormatter.string(fromByteCount: Int64(offline.totalBytes), countStyle: .file))")
            }
        }
        .onAppear { offline.configure(store: model.store) }
    }

    private var photosRow: some View {
        let photos = remotePhotos
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ảnh quán ăn và khách sạn")
                    Text(prefetch.done.map { "\($0)/\(photos.count) ảnh đã lưu" } ?? "\(photos.count) ảnh trên mạng")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if prefetch.value == nil || prefetch.done != nil {
                    Button(prefetch.done == nil ? "Tải" : "Tải lại") { start(photos) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!model.network.online)
                }
            }
            if let v = prefetch.value, prefetch.done == nil {
                ProgressView(value: v)
            }
        }
    }

    private func start(_ photos: [Photo]) {
        let state = prefetch
        state.value = 0
        state.done = nil
        Task {
            let done = await PhotoCache.shared.prefetch(photos) { p in
                Task { @MainActor in state.value = p }
            }
            state.done = done
        }
    }
}

private struct AreaRow: View {
    let name: String
    let progress: Double?
    let bytes: UInt64?
    let complete: Bool
    let download: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressRing(value: complete ? 1 : (progress ?? 0), active: progress != nil && !complete)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if let bytes, bytes > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            if complete || progress != nil {
                Menu {
                    if !complete { Button("Tiếp tục tải", systemImage: "arrow.down.circle", action: download) }
                    Button("Xoá", systemImage: "trash", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis.circle").imageScale(.large)
                }
                .accessibilityLabel("Tuỳ chọn \(name)")
            } else {
                Button("Tải", action: download)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ProgressRing: View {
    let value: Double
    let active: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.fill.tertiary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(value >= 1 ? Color.green : .accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if value >= 1 {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
            }
        }
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
            Text("Giờ Nhật. Thông báo, widget và Live Activity chạy theo đồng hồ này.")
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
