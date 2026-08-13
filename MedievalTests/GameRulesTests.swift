import Foundation
@testable import Medieval
import Testing

struct GameRulesTests {
    private let crown = Player(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Crown")
    private let union = Player(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, displayName: "Union")

    @Test func phasesAdvanceOnlyInTheirLegalOrder() throws {
        let initial = GameState(players: [crown, union], seed: 42)
        let construction = try GameRules.apply(.advancePhase(playerID: crown.id), to: initial).get()
        let movement = try GameRules.apply(.advancePhase(playerID: crown.id), to: construction).get()
        let combat = try GameRules.apply(.advancePhase(playerID: crown.id), to: movement).get()

        #expect(initial.phase == .economy)
        #expect(construction.phase == .construction)
        #expect(movement.phase == .movement)
        #expect(combat.phase == .combat)
    }

    @Test func endingCombatMovesToNextPlayerAndResetsPhase() throws {
        let initial = GameState(players: [crown, union], seed: 42, phase: .combat)
        let next = try GameRules.apply(.endTurn(playerID: crown.id), to: initial).get()

        #expect(next.turn == 1)
        #expect(next.activePlayer == union)
    }

    @Test func fullRoundIncrementsTurn() throws {
        let initial = GameState(players: [crown, union], seed: 42, phase: .combat)
        let afterFirstTurn = try GameRules.apply(.endTurn(playerID: crown.id), to: initial).get()
        let unionCombat = GameState(players: afterFirstTurn.players, seed: afterFirstTurn.seed, activePlayerIndex: afterFirstTurn.activePlayerIndex, turn: afterFirstTurn.turn, phase: .combat)
        let afterRound = try GameRules.apply(.endTurn(playerID: union.id), to: unionCombat).get()

        #expect(afterRound.turn == 2)
        #expect(afterRound.activePlayer == initial.activePlayer)
    }

    @Test func invalidPlayerOrPhaseDoesNotChangeState() {
        let initial = GameState(players: [crown, union], seed: 42)

        #expect(GameRules.apply(.advancePhase(playerID: union.id), to: initial) == .failure(.playerIsNotActive))
        #expect(GameRules.apply(.endTurn(playerID: crown.id), to: initial) == .failure(.invalidPhase(.economy)))
        #expect(GameRules.apply(.advancePhase(playerID: crown.id), to: GameState(players: [crown, union], phase: .combat)) == .failure(.invalidPhase(.combat)))
    }

    @Test func optionalPhasesCanBeSkippedWithoutMutatingOtherState() throws {
        let initial = GameState(players: [crown, union], seed: 42, phase: .construction)
        let skipped = try GameRules.apply(.advancePhase(playerID: crown.id), to: initial).get()

        #expect(skipped.phase == .movement)
        #expect(skipped.activePlayer == crown)
        #expect(skipped.turn == initial.turn)
    }

    @Test func stateAndReplayAreCodableAndDeterministic() throws {
        // A turn walks economy → construction → movement → combat before it can
        // end, so a faithful replay has to carry the phase steps too.
        let actions: [GameAction] = [
            .advancePhase(playerID: crown.id),
            .advancePhase(playerID: crown.id),
            .advancePhase(playerID: crown.id),
            .endTurn(playerID: crown.id),
        ]
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
            actions: [.advancePhase(playerID: crown.id), .advancePhase(playerID: UUID())]
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
