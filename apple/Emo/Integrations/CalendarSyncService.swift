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

    private let source = AppleCalendarSource()
    private let context: ModelContext
    private let defaults: UserDefaults
    private var debounce: Task<Void, Never>?

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.enabled)
        selectedCalendars = Set(defaults.stringArray(forKey: Key.calendars) ?? [])
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: source.store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync() }
        }
        if isEnabled, hasAccess { reloadCalendars(); sync() }
    }

    /// Turns the integration on (asking for access) or off (removing everything it imported).
    func setEnabled(_ on: Bool) async {
        if on {
            do {
                hasAccess = try await source.requestAccess()
            } catch {
                errorMessage = error.localizedDescription
            }
            accessDenied = AppleCalendarSource.accessDenied
            guard hasAccess else { return }
            isEnabled = true
            defaults.set(true, forKey: Key.enabled)
            reloadCalendars()
            if selectedCalendars.isEmpty {
                setSelected(Set(calendars.map(\.id)))   // start with everything; the user can narrow it
            } else {
                sync()
            }
        } else {
            isEnabled = false
            defaults.set(false, forKey: Key.enabled)
            run { try CalendarReconciler(context: context).removeAll(provider: AppleCalendarSource.provider) }
        }
    }

    func setSelected(_ ids: Set<String>) {
        selectedCalendars = ids
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
        hasAccess = AppleCalendarSource.hasAccess
        accessDenied = AppleCalendarSource.accessDenied
        calendars = hasAccess ? source.calendars() : []
    }

    /// Pulls a fresh snapshot of the next 14 days and reconciles it.
    func sync() {
        guard isEnabled, AppleCalendarSource.hasAccess else { return }
        let snapshot = source.snapshot(selected: selectedCalendars, from: .today())
        run { try CalendarReconciler(context: context).apply(snapshot) }
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
