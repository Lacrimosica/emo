import Foundation
import Testing
@testable import EmoKit

@Suite struct ReminderNotesTests {
    @Test func readsKeyedLinesAndKeepsTheRestAsFreeText() {
        let notes = ReminderNotes("""
            ongoing: 3x/week 1h
            part of: Job hunt
            context: product design roles, Milan; use CV v3

            Ask Marta about the portfolio.
            """)
        #expect(notes.partOf == "Job hunt")
        #expect(notes.context == "product design roles, Milan; use CV v3")
        #expect(notes.ongoing == .init(sessionsPerWeek: 3, sessionMinutes: 60))
        #expect(notes.when == nil)
        #expect(notes.freeText == "Ask Marta about the portfolio.")
    }

    @Test func keysAreTolerantOfCaseSpacingAndHyphens() {
        let notes = ReminderNotes("Part  Of :  Kitchen\nWHEN: This week\npart-of: ignored duplicate")
        #expect(notes.partOf == "Kitchen")
        #expect(notes.when == .week)
    }

    @Test func malformedAndUnknownLinesAreFreeText() {
        let raw = "Meeting at 10:30 with Sam\nnot a key line\ncolour: blue\n: empty key\nwhen: someday"
        let notes = ReminderNotes(raw)
        #expect(notes.fields.keys.sorted { $0.rawValue < $1.rawValue } == [.when])
        #expect(notes.when == nil)   // unknown value: ignored, not guessed
        #expect(notes.freeText == "Meeting at 10:30 with Sam\nnot a key line\ncolour: blue\n: empty key")
    }

    @Test func hashLinesAreLeftAsFreeText() {
        let notes = ReminderNotes("#context: not a key\n#jobs")
        #expect(notes.context == nil)
        #expect(notes.freeText == "#context: not a key\n#jobs")
    }

    @Test(arguments: [
        ("3x/week 1h", 3, 60), ("3/week", 3, nil), ("3x a week", 3, nil), ("x3", 3, nil),
        ("2 times a week 45m", 2, 45), ("1.5h", nil, 90), ("1h30", nil, 90), ("4x 30 min", 4, 30),
        ("", nil, nil), ("daily-ish", nil, nil),
    ] as [(String, Int?, Int?)])
    func ongoingValuesAreParsedTolerantly(value: String, sessions: Int?, minutes: Int?) {
        let ongoing = ReminderNotes("ongoing: \(value)").ongoing
        #expect(ongoing == .init(sessionsPerWeek: sessions, sessionMinutes: minutes))
    }

    @Test func bareOngoingMeansDefaults() {
        #expect(ReminderNotes("ongoing").ongoing == .init())
        #expect(ReminderNotes("  Ongoing ").ongoing == .init())
        #expect(ReminderNotes("ongoing:").ongoing == .init())
        #expect(ReminderNotes("ongoing work on the shed").ongoing == nil)   // just a sentence
    }

    @Test func mergingRewritesOnlyKeyedLinesAndKeepsFreeTextByteForByte() {
        let raw = "part of: Job hunt\r\n  indented user text  \n\nwhen: today\n#tag\nlast line "
        let merged = ReminderNotes(raw).merging([.when: "week", .context: "Milan", .partOf: nil])
        #expect(merged == "context: Milan\r\n  indented user text  \n\nwhen: week\n#tag\nlast line ")
    }

    @Test func mergingAddsNewKeysAfterExistingKeyedLinesAtTheTop() {
        let merged = ReminderNotes("part of: Job hunt\nCall Sam").merging([.when: "today"])
        #expect(merged == "part of: Job hunt\nwhen: today\nCall Sam")
        #expect(ReminderNotes("").merging([.when: "today"]) == "when: today")
    }

    @Test func crlfNotesParseLineByLine() {
        let notes = ReminderNotes("part of: Job hunt\r\nwhen: today\r\nCall Sam")
        #expect(notes.partOf == "Job hunt" && notes.when == .today && notes.freeText == "Call Sam")
        #expect(notes.merging([.context: "Milan"]) == "part of: Job hunt\r\nwhen: today\r\ncontext: Milan\r\nCall Sam")
    }

    @Test func removingTheLastLineDropsItsSeparator() {
        #expect(ReminderNotes("Call Sam\nwhen: today").merging([.when: nil]) == "Call Sam")
        #expect(ReminderNotes("when: today").merging([.when: nil]) == "")
        #expect(ReminderNotes("when: today").merging([.context: "x"]) == "when: today\ncontext: x")
    }

    @Test func mergingNothingReturnsTheNotesUnchanged() {
        let raw = "Free text\n\nwhen: today\n"
        #expect(ReminderNotes(raw).merging([:]) == raw)
    }

    @Test func mergingRemovesDuplicateKeyLines() {
        let merged = ReminderNotes("when: today\nx\nwhen: week").merging([.when: "week"])
        #expect(merged == "when: week\nx")
    }

    @Test func ongoingFormatsCanonically() {
        #expect(ReminderNotes.Ongoing(sessionsPerWeek: 3, sessionMinutes: 60).formatted == "3x/week 1h")
        #expect(ReminderNotes.Ongoing(sessionsPerWeek: 2, sessionMinutes: 45).formatted == "2x/week 45m")
        #expect(ReminderNotes.Ongoing(sessionMinutes: 90).formatted == "1.5h")
        #expect(ReminderNotes.Ongoing().formatted == "")
    }
}

@MainActor
@Suite struct EmoPromptTests {
    @Test func everyExampleInThePromptParses() {
        for example in EmoPrompt.notesExamples {
            #expect(!ReminderNotes(example).fields.isEmpty, "\(example)")
        }
        #expect(EmoPrompt.notesExamples.allSatisfy { EmoPrompt.base.contains($0) })
    }

    @Test func promptDescribesEveryKey() {
        for key in ReminderNotes.Key.allCases {
            #expect(EmoPrompt.base.contains("- \(key.rawValue):"), "\(key.rawValue)")
        }
    }

    @Test func rendersATaskWithItsListAndNotes() throws {
        let container = try EmoStore.makeContainer(.inMemory)
        let task = try Backlog(context: container.mainContext).add(TaskDraft(name: "Send CV"))
        task.listRole = .nextAction
        task.listArea = "Personal"
        task.notes = "part of: Job hunt\ncontext: design roles, Milan\nAsk Marta first.\nThen send."
        #expect(EmoPrompt.render(task)
            == "Send CV · next_action/Personal · part of: Job hunt · context: design roles, Milan · notes: Ask Marta first. / Then send.")
        #expect(task.partOf == "Job hunt" && task.notesContext == "design roles, Milan")
    }
}
