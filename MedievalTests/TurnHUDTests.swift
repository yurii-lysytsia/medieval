@testable import MedievalDomain
import Testing

struct TurnHUDTests {
    @Test func showsActivePlayerPhaseCoinsAndLegalHint() {
        let worldPlayers = [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")]
        let players = [
            Player(displayName: "Корона", worldPlayerID: "one", color: .gold),
            Player(displayName: "Союз", worldPlayerID: "two", color: .blue),
        ]
        let state = GameState(players: players, turn: 3, phase: .movement)
        let hud = TurnHUDSnapshot(state: state, economy: EconomyState(players: worldPlayers, startingGold: 120))

        #expect(hud.playerName == "Корона")
        #expect(hud.playerColor == .gold)
        #expect(hud.turn == 3)
        #expect(hud.phaseTitle == "Рух")
        #expect(hud.coins == 120)
        #expect(hud.canAdvance)
        #expect(hud.hint.contains("армію"))
    }

    @Test func blocksAdvancingWhileModalContentIsPending() {
        let worldPlayers = [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")]
        let state = GameState(players: [Player(displayName: "One", worldPlayerID: "one"), Player(displayName: "Two", worldPlayerID: "two")])
        let economy = EconomyState(players: worldPlayers, startingGold: 100)

        #expect(!TurnHUDSnapshot(state: state, economy: economy, hasBlockingPresentation: true).canAdvance)
    }
}
