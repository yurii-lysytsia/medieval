import Combine
import MedievalDomain

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var state: GameState

    init(state: GameState = GameStore.newMatch()) {
        self.state = state
    }

    func send(_ action: GameAction) {
        guard case let .success(next) = GameRules.apply(action, to: state) else { return }
        state = next
    }

    func endTurn() {
        send(.endTurn(playerID: state.activePlayer.id))
    }

    func startNewGame() {
        state = Self.newMatch()
    }

    /// The roster every MVP match starts from. A function rather than a stored
    /// constant so each new match gets fresh player identities; `nonisolated`
    /// so it can also be evaluated as `init`'s default argument.
    nonisolated static func newMatch() -> GameState {
        GameState(players: [
            Player(displayName: "Корона"),
            Player(displayName: "Союз"),
        ])
    }
}
