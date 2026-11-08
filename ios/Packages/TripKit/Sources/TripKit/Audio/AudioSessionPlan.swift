/// The app's one audio session, shared by the Speaker (reading Japanese aloud) and Nghe (listening): who holds it,
/// when the Speaker gives it back, and what a failed session call does. Events go in, in the order they happen; an
/// ordered list of commands comes out. The plan's state changes first, so the next event is decided on it even
/// while the commands of this one still run. No AVFoundation here: the app maps each `Setup` to its category, mode
/// and options, runs the `.session` steps on one serial queue in order, and keeps the waits.
///
/// - A line read while Nghe listens goes through the recording session as it is; Nghe ends that session.
/// - Nghe stopping with nothing being read deactivates first (what another app plays comes back up), then sets the
///   category from before listening, which on an inactive session moves nothing else.
/// - Nghe stopping mid-line leaves the session active, in the Speaker's setup; the category from before is dropped
///   and the Speaker's release ends the session after the line.
/// - The Speaker's release comes `releaseAfter` after its last line ends, and deactivates only if nothing took the
///   session meanwhile: the generation it was scheduled under must still be the current one.
/// - A category is set only when it differs from the one set last.
public struct AudioSessionPlan: Sendable, Equatable {
    /// The two setups the app sets: the Speaker's (mixable, ducking what else plays, heard with the switch on
    /// silent) and Nghe's (recording). The app writes their AVFoundation values in one place.
    public enum Setup: Sendable, Hashable {
        case speaker
        case listener
    }

    /// Who is to end the session.
    public enum Holder: Sendable, Hashable {
        case nobody
        case speaker
        /// `active` is false once Nghe's activation failed: there is nothing to deactivate then
        case listener(active: Bool)
    }

    /// Work on the session itself, run on the app's audio queue in order. A batch stops at its first failing step:
    /// what follows it was decided on it succeeding.
    public enum Step: Sendable, Hashable {
        case setCategory(Setup)
        /// remember the session's setup as it is now (the queue keeps it), to be given back by `restorePrior`
        case capturePrior
        case restorePrior
        case activate
        /// with `notifyOthersOnDeactivation`, so what another app plays comes back up
        case deactivate
    }

    public enum Command: Sendable, Hashable {
        case session(Step)
        /// wait, then send `releaseDue(generation:)`
        case release(afterMilliseconds: Int, generation: Int)
        /// the wait of a release that will not be wanted: cancelling it saves the wake, the generation already
        /// makes it harmless
        case cancelRelease
        /// wait on the audio queue, then send `retryDue(generation:)`
        case retry(afterMilliseconds: Int, generation: Int)
    }

    /// A step that threw: the steps after it in its batch did not run.
    public struct Failure: Sendable, Hashable {
        public var step: Step
        /// the session was busy (deactivated while audio still played)
        public var busy: Bool

        public init(step: Step, busy: Bool) {
            self.step = step
            self.busy = busy
        }
    }

    public enum Event: Sendable, Hashable {
        /// the Speaker is asked to read a line
        case speakerWillSpeak
        /// nothing is left to say: no line is being read or waiting
        case speakerDone
        case releaseDue(generation: Int)
        /// Nghe starts the microphone; its ticket is the `generation` after this event
        case listenerStarting
        /// Nghe gives the session back (a stop, or the listener going away); `lineBeingRead` is the Speaker's
        case listenerStopped(ticket: Int, lineBeingRead: Bool)
        /// a step of a batch decided under `generation` failed
        case failed(Failure, generation: Int)
        case retryDue(generation: Int)
        /// the system's audio services restarted: the session's category is the default again
        case mediaServicesReset
    }

    /// after the Speaker's last line, in milliseconds: a deactivation right at the end of a line is often refused
    /// as busy, and a line read straight after keeps the session
    public static let releaseAfter = 500
    /// a deactivation refused as busy is tried once more after this, in milliseconds
    public static let busyRetryAfter = 150

    public private(set) var holder = Holder.nobody
    /// Bumped by every take of the session (a line unless Nghe holds it, a listen): what comes due or fails under
    /// an older one does nothing. Nghe's ticket is the generation its listen took.
    public private(set) var generation = 0
    /// the Speaker's release is scheduled, not yet due
    public private(set) var releasing = false
    /// the category set last; nil when it is not known
    public private(set) var lastSet: Setup?
    /// a setup from before Nghe is kept on the queue, to be given back
    public private(set) var priorCaptured = false
    /// the deactivation of this generation, and how far its one busy retry has gone
    private var deactivation: Deactivation?

    private struct Deactivation: Sendable, Equatable {
        enum Retry: Sendable, Equatable { case unused, waiting, used }
        let steps: [Step]
        var retry = Retry.unused
    }

    public init() {}

    public mutating func handle(_ event: Event) -> [Command] {
        switch event {
        case .speakerWillSpeak:
            if case .listener = holder { return [] }
            var out = take()
            holder = .speaker
            out += set(.speaker)
            return out

        case .speakerDone:
            guard holder == .speaker, !releasing else { return [] }
            releasing = true
            return [.release(afterMilliseconds: Self.releaseAfter, generation: generation)]

        case .releaseDue(let g):
            guard releasing, g == generation else { return [] }
            releasing = false
            holder = .nobody
            return deactivate([.deactivate])

        case .listenerStarting:
            var out = take()
            holder = .listener(active: true)
            if !priorCaptured {
                priorCaptured = true
                out.append(.session(.capturePrior))
            }
            out += set(.listener)
            out.append(.session(.activate))
            return out

        case .listenerStopped(let ticket, let lineBeingRead):
            guard case .listener(let active) = holder, ticket == generation else { return [] }
            if active, lineBeingRead {
                holder = .speaker
                priorCaptured = false
                return set(.speaker)
            }
            holder = .nobody
            var steps: [Step] = active ? [.deactivate] : []
            if priorCaptured {
                priorCaptured = false
                // the setup given back is not known here
                lastSet = nil
                steps.append(.restorePrior)
            }
            return active ? deactivate(steps) : steps.map(Command.session)

        case .failed(let failure, let g):
            // a failed set leaves the category unknown, whoever set it
            if case .setCategory = failure.step { lastSet = nil }
            guard g == generation else { return [] }
            switch failure.step {
            case .setCategory(.listener), .activate:
                if case .listener(active: true) = holder { holder = .listener(active: false) }
                return []
            case .deactivate:
                guard failure.busy, var d = deactivation, d.retry == .unused else {
                    deactivation = nil
                    return []
                }
                d.retry = .waiting
                deactivation = d
                return [.retry(afterMilliseconds: Self.busyRetryAfter, generation: g)]
            default:
                return []
            }

        case .retryDue(let g):
            guard g == generation, var d = deactivation, d.retry == .waiting else { return [] }
            d.retry = .used
            deactivation = d
            return d.steps.map(Command.session)

        case .mediaServicesReset:
            lastSet = nil
            return []
        }
    }

    /// Someone new takes the session: a pending release is cancelled, and what was decided before goes stale.
    private mutating func take() -> [Command] {
        let out: [Command] = releasing ? [.cancelRelease] : []
        releasing = false
        generation += 1
        return out
    }

    private mutating func set(_ setup: Setup) -> [Command] {
        guard lastSet != setup else { return [] }
        lastSet = setup
        return [.session(.setCategory(setup))]
    }

    private mutating func deactivate(_ steps: [Step]) -> [Command] {
        deactivation = Deactivation(steps: steps)
        return steps.map(Command.session)
    }
}
