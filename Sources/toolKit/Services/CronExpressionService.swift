import Foundation

struct CronExpressionService {
    struct Explanation {
        let summary: String
        let details: [String]
        let nextRuns: [Date]
    }

    enum CronError: LocalizedError {
        case invalidFieldCount
        case invalidField(name: String, value: String)
        case noUpcomingRuns

        var errorDescription: String? {
            switch self {
            case .invalidFieldCount:
                return "Use a standard 5-field cron expression: minute hour day-of-month month day-of-week."
            case .invalidField(let name, let value):
                return "The \(name) field is invalid: \(value)"
            case .noUpcomingRuns:
                return "No matching run time was found in the next two years."
            }
        }
    }

    private struct CronField {
        let name: String
        let raw: String
        let values: Set<Int>
        let minimum: Int
        let maximum: Int
        let isWildcard: Bool

        func contains(_ value: Int) -> Bool {
            values.contains(value)
        }
    }

    private struct ParsedExpression {
        let minute: CronField
        let hour: CronField
        let dayOfMonth: CronField
        let month: CronField
        let weekday: CronField
    }

    func generate(
        mode: CronGeneratorMode,
        minute: Int,
        hour: Int,
        dayOfMonth: Int,
        weekday: Int,
        intervalMinutes: Int
    ) -> String {
        let minute = clamp(minute, 0...59)
        let hour = clamp(hour, 0...23)
        let dayOfMonth = clamp(dayOfMonth, 1...31)
        let weekday = clamp(weekday, 0...6)
        let intervalMinutes = clamp(intervalMinutes, 1...59)

        switch mode {
        case .everyNMinutes:
            return "*/\(intervalMinutes) * * * *"
        case .hourly:
            return "\(minute) * * * *"
        case .daily:
            return "\(minute) \(hour) * * *"
        case .weekly:
            return "\(minute) \(hour) * * \(weekday)"
        case .monthly:
            return "\(minute) \(hour) \(dayOfMonth) * *"
        }
    }

    func explain(_ expression: String, from date: Date = Date(), count: Int = 8) throws -> Explanation {
        let parsed = try parse(expression)
        let nextRuns = try upcomingRuns(for: parsed, from: date, count: count)
        return Explanation(
            summary: summary(for: parsed),
            details: [
                "Minute: \(describe(parsed.minute))",
                "Hour: \(describe(parsed.hour))",
                "Day of month: \(describe(parsed.dayOfMonth))",
                "Month: \(describe(parsed.month, names: monthNames))",
                "Day of week: \(describe(parsed.weekday, names: weekdayNames))"
            ],
            nextRuns: nextRuns
        )
    }

    private func parse(_ expression: String) throws -> ParsedExpression {
        let parts = expression
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map(String.init)
        guard parts.count == 5 else {
            throw CronError.invalidFieldCount
        }

        return ParsedExpression(
            minute: try parseField(parts[0], name: "minute", minimum: 0, maximum: 59),
            hour: try parseField(parts[1], name: "hour", minimum: 0, maximum: 23),
            dayOfMonth: try parseField(parts[2], name: "day of month", minimum: 1, maximum: 31),
            month: try parseField(parts[3], name: "month", minimum: 1, maximum: 12, aliases: monthAliases),
            weekday: try parseField(parts[4], name: "day of week", minimum: 0, maximum: 7, aliases: weekdayAliases)
        )
    }

    private func parseField(
        _ rawValue: String,
        name: String,
        minimum: Int,
        maximum: Int,
        aliases: [String: Int] = [:]
    ) throws -> CronField {
        let normalized = rawValue.uppercased()
        guard !normalized.isEmpty else {
            throw CronError.invalidField(name: name, value: rawValue)
        }

        if normalized == "*" || normalized == "?" {
            return CronField(
                name: name,
                raw: rawValue,
                values: Set(minimum...normalizedMaximum(maximum, name: name)),
                minimum: minimum,
                maximum: normalizedMaximum(maximum, name: name),
                isWildcard: true
            )
        }

        var values = Set<Int>()
        for component in normalized.split(separator: ",").map(String.init) {
            let parsedValues = try parseComponent(
                component,
                name: name,
                minimum: minimum,
                maximum: maximum,
                aliases: aliases
            )
            values.formUnion(parsedValues)
        }

        if name == "day of week", values.contains(7) {
            values.remove(7)
            values.insert(0)
        }

        guard !values.isEmpty else {
            throw CronError.invalidField(name: name, value: rawValue)
        }

        return CronField(
            name: name,
            raw: rawValue,
            values: values,
            minimum: minimum,
            maximum: normalizedMaximum(maximum, name: name),
            isWildcard: false
        )
    }

    private func parseComponent(
        _ component: String,
        name: String,
        minimum: Int,
        maximum: Int,
        aliases: [String: Int]
    ) throws -> Set<Int> {
        let stepParts = component.split(separator: "/", maxSplits: 1).map(String.init)
        let base = stepParts[0]
        let step: Int
        if stepParts.count == 2 {
            guard let parsedStep = Int(stepParts[1]), parsedStep > 0 else {
                throw CronError.invalidField(name: name, value: component)
            }
            step = parsedStep
        } else {
            step = 1
        }

        let range: ClosedRange<Int>
        if base == "*" || base == "?" {
            range = minimum...maximum
        } else if base.contains("-") {
            let bounds = base.split(separator: "-", maxSplits: 1).map(String.init)
            guard bounds.count == 2,
                  let start = value(for: bounds[0], aliases: aliases),
                  let end = value(for: bounds[1], aliases: aliases),
                  start <= end,
                  start >= minimum,
                  end <= maximum
            else {
                throw CronError.invalidField(name: name, value: component)
            }
            range = start...end
        } else {
            guard let value = value(for: base, aliases: aliases),
                  value >= minimum,
                  value <= maximum
            else {
                throw CronError.invalidField(name: name, value: component)
            }
            range = value...value
        }

        return Set(stride(from: range.lowerBound, through: range.upperBound, by: step))
    }

    private func value(for token: String, aliases: [String: Int]) -> Int? {
        aliases[token] ?? Int(token)
    }

    private func upcomingRuns(for parsed: ParsedExpression, from date: Date, count: Int) throws -> [Date] {
        let calendar = Calendar.current

        guard var cursor = calendar.date(byAdding: .minute, value: 1, to: calendar.startOfMinute(for: date)) else {
            throw CronError.noUpcomingRuns
        }

        let deadline = calendar.date(byAdding: .year, value: 2, to: cursor) ?? cursor
        var results: [Date] = []

        while cursor <= deadline && results.count < count {
            if matches(cursor, parsed: parsed, calendar: calendar) {
                results.append(cursor)
            }
            guard let next = calendar.date(byAdding: .minute, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }

        guard !results.isEmpty else {
            throw CronError.noUpcomingRuns
        }

        return results
    }

    private func matches(_ date: Date, parsed: ParsedExpression, calendar: Calendar) -> Bool {
        let minute = calendar.component(.minute, from: date)
        let hour = calendar.component(.hour, from: date)
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let calendarWeekday = calendar.component(.weekday, from: date)
        let cronWeekday = calendarWeekday == 1 ? 0 : calendarWeekday - 1

        guard parsed.minute.contains(minute),
              parsed.hour.contains(hour),
              parsed.month.contains(month)
        else {
            return false
        }

        let matchesDayOfMonth = parsed.dayOfMonth.contains(day)
        let matchesWeekday = parsed.weekday.contains(cronWeekday)

        if parsed.dayOfMonth.isWildcard && parsed.weekday.isWildcard {
            return true
        }
        if parsed.dayOfMonth.isWildcard {
            return matchesWeekday
        }
        if parsed.weekday.isWildcard {
            return matchesDayOfMonth
        }
        return matchesDayOfMonth || matchesWeekday
    }

    private func summary(for parsed: ParsedExpression) -> String {
        "Runs \(describe(parsed.minute)) \(describeHourContext(parsed.hour)) \(describeDayContext(parsed.dayOfMonth, parsed.weekday)) \(describeMonthContext(parsed.month))."
    }

    private func describe(_ field: CronField, names: [Int: String] = [:]) -> String {
        if field.isWildcard {
            return "every \(field.name)"
        }

        if field.raw.hasPrefix("*/"),
           let step = Int(field.raw.dropFirst(2)) {
            return "every \(step) \(field.name)\(step == 1 ? "" : "s")"
        }

        let sorted = field.values.sorted()
        if sorted.count == 1, let value = sorted.first {
            return "at \(names[value] ?? String(value))"
        }
        if sorted.count <= 6 {
            return "at \(sorted.map { names[$0] ?? String($0) }.joined(separator: ", "))"
        }
        return "\(sorted.count) selected \(field.name)s"
    }

    private func describeHourContext(_ field: CronField) -> String {
        field.isWildcard ? "of every hour" : "during hour \(describe(field))"
    }

    private func describeDayContext(_ dayOfMonth: CronField, _ weekday: CronField) -> String {
        if dayOfMonth.isWildcard && weekday.isWildcard {
            return "on every day"
        }
        if dayOfMonth.isWildcard {
            return "on \(describe(weekday, names: weekdayNames))"
        }
        if weekday.isWildcard {
            return "on day \(describe(dayOfMonth))"
        }
        return "when day-of-month is \(describe(dayOfMonth)) or weekday is \(describe(weekday, names: weekdayNames))"
    }

    private func describeMonthContext(_ field: CronField) -> String {
        field.isWildcard ? "in every month" : "in \(describe(field, names: monthNames))"
    }

    private func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func normalizedMaximum(_ maximum: Int, name: String) -> Int {
        name == "day of week" ? 6 : maximum
    }

    private var monthAliases: [String: Int] {
        [
            "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
            "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12
        ]
    }

    private var weekdayAliases: [String: Int] {
        [
            "SUN": 0, "MON": 1, "TUE": 2, "WED": 3, "THU": 4, "FRI": 5, "SAT": 6
        ]
    }

    private var monthNames: [Int: String] {
        [
            1: "January", 2: "February", 3: "March", 4: "April",
            5: "May", 6: "June", 7: "July", 8: "August",
            9: "September", 10: "October", 11: "November", 12: "December"
        ]
    }

    private var weekdayNames: [Int: String] {
        [
            0: "Sunday", 1: "Monday", 2: "Tuesday", 3: "Wednesday",
            4: "Thursday", 5: "Friday", 6: "Saturday"
        ]
    }
}

private extension Calendar {
    func startOfMinute(for date: Date) -> Date {
        let components = dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return self.date(from: components) ?? date
    }
}
