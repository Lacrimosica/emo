import Foundation

/// What a task list is for, in a Next-Action / Someday-Maybe system
/// (scotthyoung.com/blog/2024/11/29/productivity-end/). Only committed work is scheduled;
/// everything else is remembered but kept off the calendar.
public enum ListRole: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Captured but not yet processed into a real action.
    case inbox
    /// Small recurring checklist items (e.g. "CHECKLIST DAILY").
    case routine
    /// Committed, actionable work.
    case nextAction = "next_action"
    /// Blocked on someone else.
    case waiting
    /// A multi-step outcome, not a single action.
    case project
    /// Worth remembering, not committed to.
    case someday
    /// Things to buy (groceries, by store).
    case shopping
    /// Reference only.
    case idea

    public var id: String { rawValue }

    /// Whether the auto-scheduler may put tasks from this list on the calendar.
    public var isSchedulable: Bool { self == .nextAction || self == .routine }
}

/// A list's role plus the area of life it covers ("NA - Home" → next action, area "Home").
public struct ListAssignment: Equatable, Sendable {
    public var role: ListRole
    public var area: String?

    public init(role: ListRole, area: String? = nil) {
        self.role = role
        self.area = area
    }

    /// Reads a list title written as `ROLE - Area` (or a bare role such as "INBOX", "Ideas").
    /// Role keywords are matched case-insensitively, abbreviations included ("NA" = next action).
    /// A title with no role keyword is treated as a next-action list named after itself, so lists
    /// outside the system keep being scheduled as before.
    public static func infer(fromTitle title: String) -> ListAssignment {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let (prefix, area) = split(trimmed)
        if let role = role(for: prefix) {
            return ListAssignment(role: role, area: area)
        }
        return ListAssignment(role: .nextAction, area: trimmed.isEmpty ? nil : trimmed)
    }

    private static let separators: [Character] = ["-", "–", "—", ":", "·", "|"]

    private static func split(_ title: String) -> (prefix: String, area: String?) {
        guard let index = title.firstIndex(where: separators.contains) else { return (title, nil) }
        let prefix = title[..<index].trimmingCharacters(in: .whitespaces)
        let area = title[title.index(after: index)...].trimmingCharacters(in: .whitespaces)
        return (prefix, area.isEmpty ? nil : area)
    }

    private static func role(for prefix: String) -> ListRole? {
        let p = prefix.uppercased()
        let words = p.split(whereSeparator: { !$0.isLetter }).map(String.init)
        func starts(_ stems: String...) -> Bool { stems.contains { p.hasPrefix($0) } }
        func has(_ stems: String...) -> Bool { words.contains { w in stems.contains { w.hasPrefix($0) } } }

        if ["NA", "N/A", "TODO", "TO DO"].contains(p) || starts("NEXT") { return .nextAction }
        if starts("INBOX") { return .inbox }
        if starts("WAITING") { return .waiting }
        if starts("PROJECT") { return .project }
        if starts("SOMEDAY", "MAYBE") { return .someday }
        if has("GROCER", "SHOPPING") { return .shopping }
        if starts("IDEA") { return .idea }
        if has("CHECKLIST", "DAILY", "ROUTINE", "HABIT") { return .routine }
        return nil
    }
}
