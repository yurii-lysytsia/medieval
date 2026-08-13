@testable import Medieval
import Testing

struct JournalPresentationTests {
    @Test func formatsTurnPhaseAndMovementDescription() {
        let entry = MatchJournalEntry(turn: 4, phase: .movement, event: .armyMoved(armyID: "army", from: "a", to: "b", cost: 3))
        let item = JournalItem(entry: entry, index: 2)

        #expect(item.id == "match-2")
        #expect(item.turn == 4)
        #expect(item.phase == .movement)
        #expect(item.text.contains("a → b"))
        #expect(item.text.contains("3"))
    }

    @Test func noticeKeepsCriticalMessageWithTimeAndContext() {
        let notice = GameNotice(turn: 2, phase: .construction, severity: .error, text: "Недостатньо монет")

        #expect(notice.turn == 2)
        #expect(notice.phase == .construction)
        #expect(notice.severity == .error)
        #expect(notice.text == "Недостатньо монет")
    }
}
