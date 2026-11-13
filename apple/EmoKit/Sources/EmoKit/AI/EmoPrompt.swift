import Foundation

/// The system-prompt fragment every AI call starts with: how the user's lists work and the
/// reminder-notes syntax. This is the single source of truth for that syntax; `ReminderNotes`
/// parses it, and the tests parse every example below so the two can't drift apart.
public enum EmoPrompt {
    /// Notes written in the syntax, shown to the AI. Each must parse to at least one keyed field.
    public static let notesExamples = [
        "ongoing: 3x/week 1h\npart of: Job hunt\ncontext: product design roles, Milan; use CV v3",
        "when: today\nCall before 6pm, they close early.",
        "part of: Kitchen renovation\nwhen: week",
        "ongoing",
    ]

    public static let base = """
        You help the user plan their time with Emo, a day planner. Their tasks come from lists in a \
        Next Action / Someday-Maybe system. A list is named "ROLE - Area" (e.g. "NA - Home", \
        "SOMEDAY - Personal"). Roles: NA (next action: committed, actionable work), CHECKLIST DAILY \
        (small daily routines), INBOX (captured, not yet processed), WAITING (blocked on someone \
        else), PROJECTS (multi-step outcomes, not single actions), SOMEDAY (worth remembering, not \
        committed), SHOPPING, IDEAS. Only NA and daily checklist tasks are ever scheduled. The Area \
        is the part of life a list covers.

        A task's notes may start with keyed lines, one "key: value" per line, lowercase keys:
        - ongoing: doing it doesn't finish it; optional sessions and length, e.g. "3x/week 1h", "2x/week 45m"; a bare "ongoing" uses defaults
        - part of: the parent or section the task sits under, a short name
        - context: one short line the planner needs to size or understand the task
        - when: the user's goal for it: "today" or "week"
        Examples:
        \(notesExamples.map { "---\n" + $0 }.joined(separator: "\n"))
        ---
        Every other line in the notes is the user's own text: read it, never rewrite it. Never use \
        "#" in notes (Reminders turns it into a tag Emo can't see). When suggesting changes to a \
        task's notes, change only keyed lines, and as few as possible.
        """

    /// One task as the AI sees it: `title · role/area · part of · context · notes`.
    public static func render(_ task: TaskItem) -> String {
        let notes = task.parsedNotes
        var parts = [task.name]
        if let role = task.listRole {
            parts.append([role.rawValue, task.listArea].compactMap { $0 }.joined(separator: "/"))
        } else if let area = task.listArea {
            parts.append(area)
        }
        if let partOf = notes.partOf { parts.append("part of: \(partOf)") }
        if let context = notes.context { parts.append("context: \(context)") }
        if let when = notes.when { parts.append("when: \(when.rawValue)") }
        if let ongoing = notes.ongoing {
            parts.append(ongoing.formatted.isEmpty ? "ongoing" : "ongoing: \(ongoing.formatted)")
        }
        if !notes.freeText.isEmpty {
            parts.append("notes: " + notes.freeText.replacingOccurrences(of: "\n", with: " / "))
        }
        return parts.joined(separator: " · ")
    }
}
