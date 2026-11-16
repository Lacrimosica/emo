import Foundation
import SwiftData

/// A short fact about the user's life the assistant should know ("Poli = university",
/// "groceries happen Saturday morning"). Visible and editable in Settings (ticket 21).
///
/// CloudKit-compatible (ADR 0001): defaulted scalars, no relationships or unique constraints.
@Model
public final class MemoryNote {
    public var id: UUID = UUID()
    public var text: String = ""
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    init(text: String, now: Date) {
        self.text = text
        self.createdAt = now
        self.updatedAt = now
    }
}

/// The assistant's memory notes. Only the notes relevant to a conversation are sent to the
/// model, so a cloud provider sees as little as possible.
@MainActor
public struct AIMemory {
    nonisolated public static let maxLength = 160
    /// With this many notes or fewer, all of them are relevant.
    public static let sendAllBelow = 8
    public static let relevantLimit = 8

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func all() throws -> [MemoryNote] {
        try context.fetch(FetchDescriptor<MemoryNote>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    /// Adds a note (trimmed, one line, shortened). Returns nil for an empty or duplicate note.
    @discardableResult
    public func add(_ text: String, now: Date = Date()) throws -> MemoryNote? {
        guard let clean = Self.clean(text) else { return nil }
        if try all().contains(where: { $0.text.caseInsensitiveCompare(clean) == .orderedSame }) { return nil }
        let note = MemoryNote(text: clean, now: now)
        context.insert(note)
        try context.save()
        return note
    }

    public func update(_ note: MemoryNote, text: String, now: Date = Date()) throws {
        guard let clean = Self.clean(text) else { return try delete(note) }
        note.text = clean
        note.updatedAt = now
        try context.save()
    }

    public func delete(_ note: MemoryNote) throws {
        context.delete(note)
        try context.save()
    }

    /// The notes worth sending for a conversation about `text`: all of them while there are few,
    /// otherwise those sharing words with it.
    public func relevant(to text: String) throws -> [String] {
        let notes = try all().map(\.text)
        guard notes.count > Self.sendAllBelow else { return notes }
        let said = Self.words(text)
        return notes
            .map { ($0, Self.words($0).intersection(said).count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(Self.relevantLimit)
            .map(\.0)
    }

    /// The instructions fragment for `notes`, or "" when there are none.
    nonisolated public static func instructions(_ notes: [String]) -> String {
        guard !notes.isEmpty else { return "" }
        return "\n\nWhat you know about the user (use it, don't repeat it back):\n" + notes.map { "- \($0)" }.joined(separator: "\n")
    }

    nonisolated static func clean(_ text: String) -> String? {
        var value = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.count > maxLength { value = String(value.prefix(maxLength)).trimmingCharacters(in: .whitespaces) }
        return value
    }

    nonisolated private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 3 })
    }
}
