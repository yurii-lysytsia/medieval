import Foundation

public struct PendingEncounter: Equatable, Sendable {
    public let attackerID: ArmyID
    public let defenderID: ArmyID
    public let destination: HexID
    public let route: MovementRoute

    public init(attackerID: ArmyID, defenderID: ArmyID, destination: HexID, route: MovementRoute) {
        self.attackerID = attackerID
        self.defenderID = defenderID
        self.destination = destination
        self.route = route
    }
}

public struct StrategicMovementResolution: Equatable, Sendable {
    public let game: GameState
    public let world: WorldState
    public let encounter: PendingEncounter?

    public init(game: GameState, world: WorldState, encounter: PendingEncounter? = nil) {
        self.game = game
        self.world = world
        self.encounter = encounter
    }
}

public enum StrategicMovementError: Error, Equatable, Sendable {
    case invalidPhase(GamePhase)
    case playerHasNoWorldIdentity
    case armyNotFound(ArmyID)
    case incompatibleOwner
    case invalidRoute
    case routeBlocked(HexID)
    case operation(ArmyOperationError)
}

public enum StrategicMovementRules {
    public static func confirmArmyMovement(
        armyID: ArmyID,
        route: MovementRoute,
        game: GameState,
        world: WorldState,
        map: StaticHexMap,
        terrain: [TerrainDefinition],
        units: [UnitDefinition]
    ) -> Result<StrategicMovementResolution, StrategicMovementError> {
        guard game.phase == .movement, world.phase == .movement else { return .failure(.invalidPhase(game.phase)) }
        guard let playerID = game.activePlayer.worldPlayerID else { return .failure(.playerHasNoWorldIdentity) }
        guard let army = world.armies.first(where: { $0.id == armyID }) else { return .failure(.armyNotFound(armyID)) }
        guard army.ownerID == playerID else { return .failure(.incompatibleOwner) }
        guard route.hexIDs.first == army.hexID, let destination = route.hexIDs.last, route.hexIDs.count > 1 else { return .failure(.invalidRoute) }

        let armyUnits = army.unitIDs.compactMap { id in world.units.first(where: { $0.id == id }) }
        let budget = armyUnits.compactMap { unit in units.first(where: { $0.id == unit.typeID })?.movement }.min() ?? 0
        guard let calculated = StrategicPathfinder.route(from: army.hexID, to: destination, budget: budget, domain: .land, map: map, world: world, terrain: terrain),
              calculated == route
        else { return .failure(.invalidRoute) }

        let occupied = Dictionary(grouping: world.armies, by: \.hexID)
        if let blocked = route.hexIDs.dropFirst().dropLast().first(where: { !(occupied[$0] ?? []).isEmpty }) {
            return .failure(.routeBlocked(blocked))
        }
        let destinationArmies = occupied[destination] ?? []
        if let defender = destinationArmies.first(where: { $0.ownerID != army.ownerID }) {
            var nextWorld = world
            nextWorld.markArmyCommanded(armyID)
            var nextGame = game
            nextGame.record(.encounterStarted(attackerID: armyID, defenderID: defender.id, hexID: destination))
            let encounter = PendingEncounter(attackerID: armyID, defenderID: defender.id, destination: destination, route: route)
            return .success(StrategicMovementResolution(game: nextGame, world: nextWorld, encounter: encounter))
        }

        let movement = ArmyOperations.moveArmy(armyID, along: route.hexIDs, world: world, map: map, terrain: terrain, units: units)
        guard case let .success(movedWorld) = movement else {
            guard case let .failure(error) = movement else { preconditionFailure() }
            return .failure(.operation(error))
        }
        var nextWorld = movedWorld
        if let friendly = destinationArmies.first(where: { $0.ownerID == army.ownerID && $0.id != armyID }) {
            let merge = ArmyOperations.merge(armyID, into: friendly.id, world: nextWorld)
            guard case let .success(mergedWorld) = merge else {
                guard case let .failure(error) = merge else { preconditionFailure() }
                return .failure(.operation(error))
            }
            nextWorld = mergedWorld
        }
        var nextGame = game
        nextGame.record(.armyMoved(armyID: armyID, from: army.hexID, to: destination, cost: route.cost))
        return .success(StrategicMovementResolution(game: nextGame, world: nextWorld))
    }
}
