import SwiftUI
import TripKit

// Dùng khi mất sóng: the map areas and the trip's photos, downloaded for when there is no signal.

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

/// Downloads belong to the app (`Downloads`), so this page only shows where they are: leave it,
/// use the rest of the app, come back, and it shows the truth.
struct OfflinePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let offline = model.offline
        let downloads = model.downloads
        Group {
            if downloads.busy || downloads.ended != nil {
                Section {
                    JobRow(downloads: downloads)
                }
            }
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
            } header: {
                Text("Bản đồ")
            }
            Section {
                PhotosRow(photos: downloads.photos, online: model.network.raw, download: { downloads.downloadPhotos() })
            } header: {
                Text("Ảnh")
            } footer: {
                Text("Vẫn tải khi rời trang hay rời app; dừng được từ màn hình khoá.")
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