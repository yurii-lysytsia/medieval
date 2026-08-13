import Foundation

public enum GameAction: Equatable, Sendable {
    case advancePhase(playerID: UUID)
    case endTurn(playerID: UUID)
    case confirmHandoff(playerID: UUID)
    case eliminatePlayer(playerID: UUID)
}

extension GameAction: Codable {
    private enum CodingKeys: String, CodingKey { case kind, playerID }
    private enum Kind: String, Codable { case advancePhase, endTurn, confirmHandoff, eliminatePlayer }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .advancePhase:
            self = try .advancePhase(playerID: container.decode(UUID.self, forKey: .playerID))
        case .endTurn:
            self = try .endTurn(playerID: container.decode(UUID.self, forKey: .playerID))
        case .confirmHandoff:
            self = try .confirmHandoff(playerID: container.decode(UUID.self, forKey: .playerID))
        case .eliminatePlayer:
            self = try .eliminatePlayer(playerID: container.decode(UUID.self, forKey: .playerID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .advancePhase(playerID):
            try container.encode(Kind.advancePhase, forKey: .kind)
            try container.encode(playerID, forKey: .playerID)
        case let .endTurn(playerID):
            try container.encode(Kind.endTurn, forKey: .kind)
            try container.encode(playerID, forKey: .playerID)
        case let .confirmHandoff(playerID):
            try container.encode(Kind.confirmHandoff, forKey: .kind)
            try container.encode(playerID, forKey: .playerID)
        case let .eliminatePlayer(playerID):
            try container.encode(Kind.eliminatePlayer, forKey: .kind)
            try container.encode(playerID, forKey: .playerID)
        }
    }
}

public enum GameRuleError: Error, Equatable, Sendable {
    case playerIsNotActive
    case invalidPhase(GamePhase)
    case playerNotFound(UUID)
    case playerAlreadyEliminated(UUID)
    case gameIsFinished
}

public enum GameRules {
    /// The sole domain entry point for changing a game. Invalid actions leave state untouched.
    public static func apply(_ action: GameAction, to state: GameState) -> Result<GameState, GameRuleError> {
        guard state.result == nil else { return .failure(.gameIsFinished) }
        var next = state

        switch action {
        case let .advancePhase(playerID):
            guard playerID == state.activePlayer.id else { return .failure(.playerIsNotActive) }
            guard let followingPhase = nextPhase(after: state.phase) else { return .failure(.invalidPhase(state.phase)) }
            next.advancePhase(to: followingPhase, using: action)
        case let .endTurn(playerID):
            guard playerID == state.activePlayer.id else { return .failure(.playerIsNotActive) }
            next.advanceTurn()
        }

        return .success(next)
    }

    private static func nextPhase(after phase: GamePhase) -> GamePhase? {
        switch phase {
        case .economy: .construction
        case .construction: .movement
        case .movement: .combat
        default: nil
        }
    }
}
