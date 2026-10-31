import Foundation

// Typed input: durations ("1h 15m"), dates ("fri", "nov 18") and the New task field's tokens
// ("!high @beta due:fri ~90m"). Pure functions, so they're easy to test.

// MARK: - Durations

/// Parses and formats durations typed by hand: "1h 15m", "1h15m", "90m", "90" (minutes), "1.5h",
/// "1:15" (h:mm), "1:12:30" (h:mm:ss), "2 hours", "45 min".
enum TaskDurationParser {
    private static let unitPattern = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)\s*(hours|hour|hrs|hr|h|minutes|minute|mins|min|m|seconds|second|secs|sec|s)(?![a-z])"#
    )

    /// Seconds, or nil when the text isn't a duration. Zero is allowed ("0", "0m").
    static func seconds(_ text: String) -> TimeInterval? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return nil }

        // A plain number is minutes
        if let number = Double(raw.replacingOccurrences(of: ",", with: ".")), number >= 0 {
            return number * 60
        }

        // h:mm or h:mm:ss
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2 || parts.count == 3 {
            let numbers = parts.map { Int($0) }
            guard numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
            let values = numbers.compactMap { $0 }
            guard values.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
            let h = Double(values[0]), m = Double(values[1]), s = parts.count == 3 ? Double(values[2]) : 0
            return h * 3600 + m * 60 + s
        }

        // Unit tokens; everything else must be whitespace
        let ns = raw as NSString
        let matches = unitPattern.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        var total: TimeInterval = 0
        var covered = 0
        for match in matches {
            let gap = ns.substring(with: NSRange(location: covered, length: match.range.location - covered))
            guard gap.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            covered = match.range.location + match.range.length
            guard let value = Double(ns.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")) else { return nil }
            switch ns.substring(with: match.range(at: 2)).first {
            case "h": total += value * 3600
            case "m": total += value * 60
            default: total += value
            }
        }
        guard ns.substring(from: covered).trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return total
    }

    /// Whole minutes (rounded), or nil when the text isn't a duration.
    static func minutes(_ text: String) -> Int? {
        seconds(text).map { Int(($0 / 60).rounded()) }
    }

    /// "1h 12m", "45m", "2h", "0m": time spent, for editing (seconds are dropped).
    static func format(seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - Dates

/// Parses typed due dates into midnight of that day:
/// - "today", "tomorrow" (tmr, tmrw), "next week" (start of next week)
/// - weekdays: "fri", "friday" (the next one after today), "next fri" (a week later)
/// - offsets: "3d", "+3", "+3d", "2w", "in 3 days", "in 2 weeks"
/// - month and day: "nov 18", "18 nov", "nov18", "november 18, 2027"
/// - numbers: "11/18" (month first unless the locale puts the day first), "11/18/2027", "2026-11-18"
/// - a bare day: "18" (the next 18th)
/// Dates without a year that already passed this year mean next year.
enum TaskDateParser {
    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> Date? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        guard !raw.isEmpty else { return nil }
        let words = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let today = calendar.startOfDay(for: now)
        func add(_ component: Calendar.Component, _ value: Int) -> Date? {
            calendar.date(byAdding: component, value: value, to: today).map { calendar.startOfDay(for: $0) }
        }

        switch raw {
        case "today", "tod", "now": return today
        case "tomorrow", "tmr", "tmrw", "tom": return add(.day, 1)
        case "next week", "nextweek", "nw": return DuePreset.nextWeek.date(now: now, calendar: calendar)
        default: break
        }

        // Weekdays
        var weekdayWords = words
        var weeksLater = 0
        if weekdayWords.first == "next", weekdayWords.count == 2 {
            weekdayWords.removeFirst()
            weeksLater = 1
        }
        if weekdayWords.count == 1, let weekday = weekday(weekdayWords[0]) {
            let current = calendar.component(.weekday, from: today)
            var days = (weekday - current + 7) % 7
            if days == 0 { days = 7 }
            return add(.day, days + weeksLater * 7)
        }

        // Offsets
        if let offset = offset(words) {
            return add(offset.component, offset.value)
        }

        // ISO 2026-11-18
        if let match = raw.firstMatch(#"^(\d{4})-(\d{1,2})-(\d{1,2})$"#) {
            return date(year: match[0], month: match[1], day: match[2], calendar: calendar)
        }

        // 11/18 or 11/18/2027 (or 18/11 when the locale puts the day first)
        if let match = raw.firstMatch(#"^(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?$"#) {
            let dayFirst = (DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "M/d")
                .first { $0 == "d" || $0 == "M" } == "d"
            let month = dayFirst ? match[1] : match[0]
            let day = dayFirst ? match[0] : match[1]
            if match.count > 2, var year = match[2] {
                if year < 100 { year += 2000 }
                return date(year: year, month: month, day: day, calendar: calendar)
            }
            return upcoming(month: month, day: day, today: today, calendar: calendar)
        }

        // Month names: "nov 18", "18 nov", "nov18", "18nov", optional year
        let spaced = raw.replacingOccurrences(of: #"(\d)(st|nd|rd|th)\b"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([a-z])(\d)"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"(\d)([a-z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "-", with: " ")
        let parts = spaced.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count == 2 || parts.count == 3 {
            var month: Int?
            var day: Int?
            if let m = self.month(parts[0]), let d = Int(parts[1].trimmingSuffixes()) {
                month = m
                day = d
            } else if let d = Int(parts[0].trimmingSuffixes()), let m = self.month(parts[1]) {
                month = m
                day = d
            }
            if let month, let day {
                if parts.count == 3 {
                    guard let year = Int(parts[2]) else { return nil }
                    return date(year: year < 100 ? year + 2000 : year, month: month, day: day, calendar: calendar)
                }
                return upcoming(month: month, day: day, today: today, calendar: calendar)
            }
        }

        // A bare day of the month: the next one
        if words.count == 1, let day = Int(words[0].trimmingSuffixes()), (1...31).contains(day) {
            var comps = calendar.dateComponents([.year, .month], from: today)
            for _ in 0..<3 {
                comps.day = day
                if let candidate = calendar.date(from: comps),
                   calendar.component(.day, from: candidate) == day, candidate >= today {
                    return candidate
                }
                comps.day = 1
                guard let first = calendar.date(from: comps), let next = calendar.date(byAdding: .month, value: 1, to: first) else { break }
                comps = calendar.dateComponents([.year, .month], from: next)
            }
        }
        return nil
    }

    private static func weekday(_ word: String) -> Int? {
        let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        let full = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let i = full.firstIndex(of: word) { return i + 1 }
        guard word.count >= 3, let i = names.firstIndex(where: { word.hasPrefix($0) }),
              full[i].hasPrefix(word) else { return nil }
        return i + 1
    }

    private static func month(_ word: String) -> Int? {
        let full = ["january", "february", "march", "april", "may", "june", "july", "august",
                    "september", "october", "november", "december"]
        guard word.count >= 3 else { return nil }
        if word == "sept" { return 9 }
        return full.firstIndex { $0.hasPrefix(word) }.map { $0 + 1 }
    }

    private static func offset(_ words: [String]) -> (component: Calendar.Component, value: Int)? {
        var words = words
        let saysIn = words.first == "in" && words.count > 1
        if saysIn { words.removeFirst() }
        let joined = words.joined(separator: " ")
        guard let match = joined.firstMatch(#"^\+?\s*(\d{1,3})\s*(d|day|days|w|wk|wks|week|weeks)?$"#) else { return nil }
        guard let value = match[0] else { return nil }
        // A bare number without "+" or "in" is a day of the month, not an offset
        let hasUnit = joined.rangeOfCharacter(from: .letters) != nil
        guard hasUnit || saysIn || joined.hasPrefix("+") else { return nil }
        return joined.contains("w") ? (.day, value * 7) : (.day, value)
    }

    private static func date(year: Int?, month: Int?, day: Int?, calendar: Calendar) -> Date? {
        guard let year, let month, let day, (1...12).contains(month), (1...31).contains(day) else { return nil }
        let comps = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: comps), calendar.component(.day, from: date) == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// This year's date, or next year's when it already passed.
    private static func upcoming(month: Int?, day: Int?, today: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: today)
        guard let date = date(year: year, month: month, day: day, calendar: calendar) else { return nil }
        return date < today ? self.date(year: year + 1, month: month, day: day, calendar: calendar) : date
    }
}

private extension String {
    /// Capture groups of the first match as Ints (nil for groups that didn't take part).
    func firstMatch(_ pattern: String) -> [Int?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = self as NSString
        guard let match = regex.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<match.numberOfRanges).map { i in
            let range = match.range(at: i)
            return range.location == NSNotFound ? nil : Int(ns.substring(with: range))
        }
    }

    /// "18th" -> "18"
    func trimmingSuffixes() -> String {
        for suffix in ["st", "nd", "rd", "th"] where hasSuffix(suffix) && count > suffix.count {
            return String(dropLast(suffix.count))
        }
        return self
    }
}

// MARK: - Quick add tokens

/// What a one-line New task box understood (the menu bar search, the global box, the List's
/// field): the title plus any tokens. It reads the same words as the composer (ComposerInput):
/// - `!high` `!med` `!low` (also `!h` `!m` `!l`, `!1`–`!3`): priority
/// - `@beta` or `@"beta launch"`: milestone (matched by name in the target project)
/// - `+atlas` or `+"side project"`: project (the task goes there, and it becomes the remembered one)
/// - `#now` `#next` `#backlog`: sprint
/// - `*review` or `*"in review"`: status (matched by name in the target project's workflow)
/// - `%bug` or `%"needs review"`: label (several allowed; a name that doesn't exist is created)
/// - `due:fri`, `due:nov18`, `due:"nov 18"`, `today`, `tomorrow`: due date
/// - `~90m`, `2h`, `1h30m`: expected time
/// Unrecognised tokens stay in the title, so nothing typed is lost.
struct QuickAddInput: Equatable, Sendable {
    var title: String
    var priority: TaskPriority?
    var milestoneQuery: String?
    var dueDate: Date?
    var expectedMinutes: Int?
    var projectQuery: String?
    var slot: SprintSlot?
    /// The word that set `slot` as typed ("#next"), to put back for a project without sprints
    var slotWord: String?
    var statusQuery: String?
    /// Every %label word, as typed (without the %)
    var labelQueries: [String] = []

    var hasTokens: Bool {
        priority != nil || milestoneQuery != nil || dueDate != nil || expectedMinutes != nil
            || projectQuery != nil || slot != nil || statusQuery != nil || !labelQueries.isEmpty
    }

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> QuickAddInput {
        var result = QuickAddInput(title: "")
        var kept: [String] = []
        for word in ComposerInput.words(text) {
            switch ComposerInput.token(word, now: now, calendar: calendar) {
            case let .priority(priority)?: result.priority = priority
            case let .milestone(name)?: result.milestoneQuery = name
            case let .due(date)?: result.dueDate = date
            case let .minutes(minutes)?: result.expectedMinutes = minutes
            case let .project(name)?: result.projectQuery = name
            case let .slot(slot)?:
                result.slot = slot
                result.slotWord = word
            case let .status(name)?: result.statusQuery = name
            case let .label(name)?: result.labelQueries.append(name)
            case nil: kept.append(word)
            }
        }
        result.title = kept.joined(separator: " ")
        return result
    }
}
