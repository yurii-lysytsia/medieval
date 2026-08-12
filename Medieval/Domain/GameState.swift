import Foundation

public struct Player: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String

    public init(id: UUID = UUID(), displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct GameState: Equatable, Sendable {
    public private(set) var players: [Player]
    public private(set) var activePlayerIndex: Int
    public private(set) var turn: Int

    public init(players: [Player], activePlayerIndex: Int = 0, turn: Int = 1) {
        precondition(!players.isEmpty, "A game needs at least one player.")
        precondition(players.indices.contains(activePlayerIndex), "Active player must be in the game.")
        precondition(turn > 0, "Turn number must be positive.")
        self.players = players
        self.activePlayerIndex = activePlayerIndex
        self.turn = turn
    }

    public var activePlayer: Player {
        players[activePlayerIndex]
    }

    mutating func advanceTurn() {
        activePlayerIndex = (activePlayerIndex + 1) % players.count
        if activePlayerIndex == 0 {
            turn += 1
        }
    }
}
