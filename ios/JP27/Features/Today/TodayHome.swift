import SwiftUI
import TripKit

// MARK: - Home, before the trip

/// The trip's cover and what to do about it until the plane: photographs of where it goes, the
/// days left as the flag's red sun on white, the five cities as a metro line that steers the day
/// cards, booking windows as tickets, meals, a phrase, the checklist, Fuji and a rehearsal. Every
/// card opens what it shows; section titles only where the content cannot name itself.
struct TodayHome: View {
    @Environment(AppModel.self) private var model
    let days: Int
    /// the day card the carousel rests on; the metro line follows it and moves it
    @State private var focus: String?
    @State private var shown: TalkShowItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            HomeCover(days: days)
            // the metro line is the day cards' index, so the two sit together without a title
            VStack(alignment: .leading, spacing: 18) {
                HomeChapters(focus: $focus)
                    .padding(.horizontal, Metrics.gutter)
                HomeDays(focus: $focus)
            }
            HomeTickets()
            HomeMeals()
            HomePhrase(shown: $shown)
                .padding(.horizontal, Metrics.gutter)
            HomeChecklist()
                .padding(.horizontal, Metrics.gutter)
            HomeFuji()
                .padding(.horizontal, Metrics.gutter)
            HomeRehearse()
                .padding(.horizontal, Metrics.gutter)
        }
        .padding(.bottom, 40)
        .phraseCover($shown)
    }
}

// MARK: - Cover

/// Photographs of the trip, edge to edge under the status bar and fading into the paper; then the
/// countdown as the Hinomaru's disc beside the trip's two ends and its dates.
private struct HomeCover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let days: Int
    @State private var page: Int? = 0
    @State private var risen = false
    /// the photographs are on screen: off it, nothing turns or drifts
    @State private var visible = true
    /// pages turned by themselves since the cover came into view: one tour of the covers, then it
    /// rests, so a home left open does not redraw every frame for as long as it stays open
    @State private var toured = 0

    static let height: CGFloat = 520

    var body: some View {
        let shots = HomePicks.cover(model)
        let trip = model.store.trip
        VStack(alignment: .leading, spacing: 20) {
            photos(shots)
            HStack(alignment: .center, spacing: 18) {
                HomeSun(days: days, risen: risen)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(trip.chapters.first?.name ?? "") → \(trip.chapters.last?.name ?? "")")
                        .font(.title2.weight(.bold))
                        .tracking(-0.4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(HomePicks.dates(trip.meta))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(trip.days.count) ngày · \(trip.meta.nights) đêm")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(risen ? 1 : 0)
                .offset(y: risen ? 0 : 10)
            }
            .padding(.horizontal, Metrics.gutter)
            .accessibilityElement(children: .combine)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.7).delay(0.1)) { risen = true }
        }
        // a new photograph every few seconds while the cover is in view; a swipe restarts the wait.
        // Under a sheet or behind another tab it waits: nothing turns while you look at something
        // else, and no page turn lands in the middle of a sheet's zoom. (Read here, not in the
        // body, so opening a sheet does not re-run the cover.) Low Power Mode is part of the id: turning
        // it on cancels the wait at once, turning it off starts the wait again.
        .task(id: "\(page ?? 0)-\(visible)-\(model.lowPower)") {
            guard visible, !reduceMotion, !model.lowPower, shots.count > 1, toured < shots.count - 1 else { return }
            repeat {
                try? await Task.sleep(for: .seconds(6))
            } while !Task.isCancelled && !(model.sheets.isEmpty && model.tab == .today)
            // Low Power Mode: the covers stay where they are
            guard !Task.isCancelled, !model.lowPower else { return }
            toured += 1
            withAnimation(.smooth(duration: 0.9)) { page = ((page ?? 0) + 1) % shots.count }
        }
        .onChange(of: visible) { _, on in if on { toured = 0 } }
    }

    private func photos(_ shots: [HomeShot]) -> some View {
        let current = min(page ?? 0, max(0, shots.count - 1))
        let height = Self.height
        return ZStack(alignment: .bottom) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(shots.indices, id: \.self) { i in
                        Button {
                            model.present(.place(shots[i].place.id), from: "home.cover.\(i)")
                        } label: {
                            // the slow drift is drawn every frame: not in Low Power Mode
                            HomeCoverPhoto(photo: shots[i].photo, current: current == i && visible && !model.lowPower)
                        }
                        .buttonStyle(.pressable(.plain))
                        .containerRelativeFrame(.horizontal)
                        .sheetSource("home.cover.\(i)")
                        .accessibilityLabel(shots[i].place.name)
                        .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            // a swipe ticks as it lands; the page turning by itself does not
            .feelsPages(page)
            .scrollIndicators(.hidden)
            .onScrollVisibilityChange(threshold: 0.15) { visible = $0 }
            // a paper mist under the status bar, and the bottom fading into the page
            .overlay(alignment: .top) {
                LinearGradient(colors: [Palette.paper.opacity(0.9), Palette.paper.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(stops: [.init(color: Palette.paper.opacity(0), location: 0), .init(color: Palette.paper.opacity(0.85), location: 0.6), .init(color: Palette.paper, location: 1)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
                    .allowsHitTesting(false)
            }
            // pulled down, the photograph grows instead of leaving a gap above it, and its mist
            // and fade grow with it: scaled before them, the mist stayed where the photograph's
            // top had been and cut a white band across it
            .visualEffect { content, proxy in
                let y = proxy.frame(in: .scrollView(axis: .vertical)).minY
                return content.scaleEffect(y > 0 ? 1 + y / height : 1, anchor: .bottom)
            }

            if shots.indices.contains(current) {
                let shot = shots[current]
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 1) {
                        if let ja = shot.place.ja {
                            Text(ja)
                                .font(.mincho(19))
                                .environment(\.locale, Locale(identifier: "ja_JP"))
                        }
                        Text("\(shot.place.name) · Ngày \(shot.day.n)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        // the licences ask for the photographer's name; it links to the file page
                        if let credit = shot.photo.credit {
                            if let page = shot.photo.page.flatMap(URL.init(string:)) {
                                Link(credit, destination: page)
                                    .buttonStyle(.pressable(.borderless))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text(credit)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .lineLimit(1)
                    .id(current)
                    .transition(.blurReplace)
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(shots.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == current ? Palette.sun : Color.primary.opacity(0.2))
                                .frame(width: i == current ? 18 : 6, height: 6)
                        }
                    }
                    .padding(.bottom, 6)
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, Metrics.gutter)
                .animation(.smooth(duration: 0.4), value: current)
            }
        }
        .frame(height: Self.height)
    }
}

private struct HomeCoverPhoto: View {
    let photo: Photo
    let current: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .overlay {
                PlacePhoto(photo: photo, maxPixel: 2400)
                    // the covers are cut to the screen's own pixels (1290 × 1560): just enough
                    // over-scan for a light parallax (4% each side), and a slow drift a little closer
                    .scaleEffect(current && !reduceMotion ? 1.12 : 1.08)
                    .animation(current ? .easeInOut(duration: 10) : .smooth(duration: 0.5), value: current)
                    .visualEffect { content, proxy in
                        content.offset(x: -proxy.frame(in: .scrollView(axis: .horizontal)).minX * 0.04)
                    }
            }
            .clipped()
            .contentShape(.rect)
    }
}

/// The days left, white on the flat red disc of the flag. Still until touched: a tap sends one ring
/// out of it and counts the wait in another unit (days, weeks, hours).
private struct HomeSun: View {
    let days: Int
    let risen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var unit = 0
    @State private var taps = 0

    static let size: CGFloat = 112

    private var reading: (value: Int, label: String) {
        switch unit {
        case 1: (days / 7, "tuần")
        case 2: (days * 24, "giờ")
        default: (days, "ngày")
        }
    }

    var body: some View {
        let reading = self.reading
        Button {
            taps += 1
            withAnimation(.snappy) { unit = (unit + 1) % 3 }
        } label: {
            ZStack {
                Circle().fill(Palette.sun)
                VStack(spacing: -3) {
                    Text("\(reading.value)")
                        .font(.figure(reading.value >= 1000 ? 30 : reading.value >= 100 ? 40 : 46, weight: .heavy))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(reading.value)))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(reading.label)
                        .font(.caption2.weight(.heavy))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .contentTransition(.opacity)
                }
                .foregroundStyle(.white)
                .padding(10)
            }
            .frame(width: Self.size, height: Self.size)
            .background {
                // one ring per touch, out of the disc and gone
                if !reduceMotion {
                    Circle()
                        .stroke(Palette.sun, lineWidth: 1.5)
                        .keyframeAnimator(initialValue: SunRing(), trigger: taps) { ring, v in
                            ring.scaleEffect(v.scale).opacity(v.opacity)
                        } keyframes: { _ in
                            KeyframeTrack(\.scale) {
                                LinearKeyframe(1, duration: 0.01)
                                CubicKeyframe(1.32, duration: 0.7)
                            }
                            KeyframeTrack(\.opacity) {
                                LinearKeyframe(0.7, duration: 0.01)
                                CubicKeyframe(0, duration: 0.7)
                            }
                        }
                }
            }
        }
        // the unit turning is a choice: `pick`, not the card's press
        .buttonStyle(.pressable(.settle, felt: false))
        .sensoryFeedback(.pick, trigger: taps)
        .scaleEffect(risen ? 1 : 0.85)
        .opacity(risen ? 1 : 0)
        .accessibilityLabel("Còn \(days) ngày")
        .accessibilityHint("Đổi đơn vị")
    }
}

nonisolated private struct SunRing {
    var scale: CGFloat = 1
    var opacity: Double = 0
}

// MARK: - Chapters as a metro line

/// The five cities as stations on one line, each run as long as its nights. Tapping a station
/// moves the day cards to its first day; scrolling the cards lights the station they are in.
private struct HomeChapters: View {
    @Environment(AppModel.self) private var model
    @Binding var focus: String?
    @State private var drawn = false
    /// stations tapped; the cards swiped tick from the cards
    @State private var taps = 0

    private var current: Chapter? {
        let day = model.days.first { $0.key == focus } ?? model.days.first
        return day.flatMap { model.store.chapter(of: $0) }
    }

    var body: some View {
        let chapters = model.store.trip.chapters
        let total = chapters.reduce(0) { $0 + $1.nights + 1 }
        let current = self.current
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { g in
                let gap: CGFloat = 4
                let width = g.size.width - gap * CGFloat(max(0, chapters.count - 1))
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { i, c in
                        let on = current?.id == c.id
                        Button {
                            let first = model.days.first { c.days.contains($0.n) }?.key
                            if first != (focus ?? model.days.first?.key) { taps += 1 }
                            withAnimation(.smooth) { focus = first }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(c.kanji)
                                    .font(.mincho(on ? 20 : 16))
                                    .foregroundStyle(on ? c.tint : Color.secondary)
                                    .lineLimit(1)
                                    .fixedSize()
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(c.tint.opacity(on ? 1 : 0.4))
                                        .frame(height: on ? 8 : 6)
                                        .scaleEffect(x: drawn ? 1 : 0.001, anchor: .leading)
                                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.12 * Double(i)), value: drawn)
                                    Circle()
                                        .fill(Palette.card)
                                        .overlay(Circle().strokeBorder(on ? c.tint : Color.primary, lineWidth: 3.5))
                                        .frame(width: 16, height: 16)
                                }
                            }
                            .frame(width: width * CGFloat(c.nights + 1) / CGFloat(max(1, total)), alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(c.name), \(c.nights) đêm")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .animation(.smooth, value: current?.id)
            }
            .frame(height: 50)
            .sensoryFeedback(.pick, trigger: taps)

            if let c = current {
                NavigationLink(value: Route.stay(c.stay)) {
                    HStack(spacing: 14) {
                        Text(c.kanji)
                            .font(.mincho(30))
                            .foregroundStyle(c.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(c.name) · \(c.nights) đêm").font(.headline)
                            Text("\(c.short) · \(range(c))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Palette.card, in: .rect(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.pressable)
                .id(c.id)
                .transition(.blurReplace)
            }
        }
        .animation(.smooth, value: current?.id)
        .onAppear { drawn = true }
    }

    /// "Ngày 1–3 · 18–20/10"
    private func range(_ c: Chapter) -> String {
        let days = model.days.filter { c.days.contains($0.n) }
        guard let a = days.first, let b = days.last else { return "" }
        if a.n == b.n { return "Ngày \(a.n) · \(Fmt.shortDate(a.date))" }
        let from = Fmt.shortDate(a.date).split(separator: "/").first.map(String.init) ?? ""
        return "Ngày \(a.n)–\(b.n) · \(from)–\(Fmt.shortDate(b.date))"
    }
}

// MARK: - Days

/// Twelve cards, one per day, its best photograph, its number large and its city in kanji; the
/// day's real path drawn small in the corner. A card opens its day, growing into it.
private struct HomeDays: View {
    @Environment(AppModel.self) private var model
    @Binding var focus: String?

    var body: some View {
        ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(model.days) { day in
                        NavigationLink(value: Route.day(day.key)) {
                            HomeDayCard(day: day)
                        }
                        .buttonStyle(.pressable)
                        .sheetSource("home.day.\(day.key)")
                        // off centre a card shrinks a little and the paper shows through it
                        // (that part is drawn inside the card, see HomeDayCard)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content.scaleEffect(phase.isIdentity ? 1 : 0.93)
                        }
                        .id(day.key)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focus, anchor: .leading)
            // a station tapped moves the cards quietly: the station has ticked
            .feelsPages(focus)
            .contentMargins(.horizontal, Metrics.gutter, for: .scrollContent)
            .scrollIndicators(.hidden)
    }
}

private struct HomeDayCard: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        let chapter = model.store.chapter(of: day)
        let tint = chapter?.tint ?? Palette.sun
        let photo = HomePicks.photo(for: day, store: model.store)
        ZStack(alignment: .bottomLeading) {
            if let photo {
                PlacePhoto(photo: photo, maxPixel: 1200)
            } else {
                // no photograph for this day: its city in kanji on the chapter's colour
                LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(alignment: .topTrailing) {
                        Text(chapter?.kanji ?? "")
                            .font(.mincho(120))
                            .foregroundStyle(.white.opacity(0.18))
                            .padding(10)
                    }
            }
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.35), .init(color: .black.opacity(0.78), location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%02d", day.n))
                        .font(.figure(46, weight: .heavy))
                        .monospacedDigit()
                    Spacer()
                    Text(chapter?.kanji ?? "")
                        .font(.mincho(24))
                        .opacity(0.9)
                }
                Text("\(day.dowKanji) · \(day.dow), \(Fmt.shortDate(day.date))")
                    .font(.caption.weight(.semibold))
                    .opacity(0.85)
                Text(day.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(width: 272, height: 384)
        // the chapter's colour runs along the top like a livery stripe
        .overlay(alignment: .top) {
            tint.frame(height: 5)
        }
        .overlay(alignment: .topTrailing) {
            RouteSpark(day: day, store: model.store, weight: 2)
                .frame(width: 84, height: 60)
                .padding(6)
                // solid, not a material: twelve live blurs in a sliding row cost every frame
                .background(Palette.paper.opacity(0.9), in: .rect(cornerRadius: 14, style: .continuous))
                .padding(12)
                .padding(.top, 4)
        }
        // off centre, a fifth of the paper over the card: the same pixels as the opaque card at
        // 80 %, as one plain layer instead of a whole card made translucent, which is an offscreen
        // pass per card on every frame the row moves
        .overlay {
            Palette.paper
                .allowsHitTesting(false)
                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                    content.opacity(phase.isIdentity ? 0 : 0.2)
                }
        }
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .contentShape(.rect(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ngày \(day.n), \(day.dow) \(Fmt.shortDate(day.date)): \(day.title)")
    }
}

// MARK: - Booking windows as tickets

private struct HomeTickets: View {
    @Environment(AppModel.self) private var model
    @State private var at: Booking?

    /// Exact openings still ahead, soonest first, then the ones set by a rule.
    private var bookings: [Booking] {
        let timed = model.guide.bookings
            .filter { ($0.date ?? .distantPast) > model.now }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        return timed + model.guide.bookings.filter { $0.at == nil }
    }

    var body: some View {
        let bookings = self.bookings
        if !bookings.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline) {
                    SectionTitle("Đặt chỗ")
                    NavigationLink(value: Route.bookings) {
                        Text("Tất cả").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.pressable(.borderless))
                }
                .padding(.horizontal, Metrics.gutter)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(bookings, id: \.self) { b in
                            NavigationLink(value: Route.bookings) {
                                HomeTicket(booking: b, now: model.now)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $at)
                .feelsPages(at)
                .contentMargins(.horizontal, Metrics.gutter, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
        }
    }
}

/// A ticket: the date it opens on the stub, the booking and its countdown on the body.
private struct HomeTicket: View {
    let booking: Booking
    let now: Date
    private let stub: CGFloat = 84

    var body: some View {
        HStack(spacing: 0) {
            stubFace
                .frame(width: stub)
            VStack(alignment: .leading, spacing: 6) {
                Text(booking.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                // a dated window has its date on the stub; only a rule needs saying
                if booking.date == nil {
                    Text(booking.rule)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if let date = booking.date {
                    Label(countdown(date), systemImage: "alarm.fill")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Palette.sun, in: .capsule)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 290, height: 136)
        .foregroundStyle(.primary)
        .background(Palette.card, in: TicketShape(stub: stub))
        .overlay(alignment: .leading) {
            RailLine()
                .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .frame(width: 2)
                .padding(.vertical, 14)
                .offset(x: stub - 1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stubFace: some View {
        if let date = booking.date {
            let parts = TripTime.isoDate(of: date).split(separator: "-")
            VStack(spacing: 0) {
                Text(parts.count == 3 ? String(Int(parts[2]) ?? 0) : "")
                    .font(.figure(34, weight: .heavy))
                    .foregroundStyle(Palette.sun)
                Text(parts.count == 3 ? "Thg \(Int(parts[1]) ?? 0)" : "")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                Text(TripTime.clock(date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.top, 2)
            }
        } else {
            Image(systemName: "calendar.badge.clock")
                .font(.title)
                .foregroundStyle(Palette.ai)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func countdown(_ date: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds < 3600 { return "còn \(max(0, Int((seconds / 60).rounded(.up)))) phút" }
        if seconds < 86400 { return "còn \(Int(seconds / 3600)) giờ" }
        return "còn \(Int(seconds / 86400)) ngày"
    }
}

// MARK: - Meals

private struct HomeMeals: View {
    @Environment(AppModel.self) private var model
    @State private var at: String?

    var body: some View {
        let meals = HomePicks.meals(model)
        if !meals.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Quán ăn")
                    .padding(.horizontal, Metrics.gutter)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(meals, id: \.place.id) { meal in
                            Button {
                                model.present(.place(meal.place.id), from: "home.meal.\(meal.place.id)")
                            } label: {
                                HomeMealCard(meal: meal)
                            }
                            .buttonStyle(.pressable)
                            .sheetSource("home.meal.\(meal.place.id)")
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $at)
                .feelsPages(at)
                .contentMargins(.horizontal, Metrics.gutter, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct HomeMealCard: View {
    let meal: HomeMeal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlacePhoto(photo: meal.place.hero, maxPixel: 700)
                .overlay {
                    if meal.place.hero == nil {
                        Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 232, height: 174)
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Text("Ngày \(meal.day.n)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Palette.paper.opacity(0.9), in: .capsule)
                        .padding(10)
                }
            Text(meal.place.name)
                .font(.headline)
                .lineLimit(1)
            Text(meal.place.dish ?? meal.place.ja ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .frame(width: 232, alignment: .leading)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A phrase a day

/// One of the trip's own sentences, a different one each day; tapped, it fills the screen for the
/// person across the counter.
private struct HomePhrase: View {
    @Environment(AppModel.self) private var model
    @Binding var shown: TalkShowItem?
    @State private var turn = 0

    var body: some View {
        let list = model.guide.phrases.trip
        if !list.isEmpty {
            let base = Calendar.current.ordinality(of: .day, in: .year, for: model.now) ?? 0
            let i = (base + turn) % list.count
            let p = list[i]
            let item = TalkShowItem(id: "home-phrase-\(i)", ja: p.ja, romaji: p.romaji, vi: p.vi)
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Tag(text: p.use, tint: Palette.sun)
                        Spacer()
                        Button {
                            withAnimation(.snappy) { turn += 1 }
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Câu khác")
                        .buttonStyle(.borderless)
                        .sensoryFeedback(.pick, trigger: turn)
                    }
                    Button {
                        shown = item
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.ja)
                                .font(.mincho(28))
                                .environment(\.locale, Locale(identifier: "ja_JP"))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(p.romaji)
                                .font(.subheadline)
                                .italic()
                                .foregroundStyle(Palette.sun)
                            Text(p.vi)
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pressable(.plain))
                    .sheetSource(item.source)
                    .id(i)
                    .transition(.blurReplace)
                    TalkSpeakButton(ja: p.ja, size: 36)
                        .padding(.leading, -8)
                }
                .padding(18)
                .background(alignment: .topTrailing) {
                    // a quiet seal in the corner: 言, "words"
                    Text("言")
                        .font(.mincho(110))
                        .foregroundStyle(Palette.sun.opacity(0.07))
                        .offset(x: 14, y: -18)
                        .accessibilityHidden(true)
                }
                .background(Palette.card)
                .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
            }
        }
    }
}

// MARK: - Checklist

/// The guide's checks, now ticked off; kept on the phone.
private struct HomeChecklist: View {
    @Environment(AppModel.self) private var model
    @AppStorage("home.checks") private var doneRaw = ""

    private var done: Set<String> { Set(doneRaw.split(separator: "\n").map(String.init)) }

    var body: some View {
        let checks = model.guide.checks
        let done = self.done
        let count = checks.filter { done.contains($0.when) }.count
        if !checks.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle("Trước khi đi", trailing: "\(count)/\(checks.count)")
                Card {
                    Meter(value: Double(count) / Double(checks.count), tint: Palette.matcha)
                        .animation(.smooth, value: count)
                    ForEach(Array(checks.enumerated()), id: \.offset) { i, c in
                        if i > 0 { Divider().padding(.leading, 44) }
                        let on = done.contains(c.when)
                        HStack(alignment: .top, spacing: 6) {
                            CheckButton(isOn: on) {
                                toggle(c.when)
                                return true
                            }
                                .padding(.top, -10)
                                .padding(.leading, -10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.when)
                                    .font(.subheadline.weight(.semibold))
                                    .strikethrough(on)
                                Text(c.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .opacity(on ? 0.6 : 1)
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ key: String) {
        var set = done
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        withAnimation(.snappy) { doneRaw = set.sorted().joined(separator: "\n") }
    }
}

// MARK: - Fuji

private struct HomeFuji: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let spots = model.guide.fuji.spots
        let visible = spots.filter(\.visible).count
        let days = Array(Set(spots.compactMap(\.day))).sorted()
        NavigationLink(value: Route.fuji) {
            ZStack(alignment: .bottomLeading) {
                // Fuji above Suruga Bay from Satta Pass, on the Tōkaidō of day 5
                FujiScene()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text("富士山")
                        .font(.mincho(32))
                    Text("\(visible) chỗ thấy Fuji · ngày \(days.joined(separator: ", "))")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.9)
                    Text("Đèo Satta · \(FujiPhotograph.credit) / Wikimedia Commons")
                        .font(.caption2)
                        .opacity(0.7)
                        .lineLimit(1)
                        .padding(.top, 4)
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .frame(height: 260)
            .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
        }
        .buttonStyle(.pressable)
        .overlay(alignment: .topTrailing) {
            Button {
                model.present(.fujiFinder, from: "home.fuji.finder")
            } label: {
                Label("Tìm Fuji", systemImage: "location.north.line.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.pressable(.glass))
            .sheetSource("home.fuji.finder")
            .padding(14)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Rehearse

private struct HomeRehearse: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.present(.settings, from: "today.rehearse")
        } label: {
            HStack(spacing: 14) {
                GlyphTile(symbol: "play.fill", tint: Palette.ai, size: 38)
                Text("Chạy thử một ngày trong chuyến").font(.headline)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Palette.card, in: .rect(cornerRadius: 22, style: .continuous))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.pressable)
        .sheetSource("today.rehearse")
    }
}

// MARK: - Picks

struct HomeShot {
    let place: Place
    let photo: Photo
    let day: Day
}

struct HomeMeal {
    let place: Place
    let day: Day
}

/// The trip's cover photographs, chosen and cut by hand for the cover (Resources/Cover, listed in
/// cover.json): one per day, 1290 × 1560, sharp at the full width of the screen where the 800 px
/// Commons set of the site is not. Each carries its credit and Commons page.
enum HomeCovers {
    struct Pick {
        let place: String
        let photo: Photo
    }

    private struct Entry: Decodable {
        let day: String
        let place: String
        let file: String
        let caption: String?
        let credit: String?
        let page: String?
    }

    /// by day key
    static let byDay: [String: Pick] = {
        guard let url = Bundle.main.url(forResource: "cover", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [:] }
        var out: [String: Pick] = [:]
        for e in entries {
            // Photo has no public initialiser: build it the way the trip data does, from JSON
            let fields = ["kind": "cover", "src": e.file, "caption": e.caption, "credit": e.credit, "page": e.page].compactMapValues { $0 }
            guard let json = try? JSONSerialization.data(withJSONObject: fields),
                  let photo = try? JSONDecoder().decode(Photo.self, from: json) else { continue }
            out[e.day] = Pick(place: e.place, photo: photo)
        }
        return out
    }()
}

/// What the home page shows, picked from the data.
enum HomePicks {
    /// The photograph each day is best known by, where the bundled set has it.
    static let favourites: Set<String> = [
        "kanda-myojin", "sensoji", "meiji-jingu", "owakudani", "ise-naiku", "toshijima-wagu",
        "kiyomizudera", "bamboo-grove", "fushimi-inari", "hozenji",
    ]

    /// One photograph per day, all in the app (they work offline): the day's cover, else its
    /// favourite or first sight from the bundled Commons set.
    static func cover(_ model: AppModel) -> [HomeShot] {
        var out: [HomeShot] = []
        for day in model.days {
            if let pick = HomeCovers.byDay[day.key], let place = model.store.place(pick.place) {
                out.append(HomeShot(place: place, photo: pick.photo, day: day))
                continue
            }
            let places = day.stops.compactMap { model.store.place($0.stop.place) }
                .filter { $0.kind != .station && $0.hero?.isBundled == true }
            let pick = places.first { favourites.contains($0.id) } ?? places.first { $0.kind == .sight }
            if let pick, let photo = pick.hero { out.append(HomeShot(place: pick, photo: photo, day: day)) }
        }
        return out
    }

    /// A day's card photograph: its cover, a favourite, else a bundled sight, else anything it has.
    static func photo(for day: Day, store: TripStore) -> Photo? {
        if let pick = HomeCovers.byDay[day.key] { return pick.photo }
        let places = day.stops.compactMap { store.place($0.stop.place) }.filter { $0.kind != .station && $0.hero != nil }
        let bundled = places.filter { $0.hero?.isBundled == true }
        return (bundled.first { favourites.contains($0.id) } ?? bundled.first { $0.kind == .sight } ?? bundled.first ?? places.first)?.hero
    }

    /// Planned meals with a photograph and a menu, in the order they come.
    static func meals(_ model: AppModel) -> [HomeMeal] {
        var seen = Set<String>()
        var out: [HomeMeal] = []
        for day in model.days {
            for (_, stop) in day.stops {
                guard let p = model.store.place(stop.place), p.kind == .food, p.hero != nil, p.menu != nil,
                      seen.insert(p.id).inserted else { continue }
                out.append(HomeMeal(place: p, day: day))
            }
        }
        return Array(out.prefix(12))
    }

    /// "18 – 29 tháng 10, 2027"
    static func dates(_ meta: Meta) -> String {
        let a = meta.start.split(separator: "-").compactMap { Int($0) }
        let b = meta.end.split(separator: "-").compactMap { Int($0) }
        guard a.count == 3, b.count == 3 else { return "" }
        if a[1] == b[1] { return "\(a[2]) – \(b[2]) tháng \(a[1]), \(a[0])" }
        return "\(a[2])/\(a[1]) – \(b[2])/\(b[1]), \(b[0])"
    }
}
