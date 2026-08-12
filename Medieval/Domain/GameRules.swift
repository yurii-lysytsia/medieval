import Foundation

public enum GameAction: Equatable, Sendable {
    case endTurn
}

public enum GameRules {
    /// The only entry point for changing the game's state.
    /// UI layers submit actions; they never mutate state directly.
    public static func applying(_ action: GameAction, to state: GameState) -> GameState {
        var next = state

        switch action {
        case .endTurn:
            next.advanceTurn()
        }

        return next
    }
}
