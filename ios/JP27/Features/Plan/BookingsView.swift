import SwiftUI
import TripKit

/// Đặt chỗ: every booking in the order to do them — the ones that open at an exact Japan time
/// with a countdown — then the checks before leaving.
struct BookingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(Array(model.guide.bookings.enumerated()), id: \.offset) { _, b in
                    PlanBookingRow(booking: b, now: model.now)
                }
            }
            if !model.guide.checks.isEmpty {
                Section("Trước khi đi") {
                    ForEach(model.guide.checks, id: \.self) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.when).font(.subheadline.weight(.semibold))
                            Text(c.text).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Đặt chỗ")
    }
}

private struct PlanBookingRow: View {
    let booking: Booking
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let date = booking.date {
                HStack(alignment: .firstTextBaseline) {
                    Label(planJapanTime(date), systemImage: "alarm")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(date > now ? Color.accentColor : .secondary)
                        .monospacedDigit()
                    Spacer()
                    PlanBookingCountdown(target: date, now: now)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(booking.rule).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(booking.rule).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(booking.title).font(.body.weight(.semibold))
            Text(booking.text).font(.subheadline)
        }
        .padding(.vertical, 4)
        .opacity(booking.date.map { $0 < now } == true ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// Days to go, or the minute countdown on the day.
private struct PlanBookingCountdown: View {
    let target: Date
    let now: Date

    var body: some View {
        let seconds = target.timeIntervalSince(now)
        if seconds <= 0 {
            Text("Đã mở")
        } else if seconds > 86400 {
            Text("còn \(Int((seconds / 86400).rounded(.up))) ngày").monospacedDigit()
        } else {
            Countdown(target: target, now: now)
        }
    }
}

/// "22/10, 0:00 giờ Nhật"
func planJapanTime(_ date: Date) -> String {
    let c = TripTime.calendar.dateComponents([.day, .month], from: date)
    return "\(c.day ?? 0)/\(c.month ?? 0), \(TripTime.clock(date)) giờ Nhật"
}
