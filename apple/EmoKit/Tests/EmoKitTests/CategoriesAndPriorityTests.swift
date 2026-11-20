import Foundation
import SwiftData
import Testing
@testable import EmoKit

@MainActor
@Suite struct CategoriesAndPriorityTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 13)

    var catalog: CategoryCatalog { CategoryCatalog(context: context) }

    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day.start(in: calendar))!
    }

    @discardableResult
    func addTask(_ name: String, hours: Double, cost: EnergyCost = .medium, category: TaskCategory = .personal,
                 priority: TaskPriority = .normal, created: Int = 0) throws -> TaskItem {
        try Backlog(context: context).add(
            TaskDraft(name: name, estimatedHours: hours, energyCost: cost, category: category, priority: priority),
            now: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + created))
        )
    }

    // MARK: Categories

    @Test func builtInsKeepTheirOriginalKeys() {
        #expect(TaskCategory.externalCommitment.key == "external_commitment")
        #expect(TaskCategory.selfCare.key == "self_care")
        #expect(TaskCategory.personal.key == "personal")
        #expect(TaskCategory.leisure.key == "leisure")
    }

    @Test func seedingAddsBuiltInsOnceAndNeverDuplicates() throws {
        try catalog.seedBuiltInsIfNeeded()
        try catalog.seedBuiltInsIfNeeded()
        let all = try catalog.all()
        #expect(all.map(\.key) == TaskCategory.builtIns.map(\.key))
        #expect(all.first { $0.key == "self_care" }?.name == "Self care")
    }

    @Test func addingAndRenamingACategoryKeepsItsTasks() throws {
        try catalog.seedBuiltInsIfNeeded()
        let admin = try catalog.add(name: "  Admin  ", colorHex: "#123456", weeklyHours: 2)
        #expect(admin.name == "Admin")
        #expect(admin.sortIndex == 4)
        let task = try addTask("Tax return", hours: 1, category: admin.taskCategory)

        try catalog.update(admin, name: "Paperwork", colorHex: "#123456", weeklyHours: 3)

        #expect(task.category.key == admin.key)
        #expect(try catalog.all().first { $0.key == admin.key }?.name == "Paperwork")
        #expect(try catalog.weeklyTargets()[admin.key] == 3 * 3600)
    }

    @Test func aCategoryIconCanBeChangedOrKept() throws {
        let gym = try catalog.add(name: "Gym", colorHex: "#00FF00", symbol: "dumbbell")
        try catalog.update(gym, name: "Gym", colorHex: "#00FF00", weeklyHours: 0)
        #expect(gym.symbol == "dumbbell")
        try catalog.update(gym, name: "Gym", colorHex: "#00FF00", weeklyHours: 0, symbol: "figure.walk")
        #expect(gym.symbol == "figure.walk")
    }

    @Test func weeklyTargetIsRoundedAndClamped() throws {
        let big = try catalog.add(name: "Gym", colorHex: "#00FF00", weeklyHours: 100)
        #expect(big.weeklyHours == 40)
        try catalog.update(big, name: "Gym", colorHex: "#00FF00", weeklyHours: 1.3)
        #expect(big.weeklyHours == 1.25)
    }

    @Test func emptyNameIsRejected() throws {
        #expect(throws: CategoryCatalog.CatalogError.emptyName) {
            try catalog.add(name: "   ", colorHex: "#000000")
        }
    }

    @Test func deletingACustomCategoryMovesItsTasksToPersonal() throws {
        try catalog.seedBuiltInsIfNeeded()
        let hobby = try catalog.add(name: "Choir", colorHex: "#ABCDEF")
        let task = try addTask("Rehearsal", hours: 1, category: hobby.taskCategory)

        let moved = try catalog.delete(hobby)

        #expect(moved == 1)
        #expect(task.category == .personal)
        #expect(try catalog.all().count == 4)
    }

    @Test func builtInCategoriesCannotBeDeleted() throws {
        try catalog.seedBuiltInsIfNeeded()
        let selfCare = try #require(try catalog.definition(forKey: "self_care"))
        #expect(throws: CategoryCatalog.CatalogError.builtInCannotBeDeleted) {
            try catalog.delete(selfCare)
        }
    }

    // MARK: Priority and ordering

    @Test func aFirstPriorityTaskBeatsAnEqualOneCreatedEarlier() {
        let earlier = PlannableTask(id: UUID(), remaining: 3600, energyCost: .medium, deadline: nil, createdAt: .distantPast)
        let first = PlannableTask(id: UUID(), remaining: 3600, energyCost: .medium, deadline: nil, createdAt: .now,
                                  priority: .first)
        #expect(DayPlanner.prioritized([earlier, first], now: at(8), dayEnergy: 3).first?.id == first.id)
    }

    @Test func aLaterPriorityTaskGoesAfterANormalOne() {
        let later = PlannableTask(id: UUID(), remaining: 3600, energyCost: .medium, deadline: nil, createdAt: .distantPast,
                                  priority: .later)
        let normal = PlannableTask(id: UUID(), remaining: 3600, energyCost: .medium, deadline: nil, createdAt: .now)
        #expect(DayPlanner.prioritized([later, normal], now: at(8), dayEnergy: 3).first?.id == normal.id)
    }

    @Test func aHighEnergyDayTakesHardTasksFirst() {
        let easy = PlannableTask(id: UUID(), remaining: 3600, energyCost: .low, deadline: nil, createdAt: .distantPast)
        let hard = PlannableTask(id: UUID(), remaining: 3600, energyCost: .high, deadline: nil, createdAt: .now)
        #expect(DayPlanner.prioritized([easy, hard], now: at(8), dayEnergy: 5).first?.id == hard.id)
        #expect(DayPlanner.prioritized([easy, hard], now: at(8), dayEnergy: 1).first?.id == easy.id)
    }

    @Test func aCategoryBehindItsTargetGoesFirst() throws {
        try catalog.seedBuiltInsIfNeeded()
        let selfCare = try #require(try catalog.definition(forKey: "self_care"))
        try catalog.update(selfCare, name: "Self care", colorHex: selfCare.colorHex, weeklyHours: 2)
        try CheckIns(context: context).record(mood: 3, energy: 1, for: day)   // 2h budget: only one task fits
        try addTask("Admin", hours: 2, created: 0)
        try addTask("Stretch", hours: 2, category: .selfCare, created: 1)

        try DayPlanning(context: context, calendar: calendar).plan(day, now: at(7))

        // Stretch is behind its target, so it takes today; Admin spills to tomorrow.
        let today = try context.fetch(FetchDescriptor<CalendarEvent>()).filter { $0.kind == .taskBlock && $0.start < at(12) }
        #expect(today.map(\.title) == ["Stretch"])
        #expect(try CalendarEngine(context: context).events(on: day.adding(days: 1, calendar: calendar), calendar: calendar)
            .filter { $0.kind == .taskBlock }.map(\.title) == ["Admin"])
    }

    @Test func backlogOrderIsPriorityThenDeadlineThenAge() throws {
        let soon = Date(timeIntervalSince1970: 1_800_000_000)
        let later = try addTask("Later one", hours: 1, priority: .later, created: 0)
        let plain = try addTask("Plain", hours: 1, created: 1)
        let dueLate = try addTask("Due late", hours: 1, created: 2)
        dueLate.deadline = soon.addingTimeInterval(86_400 * 9)
        let dueSoon = try addTask("Due soon", hours: 1, created: 3)
        dueSoon.deadline = soon
        let first = try addTask("Do first", hours: 1, priority: .first, created: 4)

        let order = Backlog.displayOrder([later, plain, dueLate, dueSoon, first]).map(\.name)
        #expect(order == ["Do first", "Due soon", "Due late", "Plain", "Later one"])
    }

    @Test func backlogShowsWhenEachTaskIsNextScheduled() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        let report = try addTask("Report", hours: 1)
        let call = try addTask("Call", hours: 1, created: 1)
        call.priority = .later
        try DayPlanning(context: context, calendar: calendar).plan(day, now: at(7))

        let blocks = try context.fetch(FetchDescriptor<CalendarEvent>(sortBy: [SortDescriptor(\.start)]))
            .filter { $0.kind == .taskBlock }
        let starts = TaskSchedule.nextStarts(blocks)
        #expect(starts[report.id] == at(9))
        #expect(starts[call.id] == at(10))
        #expect(TaskSchedule.nextStarts([]).isEmpty)
    }

    // MARK: Keep in one block

    func plan(_ tasks: [PlannableTask], busy: [DateInterval] = [], energy: Int = 5,
              settings: PlannerSettings = .default) -> DayPlan {
        DayPlanner.plan(.init(day: day, calendar: calendar, notBefore: at(8), busy: busy, tasks: tasks,
                              energy: energy, settings: settings))
    }

    @Test func anUnsplittableTaskWaitsForAGapThatHoldsAllOfIt() {
        let meeting = DateInterval(start: at(10), end: at(12))   // free: 9–10, then from 12
        let together = PlannableTask(id: UUID(), remaining: 2 * 3600, energyCost: .medium, deadline: nil,
                                     createdAt: .distantPast, keepTogether: true)
        #expect(plan([together], busy: [meeting]).blocks == [PlannedBlock(taskID: together.id, start: at(12), end: at(14))])

        var split = together
        split.keepTogether = false
        #expect(plan([split], busy: [meeting]).blocks.map(\.start) == [at(9), at(12)])
    }

    @Test func anUnsplittableTaskThatDoesntFitTheBudgetIsLeftWhole() {
        var settings = PlannerSettings.default
        settings.energyBudgetHours[1] = 1
        let together = PlannableTask(id: UUID(), remaining: 2 * 3600, energyCost: .low, deadline: nil,
                                     createdAt: .distantPast, keepTogether: true)
        let result = plan([together], energy: 1, settings: settings)
        #expect(result.blocks.isEmpty)
        #expect(result.overflow.map(\.id) == [together.id])
        let left: [TimeInterval] = result.overflow.map(\.remaining)
        #expect(left == [7200])
    }

    @Test func keepTogetherIsSavedEditedAndCarriedToTheNextOccurrence() throws {
        var draft = TaskDraft(name: "Deep work", estimatedHours: 2, recurrence: .daily)
        draft.keepTogether = true
        let task = try Backlog(context: context).add(draft)
        #expect(task.keepTogether)
        #expect(TaskDraft(task).keepTogether)

        let next = try TaskLifecycle(context: context, calendar: calendar).complete(task, now: at(18))
        #expect(next?.keepTogether == true)

        var off = TaskDraft(try #require(next))
        off.keepTogether = false
        try TaskLifecycle(context: context, calendar: calendar).update(try #require(next), with: off, now: at(18))
        #expect(next?.keepTogether == false)
    }

    // MARK: Plan Week

    @Test func planningAWeekReachesPastTheTwoDayHorizon() throws {
        // Default energy (no check-ins): 5h a day, so each 5h task takes a day of its own.
        let a = try addTask("A", hours: 5, created: 0)
        let b = try addTask("B", hours: 5, created: 1)
        let c = try addTask("C", hours: 5, created: 2)

        let summary = try DayPlanning(context: context, calendar: calendar)
            .plan(from: day, through: day.adding(days: 6, calendar: calendar), now: at(7))

        let engine = CalendarEngine(context: context)
        func dayOf(_ task: TaskItem) throws -> LocalDay? {
            try engine.events(forTask: task.id).first { $0.kind == .taskBlock }.map { LocalDay($0.start, calendar: calendar) }
        }
        #expect(try dayOf(a) == day)
        #expect(try dayOf(b) == day.adding(days: 1, calendar: calendar))
        #expect(try dayOf(c) == day.adding(days: 2, calendar: calendar))
        #expect(summary.planned == 15 * 3600)
        #expect(summary.unplacedTaskNames.isEmpty)
    }

    @Test func planningAWeekNamesWhatStillDoesntFit() throws {
        for i in 0..<9 { try addTask("Task \(i)", hours: 5, created: i) }
        let summary = try DayPlanning(context: context, calendar: calendar)
            .plan(from: day, through: day.adding(days: 6, calendar: calendar), now: at(7))
        // Seven days hold 7 of the 9 tasks; nothing spills into the following week.
        #expect(summary.unplacedTaskNames == ["Task 7", "Task 8"])
        let afterWeek = day.adding(days: 7, calendar: calendar)
        #expect(try CalendarEngine(context: context).events(on: afterWeek, calendar: calendar)
            .allSatisfy { $0.kind != .taskBlock })
    }

    // MARK: Ask Emo

    @Test func askEmoPicksTheUsersOwnCategoriesByName() {
        let options = CategoryOption.builtIns + [CategoryOption(key: "k-admin", name: "Admin")]
        let proposal = { (category: String) in
            ProposedTask(name: "Tax return", estimatedHours: 1, energyCost: "medium", category: category)
        }
        #expect(TaskClarifier.draft(from: proposal("admin"), categories: options)?.category.key == "k-admin")
        #expect(TaskClarifier.draft(from: proposal("Self Care"), categories: options)?.category == .selfCare)
        #expect(TaskClarifier.draft(from: proposal("self_care"), categories: options)?.category == .selfCare)
        #expect(TaskClarifier.draft(from: proposal("Gardening"), categories: options)?.category == .personal)
    }

    @Test func askEmoListsTheCategoriesInItsInstructions() {
        let list = TaskClarifier.categoryList(CategoryOption.builtIns + [CategoryOption(key: "k", name: "Choir")])
        #expect(list.contains("- Self care (exercise, rest and health)"))
        #expect(list.contains("- Choir"))
    }

    // MARK: Search

    @Test func searchMatchesEveryWordAcrossNameNotesAndArea() throws {
        let task = try addTask("Rinnovo passaporto", hours: 1)
        task.notes = "context: bring the old photo"
        task.listArea = "Home"
        #expect(task.matches(""))
        #expect(task.matches("PASSAPORTO"))
        #expect(task.matches("photo home"))
        #expect(!task.matches("photo office"))
        let accented = try addTask("Caffè con Luca", hours: 1)
        #expect(accented.matches("caffe"))
    }

    // MARK: Skipping

    @Test func skippingKeepsEveryDayAndUnskipOnlyTheOneDay() throws {
        let task = try addTask("Report", hours: 1)
        let tomorrow = day.adding(days: 1, calendar: calendar)
        task.addSkip(on: day)
        task.addSkip(on: tomorrow)

        #expect(task.isSkipped(on: day) && task.isSkipped(on: tomorrow))
        #expect(!task.isPlannable(on: day) && !task.isPlannable(on: tomorrow))

        task.removeSkip(on: day)
        #expect(!task.isSkipped(on: day) && task.isSkipped(on: tomorrow))
    }

    @Test func aLegacySingleSkipIsStillHonoured() throws {
        let task = try addTask("Old skip", hours: 1)
        task.skippedDayKey = day.key
        #expect(task.isSkipped(on: day))
        #expect(!task.isSkipped(on: day.adding(days: 1, calendar: calendar)))
    }
}
