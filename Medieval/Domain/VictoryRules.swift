import Foundation

public enum VictoryRuleError: Error, Equatable, Sendable {
    case playerNotFound(WorldPlayerID)
    case capitalStillStanding(WorldPlayerID)
    case gameRule(GameRuleError)
}

public struct VictoryResolution: Equatable, Sendable {
    public let game: GameState
    public let world: WorldState

    public init(game: GameState, world: WorldState) {
        self.game = game
        self.world = world
    }
}

public enum VictoryRules {
    /// Resolves the consequence of a capital destroyed by combat.
    public static func resolveCapitalLoss(
        of ownerID: WorldPlayerID,
        game: GameState,
        world: WorldState
    ) -> Result<VictoryResolution, VictoryRuleError> {
        guard !world.cities.contains(where: { $0.isCapital && $0.ownerID == ownerID }) else {
            return .failure(.capitalStillStanding(ownerID))
        }
        guard let player = game.players.first(where: { $0.worldPlayerID == ownerID }) else {
            return .failure(.playerNotFound(ownerID))
        }

        let gameResult = GameRules.apply(.eliminatePlayer(playerID: player.id), to: game)
        guard case let .success(nextGame) = gameResult else {
            guard case let .failure(error) = gameResult else { preconditionFailure() }
            return .failure(.gameRule(error))
        }

        var nextWorld = world
        nextWorld.removeForces(for: ownerID)
        if nextGame.result != nil {
            nextWorld.markFinished()
        }
        return .success(VictoryResolution(game: nextGame, world: nextWorld))
    }
}
