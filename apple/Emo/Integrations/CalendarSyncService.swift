import EmoKit
import EventKit
import Observation
import SwiftData
import SwiftUI

/// Keeps the internal calendar in step with Calendar.app: on launch, when Calendar.app changes
/// (debounced), when the app becomes active, and on demand. Settings are per Mac, because
/// EventKit calendar identifiers are device-specific.
@MainActor
@Observable
final class CalendarSyncService {
    private enum Key {
        static let enabled = "integrations.appleCalendar.enabled"
        /// Set once the user (or the first load) has chosen which calendars to use, so an empty
        /// selection afterwards means "none", not "not chosen yet".
        static let chosen = "integrations.appleCalendar.chosen"
        static let writeBack = "integrations.appleCalendar.writeBack"
        static let emoCalendarID = "integrations.appleCalendar.emoCalendarID"
        static let calendars = "integrations.appleCalendar.calendars"
    }

    private(set) var isEnabled: Bool
    private(set) var selectedCalendars: Set<String>
    private(set) var calendars: [AppleCalendarSource.CalendarInfo] = []
    private(set) var hasAccess = AppleCalendarSource.hasAccess
    private(set) var accessDenied = AppleCalendarSource.accessDenied
    private(set) var lastSync: Date?
    private(set) var lastResult: CalendarReconciler.Result?
    private(set) var errorMessage: String?
    /// Mirror Emo's planned blocks into an "Emo" calendar in Calendar.app.
    private(set) var isWriteBackEnabled: Bool

    private let source = AppleCalendarSource()
    private let context: ModelContext
    private let defaults: UserDefaults
    private var debounce: Task<Void, Never>?
    /// `EKEventStore.authorizationStatus` can keep reporting the pre-grant status until the app
    /// relaunches (seen with Reminders), so a grant from our own request is remembered here.
    private var grantedThisSession = false

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.enabled)
        isWriteBackEnabled = defaults.bool(forKey: Key.writeBack)
        selectedCalendars = Set(defaults.stringArray(forKey: Key.calendars) ?? [])
        // Re-mirror after the plan changes (debounced: a re-plan saves several times).
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleWriteBack() }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: source.store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync() }
        }
        if isEnabled { Task { await ensureAccess() } }
    }

    /// When the integration is on but macOS hasn't decided on access (first run, or a rebuilt
    /// ad-hoc-signed app, which macOS treats as a new app), ask again rather than sit idle.
    func ensureAccess() async {
        guard isEnabled else { return }
        if !grantedThisSession, EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            await setEnabled(true)
        } else {
            reloadCalendars()
            sync()
        }
    }

    /// Turns the integration on (asking for access) or off (removing everything it imported).
    func setEnabled(_ on: Bool) async {
        if on {
            do {
                hasAccess = try await source.requestAccess()
                grantedThisSession = hasAccess
            } catch {
                errorMessage = error.localizedDescription
            }
            accessDenied = AppleCalendarSource.accessDenied
            guard hasAccess else { return }
            isEnabled = true
            defaults.set(true, forKey: Key.enabled)
            source.store.reset()   // a store created before access was granted can list nothing
            reloadCalendars()
            sync()
        } else {
            isEnabled = false
            defaults.set(false, forKey: Key.enabled)
            run { try CalendarReconciler(context: context).removeAll(provider: AppleCalendarSource.provider) }
        }
    }

    func setSelected(_ ids: Set<String>) {
        selectedCalendars = ids
        defaults.set(true, forKey: Key.chosen)
        defaults.set(Array(ids), forKey: Key.calendars)
        guard isEnabled else { return }
        run { try CalendarReconciler(context: context).removeAll(provider: AppleCalendarSource.provider, keeping: ids) }
        sync()
    }

    func toggle(_ id: String) {
        var ids = selectedCalendars
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        setSelected(ids)
    }

    func reloadCalendars() {
        hasAccess = grantedThisSession || AppleCalendarSource.hasAccess
        accessDenied = !hasAccess && AppleCalendarSource.accessDenied
        // Emo's own write-back calendar is never imported: that would read our plan back as meetings.
        let emoID = defaults.string(forKey: Key.emoCalendarID)
        calendars = hasAccess ? source.calendars().filter { $0.id != emoID } : []
        // Start with every calendar the first time any are visible; the user can narrow it.
        if isEnabled, !calendars.isEmpty, !defaults.bool(forKey: Key.chosen) {
            setSelected(Set(calendars.map(\.id)))
        }
    }

    /// Pulls a fresh snapshot of the next 14 days and reconciles it.
    func sync() {
        guard isEnabled, hasAccess else { return }
        var selected = selectedCalendars
        if let emoID = defaults.string(forKey: Key.emoCalendarID) { selected.remove(emoID) }
        let snapshot = source.snapshot(selected: selected, from: .today())
        run { try CalendarReconciler(context: context).apply(snapshot) }
    }

    // MARK: Write-back

    /// Turns mirroring on (creating the Emo calendar) or off (optionally deleting it and its events).
    func setWriteBack(_ on: Bool, removeExisting: Bool = true) async {
        if on {
            if !hasAccess {
                do { hasAccess = try await source.requestAccess(); grantedThisSession = hasAccess } catch { errorMessage = error.localizedDescription }
            }
            guard hasAccess else { return }
            isWriteBackEnabled = true
            defaults.set(true, forKey: Key.writeBack)
            writeBack()
        } else {
            isWriteBackEnabled = false
            defaults.set(false, forKey: Key.writeBack)
            guard removeExisting else { return }
            do {
                try AppleCalendarWriter(store: source.store).removeCalendar(knownID: defaults.string(forKey: Key.emoCalendarID))
                try CalendarWriteBack(context: context).forgetAll()
                defaults.removeObject(forKey: Key.emoCalendarID)
            } catch {
                errorMessage = "Couldn't remove the Emo calendar: \(error.localizedDescription)"
            }
        }
    }

    private var writeBackDebounce: Task<Void, Never>?

    private func scheduleWriteBack() {
        guard isWriteBackEnabled else { return }
        writeBackDebounce?.cancel()
        writeBackDebounce = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            writeBack()
        }
    }

    /// Mirrors the next 14 days of planned blocks into the Emo calendar.
    func writeBack() {
        guard isWriteBackEnabled, hasAccess else { return }
        let today = LocalDay.today()
        let window = DateInterval(start: today.start(), end: today.adding(days: 14).start())
        do {
            let writer = AppleCalendarWriter(store: source.store)
            let cal = try writer.emoCalendar(knownID: defaults.string(forKey: Key.emoCalendarID))
            if defaults.string(forKey: Key.emoCalendarID) != cal.calendarIdentifier {
                // New or recreated calendar: anything recorded before refers to events that are gone.
                try CalendarWriteBack(context: context).forgetAll()
                defaults.set(cal.calendarIdentifier, forKey: Key.emoCalendarID)
                selectedCalendars.remove(cal.calendarIdentifier)
            }
            let planner = CalendarWriteBack(context: context)
            let ops = try planner.operations(desired: try planner.desiredEvents(from: today), window: window)
            guard !ops.isEmpty else { return }
            for (op, externalID) in try writer.apply(ops, in: cal) {
                try planner.record(op, externalID: externalID)
            }
        } catch {
            errorMessage = "Couldn't update the Emo calendar: \(error.localizedDescription)"
        }
    }

    /// Calendar.app can post several change notifications in a burst; sync once after it settles.
    private func scheduleSync() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            reloadCalendars()
            sync()
        }
    }

    private func run(_ work: () throws -> CalendarReconciler.Result) {
        do {
            lastResult = try work()
            lastSync = .now
            errorMessage = nil
        } catch {
            errorMessage = "Calendar sync failed: \(error.localizedDescription)"
        }
    }
}
