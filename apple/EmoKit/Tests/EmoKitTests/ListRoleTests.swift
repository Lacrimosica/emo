import Testing
@testable import EmoKit

@Suite struct ListRoleTests {
    func infer(_ title: String) -> ListAssignment { ListAssignment.infer(fromTitle: title) }

    /// The user's actual Reminders lists.
    @Test(arguments: [
        ("INBOX", ListRole.inbox, nil),
        ("CHECKLIST DAILY", .routine, nil),
        ("NA - Personal", .nextAction, "Personal"),
        ("NA - Home", .nextAction, "Home"),
        ("NA - Poli", .nextAction, "Poli"),
        ("NA - Smolla", .nextAction, "Smolla"),
        ("NA - DEB", .nextAction, "DEB"),
        ("NA - TA", .nextAction, "TA"),
        ("GROCERIES", .shopping, nil),
        ("WAITING", .waiting, nil),
        ("PROJECTS - Personal", .project, "Personal"),
        ("PROJECTS - Home", .project, "Home"),
        ("SOMEDAY - Personal", .someday, "Personal"),
        ("SOMEDAY - Home", .someday, "Home"),
        ("Ideas", .idea, nil),
    ] as [(String, ListRole, String?)])
    func readsTheUsersLists(title: String, role: ListRole, area: String?) {
        #expect(infer(title) == ListAssignment(role: role, area: area))
    }

    @Test func spelledOutAndPunctuatedVariants() {
        #expect(infer("Next Actions – Work") == ListAssignment(role: .nextAction, area: "Work"))
        #expect(infer("someday/maybe: home") == ListAssignment(role: .someday, area: "home"))
        #expect(infer("Waiting For") == ListAssignment(role: .waiting))
        #expect(infer("Groceries - Lidl") == ListAssignment(role: .shopping, area: "Lidl"))
    }

    @Test func unknownListsStaySchedulableUnderTheirOwnName() {
        #expect(infer("Errands") == ListAssignment(role: .nextAction, area: "Errands"))
        #expect(infer("Nanny") == ListAssignment(role: .nextAction, area: "Nanny"))   // "NA" must match whole
    }

    @Test func onlyCommittedWorkIsSchedulable() {
        #expect(ListRole.allCases.filter(\.isSchedulable) == [.routine, .nextAction])
    }
}
