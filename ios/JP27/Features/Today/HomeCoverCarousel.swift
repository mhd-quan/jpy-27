import SwiftUI
import TripKit
import UIKit
import UIKit.UIGestureRecognizerSubclass

// MARK: - The cover's photographs

/// The home's cover photographs, turned the TV app's way (measured frame by frame on a screen recording of it): the
/// next photograph fades in over the one on show where it stands, while the two drift a little the way the hand goes.
/// A drag scrubs the turn under the finger; let go, it finishes on a spring with no bounce that starts at the finger's
/// speed (`Motion.crossfade(velocity:)`), or falls back. A finger that comes down on a turn still running stops it
/// where it stands and takes it from there. By itself the cover turns every 6 s, the first photograph again after the
/// last.
///
/// Two layers, both always there: the photograph on show, and the one coming in, waiting at no opacity (so it is
/// decoded before it is needed). A turn moves one number, `HomeCoverTurn.at`, which only their opacity and offset
/// read: nothing is laid out, made or loaded while the photographs move, and no scroll view's offset drives them. A
/// turn that lands swaps the two layers' parts, not their photographs, so the one on show is never made again.
struct HomeCoverCarousel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let shots: [HomeShot]
    let height: CGFloat
    /// the photograph on show
    @State private var index = 0
    /// which of the two layers holds the photograph on show; the other holds the one coming in
    @State private var front = 0
    /// the turn under way, under the finger or on its spring; nil at rest
    @State private var turn: HomeCoverTurn?
    /// turns begun, so the end of one cut short by another does nothing
    @State private var turns = 0
    /// touches on the cover: each starts the wait for the next turn again
    @State private var touched = 0
    /// the cover is on screen: off it, nothing turns or drifts
    @State private var visible = true
    @State private var width: CGFloat = 430
    /// where the hand took hold; not drawn from, so not observed
    @State private var hand = Hand()

    final class Hand {
        /// the pan's translation as it began: the drag counts from there, so the photographs do not jump by the
        /// distance the finger had to go before it was a drag
        var origin: CGFloat = 0
        /// where the turn stood as the drag took it: 0 from rest, or where a turn the finger stopped stood
        var grab: CGFloat = 0
        /// where a turn the finger stopped was going: it goes on there if the finger leaves without a drag
        var held: CGFloat?
    }

    /// how far the two photographs drift in a turn: inside the covers' over-scan (they fill the frame, then 4 % a
    /// side at the resting 1.08: about 17 pt on the widest phones, more on narrower ones, whose frame crops the sides),
    /// so no edge ever shows; the TV app's wider art drifts further
    static let drift: CGFloat = 16
    /// the share of the width a drag takes to bring a photograph fully in
    static let reach: CGFloat = 0.6
    /// a let-go faster than this (points a second) finishes the turn the way the hand went, however far it came
    static let flick: CGFloat = 300

    var body: some View {
        let count = shots.count
        let shown = wrap(index)
        let side = turn?.side ?? 1
        let reveal = turn?.reveal ?? 0
        let incoming = wrap(shown + Int(side))
        let drift = reduceMotion ? 0 : Self.drift
        ZStack(alignment: .bottom) {
            if count > 0 {
                photos(shown: shown, incoming: incoming, reveal: reveal, side: side, drift: drift)
                captions(shown: shown, incoming: incoming, reveal: reveal, side: side, drift: drift)
            }
        }
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(1, $0) }
        .onScrollVisibilityChange(threshold: 0.15) { visible = $0 }
        // the photographs either side decoded while this one shows, so neither a turn nor a drag shows the grey under one
        .task(id: "\(shown)-\(count)") {
            guard count > 1 else { return }
            _ = await PhotoCache.shared.image(shots[wrap(shown + 1)].photo, maxPixel: 2400)
            _ = await PhotoCache.shared.image(shots[wrap(shown - 1)].photo, maxPixel: 2400)
        }
        // a turn after 6 s in a row with no sheet up and the Today tab open (so none lands in the zoom of a sheet
        // opening or closing; read here, not in the body, so a sheet does not re-run the cover); a touch starts the
        // wait again. Still under Reduce Motion, under VoiceOver (a turn would change the element being read) and in
        // Low Power Mode; each is in the id, so turned off, the turns start again. A swipe still turns.
        .task(id: "\(shown)-\(visible)-\(model.lowPower)-\(voiceOver)-\(reduceMotion)-\(touched)") {
            guard visible, !reduceMotion, !voiceOver, !model.lowPower, count > 1 else { return }
            var clear = 0
            while clear < 6 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                clear = model.sheets.isEmpty && model.tab == .today ? clear + 1 : 0
            }
            if let t = turn, t.done(CACurrentMediaTime()) { land(t) }
            guard !model.lowPower, turn == nil else { return }
            step(1)
        }
    }

    // MARK: Layers

    private func photos(shown: Int, incoming: Int, reveal: CGFloat, side: CGFloat, drift: CGFloat) -> some View {
        // what VoiceOver reads: where a turn is going, from the moment it starts
        let spoken = turn.map { dot($0) } ?? shown
        let height = self.height
        return ZStack {
            ForEach(0..<2, id: \.self) { layer in
                let up = layer == front
                // the slow drift is drawn every frame: not in Low Power Mode
                HomeCoverPhoto(photo: shots[up ? shown : incoming].photo, onShow: up, current: up && visible && !model.lowPower,
                               shift: up ? -side * drift * reveal : side * drift * (1 - reveal))
                    .opacity(up ? 1 : reveal)
                    .zIndex(up ? 0 : 1)
                    .sheetSource(up ? "home.cover.\(shown)" : "home.cover.coming")
            }
        }
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
        // pulled down, the photograph grows instead of leaving a gap above it, and its mist and fade grow with it:
        // scaled before them, the mist stayed where the photograph's top had been and cut a white band across it
        .visualEffect { content, proxy in
            let y = proxy.frame(in: .scrollView(axis: .vertical)).minY
            return content.scaleEffect(y > 0 ? 1 + y / height : 1, anchor: .bottom)
        }
        .contentShape(.rect)
        // the tap is the pan's own (`HomeCoverRecognizer`): a Button under it would take the touch first
        .gesture(HomeCoverPan(down: pressed, tapped: open, lifted: lifted, began: began, changed: dragged, ended: released))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shots[spoken].place.name)
        .accessibilityValue("Ảnh \(spoken + 1) trên \(shots.count)")
        .accessibilityAddTraits([.isButton, .isImage])
        .accessibilityAction { open() }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }

    /// The place's names and the photographer under the photograph, crossing with it. The dots move at halfway
    /// under the finger, and as a turn sets off (by itself, from VoiceOver, or let go).
    private func captions(shown: Int, incoming: Int, reveal: CGFloat, side: CGFloat, drift: CGFloat) -> some View {
        let dot = reveal >= 0.5 ? incoming : shown
        return HStack(alignment: .bottom) {
            ZStack(alignment: .bottomLeading) {
                ForEach(0..<2, id: \.self) { layer in
                    let up = layer == front
                    let at = up ? shown : incoming
                    HomeCoverCaption(shot: shots[at])
                        .id(at)
                        .offset(x: up ? -side * drift * reveal : side * drift * (1 - reveal))
                        .opacity(up ? 1 - reveal : reveal)
                        .zIndex(up ? 0 : 1)
                        // the credit's link: on the caption on show, at rest
                        .allowsHitTesting(up && turn == nil)
                        .accessibilityHidden(!up)
                }
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(shots.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == dot ? Palette.sun : Color.primary.opacity(0.2))
                        .frame(width: i == dot ? 18 : 6, height: 6)
                }
            }
            .padding(.bottom, 6)
            // a swipe that starts on the dots turns the photograph under them
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // the dot stretching is a pick
            .animation(Motion.reduced(Motion.pick, reduceMotion), value: dot)
        }
        .padding(.horizontal, Metrics.gutter)
    }

    // MARK: Turning

    private func wrap(_ i: Int) -> Int {
        let n = max(1, shots.count)
        return (i % n + n) % n
    }

    /// The photograph the dots show for `t`: the one coming in once it is half in.
    private func dot(_ t: HomeCoverTurn) -> Int {
        t.reveal >= 0.5 ? wrap(index + Int(t.side)) : wrap(index)
    }

    /// One photograph on (1) or back (−1): by itself, or from VoiceOver. From rest to the next one, one write on the
    /// spring: the next photograph is already there at no opacity, so its opacity and drift go from where they are.
    /// Back, or straight after another turn, the layer coming in takes its photograph first, with nothing moving, and
    /// sets off a frame later: in the same write it would come in from the other side.
    private func step(_ by: CGFloat) {
        guard shots.count > 1 else { return }
        let ready = turn == nil && by > 0
        if let t = turn { land(t) }
        turns += 1
        let t = HomeCoverTurn(at: 0, side: by, dragging: false, id: turns, from: 0, began: CACurrentMediaTime(), velocity: 0)
        guard !ready else {
            spring(t, to: by, rate: 0)
            return
        }
        quiet { turn = t }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            guard let now = turn, now.id == t.id, !now.dragging else { return }
            spring(now, to: by, rate: 0)
        }
    }

    /// A finger on the cover: the wait for the next turn starts again; a turn still running stops under it; at rest,
    /// the place on show starts loading (`Prefetch`), as a card's does when pressed.
    private func pressed() {
        Haptic.prepare(.page)
        touched += 1
        hand.held = nil
        if let t = turn {
            // a drag left behind, or a turn whose end was never reported (it would long have settled), lands now
            if t.dragging || t.done(CACurrentMediaTime()) {
                land(t)
            } else {
                take(t)
                return
            }
        }
        guard !shots.isEmpty else { return }
        Prefetch.place(shots[wrap(index)].place.id, model: model, at: .touch)
    }

    /// The finger stops a turn still running where it stands, and holds it. Past halfway, the photograph coming in
    /// becomes the one on show then and there, the turn now coming from the other side, which looks the same: so a
    /// drag from here that goes past it goes on to the photograph after it, as a flick in a row does.
    private func take(_ t: HomeCoverTurn) {
        var at = t.now(CACurrentMediaTime())
        var target = t.at
        var side = t.side
        let past = abs(at) >= 0.5
        if past {
            at -= side
            target -= side
            side = -side
        }
        turns += 1
        hand.held = target
        let held = HomeCoverTurn(at: at, side: side, dragging: true, id: turns)
        quiet {
            if past {
                index = wrap(index + Int(t.side))
                front = 1 - front
            }
            turn = held
        }
    }

    /// The finger left without a drag (a tap, or the page's scroll took the touch): a turn it stopped goes on where
    /// it was going.
    private func lifted() {
        guard let target = hand.held else { return }
        hand.held = nil
        guard let t = turn, t.dragging else { return }
        spring(t, to: target, rate: 0)
    }

    /// The photograph on show opens its place. Not mid-turn: what is under the finger is becoming another.
    private func open() {
        if let t = turn, t.done(CACurrentMediaTime()) { land(t) }
        guard turn == nil, !shots.isEmpty else { return }
        let shown = wrap(index)
        Haptic.press()
        model.present(.place(shots[shown].place.id), from: "home.cover.\(shown)")
    }

    /// The drag begins, `dx` from where the finger came down: from rest, the photograph on the side the hand moves
    /// away from starts to come in; a turn the finger stopped goes on from where it stands.
    private func began(_ dx: CGFloat) {
        guard shots.count > 1 else { return }
        if let t = turn, !t.dragging { take(t) }
        hand.held = nil
        hand.origin = dx
        if let t = turn, t.dragging {
            hand.grab = t.at
        } else {
            turns += 1
            hand.grab = 0
            let fresh = HomeCoverTurn(at: 0, side: dx < 0 ? 1 : -1, dragging: true, id: turns)
            quiet { turn = fresh }
        }
    }

    /// The finger at `dx`: the turn goes as far as the hand has, a leftward hand bringing the next photograph in.
    private func dragged(_ dx: CGFloat) {
        guard var t = turn, t.dragging else { return }
        let before = dot(t)
        t.at = min(1, max(-1, hand.grab - (dx - hand.origin) / (width * Self.reach)))
        if t.at != 0 { t.side = t.at > 0 ? 1 : -1 }
        // the dots move at halfway, and the hand feels it, as on the other carousels (`feelsPages`)
        if dot(t) != before { Haptic.page() }
        turn = t
    }

    /// Let go, moving at `vx` points a second: on to the photograph coming in if it is over a third in (unless
    /// flung back) or was flung its way, else back; on the spring, at the hand's speed.
    private func released(_ dx: CGFloat, _ vx: CGFloat) {
        touched += 1
        guard let t = turn, t.dragging else { return }
        // the hand's speed toward the photograph coming in (a leftward hand brings in the next one)
        let toward = -vx * t.side
        let on = toward > Self.flick || (t.reveal > 0.35 && toward > -Self.flick)
        if dot(t) != (on ? wrap(index + Int(t.side)) : wrap(index)) { Haptic.page() }
        spring(t, to: on ? t.side : 0, rate: -vx / (width * Self.reach))
    }

    /// `t` on the spring to `target` (1, −1 or 0), setting off at `rate`, how fast `at` was moving (a second).
    private func spring(_ t: HomeCoverTurn, to target: CGFloat, rate: CGFloat) {
        let change = target - t.at
        guard abs(change) > 0.001 else {
            var there = t
            there.at = target
            land(there)
            return
        }
        // the spring's speed is in parts of the way left a second: none for a hand going the other way, and no more
        // than the spring's own pace (2π over its length), above which it would pass the photograph and come back
        let most = 2 * Double.pi / Motion.crossfadeSpring.duration
        let velocity = min(most, max(0, Double(rate / change)))
        let n = HomeCoverTurn(at: target, side: t.side, dragging: false, id: t.id, from: t.at, began: CACurrentMediaTime(), velocity: velocity)
        withAnimation(Motion.crossfade(velocity: velocity), completionCriteria: .logicallyComplete) {
            turn = n
        } completion: {
            finish(n.id)
        }
    }

    /// The turn `id` has come to rest: the photograph it brought in becomes the one on show.
    private func finish(_ id: Int) {
        guard let t = turn, t.id == id, !t.dragging else { return }
        land(t)
    }

    /// The turn ends where it stands, at once: on to the photograph coming in if it is half in or more. The two
    /// layers swap parts in one frame, the one coming in becoming the one on show with the same photograph where it
    /// is, so the swap cannot be seen.
    private func land(_ t: HomeCoverTurn) {
        quiet {
            if t.reveal >= 0.5 {
                index = wrap(index + Int(t.side))
                front = 1 - front
            }
            turn = nil
        }
    }

    /// A change with no animation of its own, which stops the spring a turn is on where it stands. Not
    /// `disablesAnimations`: the photograph now on show still starts its slow drift, an animation tied to its value.
    private func quiet(_ change: () -> Void) {
        withTransaction(Transaction(animation: nil), change)
    }
}

/// A turn of the cover, as one number: `at` 0 is the photograph on show, 1 the next one, −1 the one before; between,
/// the one coming in shows that much (its opacity). Under the finger, `at` follows the hand; let go, it is where the
/// spring is going (1, −1 or 0), and `now` works out the way there.
struct HomeCoverTurn {
    var at: CGFloat
    /// the side the photograph coming in is on: 1 the next, −1 the one before; kept as `at` passes 0, so the one
    /// coming in is not swapped while it does not show
    var side: CGFloat
    /// under the finger: `at` is set as it moves, not animated
    var dragging: Bool
    var id: Int
    /// the spring, once let go: from where, when (`CACurrentMediaTime`), and how fast, in parts of the way a second
    var from: CGFloat = 0
    var began: TimeInterval = 0
    var velocity: Double = 0

    /// how far in the photograph coming in is
    var reveal: CGFloat { abs(at) }

    /// Where the photographs stand at `time`: on the spring (`Motion.crossfadeSpring`, which `crossfade` runs on),
    /// worked out from where it started; under the finger, where the hand put them.
    func now(_ time: TimeInterval) -> CGFloat {
        let change = at - from
        let t = time - began
        guard !dragging, change != 0, t >= 0, t < 1 else { return at }
        return from + Motion.crossfadeSpring.value(target: change, initialVelocity: change * CGFloat(velocity), time: t)
    }

    /// Let go of a second ago or more, so long settled: a turn whose end was not reported.
    func done(_ time: TimeInterval) -> Bool {
        !dragging && time - began >= 1
    }
}

private struct HomeCoverCaption: View {
    let shot: HomeShot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let ja = shot.place.ja {
                Text(ja)
                    .font(.mincho(19))
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    // a swipe that starts on the names still turns the photograph under them
                    .allowsHitTesting(false)
            }
            Text("\(shot.place.name) · Ngày \(shot.day.n)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
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
    }
}

/// One of the cover's two layers, filling its frame: a little over-scan, a turn's drift (`shift`) inside it, and a
/// slow drift a little closer while it shows the photograph on show.
private struct HomeCoverPhoto: View {
    let photo: Photo
    /// it holds the photograph on show (else the one coming in, waiting under no opacity)
    let onShow: Bool
    /// on show, in view and not in Low Power Mode: drifting slowly closer
    let current: Bool
    /// the turn's sideways drift, inside the frame
    let shift: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// drawn once already: the cover's first photograph starts at rest and drifts from there
    @State private var placed = false

    var body: some View {
        let drifting = current && placed && !reduceMotion
        Color.clear
            .overlay {
                PlacePhoto(photo: photo, maxPixel: 2400)
                    // a layer given another photograph (only ever while it waits) makes the picture again, drawn from
                    // the cache in its first frame
                    .id(photo.src)
                    // the covers are cut to the screen's own pixels (1290 × 1560): a little over-scan, which the
                    // turn's drift stays inside. Waiting, the layer goes back to rest at once, out of sight
                    .scaleEffect(drifting ? 1.12 : 1.08)
                    // motion: one-off the cover's 10 s drift is slower than any token; under Reduce Motion the scale does not change
                    .animation(drifting ? Animation.easeInOut(duration: 10) : onShow ? Motion.reduced(Motion.travel, reduceMotion) : nil, value: drifting)
                    .offset(x: shift)
            }
            .clipped()
            .contentShape(.rect)
            .onAppear { placed = true }
    }
}

// MARK: - The hand

/// The cover's one recognizer, from UIKit so it can say no: a sideways pan that begins only when the finger sets
/// off more sideways than up or down, while the page's own scroll waits for that answer, so a swipe never also
/// scrolls the page and a flick up on the photograph still scrolls it. It also tells of the finger coming down, of a
/// tap, and of a touch that ended without a drag, so the photograph needs no Button: a Button's gesture would come
/// before the pan and keep it from starting.
private struct HomeCoverPan: UIGestureRecognizerRepresentable {
    let down: @MainActor () -> Void
    let tapped: @MainActor () -> Void
    let lifted: @MainActor () -> Void
    /// the finger's distance across from where it came down (points; leftward is negative)
    let began: @MainActor (CGFloat) -> Void
    let changed: @MainActor (CGFloat) -> Void
    /// the distance, and the speed across as it let go (points a second); a pan taken away ends at no speed
    let ended: @MainActor (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> HomeCoverRecognizer {
        let pan = HomeCoverRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        updateUIGestureRecognizer(pan, context: context)
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: HomeCoverRecognizer, context: Context) {
        recognizer.down = down
        recognizer.tapped = tapped
        recognizer.lifted = lifted
    }

    func handleUIGestureRecognizerAction(_ recognizer: HomeCoverRecognizer, context: Context) {
        let dx = context.converter.localTranslation?.x ?? 0
        switch recognizer.state {
        case .began:
            began(dx)
        case .changed:
            changed(dx)
        case .ended:
            ended(dx, context.converter.localVelocity?.x ?? 0)
        case .cancelled, .failed:
            ended(dx, 0)
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// whether the page was scrolling as the touch arrived, read before any recognizer has it (the scroll view
        /// stops as it gets the touch)
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if let cover = gestureRecognizer as? HomeCoverRecognizer, cover.numberOfTouches == 0 {
                cover.stopping = HomeCoverRecognizer.scrollView(holding: touch.view)?.isDecelerating == true
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // the way the finger has gone so far, not its speed, which a slow drag leaves near nought
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let moved = pan.translation(in: nil)
            let sideways = abs(moved.x) > abs(moved.y)
            // up or down: the page's scroll has the touch, and a turn the finger stopped goes on
            if !sideways { (pan as? HomeCoverRecognizer)?.lifted?() }
            return sideways
        }

        /// the page's scroll (its scroll view's own pan) waits for this pan to say no before it moves
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scroll = otherGestureRecognizer.view as? UIScrollView else { return false }
            return otherGestureRecognizer === scroll.panGestureRecognizer
        }
    }
}

/// The pan, telling also of the finger coming down (`down`), of a tap (`tapped`: one finger lifted within 10 pt of
/// where it came down, the pan never having begun) and of the touch over without a drag (`lifted`). A touch that
/// stops the page's scroll on its way is not a tap, as on a Button in a scroll view.
private final class HomeCoverRecognizer: UIPanGestureRecognizer {
    var down: (@MainActor () -> Void)?
    var tapped: (@MainActor () -> Void)?
    var lifted: (@MainActor () -> Void)?
    /// the page was scrolling as this touch came down
    var stopping = false
    private var start: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard start == nil, let touch = touches.first else { return }
        start = touch.location(in: nil)
        stopping = stopping || Self.scrollView(holding: touch.view ?? view)?.isDecelerating == true
        down?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, !stopping, let start, let touch = touches.first, (event.allTouches?.count ?? 1) == 1 {
            let at = touch.location(in: nil)
            if hypot(at.x - start.x, at.y - start.y) < 10 { tapped?() }
        }
        super.touchesEnded(touches, with: event)
    }

    /// After every touch, a drag or not; after a drag `lifted` finds nothing held.
    override func reset() {
        super.reset()
        start = nil
        stopping = false
        lifted?()
    }

    /// the scroll view a view sits in, if any
    static func scrollView(holding view: UIView?) -> UIScrollView? {
        var at = view
        while let v = at {
            if let scroll = v as? UIScrollView { return scroll }
            at = v.superview
        }
        return nil
    }
}
