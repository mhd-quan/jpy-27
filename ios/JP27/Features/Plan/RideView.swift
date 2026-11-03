import SwiftUI
import TripKit

/// One ride: where to sit, the stations as a strip with what shows on each side, the stop before
/// yours, and — while riding — the live position and the alarm.
struct RideView: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        if let ride = (model.store.trip.rides + model.store.trip.altRides).first(where: { $0.id == id }) {
            PlanRideContent(ride: ride)
        } else {
            ContentUnavailableView("Không có chuyến này", systemImage: "tram")
        }
    }
}

private struct PlanRideContent: View {
    @Environment(AppModel.self) private var model
    let ride: Ride
    // counted here around the live card, whose start and end buttons are gone once pressed; a ride
    // that starts or ends by itself (at the station, on arrival) stays quiet
    @State private var followed = 0
    @State private var ended = 0

    private var isLive: Bool { model.live.ride?.id == ride.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                PlanRideHeader(ride: ride)
                PlanRideLive(ride: ride, followed: $followed, ended: $ended)
                    .sensoryFeedback(.start, trigger: followed)
                    .sensoryFeedback(.stop, trigger: ended)
                PlanRideSeat(ride: ride)
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Các ga", trailing: ride.hidden > 0 ? "bỏ qua \(ride.hidden) ga tàu chạy suốt" : nil)
                    Card(padding: 14) {
                        PlanStationStrip(ride: ride, status: isLive ? model.live.status : nil)
                    }
                }
                if !ride.transfers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Đổi tàu")
                        Card {
                            PlanRows(items: ride.transfers) { t in
                                PlanParagraph(title: t.at, text: t.text)
                            }
                        }
                    }
                }
                if let alight = ride.alight { PlanAlightCard(alight: alight, station: ride.toName) }
                if ride.board != nil || ride.pay != nil || ride.onboard != nil {
                    Card {
                        if let board = ride.board { PlanInfoRow(symbol: "door.left.hand.open", text: board, label: "Lên xe") }
                        if let pay = ride.pay { PlanInfoRow(symbol: "yensign.circle", text: pay, label: "Trả tiền") }
                        if let onboard = ride.onboard { PlanInfoRow(symbol: "cup.and.saucer", text: onboard, label: "Trên tàu") }
                    }
                }
                PlanLinkChips(sources: ride.sources)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .screen()
        .navigationTitle(ride.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Header and seat

private struct PlanRideHeader: View {
    @Environment(AppModel.self) private var model
    let ride: Ride

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LineBadge(name: ride.lineName, color: Color(hex: ride.color), mode: planRideMode(ride, store: model.store))
            Text("\(ride.fromName) → \(ride.toName)").font(.title2.weight(.bold))
            HStack(spacing: 20) {
                if let at = ride.at { Stat(value: at, label: "khởi hành") }
                if let min = ride.min { Stat(value: "\(min) phút", label: "trên tàu") }
                Stat(value: Fmt.km(ride.km), label: "quãng đường")
                if let day = model.store.day(ride.day) { Stat(value: planDayName(day.key, store: model.store), label: Fmt.shortDate(day.date)) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.top, 8)
    }
}

private struct PlanRideSeat: View {
    let ride: Ride

    var body: some View {
        if ride.seatVerdict != nil || ride.seat != nil || ride.train != nil {
            Card {
                if let verdict = ride.seatVerdict {
                    Label(verdict, systemImage: verdictSymbol(verdict))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                if let seat = ride.seat { Text(seat).font(.subheadline) }
                if let train = ride.train {
                    Divider()
                    PlanParagraph(title: "Tàu", text: train)
                }
            }
        }
    }

    private func verdictSymbol(_ v: String) -> String {
        if v.contains("trái") { return "arrow.left.square.fill" }
        if v.contains("phải") { return "arrow.right.square.fill" }
        return "rectangle.split.2x1.fill"
    }
}

// MARK: - Live

private struct PlanRideLive: View {
    @Environment(AppModel.self) private var model
    let ride: Ride
    @Binding var followed: Int
    @Binding var ended: Int

    var body: some View {
        if model.live.ride?.id == ride.id {
            Card {
                if let s = model.live.status {
                    let next = s.nextStop.map { ride.stations[$0] }
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.alightSoon ? "Chuẩn bị xuống" : "Ga tiếp theo").font(.caption).foregroundStyle(s.alightSoon ? Color.red : Color.secondary)
                            Text(next?.en ?? ride.toName).font(.title2.weight(.bold))
                            if let ja = next?.ja { Text(ja).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if let arrival = model.live.arrival {
                            Stat(value: TripTime.clock(arrival), label: "tới \(ride.toName)")
                        }
                    }
                    ProgressView(value: min(1, max(0, s.progress)))
                        .tint(Color(hex: ride.color))
                    if let side = s.fujiSide {
                        Label("Fuji bên \(side == .left ? "trái" : "phải")", systemImage: side == .left ? "arrow.left" : "arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                } else {
                    Label("Đang chờ vị trí trên tuyến", systemImage: "location.circle")
                        .foregroundStyle(.secondary)
                }
                alarmToggle
                Button(role: .destructive) {
                    ended += 1
                    Task { await model.live.end(model: model, immediately: true) }
                } label: {
                    Text("Kết thúc").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        } else {
            VStack(spacing: 12) {
                Button {
                    followed += 1
                    withAnimation(.smooth) { model.live.start(ride, model: model) }
                } label: {
                    Label("Theo dõi chuyến", systemImage: "dot.radiowaves.left.and.right")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                alarmToggle
                    .padding(.horizontal, 4)
            }
        }
    }

    /// A real alarm: it rings through silent mode, so it says so, and it is off by default on
    /// boats, buses and short rides.
    private var alarmToggle: some View {
        Toggle(isOn: alarmBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Báo thức trước ga xuống")
                Text("Kêu cả khi máy để im lặng")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var alarmBinding: Binding<Bool> {
        Binding(get: { model.wakeAlarmIsOn(ride) }, set: { model.setWakeAlarm($0, for: ride) })
    }
}

// MARK: - Station strip

/// Stations top to bottom on a rail in the line's colour; what to see beside the stretch it covers.
private struct PlanStationStrip: View {
    let ride: Ride
    let status: RideTracker.Status?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ride.stations.indices, id: \.self) { i in
                PlanStationRow(ride: ride, index: i, status: status)
                ForEach(ride.events.indices.filter { ride.events[$0].from == i }, id: \.self) { e in
                    PlanEventRow(ride: ride, event: ride.events[e], last: i == ride.stations.count - 1)
                }
            }
        }
    }
}

private struct PlanStationRow: View {
    let ride: Ride
    let index: Int
    let status: RideTracker.Status?

    private var station: Ride.Station { ride.stations[index] }
    private var color: Color { Color(hex: ride.color) }
    private var isFirst: Bool { index == 0 }
    private var isLast: Bool { index == ride.stations.count - 1 }
    private var passed: Bool { status.map { station.km <= $0.km + 0.15 } ?? false }
    private var isNext: Bool { status?.nextStop == index }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(station.stop ? AnyShapeStyle(color) : AnyShapeStyle(Palette.card))
                    .overlay(Circle().stroke(color, lineWidth: 2.5))
                    .frame(width: station.stop ? 14 : 10, height: station.stop ? 14 : 10)
                if isNext {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor, in: .circle)
                }
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(station.en).font(station.stop ? .body.weight(.semibold) : .subheadline)
                    ForEach(station.marks, id: \.self) { mark in
                        if let tag = markTag(mark) { tag }
                    }
                }
                Text(station.ja).font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(passed ? Color.secondary : Color.primary)
            Spacer(minLength: 0)
            Text(Fmt.decimal(station.km, digits: 1)).font(.caption).monospacedDigit().foregroundStyle(.tertiary)
        }
        .frame(minHeight: station.stop ? 48 : 36)
        // the rail, sized to the row: half above the dot, half below
        .background(alignment: .leading) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : color)
                Rectangle().fill(isLast ? Color.clear : color)
            }
            .frame(width: 4)
            .padding(.leading, 9)
        }
        .accessibilityElement(children: .combine)
    }

    private func markTag(_ mark: String) -> Tag? {
        switch mark {
        case "board": Tag(text: "Lên", tint: .green)
        case "alight": Tag(text: "Xuống", tint: .red)
        case "transfer": Tag(text: "Đổi tàu", tint: .blue)
        case "prev": Tag(text: "Chuẩn bị", tint: .orange)
        default: nil
        }
    }
}

/// What shows on which side from this station on.
private struct PlanEventRow: View {
    let ride: Ride
    let event: Ride.Event
    let last: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Tag(text: sideLabel, symbol: sideSymbol, tint: event.fuji ? .indigo : .secondary)
                if event.fuji { Tag(text: "Fuji", symbol: "mountain.2.fill", tint: .indigo) }
                if event.to > event.from, ride.stations.indices.contains(event.to) {
                    Text("tới \(ride.stations[event.to].en)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(event.what).font(.subheadline)
            if let tip = event.tip {
                Text(tip).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(event.fuji ? Color.indigo.opacity(0.08) : Color(.tertiarySystemFill).opacity(0.5), in: .rect(cornerRadius: 14, style: .continuous))
        .padding(.vertical, 4)
        .padding(.leading, 34)
        .overlay(alignment: .leading) {
            if !last {
                Rectangle().fill(Color(hex: ride.color)).frame(width: 4).padding(.leading, 9)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sideLabel: String {
        switch event.side {
        case .left: "Bên trái"
        case .right: "Bên phải"
        case .both: "Hai bên"
        case .front: "Phía trước"
        case .down: "Phía dưới"
        }
    }

    private var sideSymbol: String {
        switch event.side {
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .both: "arrow.left.and.right"
        case .front: "arrow.up"
        case .down: "arrow.down"
        }
    }
}

/// The stop before yours: what the train will say, and what to do on the platform.
private struct PlanAlightCard: View {
    let alight: Ride.Alight
    let station: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Xuống ở \(station)")
            Card {
                Label("Chuẩn bị khi qua \(alight.prevSt)", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                if let announce = alight.announce {
                    HStack(alignment: .top) {
                        JapaneseLine(ja: announce, romaji: alight.announceRomaji, size: .title3)
                        Spacer(minLength: 0)
                        Button {
                            Speaker.shared.say(announce)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .frame(width: 44, height: 44)
                        }
                        // read aloud: the line answers under the finger
                        .buttonStyle(.pressable(.bordered))
                        .clipShape(.circle)
                        .accessibilityLabel("Nghe câu thông báo")
                    }
                }
                if let text = alight.text { Text(text).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - All rides

/// Every ride of the plan by day, the alternative day last.
struct TrainsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(model.store.trip.days + model.store.trip.altDays) { day in
                let rides = model.store.rides(on: day)
                if !rides.isEmpty {
                    Section {
                        ForEach(rides) { ride in
                            NavigationLink(value: Route.ride(ride.id)) {
                                PlanTrainRow(ride: ride)
                            }
                        }
                    } header: {
                        Text(day.isAlternative ? "\(day.title) (thay ngày \(day.replaces ?? day.n))" : "Ngày \(day.n) · \(day.title)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .paperList()
        .navigationTitle("Trên tàu")
    }
}

private struct PlanTrainRow: View {
    @Environment(AppModel.self) private var model
    let ride: Ride

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LineBadge(name: ride.lineName, color: Color(hex: ride.color), mode: planRideMode(ride, store: model.store))
            Text("\(ride.fromName) → \(ride.toName)" + (ride.at.map { " · \($0)" } ?? ""))
                .font(.body.weight(.semibold))
                .monospacedDigit()
            if let verdict = ride.seatVerdict {
                Text(verdict).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
