import Foundation
import os
import Synchronization
import TripKit

// The app's log, kept on the phone: a file a day in Application Support/Logs (JSON Lines, one
// `LogLine` each), 14 days and 10 MB kept (`LogRetention`), out of the iCloud backup; every line also
// goes to os.Logger (subsystem tech.delphyra.jp27, its group as the category), so Console reads it
// too. Cài đặt › Hỗ trợ › Log shows the newest lines, clears them, and exports them as a .zip with the
// crash reports MetricKit hands over (`MetricsInbox`, in Logs/diagnostics) and its daily payloads.

/// Logging from any thread, in order, without waiting: a line goes into a queue under a lock (`t`, the
/// real clock's instant, taken under it, so the queue's order is the time's) and a writer, off the main
/// thread, appends the queue to the day's file. In the foreground a line waits up to 2 seconds for
/// company, and 64 lines are written at once; in the background (iOS may suspend the app any moment)
/// and for an `error`, a line is written at once. A write that fails keeps its lines for the next one
/// (2000 at most) and is shown on the log page (`lastWriteError`); once writing works again, a line in
/// the file says how many were lost and why.
///
/// A line holds no text the user typed (notes, expense names, journal), no other phone's name (the
/// first characters of its key's fingerprint instead), and no exact position (`LogRedact.text`): every
/// line also goes to the system log, as public.
nonisolated enum AppLog {
    static let subsystem = "tech.delphyra.jp27"
    /// Application Support/Logs: the day files, and `diagnostics/` with MetricKit's reports
    static let folder = URL.applicationSupportDirectory.appending(path: "Logs", directoryHint: .isDirectory)
    /// lines written at once in the foreground
    static let batch = 64
    /// how long a line waits for company in the foreground
    static let wait: Duration = .seconds(2)

    /// What the lock guards: the lines not yet taken, whether a write is on its way (in `wait`, or at
    /// once), and whether the app is in front.
    nonisolated struct State: Sendable {
        var queue = LogQueue()
        var timed = false
        var urgent = false
        /// false until the app first comes to the front: a launch in the background writes at once
        var foreground = false
    }

    private static let state = Mutex(State())
    private static let writer = LogWriter(folder: folder)
    private static let loggers: [LogCategory: Logger] = Dictionary(
        uniqueKeysWithValues: LogCategory.allCases.map { ($0, Logger(subsystem: subsystem, category: $0.rawValue)) }
    )

    // MARK: - Writing

    /// Something that happened. `msg` is a fixed sentence of the app; `fields` short values: ids,
    /// counts, a choice, a position through `LogRedact.text`.
    static func info(_ cat: LogCategory, _ msg: String, _ fields: [String: String] = [:]) {
        add(.info, cat, msg, fields)
    }

    /// Something that went wrong and was handled (a retry, a fallback).
    static func warning(_ cat: LogCategory, _ msg: String, _ fields: [String: String] = [:]) {
        add(.warning, cat, msg, fields)
    }

    /// Something that failed. Written at once, whatever the app's state.
    static func error(_ cat: LogCategory, _ msg: String, _ fields: [String: String] = [:]) {
        add(.error, cat, msg, fields)
    }

    /// The app came to the front (`AppModel.activate`) or left it (`deactivate`). Away, every line is
    /// written at once.
    static func foreground(_ inFront: Bool) {
        state.withLock { $0.foreground = inFront }
    }

    /// Everything logged so far, on disk (or kept for the next write, if it failed). `deactivate`
    /// waits for it under a background task.
    static func flush() async {
        await writer.write()
    }

    // MARK: - Reading

    /// The newest `limit` lines at `minimum` or above, newest first: those on disk, and those no write
    /// has taken yet (everything waiting is written first). Read off the main thread.
    static func recent(limit: Int, minimum: LogLevel) async -> [LogLine] {
        await writer.recent(limit: limit, minimum: minimum)
    }

    /// Bytes the log takes on disk: every file of Logs/, the reports in `diagnostics/` with them. (The
    /// 10 MB cap counts the day files only.)
    static func usage() async -> Int {
        await writer.usage()
    }

    /// Deletes the log: the day files and the reports in Logs/, the lines waiting, those kept from a
    /// failed write, the count of lines lost and the last write error. Leaves MetricKit's daily
    /// payloads (Caches/metrics, Số đo's) alone.
    static func clear() async {
        await writer.clear()
    }

    /// The last write that failed this launch, with its time ("14:03:21 · Không ghi được …"), until
    /// `clear`; nil if none failed. A later write that works does not clear it: lines may be missing.
    static func lastWriteError() async -> String? {
        await writer.failure
    }

    // MARK: - Crash reports, the export

    /// MetricKit's reports (`MetricsInbox`), each kept as its JSON in Logs/diagnostics, the 20 newest.
    static func keep(diagnostics reports: [(end: Date, json: Data)]) async {
        await writer.keep(reports)
    }

    /// The log as a .zip in the temporary folder, for the share sheet: "JP27-log-<yyyyMMdd-HHmm>.zip",
    /// holding Logs/ (the day files, `diagnostics/`), metrics/ (Caches/metrics, MetricKit's daily
    /// payloads) and `info.json`, which is `info` as given (keys sorted). The caller builds `info` from
    /// what is not private (version, iOS, model, language, settings, offline readiness, checks): never
    /// the phone's name (`UIDevice.name`) nor anything the user typed. Everything waiting is written
    /// first; the zip is made by `NSFileCoordinator`'s `.forUploading`, off the main thread. The
    /// previous exports' zips are deleted.
    @concurrent static func export(info: [String: String]) async throws -> URL {
        let files = FileManager.default
        let temporary = files.temporaryDirectory
        let name = LogRetention.exportName(Date(), in: .autoupdatingCurrent)
        // the earlier exports' zips: their share sheets are closed by now; a leftover only costs space
        for old in (try? files.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix("JP27-log-") && old.pathExtension == "zip" {
            try? files.removeItem(at: old)
        }
        // a folder of its own, so a second export within the minute, or one a killed export left, is
        // never in the way
        let scratch = temporary.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        // the copies only: the zip has left it before this runs
        defer { try? files.removeItem(at: scratch) }
        let work = scratch.appending(path: name, directoryHint: .isDirectory)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        try await writer.copy(into: work)
        if files.fileExists(atPath: MetricsInbox.folder.path(percentEncoded: false)) {
            try files.copyItem(at: MetricsInbox.folder, to: work.appending(path: "metrics", directoryHint: .isDirectory))
        }
        let about = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        try about.write(to: work.appending(path: "info.json", directoryHint: .notDirectory), options: .atomic)

        let zip = temporary.appending(path: name + ".zip", directoryHint: .notDirectory)
        var refused: NSError?
        var failed: (any Error)?
        var moved = false
        // the zip exists only inside the block (the coordinator unlinks it after), so it moves out
        // there; when coordinating fails the block never runs, and `refused` says why
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: work, options: .forUploading, error: &refused) { zipped in
            do {
                try FileManager.default.moveItem(at: zipped, to: zip)
                moved = true
            } catch {
                failed = error
            }
        }
        if let refused { throw refused }
        if let failed { throw failed }
        guard moved else { throw CocoaError(.fileWriteUnknown) }
        return zip
    }

    // MARK: - The queue

    private static func add(_ level: LogLevel, _ cat: LogCategory, _ msg: String, _ fields: [String: String]) {
        let taken: (line: LogLine, wake: Duration?) = state.withLock { s in
            let line = LogLine(t: Date(), level: level, cat: cat, msg: msg, fields: fields.isEmpty ? nil : fields)
            s.queue.append(line)
            if level == .error || !s.foreground || s.queue.count >= AppLog.batch {
                guard !s.urgent else { return (line, nil) }
                s.urgent = true
                return (line, .zero)
            }
            guard !s.timed else { return (line, nil) }
            s.timed = true
            return (line, AppLog.wait)
        }
        // outside the lock: neither the system log nor a task is started holding it
        system(taken.line)
        // nobody waits for this one: `flush` is what iOS waits for
        if let wake = taken.wake { Task { await writer.drain(after: wake) } }
    }

    /// The lines waiting, oldest first, and how many the queue has dropped since it was made; a write
    /// is no longer on its way.
    fileprivate static func take() -> (lines: [LogLine], dropped: Int) {
        state.withLock { s in
            s.timed = false
            s.urgent = false
            return (s.queue.drain(), s.queue.dropped)
        }
    }

    /// The lines waiting, gone, and the queue's count of dropped lines with them.
    fileprivate static func discard() {
        state.withLock { s in
            s.queue = LogQueue()
            s.timed = false
            s.urgent = false
        }
    }

    /// `line` in the system log (Console): `info` as a notice, so it shows without "Include Info
    /// Messages", like the app's other informational lines.
    fileprivate static func system(_ line: LogLine) {
        let fields = (line.fields ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        let text = ([line.msg] + fields).joined(separator: " ")
        let logger = loggers[line.cat] ?? Logger(subsystem: subsystem, category: line.cat.rawValue)
        switch line.level {
        case .info: logger.notice("\(text, privacy: .public)")
        case .warning: logger.warning("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        }
    }

    /// A failure of the log itself, in Console only: as a line of the log it would only fail again.
    fileprivate static func console(_ reason: String) {
        let logger = loggers[.app] ?? Logger(subsystem: subsystem, category: LogCategory.app.rawValue)
        logger.error("log: \(reason, privacy: .public)")
    }
}

/// The one writer of Logs/: appends, retention, reads, clearing, the export's copy and MetricKit's
/// reports, one at a time, off the main thread. Each write takes the queue and appends it without
/// suspending in between, so batches reach the file in the order they were taken.
private actor LogWriter {
    private let folder: URL
    private let reports: URL
    /// lines a write could not take (a full disk, a file locked before the first unlock): written
    /// first next time, 2000 at most
    private var backlog = LogQueue()
    /// the queue's and the backlog's counts of dropped lines, as last seen
    private var seenQueue = 0
    private var seenBacklog = 0
    /// lines lost since the file last said so, and why
    private var lost = 0
    private var lossReason: String?
    /// the last write failure, without its time (why the backlog dropped lines)
    private var writeError: String?
    /// the last write failure with its time, for the log page
    private(set) var failure: String?
    /// the folder was set out of the backup this launch
    private var excluded = false
    /// day files whose last append failed halfway and could not be taken back: the next line starts
    /// on its own
    private var broken: Set<String> = []

    private static let full = "Log hôm nay đã quá 10 MB"
    private static let queueFull = "Hàng đợi log đầy"

    init(folder: URL) {
        self.folder = folder
        reports = folder.appending(path: "diagnostics", directoryHint: .isDirectory)
    }

    /// The write a line asked for, `delay` after it.
    func drain(after delay: Duration) async {
        if delay > .zero {
            // a wake-up nobody cancels
            try? await Task.sleep(for: delay)
        }
        write()
    }

    /// Everything waiting onto disk: what earlier writes could not take first, then the queue, each
    /// line in the file of its own day. Then the folder trimmed to 14 days and 10 MB.
    func write() {
        let taken = AppLog.take()
        if taken.dropped > seenQueue { lose(taken.dropped - seenQueue, because: Self.queueFull) }
        seenQueue = taken.dropped
        let pending = backlog.drain() + taken.lines
        guard !pending.isEmpty else { return }
        let result = append(pending)
        // what could not be written waits for the next write, in order: the newest 2000
        for line in result.unwritten { backlog.append(line) }
        if backlog.dropped > seenBacklog { lose(backlog.dropped - seenBacklog, because: writeError ?? Self.queueFull) }
        seenBacklog = backlog.dropped
        if result.unwritten.isEmpty, result.written > 0, lost > 0 { reportLoss() }
        trim()
    }

    // MARK: Appending

    /// `lines` appended to their days' files, in order: how many were written, and those left from the
    /// first file that failed (lines past a full day's file are lost, and counted).
    private func append(_ lines: [LogLine]) -> (written: Int, unwritten: ArraySlice<LogLine>) {
        do {
            try prepare()
        } catch {
            fail("Không tạo được thư mục log: \(error.localizedDescription)")
            return (0, lines[...])
        }
        let zone = TimeZone.autoupdatingCurrent
        var written = 0
        var start = lines.startIndex
        while start < lines.endIndex {
            // a batch across midnight goes to two files
            let name = LogRetention.dayName(lines[start].t, in: zone)
            var end = start + 1
            while end < lines.endIndex, LogRetention.dayName(lines[end].t, in: zone) == name { end += 1 }
            guard let added = add(lines[start..<end].map { $0.encoded() }, to: name) else {
                return (written, lines[start...])
            }
            if added < end - start {
                lose(end - start - added, because: Self.full)
                fail(Self.full)
            }
            written += added
            start = end
        }
        return (written, [])
    }

    /// The encoded `lines` appended to the day file `name`, as many as keep it within `maxBytes`: how
    /// many; nil when the file could not be written, and then nothing of them is left in it (a part
    /// written before the failure is cut off again).
    private func add(_ lines: [Data], to name: String) -> Int? {
        let url = folder.appending(path: name, directoryHint: .notDirectory)
        let path = url.path(percentEncoded: false)
        let files = FileManager.default
        if !files.fileExists(atPath: path), !files.createFile(atPath: path, contents: nil) {
            fail("Không tạo được file \(name)")
            return nil
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            fail("Không mở được \(name): \(error.localizedDescription)")
            return nil
        }
        // the throwing calls only: `write(_:)` and `seekToEndOfFile()` raise an exception Swift cannot
        // catch (a full disk would end the app)
        var start: UInt64?
        var added = 0
        do {
            let end = try handle.seekToEnd()
            start = end
            let gap = broken.contains(name) && end > 0 ? Data([0x0A]) : Data()
            added = LogRetention.fitting(lines.map(\.count), after: Int(end) + gap.count)
            if added > 0 {
                var data = gap
                for line in lines.prefix(added) { data.append(line) }
                try handle.write(contentsOf: data)
                broken.remove(name)
            }
        } catch {
            let reason = error.localizedDescription
            // only to where the end was found: never cut a file whose end was not read
            if let start {
                do { try handle.truncate(atOffset: start) } catch { broken.insert(name) }
            }
            close(handle, name)
            fail("Không ghi được \(name): \(reason)")
            return nil
        }
        close(handle, name)
        return added
    }

    private func close(_ handle: FileHandle, _ name: String) {
        do {
            try handle.close()
        } catch {
            fail("Không đóng được \(name): \(error.localizedDescription)")
        }
    }

    /// The folder, made if missing, and out of the iCloud backup (tried once a launch; the flag covers
    /// what is in it).
    private func prepare() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard !excluded else { return }
        excluded = true
        var url = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try url.setResourceValues(values)
        } catch {
            // the log goes on; the backup carries it
            fail("Không để được thư mục log ngoài bản sao lưu: \(error.localizedDescription)")
        }
    }

    /// After lines were lost, the first write that works says so in the file: how many, and why. Kept
    /// for a later write if this one cannot be appended.
    private func reportLoss() {
        let line = LogLine(t: Date(), level: .warning, cat: .app, msg: "Không ghi được một số dòng log",
                           fields: ["dropped": "\(lost)", "error": lossReason ?? Self.queueFull])
        guard add([line.encoded()], to: LogRetention.dayName(line.t, in: .autoupdatingCurrent)) == 1 else { return }
        AppLog.system(line)
        lost = 0
        lossReason = nil
    }

    private func lose(_ count: Int, because reason: String) {
        lost += count
        lossReason = reason
    }

    /// A failure of the log, kept with its time for the log page and said in Console; never a line of
    /// the log, which would only fail again.
    private func fail(_ reason: String) {
        writeError = reason
        failure = Self.clock(Date()) + " · " + reason
        AppLog.console(reason)
    }

    /// "14:03:21" on the phone's clock, in Gregorian digits
    private static func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return [c.hour, c.minute, c.second].map { n in
            let s = String(n ?? 0)
            return s.count < 2 ? "0" + s : s
        }.joined(separator: ":")
    }

    // MARK: Retention

    /// The day files past 14 days or 10 MB, deleted (`LogRetention.toDelete`); after every write, so
    /// the folder never stays over the cap until the day changes.
    private func trim() {
        let files = FileManager.default
        guard files.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        let listing: [LogFile]
        do {
            listing = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]).map { url in
                LogFile(name: url.lastPathComponent, bytes: try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
        } catch {
            fail("Không đọc được thư mục log: \(error.localizedDescription)")
            return
        }
        for name in LogRetention.toDelete(listing, today: LogRetention.dayName(Date(), in: .autoupdatingCurrent)) {
            remove(folder.appending(path: name, directoryHint: .notDirectory))
        }
    }

    private func remove(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            fail("Không xoá được \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: Reading

    /// The newest `limit` lines at `minimum` or above, newest first, everything waiting written first.
    /// Each day file's newest matching lines are read, then all are ordered by time: after a move west
    /// (Tokyo to Hanoi) an earlier day's file gets newer lines than a later one.
    func recent(limit: Int, minimum: LogLevel) -> [LogLine] {
        write()
        guard limit > 0 else { return [] }
        var found: [(line: LogLine, order: Int)] = []
        for name in dayFiles() {
            for line in tail(of: name, limit: limit, minimum: minimum) { found.append((line, found.count)) }
        }
        // what no write could take yet: newer than anything on disk
        let held = backlog.drain()
        for line in held { backlog.append(line) }
        for line in held where line.level >= minimum { found.append((line, found.count)) }
        // the same millisecond: the later in the files is the newer
        found.sort { ($0.line.t, $0.order) > ($1.line.t, $1.order) }
        return found.prefix(limit).map(\.line)
    }

    /// The day files, by name
    private func dayFiles() -> [String] {
        // a folder that cannot be listed reads as empty: the page shows what it can
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".jsonl") }.sorted()
    }

    /// The newest `limit` lines at `minimum` or above of the day file `name`, in the file's order. A
    /// line that does not decode (cut short, from a later build) is skipped.
    private func tail(of name: String, limit: Int, minimum: LogLevel) -> [LogLine] {
        let data: Data
        do {
            data = try Data(contentsOf: folder.appending(path: name, directoryHint: .notDirectory))
        } catch {
            return []
        }
        var lines: [LogLine] = []
        for chunk in data.split(separator: 0x0A).reversed() {
            guard let line = LogLine.decode(chunk), line.level >= minimum else { continue }
            lines.append(line)
            if lines.count == limit { break }
        }
        return lines.reversed()
    }

    /// Bytes of the regular files in Logs/ and Logs/diagnostics/.
    func usage() -> Int {
        write()
        // a folder or a size that cannot be read counts nothing: this is a figure to show, not a decision
        let urls = ((try? regularFiles(in: folder)) ?? []) + ((try? regularFiles(in: reports)) ?? [])
        return urls.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// The regular files directly in `directory`; none when it was not made yet.
    private func regularFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
            .filter { try $0.resourceValues(forKeys: keys).isRegularFile == true }
    }

    // MARK: Clearing, the export, MetricKit

    func clear() {
        AppLog.discard()
        backlog = LogQueue()
        seenQueue = 0
        seenBacklog = 0
        lost = 0
        lossReason = nil
        writeError = nil
        failure = nil
        broken = []
        // the files only, never the folders: Logs/ keeps its backup flag
        for directory in [folder, reports] {
            do {
                for url in try regularFiles(in: directory) { remove(url) }
            } catch {
                fail("Không đọc được thư mục \(directory.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// Everything waiting written, then Logs/ (with `diagnostics/`) copied into `work` as "Logs": no
    /// write, trim or report runs during the copy.
    func copy(into work: URL) throws {
        write()
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        try FileManager.default.copyItem(at: folder, to: work.appending(path: "Logs", directoryHint: .isDirectory))
    }

    /// MetricKit's reports, each as its JSON in `diagnostics/` (`LogRetention.diagnosticName`), then
    /// the 20 newest kept.
    func keep(_ payloads: [(end: Date, json: Data)]) {
        let files = FileManager.default
        do {
            try prepare()
            try files.createDirectory(at: reports, withIntermediateDirectories: true)
        } catch {
            fail("Không tạo được thư mục báo cáo chẩn đoán: \(error.localizedDescription)")
            return
        }
        var used: [String: Int] = [:]
        for payload in payloads {
            let first = LogRetention.diagnosticName(payload.end, index: 0)
            let index = used[first, default: 0]
            used[first] = index + 1
            let name = LogRetention.diagnosticName(payload.end, index: index)
            do {
                try payload.json.write(to: reports.appending(path: name, directoryHint: .notDirectory), options: .atomic)
            } catch {
                fail("Không lưu được báo cáo chẩn đoán \(name): \(error.localizedDescription)")
            }
        }
        let names: [String]
        do {
            names = try files.contentsOfDirectory(atPath: reports.path(percentEncoded: false))
        } catch {
            fail("Không đọc được thư mục báo cáo chẩn đoán: \(error.localizedDescription)")
            return
        }
        for name in LogRetention.diagnosticsToDelete(names) {
            remove(reports.appending(path: name, directoryHint: .notDirectory))
        }
    }
}
