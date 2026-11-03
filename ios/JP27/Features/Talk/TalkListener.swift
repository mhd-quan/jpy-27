import AVFoundation
import Foundation
import Observation
import Speech
import TripKit

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

    init(scenarios: [Scenario]) {
        matcher = HeardMatcher(scenarios: scenarios)
    }

    var isListening: Bool { state == .listening }

    func toggle() async {
        if isListening { await stop() } else { await start() }
    }

    func start() async {
        guard state != .listening, state != .preparing else { return }
        state = .preparing
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .unavailable("Cần quyền micro trong Cài đặt để nghe.")
            return
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP")) else {
            state = .unavailable("Máy này chưa nghe được tiếng Nhật.")
            return
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        do {
            // the Japanese model downloads once, then works with no signal
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                state = .unavailable("Không mở được micro.")
                return
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.transcriber = transcriber
            self.analyzer = analyzer
            self.continuation = continuation
            listen(to: transcriber)
            try await analyzer.start(inputSequence: stream)
            try startAudio(feeding: continuation, as: format)
            state = .listening
        } catch {
            await stop()
            state = .unavailable("Không bắt đầu nghe được.")
        }
    }

    func stop() async {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        continuation?.finish()
        continuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        transcriber = nil
        if !partial.isEmpty { finish(partial) }
        partial = ""
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

    private func startAudio(feeding continuation: AsyncStream<AnalyzerInput>.Continuation, as format: AVAudioFormat) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let feed = TalkAudioFeed(from: input.outputFormat(forBus: 0), to: format, continuation: continuation)
        TalkAudioFeed.install(feed, on: input)
        engine.prepare()
        try engine.start()
        self.engine = engine
    }
}

/// Converts microphone buffers to the analyzer's format on the audio thread. Everything it holds
/// is touched only from the one real-time tap callback, which never runs concurrently with itself,
/// hence `@unchecked Sendable`.
nonisolated final class TalkAudioFeed: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let target: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation

    init(from source: AVAudioFormat, to target: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        converter = source == target ? nil : AVAudioConverter(from: source, to: target)
        self.target = target
        self.continuation = continuation
    }

    /// Installed from a nonisolated context with a @Sendable block, so the tap does not inherit
    /// the main actor and trip the runtime isolation check on the audio thread.
    static func install(_ feed: TalkAudioFeed, on node: AVAudioInputNode) {
        node.installTap(onBus: 0, bufferSize: 4096, format: node.outputFormat(forBus: 0)) { @Sendable (buffer: AVAudioPCMBuffer, _: AVAudioTime) in
            feed.push(buffer)
        }
    }

    func push(_ buffer: AVAudioPCMBuffer) {
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
