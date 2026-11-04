import Foundation
import SwiftData

#if DEBUG
// Debug only: answers, on the phone, what this build's SwiftData does with a write that breaks
// `#Unique` (docs/superpowers/checklists/2026-11-device-phase1-3.md, Task 1.4, step 9).
extension AppModel {
    /// Settings › Chẩn đoán › "Thử ghi trùng chỉ số": what this phone's SwiftData does when one write
    /// puts two marks of a day on one index (`#Unique` on day and index), the clash `loadRecords`
    /// writes in two steps to avoid. Two marks on a day no plan has (0 and 1) swap indexes, then one
    /// is moved onto the other's. Says for each whether the write failed or went through, and which
    /// rows were left; the rows are taken away after.
    func uniqueProbe() -> String {
        let key = "debug.unique"
        func rows() -> [Checkmark] {
            ((try? context.fetch(FetchDescriptor<Checkmark>(predicate: #Predicate { $0.day == key }))) ?? []).sorted { $0.at < $1.at }
        }
        func clear() throws(SaveFailure) {
            for c in rows() { context.delete(c) }
            try context.commit()
        }
        func outcome(_ name: String, _ change: ([Checkmark]) -> Void) -> String {
            do {
                try clear()
                context.insert(Checkmark(day: key, index: 0, at: Date(timeIntervalSince1970: 0)))
                context.insert(Checkmark(day: key, index: 1, at: Date(timeIntervalSince1970: 1)))
                try context.commit()
            } catch {
                return "\(name): không chuẩn bị được (\(error.localizedDescription))"
            }
            let two = rows()
            guard two.count == 2 else { return "\(name): không chuẩn bị được (\(two.count) dòng)" }
            change(two)
            do {
                try context.commit()
            } catch {
                return "\(name): lỗi, không lưu (\(error.localizedDescription))"
            }
            let left = rows().map { "\($0.at.timeIntervalSince1970 == 0 ? "A" : "B")@\($0.index)" }
            return "\(name): lưu được, còn \(left.count) dòng \(left.joined(separator: " "))"
        }
        let swap = outcome("A↔B đổi chỗ") { $0[0].index = 1; $0[1].index = 0 }
        let onto = outcome("A chồng lên B") { $0[0].index = 1 }
        do {
            try clear()
        } catch {
            return [swap, onto, "dọn không được: \(error.localizedDescription)"].joined(separator: "\n")
        }
        return [swap, onto].joined(separator: "\n")
    }
}
#endif
