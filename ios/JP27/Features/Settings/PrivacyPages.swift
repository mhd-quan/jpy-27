import CoreLocation
import Photos
import SwiftUI
import TripKit
import UIKit

// What the app may use and what it keeps of where you went: the permissions, the location journal.

// MARK: - Journal

/// The location journal: its switch, and the history deleted on request.
struct JournalSection: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false
    /// how many rows the last "Xoá lịch sử vị trí" deleted
    @State private var deleted: Int?
    /// the location history's rows, counted when the page opens (nil: not counted, or unreadable)
    @State private var history: (visits: Int, traces: Int)?

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle(isOn: $model.journalEnabled) {
                Label {
                    Text("Ghi nhật ký vị trí")
                } icon: {
                    SettingsIcon(symbol: "book.pages.fill", tint: .indigo)
                }
            }
            Button(role: .destructive) {
                confirming = true
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Xoá lịch sử vị trí")
                        if let deleted {
                            Text(deleted == 0 ? "Không còn gì để xoá" : "Đã xoá \(deleted) mục")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    SettingsIcon(symbol: "trash", tint: .red)
                }
            }
            .alert("Xoá lịch sử vị trí?", isPresented: $confirming) {
                Button("Xoá", role: .destructive, action: delete)
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Mọi chỗ đã ghé và vết đường đi đã ghi trên máy này. Dấu đã đi và điểm bỏ vẫn giữ.")
            }
            // what the location journal holds (Visit, Trace rows), in the records the app reads now
            LabeledContent {
                Text(history.map { "\($0.visits) · \($0.traces)" } ?? "—").monospacedDigit()
            } label: {
                Label {
                    Text("Lịch sử vị trí: chỗ ghé · điểm vết")
                } icon: {
                    SettingsIcon(symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: .gray)
                }
            }
            .onAppear { history = model.locationHistoryCount() }
            // counted again after "Xoá lịch sử vị trí", on the same page
            .onChange(of: model.historyDeletions) { history = model.locationHistoryCount() }
        } footer: {
            Text("Chỉ trong 18–29/10/2027, chỉ trên máy này")
        }
    }

    private func delete() {
        let before = model.saveIssue?.id
        let n = model.purgeLocationHistory(outsideTripOnly: false)
        // a write that failed is told by the alert, not as a count
        deleted = model.saveIssue?.id == before ? n : nil
    }
}

// MARK: - Permissions

struct PermissionsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    /// AlarmKit and ActivityKit states are read, not observed: bump to re-read after a request
    @State private var tick = 0
    /// iOS's upgrade to "Always" was asked once (here or on Today): Settings from then on
    @AppStorage(AppModel.locationAskedAlwaysKey) private var askedAlways = false

    var body: some View {
        let _ = tick
        let states = PermissionStates(model)
        Section {
            location(states.location)
            PermissionRow(
                title: "Thông báo", detail: "Nhắc giờ tàu, xe, đặt bàn", symbol: "bell.badge.fill", tint: .red,
                state: states.notifications,
                action: { Task { await model.notifications.requestAuthorization(); await model.notifications.refreshStatus(); if !model.notifications.authorized { openSettings() } } })
            PermissionRow(
                title: "Báo thức", detail: "Đánh thức trước ga cần xuống", symbol: "alarm.fill", tint: .orange,
                state: states.alarms,
                action: { Task { if !(await model.alarms.requestAuthorization()) { openSettings() }; tick += 1 } })
            PermissionRow(
                title: "Ảnh", detail: "Gắn ảnh vào nhật ký mỗi tối", symbol: "photo.on.rectangle.angled", tint: .indigo,
                state: states.photos,
                action: {
                    if model.photos.status == .notDetermined {
                        Task { await model.photos.request() }
                    } else {
                        openSettings()
                    }
                })
            PermissionRow(
                title: "Live Activities", detail: "Ga kế, lúc xuống, Fuji bên nào", symbol: "dot.radiowaves.left.and.right", tint: .teal,
                state: states.live,
                action: openSettings)
        }
        .task { await model.notifications.refreshStatus() }
    }

    private func location(_ state: PermissionRow.State) -> some View {
        let status = model.location.authorization
        return PermissionRow(
            title: "Vị trí luôn bật", detail: "Nhắc khi tới quán, tới ga", symbol: "location.fill", tint: .blue,
            state: state,
            action: {
                switch status {
                case .notDetermined: model.location.requestWhenInUse()
                case .authorizedWhenInUse where !askedAlways:
                    // iOS shows this upgrade once; after that only Settings can change it
                    askedAlways = true
                    model.location.requestAlways()
                default: openSettings()
                }
            })
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

struct PermissionRow: View {
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

/// What each row of the Quyền page shows, read in one place for the page and for the main page's
/// "\(on)/\(total) đã bật" and "\(n) quyền đang tắt". AlarmKit's and ActivityKit's answers are read, not
/// observed: whoever shows them reads them again when it shows (a `tick`).
struct PermissionStates {
    let location: PermissionRow.State
    let notifications: PermissionRow.State
    let alarms: PermissionRow.State
    let photos: PermissionRow.State
    let live: PermissionRow.State

    init(_ model: AppModel) {
        location = switch model.location.authorization {
        case .authorizedAlways: .on
        case .authorizedWhenInUse: .partial("Khi dùng app")
        case .notDetermined: .ask
        default: .off
        }
        notifications = model.notifications.authorized ? .on : (model.notifications.undetermined ? .ask : .off)
        alarms = model.alarms.authorized ? .on : .ask
        photos = switch model.photos.status {
        case .authorized: .on
        case .limited: .partial("Một phần")
        case .notDetermined: .ask
        default: .off
        }
        live = model.live.isAvailable ? .on : .off
    }

    var all: [PermissionRow.State] { [location, notifications, alarms, photos, live] }
    /// "đã bật": given, or given in part ("Khi dùng app", "Một phần")
    var on: Int { all.filter { $0.isOn }.count }
    /// "đang tắt": refused, or not asked yet
    var off: Int { all.count - on }
}

extension PermissionRow.State {
    var isOn: Bool {
        switch self {
        case .on, .partial: true
        case .off, .ask: false
        }
    }
}
