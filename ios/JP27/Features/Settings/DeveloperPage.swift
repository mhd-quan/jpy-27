import SwiftUI
import TripKit

// Nhà phát triển, in every build (spec 2.4): the frame readings over the map, the reschedule count, and the tools
// the device checks use. Each use of a tool is a line of the log (`dev`).

/// The tools of the device checks, here in Release too, for the build the owner really runs. A pretend failure is
/// switched on only through "Bật giả lỗi?", never kept past a relaunch (`Records.failSaves`, `failReads`), and the
/// main page shows a red band while one is on. Deleting the Fuji pictures asks first: Tải tất cả downloaded them.
struct DeveloperSection: View {
    /// "Chi tiết kiểm tra ở màn đi tàu": the ride card's lines for the device checks (`RideView`), off by default
    static let rideDetailsKey = "dev.rideDetails"

    @Environment(AppModel.self) private var model
    @AppStorage(MapPacer.readingsKey) private var readings = false
    @AppStorage(Self.rideDetailsKey) private var rideDetails = false
    /// what AlarmKit listed, the last time it was asked
    @State private var systemAlarms: String?
    /// what the last `uniqueProbe` found
    @State private var unique: String?
    /// the latest fix taken (`LocationService.fixedAt`), read on opening the page and on a tap
    @State private var lastFix: String?
    /// what `Caches/MapSnapshots` holds, read on opening the page
    @State private var mapPictures: String?
    /// how far the photos' tones moved from the 96 px thumbnail, the last time it was asked
    @State private var toneDrift: String?
    /// `FujiTerrainPictures.pictureOnly`, as the switch shows it (a static: not observed)
    @State private var fujiPictureOnly = FujiTerrainPictures.pictureOnly
    /// what `Caches/Fuji` holds, read on opening the page and after "Xoá"
    @State private var fujiPictures: String?
    /// a pretend failure asked for, waiting for "Bật"
    @State private var pending: Pending?
    /// "Xoá" of the Fuji pictures asked for, waiting for its confirmation
    @State private var clearingFuji = false
    /// what the last "Thông báo Đã tới thử" tap found, when it found no stop to post for
    @State private var arrivedNote: String?

    /// What "Bật giả lỗi?" would switch on.
    private enum Pending: Equatable {
        case saves(Records.FailSaves)
        case reads
    }

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { readings }, set: { on in
                readings = on
                AppLog.info(.dev, "Đo khung hình bản đồ", ["value": "\(on)"])
            })) {
                Label {
                    Text("Đo khung hình bản đồ")
                } icon: {
                    SettingsIcon(symbol: "speedometer", tint: .gray)
                }
            }
        } footer: {
            Text("Hiện ở góc bản đồ thời gian của từng khung hình.")
        }
        Section("Nhắc giờ và báo thức") {
            // since launch, as of when this page opened: one per return to the app before the trip
            LabeledContent {
                Text("\(model.reschedules) lần").monospacedDigit()
            } label: {
                Label {
                    Text("Đặt lại nhắc giờ, geofence, báo thức")
                } icon: {
                    SettingsIcon(symbol: "arrow.triangle.2.circlepath", tint: .gray)
                }
            }
            testAlarm(minutes: 2)
            testAlarm(minutes: 5)
            Button {
                AppLog.info(.dev, "Báo thức trong hệ thống")
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
            // for docs/superpowers/checklists/2026-11-device-phase1-3.md, Task 2.1c
            testArrived(asBeforeIDs: false)
            testArrived(asBeforeIDs: true)
        }
        Section("Sổ ghi chép") {
            // for docs/superpowers/checklists/2026-11-device-phase1-3.md, Task 1.4. Off is at once; any other
            // choice waits for "Bật" (the picker shows the real value meanwhile)
            Picker(selection: Binding(get: { Records.failSaves }, set: { choice in
                if choice == .off {
                    setSaves(.off)
                } else if choice != Records.failSaves {
                    pending = .saves(choice)
                }
            })) {
                ForEach(Records.FailSaves.allCases) { Text($0.label).tag($0) }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Giả lỗi lưu")
                        Text("Lần lưu tới: một lần báo lỗi rồi thôi. Mọi lần lưu: tới khi tắt").font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    SettingsIcon(symbol: "xmark.octagon", tint: .red)
                }
            }
            // on one row (a section's modifier goes to each of its rows); the toggle below asks through it too.
            // Swiping the alert away is "Huỷ"; the choice comes with the button, so the order of the two does not matter
            .alert("Bật giả lỗi?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { p in
                Button("Bật") { apply(p) }
                Button("Huỷ", role: .cancel) {}
            } message: { p in
                Text(p == .reads ? "Đọc sổ chi sẽ báo lỗi tới khi tắt hoặc mở lại app." : "Lưu sẽ báo lỗi tới khi tắt hoặc mở lại app.")
            }
            Toggle(isOn: Binding(get: { Records.failReads }, set: { on in
                if on { pending = .reads } else { setReads(false) }
            })) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Giả lỗi đọc sổ chi")
                        Text("Mọi lần đọc sổ chi để ghi hay để đồng bộ báo lỗi, tới khi tắt").font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    SettingsIcon(symbol: "xmark.octagon", tint: .red)
                }
            }
            Button {
                AppLog.info(.dev, "Thử ghi trùng chỉ số")
                unique = model.uniqueProbe()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Thử ghi trùng chỉ số")
                        if let unique {
                            Text(unique).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    SettingsIcon(symbol: "square.on.square", tint: .gray)
                }
            }
        }
        Section("Đi tàu và bản đồ") {
            Toggle(isOn: Binding(get: { rideDetails }, set: { on in
                rideDetails = on
                AppLog.info(.dev, "Chi tiết kiểm tra ở màn đi tàu", ["value": "\(on)"])
            })) {
                Label {
                    Text("Chi tiết kiểm tra ở màn đi tàu")
                } icon: {
                    SettingsIcon(symbol: "tram.fill", tint: .gray)
                }
            }
            // for docs/superpowers/checklists/2026-11-device-phase1-3.md, Bước 0: fixes still taken after
            // the phone's clock was set back (`Presence.takes`)
            Button {
                AppLog.info(.dev, "Vị trí lúc")
                lastFix = lastFixSummary()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vị trí lúc")
                        Text(lastFix ?? "—").font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                    }
                } icon: {
                    SettingsIcon(symbol: "location", tint: .gray)
                }
            }
            .onAppear { lastFix = lastFixSummary() }
            // for docs/perf/2026-11-device-perf-phase4-5.md, Task 4.1: a picture and the live map that replaces
            // it frame the same view; marking stops adds no picture
            NavigationLink {
                MapFrameCheck()
                    .onAppear { AppLog.info(.dev, "So khung bản đồ") }
            } label: {
                Label {
                    Text("So khung bản đồ")
                } icon: {
                    SettingsIcon(symbol: "map", tint: .teal)
                }
            }
            LabeledContent {
                Text(mapPictures ?? "—").monospacedDigit()
            } label: {
                Label {
                    Text("Ảnh bản đồ đã lưu")
                } icon: {
                    SettingsIcon(symbol: "photo.on.rectangle", tint: .gray)
                }
            }
            .task { mapPictures = await MapSnapshots.usage() }
        }
        Section("Ảnh và Fuji") {
            // for docs/perf/2026-11-device-perf-phase4-5.md, Task 5.1a: the tone of a photo read from the decode its
            // page draws, against the one the 96 px thumbnail gave before
            Button {
                AppLog.info(.dev, "So màu ảnh")
                let photos = toneDriftPhotos()
                toneDrift = "Đang so \(photos.count) ảnh…"
                Task { toneDrift = await PhotoCache.toneDrift(photos) }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("So màu ảnh: mới và cũ")
                        if let toneDrift {
                            Text(toneDrift).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    SettingsIcon(symbol: "eyedropper", tint: .gray)
                }
            }
            // for docs/perf/2026-11-device-perf-phase4-5.md, Task 5.3: what MapKit's snapshotter draws of the terrain,
            // with no live map coming in under it (not kept)
            Toggle(isOn: Binding(get: { fujiPictureOnly }, set: { on in
                fujiPictureOnly = on
                FujiTerrainPictures.pictureOnly = on
                AppLog.info(.dev, "Fuji: chỉ ảnh địa hình", ["value": "\(on)"])
            })) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fuji: chỉ ảnh địa hình")
                        Text("Trang Fuji và thẻ điểm ngắm chỉ hiện ảnh chụp sẵn, không mở bản đồ thật, tới khi tắt hoặc mở lại app").font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    SettingsIcon(symbol: "mountain.2", tint: Palette.fuji)
                }
            }
            .onAppear { fujiPictureOnly = FujiTerrainPictures.pictureOnly }
            LabeledContent {
                HStack(spacing: 12) {
                    Text(fujiPictures ?? "—").monospacedDigit()
                    // only the folder's own pictures, and those in memory: the next page draws its picture afresh.
                    // Not while a download runs: Tải tất cả may be drawing them now
                    Button("Xoá", role: .destructive) { clearingFuji = true }
                        .buttonStyle(.borderless)
                        .disabled(model.downloads.busy)
                }
            } label: {
                Label {
                    Text("Ảnh địa hình Fuji đã lưu")
                } icon: {
                    SettingsIcon(symbol: "photo.on.rectangle", tint: .gray)
                }
            }
            .task { fujiPictures = await FujiTerrainPictures.usage() }
            // on its row: a section's modifier goes to each of its rows
            .alert("Xoá ảnh địa hình Fuji?", isPresented: $clearingFuji) {
                Button("Xoá", role: .destructive, action: clearFuji)
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Trang Fuji khi mất sóng thiếu ảnh tới khi tải lại.")
            }
        }
    }

    /// The Fuji pictures deleted, unless a download began while the confirmation was up (one resumed on its own).
    private func clearFuji() {
        guard !model.downloads.busy else { return }
        AppLog.info(.dev, "Xoá ảnh địa hình Fuji")
        Task {
            await FujiTerrainPictures.shared.clear()
            fujiPictures = await FujiTerrainPictures.usage()
            // Dùng khi mất sóng says what is there now
            await model.downloads.readiness.refresh()
        }
    }

    /// Switches on what "Bật giả lỗi?" asked for.
    private func apply(_ p: Pending) {
        switch p {
        case .saves(let choice): setSaves(choice)
        case .reads: setReads(true)
        }
    }

    private func setSaves(_ choice: Records.FailSaves) {
        Records.failSaves = choice
        AppLog.info(.dev, "Giả lỗi lưu", ["value": choice.rawValue])
    }

    private func setReads(_ on: Bool) {
        Records.failReads = on
        AppLog.info(.dev, "Giả lỗi đọc sổ chi", ["value": "\(on)"])
    }

    /// For "So màu ảnh": the day covers (JPEG, the most shrunk when a tone is read) first, then bundled place
    /// photos by name, twenty in all
    private func toneDriftPhotos() -> [Photo] {
        let covers = HomeCovers.byDay.keys.sorted().compactMap { HomeCovers.byDay[$0]?.photo }
        let places = model.store.places.values.compactMap(\.hero).filter(\.isBundled).sorted { $0.src < $1.src }
        var seen = Set<String>()
        return Array((covers + places).filter { seen.insert($0.src).inserted }.prefix(20))
    }

    /// "7:20:05 · ±12 m": when the latest fix used was taken, on the phone's clock, and how precise it was
    private func lastFixSummary() -> String? {
        guard let at = model.location.fixedAt else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: at)
        let time = "\(c.hour ?? 0):\(String(format: "%02d", c.minute ?? 0)):\(String(format: "%02d", c.second ?? 0))"
        guard let accuracy = model.location.horizontalAccuracy else { return time }
        return "\(time) · ±\(Int(accuracy.rounded())) m"
    }

    /// A "Đã tới" notification, now, for the first food stop not yet done of the day the app shows
    /// (`focusDay`): as this build posts it on entering the stop's circle, or as builds before item ids
    /// did (the day and the index only). The first marks the stop; the second must mark nothing.
    private func testArrived(asBeforeIDs: Bool) -> some View {
        Button {
            let day = model.focusDay
            let kind = asBeforeIDs ? "old" : "new"
            guard let (i, stop) = day.stops.first(where: { model.store.place($0.stop.place)?.kind == .food && !model.isDone(day, $0.index) }),
                  let place = model.store.place(stop.place) else {
                AppLog.info(.dev, "Thông báo Đã tới thử", ["kind": kind, "stop": "none"])
                arrivedNote = "Không có chỗ ăn nào chưa tới"
                return
            }
            AppLog.info(.dev, "Thông báo Đã tới thử", ["kind": kind])
            arrivedNote = nil
            Task {
                if asBeforeIDs {
                    await model.notifications.arrivedAsBeforeIDs(at: place, day: day.key, index: i)
                } else {
                    await model.notifications.arrived(at: place, store: model.store, people: model.people, item: ItemRef(day: day.key, id: day.items[i].id))
                }
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(asBeforeIDs ? "Thông báo Đã tới thử, kiểu cũ" : "Thông báo Đã tới thử")
                    if let arrivedNote {
                        Text(arrivedNote).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                SettingsIcon(symbol: "checkmark.circle", tint: asBeforeIDs ? Color.gray : Color.green)
            }
        }
    }

    /// A real alarm for a ride that does not exist, set the way a followed ride sets one (asks for
    /// permission, replaces only once set), for the device checks in
    /// docs/superpowers/checklists/2026-11-device-phase1-3.md. Two lengths on the same ride: the
    /// second moves the first by more than two minutes, so it is a replacement.
    private func testAlarm(minutes: Double) -> some View {
        Button {
            AppLog.info(.dev, "Báo thức thử", ["minutes": "\(Int(minutes))"])
            Task { await model.alarms.alight(rideID: "debug.wake", station: "Ga thử", at: Date().addingTimeInterval(minutes * 60)) }
        } label: {
            Label {
                Text("Báo thức thử sau \(Int(minutes)) phút")
            } icon: {
                SettingsIcon(symbol: "alarm", tint: .orange)
            }
        }
    }
}
