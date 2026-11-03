import Foundation

/// Spending categories, the same split as the budget (guide.json budget.lines ids).
public enum SpendCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case food, shop, move, ticket, hotel, ryokan, extra

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .food: "Ăn uống"
        case .shop: "Mua sắm"
        case .move: "Di chuyển"
        case .ticket: "Vé tham quan"
        case .hotel: "Khách sạn"
        case .ryokan: "Ryokan"
        case .extra: "Phụ phí"
        }
    }

    /// The category a place's spending most likely belongs to.
    public static func of(_ place: Place?) -> SpendCategory {
        switch place?.kind {
        case .food: .food
        case .shop: .shop
        case .station: .move
        case .stay: place?.id == "mizunoto" ? .ryokan : .hotel
        case .sight: .ticket
        case nil: .extra
        }
    }
}

/// How something was paid. IC is Suica on the phone or the card.
public enum PayMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case cash, card, ic

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cash: "Tiền mặt"
        case .card: "Thẻ"
        case .ic: "Suica"
        }
    }
}

public struct Estimate: Sendable, Hashable {
    /// yen for the party
    public let low: Int
    public let high: Int
    public var mid: Int { (low + high) / 2 }

    public init(low: Int, high: Int) {
        self.low = min(low, high)
        self.high = max(low, high)
    }

    public var label: String {
        low == high ? Fmt.yen(low) : "\(Fmt.yen(low))–\(Fmt.grouped(high))"
    }
}

public enum Spend {
    /// "¥1.400–1.700" or "¥2.000" → yen bounds, per person.
    public static func range(_ price: String?) -> (Int, Int)? {
        guard let price else { return nil }
        let numbers = price.matches(of: /[0-9][0-9.]*/).compactMap { Int($0.output.replacingOccurrences(of: ".", with: "")) }.filter { $0 >= 50 }
        guard let a = numbers.first else { return nil }
        return (a, numbers.dropFirst().first ?? a)
    }

    /// What a visit will cost the party: the plan's figure, else the per-person price, else the house dishes.
    public static func estimate(stop: Stop?, place: Place, people: Int = 2) -> Estimate? {
        if let cost = stop?.cost { return Estimate(low: cost, high: cost) }
        if let (a, b) = range(place.price) { return Estimate(low: a * people, high: b * people) }
        let picks = (place.menu?.items ?? []).filter { $0.pick == .signature || $0.pick == .popular }.compactMap(\.yen)
        if let first = picks.first { return Estimate(low: first * people, high: (picks.max() ?? first) * people) }
        let snack = (place.snack?.get ?? []).compactMap(\.yen)
        if let s = snack.first { return Estimate(low: s * people, high: snack.reduce(0, +) * people) }
        return nil
    }
}

/// Cash the next days will ask for at places that take only cash (and, as a maybe, mixed ones).
public struct CashPlan: Sendable {
    public struct Need: Sendable, Hashable {
        public let day: String
        public let index: Int
        public let placeID: String
        public let yen: Int
        public let certain: Bool
    }

    public let needs: [Need]
    public var certain: Int { Yen.total(needs.filter(\.certain).map(\.yen)) }
    public var possible: Int { Yen.total(needs.map(\.yen)) }

    /// Stops from (day, cursor) through the end of the following day.
    public init(store: TripStore, days: [Day], from dayIndex: Int, cursor: Int, horizon: Int = 2) {
        var out: [Need] = []
        for (k, day) in days.enumerated() where k >= dayIndex && k < dayIndex + horizon {
            for (i, stop) in day.stops where k > dayIndex || i >= cursor {
                guard let p = store.place(stop.place), let pay = p.payment, pay != .card,
                      let est = Spend.estimate(stop: stop, place: p) else { continue }
                out.append(Need(day: day.key, index: i, placeID: p.id, yen: est.high, certain: pay == .cash))
            }
        }
        needs = out
    }

    /// What to withdraw so cash on hand covers the certain needs with a margin for small things.
    public func shortfall(onHand: Int, margin: Int = 5000) -> Int {
        max(0, Yen.difference(Yen.total([certain, margin]), onHand))
    }
}

/// Spending against the budget, by category.
public struct BudgetStatus: Sendable {
    public struct Row: Sendable, Identifiable {
        public var id: String { category.rawValue }
        public let category: SpendCategory
        public let planned: Int
        public let spent: Int
        public var left: Int { Yen.difference(planned, spent) }
        public var share: Double { planned > 0 ? Double(spent) / Double(planned) : 0 }
    }

    public let rows: [Row]
    public let reserve: Int
    public var planned: Int { Yen.total(rows.map(\.planned) + [reserve]) }
    public var spent: Int { Yen.total(rows.map(\.spent)) }

    public init(budget: Budget, spent: [SpendCategory: Int]) {
        rows = SpendCategory.allCases.map { c in
            Row(category: c, planned: budget.lines.first { $0.id == c.rawValue }?.yen ?? 0, spent: spent[c] ?? 0)
        }
        reserve = budget.lines.first { $0.id == "reserve" }?.yen ?? 0
    }
}
