import SwiftUI
import TripKit
import UIKit
import UIKit.UIGestureRecognizerSubclass

// MARK: - The cover's photographs

/// The home's cover photographs, turned the TV app's way (measured frame by frame on a screen recording of it): the
/// next photograph fades in over the one on show where it stands, while the two drift a little the way the hand goes.
/// A drag scrubs the turn under the finger; let go, it finishes on a spring with no bounce that starts at the finger's
/// speed (`Motion.crossfade(velocity:)`), or falls back. A drag that lands on a turn still running takes it where it
/// stands. By itself the cover turns every 6 s, the first photograph again after the last.
///
/// Two layers, both always there: the photograph on show, and the next one waiting at no opacity (so it is decoded
/// before it is needed). A turn moves one number, `HomeCoverTurn.at`, which only their opacity and offset read:
/// nothing is laid out, made or loaded while the photographs move, and no scroll view's offset drives them.
struct HomeCoverCarousel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let shots: [HomeShot]
    let height: CGFloat
    /// the photograph on show
    @State private var index = 0
    /// the turn under way, dragged or on its spring; nil at rest
    @State private var turn: HomeCoverTurn?
    /// turns begun, so the end of one cut short by another does nothing
    @State private var turns = 0
    /// touches on the cover: each starts the wait for the next turn again
    @State private var touched = 0
    /// the cover is on screen: off it, nothing turns or drifts
    @State private var visible = true
    @State private var width: CGFloat = 430
    /// where the drag took hold; not drawn from, so not observed
    @State private var hand = Hand()

    final class Hand {
        /// the pan's translation as it began: the drag counts from there, so the photographs do not jump by the
        /// distance the finger had to go before it was a drag
        var origin: CGFloat = 0
        /// where the turn stood as the drag took it: 0 from rest, or where a turn still running had got to
        var grab: CGFloat = 0
    }

    /// how far the two photographs drift in a turn: inside the covers' over-scan (4 % a side at the resting 1.08,
    /// about 17 pt), so no edge ever shows; the TV app's wider art drifts further
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
        // a turn every 6 s while the cover is in view; a touch starts the wait again. Under a sheet or behind another
        // tab it waits, so no turn lands in a sheet's zoom (read here, not in the body, so a sheet does not re-run the
        // cover). Still under Reduce Motion, under VoiceOver (a turn would change the element being read) and in Low
        // Power Mode (`lowPower` is in the id: turned off, the turns start again); a swipe still turns.
        .task(id: "\(shown)-\(visible)-\(model.lowPower)-\(voiceOver)-\(touched)") {
            guard visible, !reduceMotion, !voiceOver, !model.lowPower, count > 1 else { return }
            repeat {
                try? await Task.sleep(for: .seconds(6))
            } while !Task.isCancelled && !(model.sheets.isEmpty && model.tab == .today)
            guard !Task.isCancelled, !model.lowPower, turn == nil else { return }
            step(1)
        }
    }

    // MARK: Layers

    private func photos(shown: Int, incoming: Int, reveal: CGFloat, side: CGFloat, drift: CGFloat) -> some View {
        let shot = shots[shown]
        let height = self.height
        return ZStack {
            // the slow drift is drawn every frame: not in Low Power Mode
            HomeCoverPhoto(photo: shot.photo, current: visible && !model.lowPower, shift: -side * drift * reveal)
                .sheetSource("home.cover.\(shown)")
                .id(shown)
            HomeCoverPhoto(photo: shots[incoming].photo, current: false, shift: side * drift * (1 - reveal))
                .opacity(reveal)
                .id(incoming)
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
        .gesture(HomeCoverPan(down: pressed, tapped: open, began: began, changed: dragged, ended: released))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shot.place.name)
        .accessibilityValue("Ảnh \(shown + 1) trên \(shots.count)")
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

    /// The place's names and the photographer under the photograph, crossing with it; the dots move at halfway.
    private func captions(shown: Int, incoming: Int, reveal: CGFloat, side: CGFloat, drift: CGFloat) -> some View {
        let dot = reveal >= 0.5 ? incoming : shown
        return HStack(alignment: .bottom) {
            ZStack(alignment: .bottomLeading) {
                HomeCoverCaption(shot: shots[shown])
                    .offset(x: -side * drift * reveal)
                    .opacity(1 - reveal)
                    // the credit's link: not while the caption is giving way
                    .allowsHitTesting(turn == nil)
                    .id(shown)
                HomeCoverCaption(shot: shots[incoming])
                    .offset(x: side * drift * (1 - reveal))
                    .opacity(reveal)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .id(incoming)
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

    /// One photograph on (1) or back (−1) from rest: by itself, or from VoiceOver. One write on the spring: the
    /// next photograph is already there at no opacity, so its opacity and drift go from where they are.
    private func step(_ by: CGFloat) {
        guard shots.count > 1 else { return }
        if let t = turn { land(t) }
        turns += 1
        let t = HomeCoverTurn(at: by, side: by, dragging: false, id: turns, from: 0, began: CACurrentMediaTime(), velocity: 0)
        withAnimation(Motion.crossfade, completionCriteria: .logicallyComplete) {
            turn = t
        } completion: {
            finish(t.id)
        }
    }

    /// A finger on the cover: the wait for the next turn starts again, and the place on show starts loading
    /// (`Prefetch`), as a card's does when pressed.
    private func pressed() {
        Haptic.prepare(.page)
        touched += 1
        guard turn == nil, !shots.isEmpty else { return }
        Prefetch.place(shots[wrap(index)].place.id, model: model, at: .touch)
    }

    /// The photograph on show opens its place. Not mid-turn: what is under the finger is becoming another.
    private func open() {
        guard turn == nil, !shots.isEmpty else { return }
        let shown = wrap(index)
        Haptic.press()
        model.present(.place(shots[shown].place.id), from: "home.cover.\(shown)")
    }

    /// The drag begins, `dx` from where the finger came down: from rest, the photograph on the side the hand moves
    /// away from starts to come in; on a turn still running, the hand takes it where it stands.
    private func began(_ dx: CGFloat) {
        guard shots.count > 1 else { return }
        hand.origin = dx
        turns += 1
        let id = turns
        if let t = turn, !t.dragging {
            let at = t.now(CACurrentMediaTime())
            hand.grab = at
            still { turn = HomeCoverTurn(at: at, side: t.side, dragging: true, id: id) }
        } else {
            hand.grab = 0
            still { turn = HomeCoverTurn(at: 0, side: dx < 0 ? 1 : -1, dragging: true, id: id) }
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

    /// Let go, moving at `vx` points a second: on to the photograph coming in if it came far enough or the hand
    /// was flung its way, else back; on the spring, at the hand's speed.
    private func released(_ dx: CGFloat, _ vx: CGFloat) {
        touched += 1
        guard let t = turn, t.dragging else { return }
        // how fast `at` was moving, and the hand's speed toward the photograph coming in
        let rate = -vx / (width * Self.reach)
        let toward = -vx * t.side
        let on = toward > Self.flick || (t.reveal > 0.35 && toward > -Self.flick)
        let target: CGFloat = on ? t.side : 0
        if dot(t) != (on ? wrap(index + Int(t.side)) : wrap(index)) { Haptic.page() }
        let change = target - t.at
        guard abs(change) > 0.001 else {
            var done = t
            done.at = target
            land(done)
            return
        }
        // the spring's speed is in parts of the way left a second; a hand going the other way starts it at rest
        let velocity = min(30, max(0, Double(rate / change)))
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
    /// layers swap in one frame with nothing animated, the one coming in becoming the one on show where it is, so
    /// the swap cannot be seen.
    private func land(_ t: HomeCoverTurn) {
        still {
            if t.reveal >= 0.5 { index = wrap(index + Int(t.side)) }
            turn = nil
        }
    }

    /// A change with nothing animated, which also stops the spring a turn is on where it stands.
    private func still(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

/// A turn of the cover, as one number: `at` 0 is the photograph on show, 1 the next one, −1 the one before; between,
/// the one coming in shows that much (its opacity). Dragged, `at` follows the hand; let go, it is where the spring is
/// going (1, −1 or 0), and `now` works out the way there.
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
    /// worked out from where it started; dragged, where the hand put them.
    func now(_ time: TimeInterval) -> CGFloat {
        let change = at - from
        let t = time - began
        guard !dragging, change != 0, t >= 0, t < 1 else { return at }
        return from + Motion.crossfadeSpring.value(target: change, initialVelocity: change * CGFloat(velocity), time: t)
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

/// One cover photograph, filling its frame: a little over-scan, a turn's drift (`shift`) inside it, and a slow drift
/// a little closer while it is the one on show.
private struct HomeCoverPhoto: View {
    let photo: Photo
    let current: Bool
    /// the turn's sideways drift, inside the frame
    let shift: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// drawn once already: a photograph that has just become the one on show starts at rest and drifts from there
    @State private var placed = false

    var body: some View {
        let drifting = current && placed && !reduceMotion
        Color.clear
            .overlay {
                PlacePhoto(photo: photo, maxPixel: 2400)
                    // the covers are cut to the screen's own pixels (1290 × 1560): at 1.08 about 17 pt over a side,
                    // which the turn's drift of 16 stays inside
                    .scaleEffect(drifting ? 1.12 : 1.08)
                    // motion: one-off the cover's 10 s drift is slower than any token; under Reduce Motion the scale does not change
                    .animation(drifting ? Animation.easeInOut(duration: 10) : Motion.reduced(Motion.travel, reduceMotion), value: drifting)
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
/// scrolls the page and a flick up on the photograph still scrolls it. It also tells of the finger coming down and
/// of a tap, so the photograph needs no Button: a Button's gesture would come before the pan and keep it from starting.
private struct HomeCoverPan: UIGestureRecognizerRepresentable {
    let down: @MainActor () -> Void
    let tapped: @MainActor () -> Void
    /// the finger's distance across from where it came down (points; leftward is negative)
    let began: @MainActor (CGFloat) -> Void
    let changed: @MainActor (CGFloat) -> Void
    /// the distance, and the speed across as it let go (points a second); a pan taken away ends at no speed
    let ended: @MainActor (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> HomeCoverRecognizer {
        let pan = HomeCoverRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        pan.down = down
        pan.tapped = tapped
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: HomeCoverRecognizer, context: Context) {
        recognizer.down = down
        recognizer.tapped = tapped
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
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // the way the finger has gone so far, not its speed, which a slow drag leaves near nought
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let moved = pan.translation(in: nil)
            return abs(moved.x) > abs(moved.y)
        }

        /// the page's scroll (a scroll view's own pan) waits for this pan to say no before it moves
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer.view is UIScrollView
        }
    }
}

/// The pan, telling also of the finger coming down (`down`) and of a tap (`tapped`): one finger lifted within 10 pt of
/// where it came down, the pan never having begun. A touch that stops the page's scroll on its way is not a tap, as
/// on a Button in a scroll view.
private final class HomeCoverRecognizer: UIPanGestureRecognizer {
    var down: (@MainActor () -> Void)?
    var tapped: (@MainActor () -> Void)?
    private var start: CGPoint?
    private var stopping = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard start == nil, let touch = touches.first else { return }
        start = touch.location(in: nil)
        stopping = scrollView?.isDecelerating == true
        down?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, !stopping, let start, let touch = touches.first, (event.allTouches?.count ?? 1) == 1 {
            let at = touch.location(in: nil)
            if hypot(at.x - start.x, at.y - start.y) < 10 { tapped?() }
        }
        super.touchesEnded(touches, with: event)
    }

    override func reset() {
        super.reset()
        start = nil
        stopping = false
    }

    /// the scroll view the cover is in, if the recognizer sits in its views
    private var scrollView: UIScrollView? {
        var at = view
        while let v = at {
            if let scroll = v as? UIScrollView { return scroll }
            at = v.superview
        }
        return nil
    }
}
