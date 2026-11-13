import Foundation
import SwiftData

/// Ties an item in an integration (an Apple Calendar event, a reminder…) to what the engine made
/// of it: a linked internal event or task. Lets the reconciler tell new / changed / removed apart.
///
/// CloudKit-compatible (ADR 0001): defaulted scalars, no unique constraint (deduped in code).
@Model
public final class ExternalLink {
    public var provider: String = ""
    /// Stable identity in the provider (survives edits; same on every device).
    public var externalID: String = ""
    /// The calendar / list the item lives in.
    public var sourceID: String = ""
    /// Fingerprint of the fields Emo mirrors; a different hash means the item changed.
    public var contentHash: String = ""
    public var lastSeenAt: Date = Date()
    /// The internal `CalendarEvent` this item became (calendar integrations).
    public var eventID: UUID?
    /// The `TaskItem` this item became (task integrations such as Reminders).
    public var taskID: UUID?

    init(provider: String, externalID: String, sourceID: String, contentHash: String, now: Date) {
        self.provider = provider
        self.externalID = externalID
        self.sourceID = sourceID
        self.contentHash = contentHash
        self.lastSeenAt = now
    }
}
