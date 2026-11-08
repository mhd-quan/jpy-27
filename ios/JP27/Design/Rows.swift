import SwiftUI
import TripKit

// Rows shared by Today, the day page, guides and lists, so the same thing always looks the same.

/// One item of a day's timeline, on a rail drawn the web's way: a move runs as a thick line in its
/// operator's colour (dashed over water and air, dotted on foot) with its mode in a dot; a stop is
/// a numbered node in its kind's colour, stamped red once visited; a station is an open ring. The
/// rail through a stop takes the colours of the moves either side, so the day reads as one line.
/// Rows stack with no spacing so the rail runs on unbroken.
struct ItemRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model
    /// the card the row sits on, which its nodes cut out of the rail with
    @Environment(\.cardSurface) private var surface
    let day: Day
    let index: Int
    var showsCheck = true
    /// under a stop's text, inside the row so the rail runs past it (the map's side trips)
    var below: AnyView?

    private var item: DayItem { day.items[index] }

    /// from the row's top to the middle of its node
    private static let nodeCenter: CGFloat = 20
    private static let timeWidth: CGFloat = 44
    private static let railWidth: CGFloat = 26

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TimeColumn(day: day, index: index, at: item.at)
                .padding(.top, 1)
            node
                .frame(width: Self.railWidth)
            switch item {
            case .stop(let s): stop(s)
            case .move(let m): move(m)
            }
        }
        .padding(.vertical, 9)
        .background(alignment: .topLeading) {
            rail
                .frame(width: Self.railWidth)
                .padding(.leading, Self.timeWidth + 10)
        }
    }

    // MARK: Rail

    @ViewBuilder
    private var rail: some View {
        switch item {
        case .move(let m):
            railLine(m)
        case .stop:
            VStack(spacing: 0) {
                segment(index - 1).frame(height: Self.nodeCenter)
                segment(index + 1)
            }
        }
    }

    /// The half of a stop's rail toward item `i`: that move's line, a hairline toward another
    /// stop, nothing past either end of the day.
    @ViewBuilder
    private func segment(_ i: Int) -> some View {
        if day.items.indices.contains(i) {
            if case .move(let m) = day.items[i] {
                railLine(m)
            } else {
                RailLine().stroke(Color.secondary.opacity(0.3), lineWidth: 2)
            }
        } else {
            Color.clear
        }
    }

    private func railLine(_ m: Move) -> some View {
        let line = model.store.line(m.leg.line)
        let mode = line?.mode ?? .walk
        let color = mode == .walk ? Color.secondary.opacity(0.55) : Color(hex: line?.color ?? "#8E8E93")
        return RailLine().stroke(color, style: mode.rail(mode == .walk ? 3 : 4))
    }

    @ViewBuilder
    private var node: some View {
        switch item {
        case .move(let m):
            let line = model.store.line(m.leg.line)
            ModeDot(mode: line?.mode ?? .walk, color: Color(hex: line?.color ?? "#8E8E93"), size: 24)
                .background(Circle().fill(surface ?? Palette.card))
                .padding(.top, Self.nodeCenter - 12 - 9)
        case .stop(let s):
            let place = model.store.place(s.place)
            if place?.kind == .station {
                Circle()
                    .fill(surface ?? Palette.card)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.75), lineWidth: 3))
                    .frame(width: 16, height: 16)
                    .padding(.top, Self.nodeCenter - 8 - 9)
            } else if model.isDone(day, index) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Palette.sun, in: .circle)
                    .padding(.top, Self.nodeCenter - 11 - 9)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("\(ordinal(s))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background((place?.kind ?? .sight).tint, in: .circle)
                    .overlay(Circle().strokeBorder(surface ?? Palette.card, lineWidth: 2))
                    .padding(.top, Self.nodeCenter - 11 - 9)
                    .opacity(model.isSkipped(day, index) ? 0.45 : 1)
            }
        }
    }

    /// The stop's number among the day's stops, stations not counted (the web's numbered nodes).
    private func ordinal(_ s: Stop) -> Int {
        if let n = s.n { return n }
        return day.stops.filter { $0.index <= index && model.store.place($0.stop.place)?.kind != .station }.count
    }

    // MARK: Stop

    private func stop(_ s: Stop) -> some View {
        let place = model.store.place(s.place)
        let done = model.isDone(day, index)
        let skipped = model.isSkipped(day, index)
        let reserved = s.place.map(model.store.reserved.contains) ?? false
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(s.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(skipped)
                    .foregroundStyle(done || skipped ? .secondary : .primary)
                if let text = s.text {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                let tags = tagList(s, place: place, reserved: reserved)
                if !tags.isEmpty {
                    HStack(spacing: 6) { ForEach(tags, id: \.text) { $0 } }
                }
                if let below {
                    below.padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            if showsCheck, place?.kind != .station {
                CheckButton(isOn: done) { withAnimation(Motion.reduced(Motion.pick, reduceMotion)) { model.toggleDone(day, index) } }
                    .padding(.top, -10)
            }
        }
        .contentShape(.rect)
        .opacity(skipped ? 0.55 : 1)
        .accessibilityElement(children: .contain)
    }

    private func tagList(_ s: Stop, place: Place?, reserved: Bool) -> [Tag] {
        var tags: [Tag] = []
        if reserved { tags.append(Tag(text: "Đã đặt", symbol: "checkmark.seal.fill", tint: Palette.matcha)) }
        if let cost = s.cost { tags.append(Tag(text: Fmt.yen(cost), tint: .secondary)) }
        if place?.payment == .cash { tags.append(Tag(text: "Tiền mặt", symbol: "banknote.fill", tint: Place.Kind.food.tint)) }
        if s.isOptional { tags.append(Tag(text: "Nếu còn sức", tint: .secondary)) }
        return tags
    }

    // MARK: Move

    private func move(_ m: Move) -> some View {
        let line = model.store.line(m.leg.line)
        let mode = line?.mode ?? .walk
        let minutes = model.itinerary.minutes(of: m, pace: model.pace.factor)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(moveTitle(m, line: line, mode: mode, minutes: minutes))
                    .font(.subheadline.weight(mode == .walk ? .regular : .semibold))
                if let note = m.leg.note {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.top, 3)
            Spacer(minLength: 0)
            if mode != .walk, model.store.ride(containing: m.leg.id, on: day) != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 5)
            }
        }
        .foregroundStyle(model.isDone(day, index) ? .secondary : .primary)
        .accessibilityElement(children: .combine)
    }

    private func moveTitle(_ m: Move, line: Line?, mode: Mode, minutes: Double) -> String {
        let to = model.store.place(m.leg.to)?.name ?? m.leg.to
        if mode == .walk {
            var parts = ["Đi bộ \(Fmt.duration(minutes))"]
            if let w = m.leg.walk {
                parts.append(Fmt.km(w.km))
                if w.up >= 20 { parts.append("lên \(Int(w.up)) m") }
            }
            return parts.joined(separator: " · ") + " → \(to)"
        }
        return "\(line?.name ?? m.leg.line) → \(to)" + (m.leg.min.map { " · \($0) phút" } ?? "")
    }
}

/// The time an item is planned for and, today, how far off the projection runs.
struct TimeColumn: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let index: Int
    let at: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(at ?? "")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if let delta {
                Text(delta > 0 ? "+\(delta)" : "\(delta)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(delta > 0 ? .red : .green)
                    .accessibilityLabel(delta > 0 ? "trễ \(delta) phút" : "sớm \(-delta) phút")
            }
        }
        .frame(width: 44, alignment: .trailing)
    }

    /// Minutes the projection runs behind (positive) the planned time, today only.
    private var delta: Int? {
        guard model.today?.key == day.key, !model.isDone(day, index), let planned = TripTime.minutes(at),
              let slot = model.slot(index) else { return nil }
        let d = Int((slot.ready - Double(planned)).rounded())
        return abs(d) >= 3 ? d : nil
    }
}

/// A place in a list: photo, name, what it is.
struct PlaceRow: View {
    let place: Place
    var detail: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            PlacePhoto(photo: place.hero, maxPixel: 200)
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .center) {
                    if place.hero == nil {
                        Image(systemName: place.kind.symbol).foregroundStyle(.secondary)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body.weight(.semibold)).lineLimit(2)
                if let detail = detail ?? place.dish ?? place.ja {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A researched dish: Japanese to point at, the reading, what it is, the price.
struct DishRow: View {
    let item: MenuItem
    var showsNote = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.ja).font(.headline).environment(\.locale, Locale(identifier: "ja_JP"))
                    if item.pick == .signature { Image(systemName: "star.fill").font(.caption).foregroundStyle(.orange) }
                }
                if let r = item.romaji { Text(r).font(.caption).foregroundStyle(.secondary).italic() }
                Text(item.vi).font(.subheadline)
                if showsNote, let note = item.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if let yen = item.yen {
                YenText(yen: yen).font(.subheadline.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "còn 23 phút", "12:40", updating on its own.
struct Countdown: View {
    let target: Date
    let now: Date

    var body: some View {
        let minutes = Int((target.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 {
            Text("Đi ngay").foregroundStyle(.red)
        } else if minutes < 90 {
            Text("còn \(minutes) phút").monospacedDigit()
        } else {
            Text("lúc \(TripTime.clock(target))").monospacedDigit()
        }
    }
}
