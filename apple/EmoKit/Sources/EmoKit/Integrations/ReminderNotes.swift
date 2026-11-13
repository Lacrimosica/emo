import Foundation

/// The context Emo reads from (and later writes to) a reminder's notes.
///
/// EventKit loses a reminder's indentation, sections and tags, so the user (or Emo, with approval)
/// carries that context as `key: value` lines in the notes. A line is a keyed line when its key is
/// one of `Key` (case, spacing and hyphens don't matter); every other line, including unknown keys
/// and `#tag` lines, is the user's own text and is never changed.
///
/// The syntax is described for the AI in `EmoPrompt.base`, which is the authority; keep the two in
/// step (the tests parse every example in the prompt).
public struct ReminderNotes: Equatable, Sendable {
    public enum Key: String, CaseIterable, Sendable {
        case ongoing
        case partOf = "part of"
        case context
        case when

        /// How the key is matched: lowercased, with spaces, hyphens and underscores removed.
        fileprivate var normalized: String { Key.normalize(rawValue) }

        fileprivate static func normalize(_ raw: some StringProtocol) -> String {
            String(raw.lowercased().filter { !" \t-_".contains($0) })
        }

        fileprivate init?(matching raw: some StringProtocol) {
            let n = Key.normalize(raw)
            guard let key = Key.allCases.first(where: { $0.normalized == n }) else { return nil }
            self = key
        }
    }

    /// The user's TODAY / THIS WEEK goal for the reminder (ticket 22).
    public enum When: String, Equatable, Sendable {
        case today
        case week
    }

    /// Work that doing doesn't finish (ticket 31), with an optional weekly target.
    public struct Ongoing: Equatable, Sendable {
        public var sessionsPerWeek: Int?
        public var sessionMinutes: Int?

        public init(sessionsPerWeek: Int? = nil, sessionMinutes: Int? = nil) {
            self.sessionsPerWeek = sessionsPerWeek
            self.sessionMinutes = sessionMinutes
        }

        /// Canonical value for an `ongoing:` line, e.g. "3x/week 1h", "2x/week 45m" or "".
        public var formatted: String {
            var parts: [String] = []
            if let n = sessionsPerWeek { parts.append("\(n)x/week") }
            if let m = sessionMinutes {
                parts.append(m % 60 == 0 ? "\(m / 60)h" : m > 60 && m % 30 == 0 ? "\(Double(m) / 60)h" : "\(m)m")
            }
            return parts.joined(separator: " ")
        }
    }

    /// The notes exactly as they were read.
    public let raw: String
    /// Value of each keyed line (the first one, if a key appears twice), trimmed.
    public let fields: [Key: String]
    /// Every line that isn't a keyed line, with leading and trailing blank lines dropped.
    public let freeText: String

    public init(_ raw: String) {
        self.raw = raw
        var fields: [Key: String] = [:]
        var free: [Substring] = []
        for line in Self.lines(raw) {
            if let (key, value) = Self.keyedLine(line.text) {
                if fields[key] == nil { fields[key] = value }
            } else {
                free.append(line.text)
            }
        }
        self.fields = fields
        self.freeText = free
            .drop(while: { $0.allSatisfy(\.isWhitespace) })
            .reversed().drop(while: { $0.allSatisfy(\.isWhitespace) }).reversed()
            .joined(separator: "\n")
    }

    public static func parse(_ raw: String) -> ReminderNotes { ReminderNotes(raw) }

    // MARK: Typed fields

    public var partOf: String? { nonEmpty(.partOf) }
    public var context: String? { nonEmpty(.context) }

    public var when: When? {
        guard let value = fields[.when]?.lowercased() else { return nil }
        if value.contains("today") { return .today }
        if value.contains("week") { return .week }
        return nil
    }

    /// Set when there's an `ongoing:` line, even a bare one (defaults apply).
    public var ongoing: Ongoing? {
        guard let value = fields[.ongoing] else { return nil }
        return Self.parseOngoing(value)
    }

    public var isEmpty: Bool { raw.allSatisfy(\.isWhitespace) }

    private func nonEmpty(_ key: Key) -> String? {
        guard let value = fields[key], !value.isEmpty else { return nil }
        return value
    }

    // MARK: Writing

    /// The notes with `changes` applied to keyed lines only: a value replaces that key's line in
    /// place (or is added at the top, after any keyed lines already there), nil removes it. Every
    /// other line is kept byte for byte.
    public func merging(_ changes: [Key: String?]) -> String {
        var lines = raw.isEmpty ? [] : Self.lines(raw)
        // New lines use the notes' own line ending.
        let newline = lines.first(where: { !$0.ending.isEmpty })?.ending ?? "\n"
        // Apply in a fixed order so the result doesn't depend on dictionary order.
        for key in Key.allCases {
            guard let change = changes[key] else { continue }
            let indices = lines.indices.filter { Self.keyedLine(lines[$0].text)?.key == key }
            let text = change.map { "\(key.rawValue): \($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
            if let first = indices.first {
                for index in indices.dropFirst().reversed() { Self.remove(at: index, from: &lines) }
                if let text { lines[first].text = Substring(text) } else { Self.remove(at: first, from: &lines) }
            } else if let text {
                let top = lines.prefix(while: { Self.keyedLine($0.text) != nil }).count
                lines.insert(Line(text: Substring(text), ending: top < lines.count ? newline : ""), at: top)
                // Inserted after what used to be the last line: that line now needs an ending.
                if top == lines.count - 1, top > 0, lines[top - 1].ending.isEmpty { lines[top - 1].ending = newline }
            }
        }
        return lines.map { String($0.text) + $0.ending }.joined()
    }

    /// Removes a line; if it was the last one, the line before it becomes last (no ending).
    private static func remove(at index: Int, from lines: inout [Line]) {
        let wasLast = index == lines.count - 1
        lines.remove(at: index)
        if wasLast, let last = lines.indices.last { lines[last].ending = "" }
    }

    // MARK: Parsing

    /// One line of the notes and the line ending after it ("\n", "\r\n", "\r", or "" for the last).
    private struct Line {
        var text: Substring
        var ending: String
    }

    /// Splits on any line ending, remembering each one so the notes can be rebuilt byte for byte.
    /// (In Swift "\r\n" is a single Character, so splitting on "\n" alone would miss it.)
    private static func lines(_ raw: String) -> [Line] {
        var result: [Line] = []
        var start = raw.startIndex
        var index = raw.startIndex
        while index < raw.endIndex {
            let c = raw[index]
            if c == "\n" || c == "\r\n" || c == "\r" {
                result.append(Line(text: raw[start..<index], ending: String(c)))
                start = raw.index(after: index)
            }
            index = raw.index(after: index)
        }
        result.append(Line(text: raw[start...], ending: ""))
        return result
    }

    /// `key: value`, where the key is a known `Key`. The value may be empty. A line that is just
    /// `ongoing` counts too (ongoing with default sessions).
    private static func keyedLine(_ line: Substring) -> (key: Key, value: String)? {
        if line.trimmingCharacters(in: .whitespaces).lowercased() == Key.ongoing.rawValue { return (.ongoing, "") }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let rawKey = line[..<colon]
        guard rawKey.count <= 12, rawKey.allSatisfy({ $0.isLetter || " \t-_".contains($0) }),
              let key = Key(matching: rawKey) else { return nil }
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (key, value)
    }

    /// Tolerant: "3x/week 1h", "3/week", "3x a week", "3 times a week", "x3", "45m", "1.5h", "1h30".
    static func parseOngoing(_ value: String) -> Ongoing {
        let text = value.lowercased()
        var result = Ongoing()

        // Session length: a number followed by h/hr/hour or m/min, optionally "1h30".
        if let match = text.firstMatch(of: /(\d+(?:[.,]\d+)?)\s*(?:hours?|hrs?|h)(?![a-z])\s*(\d+)?\s*(?:m|min|mins|minutes?)?/) {
            let hours = Double(match.1.replacingOccurrences(of: ",", with: ".")) ?? 0
            let extra = match.2.flatMap { Int($0) } ?? 0
            result.sessionMinutes = Int((hours * 60).rounded()) + extra
        } else if let match = text.firstMatch(of: /(\d+)\s*(?:minutes?|mins?|m)(?![a-z])/) {
            result.sessionMinutes = Int(match.1)
        }

        // Sessions per week: "3x", "x3", "3/week", "3 times", "3 a week".
        if let match = text.firstMatch(of: /(\d+)\s*(?:x|×|times?)\b|(?:x|×)\s*(\d+)\b|(\d+)\s*(?:\/|per|a|each)\s*(?:week|wk|w)\b/) {
            result.sessionsPerWeek = (match.1 ?? match.2 ?? match.3).flatMap { Int($0) }
        }
        if let n = result.sessionsPerWeek, !(1...21).contains(n) { result.sessionsPerWeek = nil }
        if let m = result.sessionMinutes, !(5...600).contains(m) { result.sessionMinutes = nil }
        return result
    }
}
