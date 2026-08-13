import Foundation
@testable import Medieval
import Testing

struct GameRulesTests {
    private let crown = Player(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Crown")
    private let union = Player(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, displayName: "Union")

    @Test func reducerMovesToNextPlayerForValidAction() throws {
        let initial = GameState(players: [crown, union], seed: 42)

        let next = try GameRules.apply(.endTurn(playerID: crown.id), to: initial).get()

        #expect(next.turn == 1)
        #expect(next.activePlayer == union)
    }

    @Test func fullRoundIncrementsTurn() throws {
        let initial = GameState(players: [crown, union], seed: 42)
        let afterFirstTurn = try GameRules.apply(.endTurn(playerID: crown.id), to: initial).get()
        let afterRound = try GameRules.apply(.endTurn(playerID: union.id), to: afterFirstTurn).get()

        #expect(afterRound.turn == 2)
        #expect(afterRound.activePlayer == initial.activePlayer)
    }

    @Test func invalidActionDoesNotChangeState() {
        let initial = GameState(players: [crown, union], seed: 42)

        let result = GameRules.apply(.endTurn(playerID: union.id), to: initial)

        #expect(result == .failure(.playerIsNotActive))
    }

    @Test func stateAndReplayAreCodableAndDeterministic() throws {
        let actions: [GameAction] = [.endTurn(playerID: crown.id), .endTurn(playerID: union.id)]
        let state = try actions.reduce(GameState(players: [crown, union], seed: 42)) { state, action in
            try GameRules.apply(action, to: state).get()
        }

        let decoded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
        let replay = GameReplay(seed: 42, players: [crown, union], actions: actions)

        #expect(decoded == state)
        #expect(try replay.replayedState() == state)
    }

    @Test func decodingRejectsStateThatBreaksInvariants() throws {
        // Synthesized Codable would write these straight into storage and hand
        // back a state whose `activePlayer` traps on the next read.
        let corrupt = """
        {"seed":42,"players":[],"activePlayerIndex":7,"turn":0}
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GameState.self, from: corrupt)
        }
    }

    @Test func replayFailsRatherThanSkippingRejectedActions() {
        let replay = GameReplay(
            seed: 42,
            players: [crown, union],
            actions: [.endTurn(playerID: crown.id), .endTurn(playerID: UUID())]
        )

        #expect(throws: GameRuleError.playerIsNotActive) {
            try replay.replayedState()
        }
    }

    @Test func seededRandomGeneratorRepeatsSequence() {
        var first = SeededRandomNumberGenerator(seed: 7)
        var second = SeededRandomNumberGenerator(seed: 7)

        #expect(first.next() == second.next())
        #expect(first.next() == second.next())
    }
}
