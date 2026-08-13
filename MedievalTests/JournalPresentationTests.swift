import Foundation
@testable import Medieval
import Testing

struct JournalPresentationTests {
    @Test func formatsTurnPhaseAndMovementDescription() {
        let entry = MatchJournalEntry(turn: 4, phase: .movement, event: .armyMoved(armyID: "army", from: "a", to: "b", cost: 3))
        let item = JournalItem(entry: entry, index: 2, players: [])

        #expect(item.id == "match-2")
        #expect(item.turn == 4)
        #expect(item.phase == .movement)
        #expect(item.text.contains("a → b"))
        #expect(item.text.contains("3"))
    }

    @Test func namesThePlayerAnEntryIsAbout() {
        // "Гравця усунено" tells the reader nothing they could act on; the
        // journal is read back precisely to find out who went out and when.
        let crown = Player(displayName: "Корона")
        let union = Player(displayName: "Союз")
        let eliminated = JournalItem(entry: MatchJournalEntry(turn: 6, phase: .combat, event: .playerEliminated(playerID: union.id)), index: 0, players: [crown, union])
        let finished = JournalItem(entry: MatchJournalEntry(turn: 6, phase: .finished, event: .matchFinished(.winner(playerID: crown.id))), index: 1, players: [crown, union])

        #expect(eliminated.text.contains("Союз"))
        #expect(finished.text.contains("Корона"))
    }

    @Test func anEntryAboutSomeoneNoLongerListedStillReads() {
        let item = JournalItem(entry: MatchJournalEntry(turn: 1, phase: .combat, event: .playerEliminated(playerID: UUID())), index: 0, players: [])

        #expect(item.text.contains("невідомий гравець"))
    }

    @Test func noticeKeepsCriticalMessageWithTimeAndContext() {
        let notice = GameNotice(turn: 2, phase: .construction, severity: .error, text: "Недостатньо монет")

        #expect(notice.turn == 2)
        #expect(notice.phase == .construction)
        #expect(notice.severity == .error)
        #expect(notice.text == "Недостатньо монет")
    }
}
