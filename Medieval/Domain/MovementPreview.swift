import Foundation

public struct MovementPreview: Equatable, Sendable {
    public let armyID: ArmyID
    public let routes: [HexID: MovementRoute]
    public let encounterHexIDs: Set<HexID>

    public init(armyID: ArmyID, routes: [HexID: MovementRoute], encounterHexIDs: Set<HexID>) {
        self.armyID = armyID
        self.routes = routes
        self.encounterHexIDs = encounterHexIDs
    }
}

public enum MovementPreviewRules {
    public static func preview(
        armyID: ArmyID,
        playerID: WorldPlayerID,
        world: WorldState,
        map: StaticHexMap,
        terrain: [TerrainDefinition],
        units: [UnitDefinition]
    ) -> MovementPreview? {
        guard world.phase == .movement,
              let army = world.armies.first(where: { $0.id == armyID && $0.ownerID == playerID }),
              !army.hasMoved,
              army.embarkedOnShipID == nil
        else { return nil }
        let armyUnits = army.unitIDs.compactMap { id in world.units.first(where: { $0.id == id }) }
        guard armyUnits.count == army.unitIDs.count else { return nil }
        let budget = armyUnits.compactMap { unit in units.first(where: { $0.id == unit.typeID })?.movement }.min() ?? 0
        let routes = StrategicPathfinder.reachableRoutes(from: army.hexID, budget: budget, domain: .land, map: map, world: world, terrain: terrain)
        let enemies = Set(world.armies.filter { $0.ownerID != playerID }.map(\.hexID))
            .union(world.cities.filter { $0.ownerID != nil && $0.ownerID != playerID }.map(\.hexID))
        return MovementPreview(armyID: armyID, routes: routes, encounterHexIDs: enemies.intersection(routes.keys))
    }
}
