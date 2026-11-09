import SwiftUI
import TripKit
import UIKit

// Hỗ trợ › Log (spec 3.3): the newest lines, filtered by level, by day; the log exported as a .zip to share; the log
// deleted after a confirmation.

/// Reads the log for the page, one read at a time for the whole app: `AppLog.unreadable` speaks of the last `recent`,
/// so the two always go as a pair, and a read asked for while one runs (another filter, the page opened again, a pull)
/// waits for it and runs after, the newest ask only. "Lỗi" reads up to 10 MB: the page shows it is reading.
@Observable final class LogReader {
    static let shared = LogReader()

    /// the lines of the last read, newest first; nil before the first
    private(set) var lines: [LogLine]?
    /// the level the last read was for
    private(set) var shown = LogLevel.info
    /// day files that read could not read
    private(set) var unreadable = 0
    /// the last failed write of the log, with its time
    private(set) var writeError: String?
    private(set) var reading = false
    @ObservationIgnored private var wanted: LogLevel?

    func read(_ minimum: LogLevel) async {
        wanted = minimum
        guard !reading else { return }
        reading = true
        defer { reading = false }
        while let next = wanted {
            wanted = nil
            let got = await AppLog.recent(limit: 200, minimum: next)
            let bad = await AppLog.unreadable()
            let error = await AppLog.lastWriteError()
            lines = got
            shown = next
            unreadable = bad
            writeError = error
        }
    }
}

/// The export, one at a time for the whole app: leaving the page and coming back does not start a second.
@Observable final class LogExport {
    static let shared = LogExport()

    private(set) var running = false
    /// the zip made last, shared from the page's "Chia sẻ log"
    private(set) var file: URL?
    /// why the last export failed
    private(set) var failure: String?

    /// `base` is what the page read on the main actor; the free space and the app's size are added here, off the main
    /// thread (`CheckRun.space`), once `running` holds: the buttons are off from the tap on.
    func run(base: [String: String]) async {
        guard !running else { return }
        running = true
        defer { running = false }
        failure = nil
        file = nil
        var info = base
        let space = await CheckRun.space()
        info["freeBytes"] = space.free.map { "\($0)" } ?? "?"
        info["appBytes"] = "\(space.app)"
        // before the export, which writes everything waiting first: the zip says it was exported
        AppLog.info(.app, "Xuất log")
        do {
            file = try await AppLog.export(info: info)
        } catch {
            failure = error.localizedDescription
            AppLog.error(.app, "Không xuất được log", ["reason": error.localizedDescription])
        }
    }

    /// The zip made earlier is let go of (iOS empties the temporary folder): the next share is of a new export.
    func forget() {
        if !running { file = nil }
        failure = nil
    }
}

/// Settings › Hỗ trợ › Log: a page of its own (`SettingsPage`), so its reading, refreshing and alert attach once.
struct LogPage: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Appearance.key) private var appearance: Appearance = .system
    @AppStorage(MapPacer.glassKey) private var glass = true
    @AppStorage(MapPacer.reliefKey) private var relief = false
    @AppStorage(SpeechPace.key) private var pace: SpeechPace = .normal
    @State private var filter = LogLevel.info
    @State private var clearing = false

    var body: some View {
        let reader = LogReader.shared
        let export = LogExport.shared
        // the level as this body draws it, for the pull (a closure of its own, not on the main actor)
        let level = filter
        SettingsPage(title: "Log") {
            if let error = reader.writeError {
                Section {
                    Label {
                        Text("Không ghi được log: \(error)").font(.subheadline)
                    } icon: {
                        SettingsIcon(symbol: "exclamationmark.triangle.fill", tint: .red)
                    }
                }
            }
            Section {
                Picker("Mức", selection: $filter) {
                    Text("Tất cả").tag(LogLevel.info)
                    Text("Cảnh báo").tag(LogLevel.warning)
                    Text("Lỗi").tag(LogLevel.error)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if reader.unreadable > 0 {
                    Text("\(reader.unreadable) file log không đọc được").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let lines = reader.lines, reader.shown == filter {
                if lines.isEmpty {
                    Section {
                        Text("Chưa có dòng nào").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(LogDay.split(lines)) { day in
                        Section(day.title) {
                            ForEach(day.rows) { LogRow(line: $0.line) }
                        }
                    }
                }
            } else {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Đang đọc log…").foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                if let file = export.file {
                    ShareLink(item: file) {
                        Label("Chia sẻ log", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        let base = exportInfo()
                        Task { await export.run(base: base) }
                    } label: {
                        HStack {
                            Label("Xuất log", systemImage: "doc.zipper")
                            Spacer()
                            if export.running { ProgressView() }
                        }
                    }
                    .disabled(export.running)
                }
                if let failure = export.failure {
                    Text("Không xuất được log: \(failure)").font(.footnote).foregroundStyle(.red)
                }
                Button("Xoá log", role: .destructive) { clearing = true }
                    .disabled(export.running)
            } footer: {
                Text("Log giữ 14 ngày, tối đa 10 MB; không có chữ bạn tự gõ.")
            }
        }
        .task(id: filter) { await reader.read(filter) }
        .refreshable { @MainActor in await LogReader.shared.read(level) }
        .onAppear { export.forget() }
        .alert("Xoá log?", isPresented: $clearing) {
            Button("Xoá", role: .destructive) {
                Task {
                    await AppLog.clear()
                    // the log says it was cleared, in an export after
                    AppLog.info(.app, "Xoá log")
                    export.forget()
                    await reader.read(filter)
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Xoá mọi dòng log và báo cáo crash trên máy, Số đo vẫn giữ.")
        }
    }

    /// What `info.json` holds, read on the main actor: nothing private (never the phone's name, its network name, nor
    /// anything typed). `LogExport.run` adds the free space and the app's size.
    private func exportInfo() -> [String: String] {
        let downloads = model.downloads
        let stale = !model.offline.stale.isEmpty
        var info: [String: String] = [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            "ios": UIDevice.current.systemVersion,
            "machine": Self.machine(),
            "language": Locale.preferredLanguages.first ?? Locale.current.identifier,
            "timeZone": TimeZone.current.identifier,
            "appearance": appearance.rawValue,
            "pace": pace.rawValue,
            "keepAwakeOnRide": "\(model.keepAwakeOnRide)",
            "glass": "\(glass)",
            "relief": "\(relief)",
            "rehearsing": "\(model.rehearsing)",
            "offline": Readiness.summary(downloads.readiness.states, mapsStale: stale, downloading: downloads.busy ? downloads.fraction : nil),
        ]
        if let checks = CheckRun.shared.lastJSON { info["checks"] = checks }
        return info
    }

    /// The model's identifier ("iPhone17,1"): `utsname.machine` only. Its `nodename` is the phone's network name,
    /// which often holds its owner's.
    private nonisolated static func machine() -> String {
        var u = utsname()
        guard uname(&u) == 0 else { return "?" }
        return withUnsafeBytes(of: &u.machine) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

/// The lines of one day (the phone's), newest first, under "Hôm nay" or "8/11".
private struct LogDay: Identifiable {
    struct Row: Identifiable {
        let id: Int
        let line: LogLine
    }

    let id: String
    let title: String
    let rows: [Row]

    /// `lines` newest first, cut where the day changes.
    static func split(_ lines: [LogLine]) -> [LogDay] {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.year, .month, .day], from: Date())
        var days: [LogDay] = []
        var rows: [Row] = []
        var current: DateComponents?
        func close() {
            guard let c = current, !rows.isEmpty else { return }
            let title = c == today ? "Hôm nay" : "\(c.day ?? 0)/\(c.month ?? 0)"
            days.append(LogDay(id: "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(days.count)", title: title, rows: rows))
        }
        for (i, line) in lines.enumerated() {
            let c = calendar.dateComponents([.year, .month, .day], from: line.t)
            if c != current {
                close()
                current = c
                rows = []
            }
            rows.append(Row(id: i, line: line))
        }
        close()
        return days
    }
}

/// One line: its time (HH:mm:ss, the phone's clock), its group, its sentence in its level's colour.
private struct LogRow: View {
    let line: LogLine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(Self.clock(line.t)).monospacedDigit()
                Text(line.cat.rawValue)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(line.msg)
                .font(.subheadline)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch line.level {
        case .info: .primary
        case .warning: .orange
        case .error: .red
        }
    }

    /// "14:03:21" in Gregorian digits, as the log's own times
    private static func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return [c.hour, c.minute, c.second].map { n in
            let s = String(n ?? 0)
            return s.count < 2 ? "0" + s : s
        }.joined(separator: ":")
    }
}
