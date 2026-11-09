import SwiftUI
import TripKit

// The trip's own pages: the alternative days, the walking pace, the rehearsal clock.

// MARK: - Alternative days

struct AlternativesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let alts = model.store.trip.altDays
        if !alts.isEmpty {
            Section {
                ForEach(alts) { alt in
                    Toggle(isOn: binding(alt.key)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alt.title)
                            Text("Thay ngày \(alt.replaces ?? alt.n) · \(Fmt.shortDate(alt.date))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Lịch trình")
            } footer: {
                Text("Nhắc giờ, geofence và widget đi theo lựa chọn này.")
            }
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { model.alternatives.contains(key) },
            set: { on in
                if on { model.alternatives.insert(key) } else { model.alternatives.remove(key) }
            })
    }
}

// MARK: - Rehearsal clock

struct RehearsalSection: View {
    @Environment(AppModel.self) private var model
    @State private var picked = Date()
    @State private var seeded = false
    /// what the picker was set to, and whether that was the clock as it is: left there, it means
    /// "now" however long the page stays open
    @State private var seed = Date()
    @State private var seededAtNow = false

    private var range: ClosedRange<Date> {
        let first = model.store.trip.days.first.flatMap { TripTime.midnight($0.date) } ?? Date()
        let last = model.store.trip.days.last.flatMap { TripTime.midnight($0.date) } ?? Date()
        return first.addingTimeInterval(-86400) ... last.addingTimeInterval(2 * 86400)
    }

    var body: some View {
        Section {
            DatePicker("Thời điểm", selection: $picked, in: range)
                .environment(\.timeZone, TripTime.zone)
            Button("Chạy thử từ thời điểm này") {
                model.rehearse(at: effectivePick)
                reseed()
            }
            // nothing to start: the picker at the clock as it is, or within a minute of it
            .disabled(RehearsalClock.start(at: effectivePick, realNow: Date(), current: model.clockOffset) == nil)
            if model.rehearsing {
                LabeledContent("Đồng hồ chuyến đi") {
                    Text(clockLabel(model.now)).monospacedDigit()
                }
                Button("Về giờ thật", role: .destructive) {
                    model.endRehearsal()
                    reseed()
                }
            }
        } header: {
            Text("Chạy thử")
        } footer: {
            Text("Giờ Nhật; nhắc, widget và Live Activity chạy theo đồng hồ này, và những gì ghi lúc chạy thử bị xoá khi về giờ thật.")
        }
        .onAppear {
            guard !seeded else { return }
            seeded = true
            reseed()
        }
    }

    /// The picker set to the trip clock as it is now (`Shared.now`: `model.now` moves only on the
    /// minute), within the picker's range.
    private func reseed() {
        let now = Shared.now
        seed = min(max(now, range.lowerBound), range.upperBound)
        seededAtNow = seed == now
        picked = seed
    }

    /// The instant the start button means: the trip clock as it is while the picker is left where it
    /// was set at now, else what was picked.
    private var effectivePick: Date {
        seededAtNow && picked == seed ? Shared.now : picked
    }

    private func clockLabel(_ d: Date) -> String {
        let c = TripTime.calendar.dateComponents([.day, .month], from: d)
        return "\(c.day ?? 0)/\(c.month ?? 0) · \(TripTime.clock(d))"
    }
}

// MARK: - Walking pace

struct PaceSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pace = model.pace
        Section {
            LabeledContent("Tốc độ đi bộ") {
                Text("\(Fmt.decimal(3.9 * pace.factor, digits: 1)) km/h").monospacedDigit()
            }
            Text(summary(pace))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Đi bộ")
        }
    }

    private func summary(_ pace: PaceModel) -> String {
        guard pace.minutes >= 1 else { return "Chưa đo. Giờ đi bộ đang tính theo 3,9 km/h trên đường bằng, chậm hơn khi lên dốc." }
        let delta = Int(((pace.factor - 1) * 100).rounded())
        let base = "Đo từ \(Int(pace.minutes.rounded())) phút đi bộ."
        if abs(delta) < 2 { return "Đúng như mô hình. " + base }
        return (delta > 0 ? "Nhanh hơn mô hình \(delta)%. " : "Chậm hơn mô hình \(-delta)%. ") + base
    }
}
