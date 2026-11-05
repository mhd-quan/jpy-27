/// An audio session's category, mode and options, as the raw values of AVAudioSession's types (TripKit
/// has no AVFoundation): what an owner wants of the session, and what the session has.
public struct AudioSetup: Sendable, Hashable {
    public let category: String
    public let mode: String
    public let options: UInt

    public init(category: String, mode: String, options: UInt) {
        self.category = category
        self.mode = mode
        self.options = options
    }
}

/// Who holds the app's audio session, and the calls each change of hands takes. Its two owners: the
/// Speaker, which reads Japanese aloud, and Nghe, which records the microphone. The steps come in the
/// order the owners issued them, from `AudioSessionController`, which makes the calls.
///
/// - The Speaker takes the session in its own setup for a line, unless Nghe holds it. Then the line is
///   spoken through Nghe's session, and its category is left alone: changing it would stop the
///   microphone.
/// - Once nothing is left to say, the Speaker's session is released `releaseDelay` later: deactivated, so
///   what another app plays comes back up. A line or Nghe coming in between voids the release. Right after
///   a line ends, a deactivation fails (`isBusy`) while the voice's audio winds down.
/// - Nghe takes the session in its own setup, and remembers the setup it found (`prior`). If it stops while
///   nothing is being read, it deactivates first and then puts `prior` back, which on an inactive session
///   moves nothing else. If it stops mid-line, it hands the active session to the Speaker, whose release
///   ends it after the line; `prior` is dropped.
public struct AudioSessionOwners: Sendable, Equatable {
    public enum Holder: Sendable, Equatable {
        case nobody
        case speaker
        /// a listen of Nghe's, by the id it was started with
        case listener(Int)
    }

    /// One call into the session.
    public enum Call: Sendable, Equatable {
        case setCategory(AudioSetup)
        case activate
        /// with `notifyOthersOnDeactivation`; tried once more when busy (`AudioSessionController`)
        case deactivate
    }

    /// how long after its last line the Speaker's session is released
    public static let releaseDelay: Duration = .milliseconds(500)

    /// `.playback / .spokenAudio / [.duckOthers]` in the app
    public let speaker: AudioSetup
    /// `.playAndRecord / .measurement / [.duckOthers, .defaultToSpeaker]` in the app
    public let listener: AudioSetup
    public private(set) var holder: Holder = .nobody
    /// a line has been said and has not ended
    public private(set) var reading = false
    /// the release due, by its ticket. Only ever set while the Speaker holds the session and nothing is
    /// being read: a line, or Nghe taking the session, voids it.
    public private(set) var release: Int?
    /// the setup the session had before Nghe took it, put back when Nghe stops with nothing being read
    public private(set) var prior: AudioSetup?
    /// the last ticket given out
    private var releases = 0

    public init(speaker: AudioSetup, listener: AudioSetup) {
        self.speaker = speaker
        self.listener = listener
    }

    /// The Speaker is about to read a line; `found` is the session's setup now.
    public mutating func say(found: AudioSetup) -> [Call] {
        reading = true
        release = nil
        if case .listener = holder { return [] }
        holder = .speaker
        return setting(speaker, over: found) + [.activate]
    }

    /// Nothing is left to say. The ticket of the release now due, when the Speaker holds the session: hand
    /// it to `releaseDue` `releaseDelay` from now.
    public mutating func ended() -> Int? {
        // a second end (a cancel and a finish, a late callback) keeps the release already due
        guard reading else { return nil }
        reading = false
        guard holder == .speaker else { return nil }
        releases += 1
        release = releases
        return releases
    }

    /// A release's time has come. Only the latest ticket counts, and only if nothing voided it since.
    public mutating func releaseDue(_ ticket: Int) -> [Call] {
        guard release == ticket else { return [] }
        release = nil
        holder = .nobody
        return [.deactivate]
    }

    /// Nghe starts listening (`id` names this listen); `found` is the session's setup now.
    public mutating func listen(_ id: Int, found: AudioSetup) -> [Call] {
        release = nil
        // a listen taking over from one not stopped yet: the setup from before the first is the one kept
        if prior == nil { prior = found }
        holder = .listener(id)
        return setting(listener, over: found) + [.activate]
    }

    /// Nghe stops the listen `id`; `found` is the session's setup now. Nothing, unless that listen holds
    /// the session.
    public mutating func listenEnded(_ id: Int, found: AudioSetup) -> [Call] {
        guard holder == .listener(id) else { return [] }
        let prior = self.prior
        self.prior = nil
        if reading {
            holder = .speaker
            return setting(speaker, over: found)
        }
        holder = .nobody
        return [.deactivate] + (prior.map { setting($0, over: found) } ?? [])
    }

    /// The category set only when the session does not have this setup already.
    private func setting(_ setup: AudioSetup, over found: AudioSetup) -> [Call] {
        setup == found ? [] : [.setCategory(setup)]
    }
}
