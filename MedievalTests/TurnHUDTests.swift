@testable import Medieval
import Testing

struct TurnHUDTests {
    @Test func showsActivePlayerPhaseCoinsAndLegalHint() {
        let worldPlayers = [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")]
        let players = [
            Player(displayName: "Корона", worldPlayerID: "one", color: .gold),
            Player(displayName: "Союз", worldPlayerID: "two", color: .blue),
        ]
        let state = GameState(players: players, turn: 3, phase: .movement)
        let hud = TurnHUDSnapshot(state: state, economy: EconomyState(players: worldPlayers, startingGold: 120), hasBlockingPresentation: false)

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
        #expect(TurnHUDSnapshot(state: state, economy: economy, hasBlockingPresentation: false).canAdvance)
    }

    @Test func phasesThatNeedAChoiceFirstDoNotOfferTheNextPhaseButton() {
        // Placement, handoff and a finished match each have their own control;
        // offering "next phase" there would skip the choice being asked for.
        let worldPlayers = [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")]
        let economy = EconomyState(players: worldPlayers, startingGold: 100)
        let players = [Player(displayName: "One", worldPlayerID: "one"), Player(displayName: "Two", worldPlayerID: "two")]

        for phase in [GamePhase.capitalPlacement, .handoff, .finished] {
            let hud = TurnHUDSnapshot(state: GameState(players: players, phase: phase), economy: economy, hasBlockingPresentation: false)
            #expect(!hud.canAdvance, "\(phase.rawValue) should not advance")
        }
        for phase in [GamePhase.economy, .construction, .movement, .combat] {
            let hud = TurnHUDSnapshot(state: GameState(players: players, phase: phase), economy: economy, hasBlockingPresentation: false)
            #expect(hud.canAdvance, "\(phase.rawValue) should advance")
        }
    }

    @Test func aPlayerWithoutATreasuryIsNotShownSomebodyElsesCoins() {
        let worldPlayers = [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")]
        let state = GameState(players: [Player(displayName: "One"), Player(displayName: "Two")])
        let hud = TurnHUDSnapshot(state: state, economy: EconomyState(players: worldPlayers, startingGold: 100), hasBlockingPresentation: false)

        #expect(hud.coins == 0)
    }
}
