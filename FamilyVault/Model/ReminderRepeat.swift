import Foundation

/// How often a due date comes back around.
///
/// An EMI is monthly and a policy renewal is usually yearly, so a one-shot
/// reminder is the wrong shape for both — it fires once and then the entry
/// goes quiet forever.
enum ReminderRepeat: String, Codable, CaseIterable, Identifiable {
    case never
    case monthly
    case quarterly
    case halfYearly
    case yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: "Once, on that date"
        case .monthly: "Every month"
        case .quarterly: "Every 3 months"
        case .halfYearly: "Every 6 months"
        case .yearly: "Every year"
        }
    }

    var shortLabel: String {
        switch self {
        case .never: "Once"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .halfYearly: "Half-yearly"
        case .yearly: "Yearly"
        }
    }

    /// Months between occurrences; nil when it doesn't repeat.
    var monthStride: Int? {
        switch self {
        case .never: nil
        case .monthly: 1
        case .quarterly: 3
        case .halfYearly: 6
        case .yearly: 12
        }
    }

    /// The due dates from `start` onwards that fall inside the horizon.
    ///
    /// Stepping with `Calendar` rather than adding 30 days keeps an EMI due on
    /// the 31st landing on the last day of a short month instead of drifting.
    func dueDates(from start: Date, notBefore floor: Date, horizonMonths: Int, limit: Int) -> [Date] {
        let calendar = Calendar.current
        guard let stride = monthStride else {
            return start >= floor ? [start] : []
        }

        guard let horizon = calendar.date(byAdding: .month, value: horizonMonths, to: floor) else { return [] }

        var dates: [Date] = []
        var step = 0
        // Walk forward from the date the user entered, skipping occurrences
        // that have already gone by.
        while dates.count < limit, step < 400 {
            guard let candidate = calendar.date(byAdding: .month, value: stride * step, to: start) else { break }
            step += 1
            if candidate > horizon { break }
            if candidate >= floor { dates.append(candidate) }
        }
        return dates
    }
}
