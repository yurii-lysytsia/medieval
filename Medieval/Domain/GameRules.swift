import Foundation

public enum GameAction: Equatable, Sendable {
    case endTurn(playerID: UUID)
}

extension GameAction: Codable {
    private enum CodingKeys: String, CodingKey { case kind, playerID }
    private enum Kind: String, Codable { case endTurn }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .endTurn:
            self = try .endTurn(playerID: container.decode(UUID.self, forKey: .playerID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .endTurn(playerID):
            try container.encode(Kind.endTurn, forKey: .kind)
            try container.encode(playerID, forKey: .playerID)
        }
    }
}

public enum GameRuleError: Error, Equatable, Sendable {
    case playerIsNotActive
}

public enum GameRules {
    /// The sole domain entry point for changing a game. Invalid actions leave state untouched.
    public static func apply(_ action: GameAction, to state: GameState) -> Result<GameState, GameRuleError> {
        var next = state

        switch action {
        case let .endTurn(playerID):
            guard playerID == state.activePlayer.id else { return .failure(.playerIsNotActive) }
            next.advanceTurn()
        }

        return .success(next)
    }
}
