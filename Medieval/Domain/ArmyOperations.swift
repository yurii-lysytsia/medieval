import Foundation

public enum ArmyOperationError: Error, Equatable, LocalizedError, Sendable {
    case invalidPhase(GamePhase)
    case armyNotFound(ArmyID)
    case armyIDAlreadyInUse(ArmyID)
    case shipNotFound(UnitID)
    case unitNotFound(UnitID)
    case incompatibleOwner
    case incompatibleLocation
    case invalidComposition
    case armyCapacityExceeded(limit: Int)
    case alreadyMoved(ArmyID)
    case shipAlreadyMoved(UnitID)
    case invalidRoute(HexID, HexID)
    case movementExceeded(required: Int, available: Int)
    case deepWaterRequiresTransport(HexID)
    case navalRouteRequired(HexID)
    case embarkationPointRequired
    case shipCapacityExceeded(limit: Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidPhase(phase): "Army operations are unavailable during \(phase.rawValue)."
        case let .armyNotFound(id): "Army \"\(id.rawValue)\" does not exist."
        case let .armyIDAlreadyInUse(id): "Army \"\(id.rawValue)\" already exists."
        case let .shipNotFound(id): "Ship \"\(id.rawValue)\" does not exist."
        case let .unitNotFound(id): "Unit \"\(id.rawValue)\" does not exist."
        case .incompatibleOwner: "All units and transports must have the same owner."
        case .incompatibleLocation: "Units must share a location for this operation."
        case .invalidComposition: "Army composition must contain unique land units."
        case let .armyCapacityExceeded(limit): "A land army can contain at most \(limit) units."
        case let .alreadyMoved(id): "Army \"\(id.rawValue)\" has already moved this turn."
        case let .shipAlreadyMoved(id): "Ship \"\(id.rawValue)\" has already moved this turn."
        case let .invalidRoute(first, second): "Hexes \"\(first.rawValue)\" and \"\(second.rawValue)\" are not adjacent."
        case let .movementExceeded(required, available): "Route costs \(required) movement, but the army has \(available)."
        case let .deepWaterRequiresTransport(id): "Land units cannot enter deep water at hex \"\(id.rawValue)\" without a ship."
        case let .navalRouteRequired(id): "A ship route must stay on water; hex \"\(id.rawValue)\" is not water."
        case .embarkationPointRequired: "Embarkation and disembarkation require adjacent coast or shallows."
        case let .shipCapacityExceeded(limit): "The ship can carry at most \(limit) land units."
        }
    }
}

public enum ArmyOperations {
    public static let maximumLandUnits = 6

    public static func formArmy(
        id: ArmyID,
        ownerID: WorldPlayerID,
        unitIDs: [UnitID],
        world: WorldState,
        map: StaticHexMap,
        definitions: [UnitDefinition]
    ) -> Result<WorldState, ArmyOperationError> {
        guard world.phase == .movement else { return .failure(.invalidPhase(world.phase)) }
        // Armies are addressed by id, so handing out one that is taken would
        // make every later lookup pick whichever copy came first.
        guard !world.armies.contains(where: { $0.id == id }) else { return .failure(.armyIDAlreadyInUse(id)) }
        guard !unitIDs.isEmpty, Set(unitIDs).count == unitIDs.count else { return .failure(.invalidComposition) }
        guard unitIDs.count <= maximumLandUnits else { return .failure(.armyCapacityExceeded(limit: maximumLandUnits)) }
        let units = unitIDs.compactMap { id in world.units.first(where: { $0.id == id }) }
        guard units.count == unitIDs.count else {
            return .failure(.unitNotFound(unitIDs.first(where: { id in !world.units.contains(where: { $0.id == id }) })!))
        }
        guard units.allSatisfy({ $0.ownerID == ownerID }) else { return .failure(.incompatibleOwner) }
        guard units.allSatisfy({ unit in definitions.first(where: { $0.id == unit.typeID })?.domain == .land }) else { return .failure(.invalidComposition) }
        guard unitIDs.allSatisfy({ id in !world.armies.contains(where: { $0.unitIDs.contains(id) }) }) else { return .failure(.invalidComposition) }
        let locations = units.compactMap { locationHex(for: $0, in: world) }
        guard locations.count == units.count, Set(locations).count == 1, let hexID = locations.first else { return .failure(.incompatibleLocation) }
        guard map.hexes.contains(where: { $0.id == hexID }) else { return .failure(.incompatibleLocation) }

        var next = world
        for unit in units {
            next.replaceUnit(copy(unit, condition: .ready, location: .hex(hexID)))
        }
        next.addArmy(Army(id: id, ownerID: ownerID, hexID: hexID, unitIDs: unitIDs))
        return .success(next)
    }

    public static func merge(_ sourceID: ArmyID, into targetID: ArmyID, world: WorldState) -> Result<WorldState, ArmyOperationError> {
        guard world.phase == .movement else { return .failure(.invalidPhase(world.phase)) }
        guard let source = world.armies.first(where: { $0.id == sourceID }) else { return .failure(.armyNotFound(sourceID)) }
        guard let target = world.armies.first(where: { $0.id == targetID }) else { return .failure(.armyNotFound(targetID)) }
        guard source.ownerID == target.ownerID else { return .failure(.incompatibleOwner) }
        guard source.hexID == target.hexID, source.embarkedOnShipID == target.embarkedOnShipID else { return .failure(.incompatibleLocation) }
        let combined = target.unitIDs + source.unitIDs
        guard Set(combined).count == combined.count else { return .failure(.invalidComposition) }
        guard combined.count <= maximumLandUnits else { return .failure(.armyCapacityExceeded(limit: maximumLandUnits)) }

        var next = world
        next.replaceArmy(Army(id: target.id, ownerID: target.ownerID, hexID: target.hexID, unitIDs: combined, hasMoved: target.hasMoved || source.hasMoved, embarkedOnShipID: target.embarkedOnShipID))
        next.removeArmy(source.id)
        return .success(next)
    }

    public static func split(
        _ armyID: ArmyID,
        moving unitIDs: [UnitID],
        into newArmyID: ArmyID,
        world: WorldState
    ) -> Result<WorldState, ArmyOperationError> {
        guard world.phase == .movement else { return .failure(.invalidPhase(world.phase)) }
        guard let army = world.armies.first(where: { $0.id == armyID }) else { return .failure(.armyNotFound(armyID)) }
        guard !world.armies.contains(where: { $0.id == newArmyID }) else { return .failure(.armyIDAlreadyInUse(newArmyID)) }
        guard !army.hasMoved else { return .failure(.alreadyMoved(armyID)) }
        guard army.embarkedOnShipID == nil else { return .failure(.incompatibleLocation) }
        let selected = Set(unitIDs)
        guard !selected.isEmpty, selected.count == unitIDs.count, selected.isSubset(of: Set(army.unitIDs)), selected.count < army.unitIDs.count else {
            return .failure(.invalidComposition)
        }

        var next = world
        next.replaceArmy(Army(id: army.id, ownerID: army.ownerID, hexID: army.hexID, unitIDs: army.unitIDs.filter { !selected.contains($0) }))
        next.addArmy(Army(id: newArmyID, ownerID: army.ownerID, hexID: army.hexID, unitIDs: unitIDs))
        return .success(next)
    }

    public static func moveArmy(
        _ armyID: ArmyID,
        along route: [HexID],
        world: WorldState,
        map: StaticHexMap,
        terrain: [TerrainDefinition],
        units definitions: [UnitDefinition]
    ) -> Result<WorldState, ArmyOperationError> {
        guard world.phase == .movement else { return .failure(.invalidPhase(world.phase)) }
        guard let army = world.armies.first(where: { $0.id == armyID }) else { return .failure(.armyNotFound(armyID)) }
        guard !army.hasMoved else { return .failure(.alreadyMoved(armyID)) }
        guard army.embarkedOnShipID == nil, route.first == army.hexID, route.count > 1 else { return .failure(.incompatibleLocation) }
        if let error = validateAdjacency(route, map: map) { return .failure(error) }
        var cost = 0
        for (origin, destination) in zip(route, route.dropFirst()) {
            guard let hex = world.hexes.first(where: { $0.id == destination }),
                  let definition = terrain.first(where: { $0.id == hex.terrainID })
            else { return .failure(.invalidRoute(origin, destination)) }
            guard hex.terrainID != "deep-water" else { return .failure(.deepWaterRequiresTransport(destination)) }
            cost += definition.movementCost + (RiverRules.crossesRiver(from: origin, to: destination, in: world) ? 1 : 0)
        }
        let armyUnits = army.unitIDs.compactMap { id in world.units.first(where: { $0.id == id }) }
        let movement = armyUnits.compactMap { unit in definitions.first(where: { $0.id == unit.typeID })?.movement }.min() ?? 0
        guard cost <= movement else { return .failure(.movementExceeded(required: cost, available: movement)) }
        let destination = route.last!
        var next = world
        for unit in armyUnits {
            next.replaceUnit(copy(unit, condition: .moved, location: .hex(destination)))
        }
        next.replaceArmy(Army(id: army.id, ownerID: army.ownerID, hexID: destination, unitIDs: army.unitIDs, hasMoved: true))
        return .success(next)
    }

    public static func embark(
        _ armyID: ArmyID,
        on shipID: UnitID,
        world: WorldState,
        map: StaticHexMap,
        definitions: [UnitDefinition]
    ) -> Result<WorldState, ArmyOperationError> {
        guard world.phase == .movement else { return .failure(.invalidPhase(world.phase)) }
        guard let army = world.armies.first(where: { $0.id == armyID }) else { return .failure(.armyNotFound(armyID)) }
        guard !army.hasMoved else { return .failure(.alreadyMoved(armyID)) }
        guard let ship = world.units.first(where: { $0.id == shipID }),
              definitions.first(where: { $0.id == ship.typeID })?.domain == .navalTransport,
              case let .hex(shipHexID) = ship.location
        else { return .failure(.shipNotFound(shipID)) }
        guard ship.ownerID == army.ownerID else { return .failure(.incompatibleOwner) }
        guard areSameOrAdjacent(army.hexID, shipHexID, map: map), isEmbarkationPair(army.hexID, shipHexID, world: world) else {
            return .failure(.embarkationPointRequired)
        }
        let capacity = definitions.first(where: { $0.id == ship.typeID })?.cargoCapacity ?? 0
        let occupied = world.units.filter { $0.location == .cargo(shipID) && $0.condition != .destroyed }.count
        guard occupied + army.unitIDs.count <= capacity else { return .failure(.shipCapacityExceeded(limit: capacity)) }

        var next = world
        for id in army.unitIDs {
            guard let unit = next.units.first(where: { $0.id == id }) else { return .failure(.unitNotFound(id)) }
            next.replaceUnit(copy(unit, condition: .embarked, location: .cargo(shipID)))
        }
        next.replaceArmy(Army(id: army.id, ownerID: army.ownerID, hexID: shipHexID, unitIDs: army.unitIDs, hasMoved: true, embarkedOnShipID: shipID))
        return .success(next)
    }

    public static func moveShip(
        _ shipID: UnitID,
        along route: [HexID],
        world: WorldState,
        map: StaticHexMap,
        definitions: [UnitDefinition]
    ) -> Result<WorldState, ArmyOperationError> {
        guard world.phase == .movement else { return .failure(.invalidPhase(world.phase)) }
        guard let ship = world.units.first(where: { $0.id == shipID }),
              let definition = definitions.first(where: { $0.id == ship.typeID && $0.domain == .navalTransport }),
              case let .hex(origin) = ship.location,
              route.first == origin,
              route.count > 1
        else { return .failure(.shipNotFound(shipID)) }
        guard ship.condition != .moved else { return .failure(.shipAlreadyMoved(shipID)) }
        if let error = validateAdjacency(route, map: map) { return .failure(error) }
        guard route.count - 1 <= definition.movement else { return .failure(.movementExceeded(required: route.count - 1, available: definition.movement)) }
        for hexID in route.dropFirst() {
            guard let terrainID = world.hexes.first(where: { $0.id == hexID })?.terrainID,
                  terrainID == "shallows" || terrainID == "deep-water"
            else { return .failure(.navalRouteRequired(hexID)) }
        }
        let destination = route.last!
        var next = world
        next.replaceUnit(copy(ship, condition: .moved, location: .hex(destination)))
        for army in world.armies where army.embarkedOnShipID == shipID {
            next.replaceArmy(Army(id: army.id, ownerID: army.ownerID, hexID: destination, unitIDs: army.unitIDs, hasMoved: true, embarkedOnShipID: shipID))
        }
        return .success(next)
    }

    public static func disembark(
        _ armyID: ArmyID,
        to destination: HexID,
        world: WorldState,
        map: StaticHexMap
    ) -> Result<WorldState, ArmyOperationError> {
        guard world.phase == .movement else { return .failure(.invalidPhase(world.phase)) }
        guard let army = world.armies.first(where: { $0.id == armyID }), let shipID = army.embarkedOnShipID else { return .failure(.armyNotFound(armyID)) }
        guard let ship = world.units.first(where: { $0.id == shipID }), case let .hex(shipHexID) = ship.location else { return .failure(.shipNotFound(shipID)) }
        guard areSameOrAdjacent(shipHexID, destination, map: map),
              let terrainID = world.hexes.first(where: { $0.id == destination })?.terrainID,
              terrainID != "deep-water",
              isEmbarkationPair(destination, shipHexID, world: world)
        else { return .failure(.embarkationPointRequired) }

        var next = world
        for id in army.unitIDs {
            guard let unit = next.units.first(where: { $0.id == id }) else { return .failure(.unitNotFound(id)) }
            next.replaceUnit(copy(unit, condition: .moved, location: .hex(destination)))
        }
        next.replaceArmy(Army(id: army.id, ownerID: army.ownerID, hexID: destination, unitIDs: army.unitIDs, hasMoved: true))
        return .success(next)
    }

    public static func destroy(_ armyID: ArmyID, world: WorldState) -> Result<WorldState, ArmyOperationError> {
        guard let army = world.armies.first(where: { $0.id == armyID }) else { return .failure(.armyNotFound(armyID)) }
        var next = world
        for id in army.unitIDs {
            guard let unit = next.units.first(where: { $0.id == id }) else { continue }
            next.replaceUnit(copy(unit, condition: .destroyed, location: unit.location))
        }
        next.removeArmy(armyID)
        return .success(next)
    }

    private static func locationHex(for unit: Unit, in world: WorldState) -> HexID? {
        switch unit.location {
        case let .hex(id): id
        case let .garrison(cityID): world.cities.first(where: { $0.id == cityID })?.hexID
        case .cargo: nil
        }
    }

    private static func copy(_ unit: Unit, condition: UnitCondition, location: UnitLocation) -> Unit {
        Unit(id: unit.id, ownerID: unit.ownerID, typeID: unit.typeID, currentHitPoints: unit.currentHitPoints, condition: condition, location: location)
    }

    private static func validateAdjacency(_ route: [HexID], map: StaticHexMap) -> ArmyOperationError? {
        for (first, second) in zip(route, route.dropFirst()) {
            let neighbors = map.neighborhoods.first(where: { $0.hexID == first })?.neighborHexIDs ?? []
            if !neighbors.contains(second) { return .invalidRoute(first, second) }
        }
        return nil
    }

    private static func areSameOrAdjacent(_ first: HexID, _ second: HexID, map: StaticHexMap) -> Bool {
        first == second || (map.neighborhoods.first(where: { $0.hexID == first })?.neighborHexIDs.contains(second) == true)
    }

    private static func isEmbarkationPair(_ first: HexID, _ second: HexID, world: WorldState) -> Bool {
        let terrainIDs = [first, second].compactMap { id in world.hexes.first(where: { $0.id == id })?.terrainID }
        return terrainIDs.contains("shallows") && !terrainIDs.contains("deep-water")
    }
}
