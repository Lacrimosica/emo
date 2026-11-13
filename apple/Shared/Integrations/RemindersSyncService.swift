import EmoKit
import EventKit
import Observation
import SwiftData
import SwiftUI

/// Keeps the backlog in step with Reminders.app (launch, changes, activation, on demand).
/// Per-Mac settings, like `CalendarSyncService`.
@MainActor
@Observable
final class RemindersSyncService {
    private enum Key {
        static let enabled = "integrations.appleReminders.enabled"
        /// Set once the user (or the first load) has chosen which lists to use, so an empty
        /// selection afterwards means "none", not "not chosen yet".
        static let chosen = "integrations.appleReminders.chosen"
        static let lists = "integrations.appleReminders.lists"
    }

    private(set) var isEnabled: Bool
    private(set) var selectedLists: Set<String>
    private(set) var lists: [AppleCalendarSource.CalendarInfo] = []
    private(set) var hasAccess = AppleRemindersSource.hasAccess
    private(set) var accessDenied = AppleRemindersSource.accessDenied
    private(set) var lastSync: Date?
    private(set) var lastResult: ReminderReconciler.Result?
    private(set) var errorMessage: String?

    private let source = AppleRemindersSource()
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
        selectedLists = Set(defaults.stringArray(forKey: Key.lists) ?? [])
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: source.store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync() }
        }
        if isEnabled { Task { await ensureAccess() } }
    }

    /// When the integration is on but macOS hasn't decided on access (first run, or a rebuilt
    /// ad-hoc-signed app, which macOS treats as a new app), ask again rather than sit idle.
    func ensureAccess() async {
        guard isEnabled else { return }
        if !grantedThisSession, EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            await setEnabled(true)
        } else {
            reloadLists()
            sync()
        }
    }

    func setEnabled(_ on: Bool) async {
        if on {
            do {
                hasAccess = try await source.requestAccess()
                grantedThisSession = hasAccess
            } catch {
                errorMessage = error.localizedDescription
            }
            accessDenied = AppleRemindersSource.accessDenied
            guard hasAccess else { return }
            isEnabled = true
            defaults.set(true, forKey: Key.enabled)
            source.store.reset()
            reloadLists()
            sync()
        } else {
            isEnabled = false
            defaults.set(false, forKey: Key.enabled)
            run { try ReminderReconciler(context: context).removeAll(provider: AppleRemindersSource.provider) }
        }
    }

    func toggle(_ id: String) {
        var ids = selectedLists
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        setSelected(ids)
    }

    func setSelected(_ ids: Set<String>) {
        selectedLists = ids
        defaults.set(true, forKey: Key.chosen)
        defaults.set(Array(ids), forKey: Key.lists)
        guard isEnabled else { return }
        run { try ReminderReconciler(context: context).removeAll(provider: AppleRemindersSource.provider, keeping: ids) }
        sync()
    }

    func reloadLists() {
        hasAccess = grantedThisSession || AppleRemindersSource.hasAccess
        accessDenied = !hasAccess && AppleRemindersSource.accessDenied
        lists = hasAccess ? source.lists() : []
        if isEnabled, !lists.isEmpty, !defaults.bool(forKey: Key.chosen) {
            setSelected(Set(lists.map(\.id)))
        }
    }

    func sync() {
        guard isEnabled, hasAccess else { return }
        let selected = selectedLists
        Task {
            let snapshot = await source.snapshot(selected: selected)
            run { try ReminderReconciler(context: context).apply(snapshot) }
        }
    }

    private func scheduleSync() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            reloadLists()
            sync()
        }
    }

    private func run(_ work: () throws -> ReminderReconciler.Result) {
        do {
            lastResult = try work()
            lastSync = .now
            errorMessage = nil
        } catch {
            errorMessage = "Reminders sync failed: \(error.localizedDescription)"
        }
    }
}
