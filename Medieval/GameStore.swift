import Combine

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var state: GameState

    init(state: GameState = GameState(players: [
        Player(displayName: "Корона"),
        Player(displayName: "Союз")
    ])) {
        self.state = state
    }

    func send(_ action: GameAction) {
        state = GameRules.applying(action, to: state)
    }
}
