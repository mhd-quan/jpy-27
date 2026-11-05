import AVFoundation
import Foundation
import Observation
import Speech
import TripKit
import UIKit

/// One heard sentence.
struct TalkSentence: Identifiable, Hashable {
    let id: UUID
    let ja: String
    /// a phrasebook "you may hear" line it matches, with a reply
    let hit: HeardMatcher.Hit?

    static func == (a: TalkSentence, b: TalkSentence) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Japanese speech to text, on the phone: SpeechAnalyzer with a SpeechTranscriber for ja-JP, fed by
/// the microphone through AVAudioEngine.
@Observable final class TalkListener {
    enum State: Equatable {
        case idle
        case preparing
        case listening
        case unavailable(String)
    }

    private(set) var state: State = .idle
    private(set) var sentences: [TalkSentence] = []
    /// the words of the sentence still being heard
    private(set) var partial = ""

    private let matcher: HeardMatcher
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var engine: AVAudioEngine?
    private var resultsTask: Task<Void, Never>?
    /// bumped by every start and stop: a start still waiting (for the microphone permission, for
    /// the Japanese model to download) when the screen closed finds it moved on, and turns nothing on
    private var attempt = 0
    /// the listen holding the audio session (`AudioSessionController.listen`), given back once by
    /// `stop()` or deinit
    @ObservationIgnored private var session: Int?
    /// the last id a listen was given: unique across listeners, so a late stop of an old one never gives
    /// back a newer one's session
    private static var sessions = 0
    /// what takes the audio away while listening (a call, Siri, a new route, the app left): one
    /// set per listen, removed first thing by `stop()`
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(scenarios: [Scenario]) {
        matcher = HeardMatcher(scenarios: scenarios)
    }

    /// Never leave the microphone or the ducked audio session behind with the screen that owned them.
    isolated deinit {
        resultsTask?.cancel()
        unwatch()
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        continuation?.finish()
        giveSessionBack()
    }

    var isListening: Bool { state == .listening }

    func toggle() async {
        if isListening { await stop() } else { await start() }
    }

    func start() async {
        guard state != .listening, state != .preparing else { return }
        attempt += 1
        let mine = attempt
        state = .preparing
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard mine == attempt else { return }
        guard allowed else {
            state = .unavailable("Cần quyền micro trong Cài đặt để nghe.")
            return
        }
        let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP"))
        guard mine == attempt else { return }
        guard let locale = supported else {
            state = .unavailable("Máy này chưa nghe được tiếng Nhật.")
            return
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        do {
            // the Japanese model downloads once, then works with no signal
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard mine == attempt else { return }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                if mine == attempt { state = .unavailable("Không mở được micro.") }
                return
            }
            guard mine == attempt else { return }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            // held before the analyzer starts, so a stop() during its start finishes them
            self.transcriber = transcriber
            self.analyzer = analyzer
            self.continuation = continuation
            listen(to: transcriber)
            try await analyzer.start(inputSequence: stream)
            // stopped while the analyzer started: stop() has finished it, the microphone stays off
            guard mine == attempt else { return }
            // The session first, off the main thread. A stop() meanwhile queues its give-back behind it,
            // and the microphone stays off.
            guard await takeSession() else { throw SessionRefused() }
            guard mine == attempt else { return }
            try startAudio(feeding: continuation, as: format, listen: mine)
            state = .listening
        } catch {
            guard mine == attempt else { return }
            await stop()
            state = .unavailable("Không bắt đầu nghe được.")
        }
    }

    func stop() async {
        attempt += 1
        let mine = attempt
        unwatch()
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        continuation?.finish()
        continuation = nil
        // the session's give-back is queued now: the other app's audio comes back up at once, not after
        // the last words are transcribed
        giveSessionBack()
        let analyzer = self.analyzer
        self.analyzer = nil
        transcriber = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        if !partial.isEmpty { finish(partial) }
        partial = ""
        // a start made while the last words were transcribed owns the state now
        guard mine == attempt else { return }
        if case .unavailable = state { return }
        state = .idle
    }

    func clear() {
        sentences = []
        partial = ""
    }

    private func listen(to transcriber: SpeechTranscriber) {
        resultsTask?.cancel()
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if result.isFinal {
                        self.partial = ""
                        if !text.isEmpty { self.finish(text) }
                    } else {
                        self.partial = text
                    }
                }
            } catch {}
        }
    }

    private func finish(_ text: String) {
        sentences.append(TalkSentence(id: UUID(), ja: text, hit: matcher.best(for: text)))
    }

    /// The session in Nghe's category, activated, ducking whatever else plays
    /// (`AudioSessionController.shared`). The id is held before the calls run, so a stop() while they run
    /// gives the session back after them.
    private func takeSession() async -> Bool {
        Self.sessions += 1
        let id = Self.sessions
        session = id
        return await AudioSessionController.shared.listen(id)
    }

    /// The session's calls failed: listening does not start.
    private nonisolated struct SessionRefused: Error {}

    /// The microphone into the analyzer, once the session is Nghe's.
    private func startAudio(feeding continuation: AsyncStream<AnalyzerInput>.Continuation, as format: AVAudioFormat, listen: Int) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // `.measurement` cancels no echo: what the app reads aloud is not heard
        let feed = TalkAudioFeed(from: input.outputFormat(forBus: 0), to: format, continuation: continuation, muted: Speaker.shared.voice)
        TalkAudioFeed.install(feed, on: input)
        engine.prepare()
        try engine.start()
        self.engine = engine
        watch(engine, listen: listen)
    }

    /// A call or Siri (an interruption begins), a new route (the engine stops itself on a
    /// configuration change, AirPods coming or going) or the app left: listening stops, and the
    /// screen says so.
    private func watch(_ engine: AVAudioEngine, listen: Int) {
        unwatch()
        observers = [
            observe(AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), listen: listen) { note in
                // only its beginning: once it ends, Nghe stays stopped until tapped again
                (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            },
            observe(.AVAudioEngineConfigurationChange, object: engine, listen: listen),
            observe(UIApplication.didEnterBackgroundNotification, object: nil, listen: listen),
        ]
    }

    /// Only Sendable values leave the notification's block: the listen it belongs to, and whether
    /// it takes the audio.
    private func observe(_ name: Notification.Name, object: Any?, listen: Int,
                         when takes: @escaping @Sendable (Notification) -> Bool = { _ in true }) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] note in
            guard takes(note) else { return }
            Task { @MainActor in await self?.audioTaken(listen) }
        }
    }

    private func unwatch() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
    }

    /// The audio was taken: stop once, and only the listen that is still running (a stop since,
    /// or a second notification for the same call, finds `attempt` moved on).
    private func audioTaken(_ listen: Int) async {
        guard listen == attempt, state == .listening else { return }
        await stop()
    }

    /// The session given back, once, without moving another app's audio (`AudioSessionOwners`). The
    /// calls run off the main thread, after those issued before, the listen's own among them.
    ///
    /// - If nothing is being read, the session is deactivated first, so what another app plays comes
    ///   back up. Then the category from before listening is put back, which on an inactive session
    ///   touches nothing else.
    /// - While the Speaker reads a line, the session stays active in the Speaker's own category, and
    ///   the Speaker ends it after the line. The category from before is dropped.
    private func giveSessionBack() {
        guard let id = session else { return }
        session = nil
        AudioSessionController.shared.listenEnded(id)
    }
}

/// Converts microphone buffers to the analyzer's format on the audio thread. Everything it holds
/// is touched only from the one real-time tap callback, which never runs concurrently with itself,
/// hence `@unchecked Sendable`.
nonisolated final class TalkAudioFeed: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let target: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    /// the app is speaking (`Speaker.voice`): its buffers are dropped
    private let muted: SpeakingFlag

    init(from source: AVAudioFormat, to target: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation, muted: SpeakingFlag) {
        converter = source == target ? nil : AVAudioConverter(from: source, to: target)
        self.target = target
        self.continuation = continuation
        self.muted = muted
    }

    /// Installed from a nonisolated context with a @Sendable block, so the tap does not inherit
    /// the main actor and trip the runtime isolation check on the audio thread.
    static func install(_ feed: TalkAudioFeed, on node: AVAudioInputNode) {
        node.installTap(onBus: 0, bufferSize: 4096, format: node.outputFormat(forBus: 0)) { @Sendable (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            feed.push(buffer)
        }
    }

    func push(_ buffer: AVAudioPCMBuffer) {
        // the app's own voice, through the speaker: not a sentence heard
        guard !muted.isOn else { return }
        guard let converter else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        // the input block is called synchronously within convert(); a local box keeps state per call
        let source = TalkOneShot(buffer)
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if let next = source.take() {
                inputStatus.pointee = .haveData
                return next
            }
            inputStatus.pointee = .noDataNow
            return nil
        }
        guard status != .error, error == nil, out.frameLength > 0 else { return }
        continuation.yield(AnalyzerInput(buffer: out))
    }
}

/// Hands a buffer to AVAudioConverter exactly once.
nonisolated private final class TalkOneShot: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
