import Foundation
import Testing
@testable import MedievalDomain

struct GameRulesTests {
    @Test func endingTurnMovesToNextPlayer() {
        let crown = Player(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Crown")
        let union = Player(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, displayName: "Union")
        let initial = GameState(players: [crown, union])

        let next = GameRules.applying(.endTurn, to: initial)

        #expect(next.turn == 1)
        #expect(next.activePlayer == union)
    }

    @Test func fullRoundIncrementsTurn() {
        let initial = GameState(players: [Player(displayName: "One"), Player(displayName: "Two")])

        let afterRound = GameRules.applying(.endTurn, to: GameRules.applying(.endTurn, to: initial))

        #expect(afterRound.turn == 2)
        #expect(afterRound.activePlayer == initial.activePlayer)
    }
}
