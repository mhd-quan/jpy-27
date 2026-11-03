import Photos
import SwiftData
import SwiftUI
import TripKit

/// The evening page: where the day actually went, what ran late, what was dropped, the photos taken
/// at each stop, and the walked trail as a heatmap over the planned route.
struct JournalView: View {
    let dayKey: String
    @Environment(AppModel.self) private var model
    @Query private var visits: [Visit]
    @Query private var traces: [Trace]
    @Query private var expenses: [Expense]
    @State private var walked: (steps: Int, km: Double)?

    init(dayKey: String) {
        self.dayKey = dayKey
        // the day runs 4:00 to 4:00 next morning, Japan time, like TripKit's Journal
        let date = AppModel.shared.store.day(dayKey)?.date
        let midnight = date.flatMap(TripTime.midnight) ?? .distantPast
        let start = midnight.addingTimeInterval(4 * 3600)
        let end = midnight.addingTimeInterval(28 * 3600)
        let key: String? = dayKey
        _visits = Query(filter: #Predicate<Visit> { $0.arrival >= start && $0.arrival < end }, sort: \Visit.arrival)
        _traces = Query(filter: #Predicate<Trace> { $0.at >= start && $0.at < end }, sort: \Trace.at)
        _expenses = Query(filter: #Predicate<Expense> { $0.day == key })
    }

    private var day: Day? { model.store.day(dayKey) }

    var body: some View {
        if let day {
            let journal = Journal(store: model.store, day: day, visits: visits.map(\.record), marked: model.marked(day), now: model.now)
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.stack) {
                    JournalMap(day: day, trail: traces.map(\.coordinate) + visits.map { Coordinate($0.lat, $0.lng) })
                    JournalStats(journal: journal, walked: walked, spent: Yen.total(expenses.filter(\.isCountable).map(\.yen)))
                    if !model.photos.allowed {
                        JournalPhotoAccess()
                    }
                    SectionTitle("Theo lịch")
                    Card {
                        ForEach(Array(journal.entries.enumerated()), id: \.element.id) { i, entry in
                            if i > 0 { Divider() }
                            JournalEntryRow(day: day, entry: entry)
                        }
                    }
                    if !journal.extras.isEmpty {
                        SectionTitle("Ghé thêm")
                        Card {
                            ForEach(Array(journal.extras.enumerated()), id: \.element.id) { i, extra in
                                if i > 0 { Divider() }
                                JournalExtraRow(extra: extra)
                            }
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 32)
            }
            .screen()
            .navigationTitle("Nhật ký · Ngày \(day.n)")
            .task(id: dayKey) { await loadWalked(day) }
        } else {
            ContentUnavailableView("Không có ngày này", systemImage: "calendar.badge.exclamationmark")
        }
    }

    private func loadWalked(_ day: Day) async {
        guard let midnight = TripTime.midnight(day.date) else { return }
        let start = midnight.addingTimeInterval(4 * 3600)
        let end = min(model.now, midnight.addingTimeInterval(28 * 3600))
        guard end > start else { return }
        walked = await model.motion.walked(from: start, to: end)
    }
}

/// The planned routes faded, the walked trail as heat, the stops on top.
private struct JournalMap: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let trail: [Coordinate]

    var body: some View {
        let base = MapContent.day(day, model: model, along: false)
        let content = MapContent(
            routes: base.routes.map { r in
                var faded = r
                faded.opacity = 0.5
                return faded
            },
            pins: base.pins,
            heat: trail
        )
        TripMap(content: content, showsUser: false, interactive: true, insets: UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28), frameID: day.key)
            .frame(height: 300)
            .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
            .accessibilityLabel("Bản đồ đường đã đi ngày \(day.n)")
    }
}

private struct JournalStats: View {
    let journal: Journal
    let walked: (steps: Int, km: Double)?
    let spent: Int

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 20) {
                Stat(value: "\(journal.visited)/\(journal.entries.count)", label: "điểm đã ghé")
                if let walked {
                    Stat(value: Fmt.km(walked.km), label: "\(Fmt.grouped(walked.steps)) bước")
                }
                Stat(value: Fmt.yen(spent), label: "đã chi")
                if journal.skipped > 0 {
                    Stat(value: "\(journal.skipped)", label: "đã bỏ")
                }
            }
        }
    }
}

private struct JournalPhotoAccess: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Gắn ảnh đã chụp vào từng điểm dừng")
                    .font(.subheadline)
                Spacer(minLength: 0)
                Button("Cho phép") {
                    Task { await model.photos.request() }
                }
                .buttonStyle(.pressable(.bordered))
            }
        }
    }
}

/// One planned stop: when you arrived against the plan, and the photos taken there.
private struct JournalEntryRow: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let entry: Journal.Entry
    @State private var assets: [PHAsset] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(arrivalText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.place.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(entry.status == .skipped ? .secondary : .primary)
                        .strikethrough(entry.status == .skipped)
                    status
                }
                Spacer(minLength: 0)
            }
            if !assets.isEmpty {
                HStack(spacing: 6) {
                    ForEach(assets, id: \.localIdentifier) { a in
                        AssetImage(asset: a, side: 120)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.leading, 54)
            }
        }
        .accessibilityElement(children: .combine)
        .task(id: "\(entry.index)-\(model.photos.allowed)") { await loadPhotos() }
    }

    private var arrivalText: String {
        if case .visited(let arrival, _, _) = entry.status { return TripTime.clock(arrival) }
        return entry.stop.at ?? ""
    }

    @ViewBuilder
    private var status: some View {
        switch entry.status {
        case .visited(_, _, let late):
            if let late, late >= 3 {
                Tag(text: "+\(late) phút", symbol: "clock.badge.exclamationmark", tint: .red)
            } else if let late, late <= -3 {
                Tag(text: "sớm \(-late) phút", symbol: "clock", tint: .green)
            } else {
                Tag(text: "Đúng giờ", symbol: "checkmark", tint: .green)
            }
        case .skipped:
            Tag(text: "Bỏ", symbol: "xmark", tint: .secondary)
        case .ahead:
            Tag(text: "Chưa tới", tint: .secondary)
        }
    }

    private func loadPhotos() async {
        guard model.photos.allowed, case .visited(let arrival, let departure, _) = entry.status else {
            assets = []
            return
        }
        let from = arrival.addingTimeInterval(-10 * 60)
        let to = departure.map { $0.addingTimeInterval(10 * 60) } ?? arrival.addingTimeInterval(60 * 60)
        let found = await model.photos.photos(from: from, to: to, near: entry.place.coordinate, limit: 3)
        guard !Task.isCancelled else { return }
        assets = found
    }
}

/// A stay that was not in the plan: a known place when one is near, else just the time.
private struct JournalExtraRow: View {
    let extra: Journal.Extra

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(TripTime.clock(extra.visit.arrival))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(extra.place?.name ?? "Một chỗ ngoài lịch")
                    .font(.body.weight(.semibold))
                if let d = extra.visit.departure {
                    Text("\(Fmt.duration(d.timeIntervalSince(extra.visit.arrival) / 60))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
