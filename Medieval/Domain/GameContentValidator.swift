import Foundation

public enum GameContentValidationError: Error, Equatable, LocalizedError, Sendable {
    case duplicateIdentifier(entity: String, id: String)
    case missingReference(entity: String, id: String, reference: String)
    case invalidNumber(field: String, value: Int, minimum: Int)
    case impassablePlacement(entity: String, hexID: HexID)
    case coordinateOutOfBounds(hexID: HexID, axis: String, value: Int, minimum: Int, maximum: Int)
    case contradictoryHex(hexID: HexID)
    case asymmetricNeighborhood(hexID: HexID, neighborHexID: HexID)
    case unsuitableCityPlacement(hexID: HexID, terrainID: TerrainID)
    case invalidRiverBoundary(id: String, firstHexID: HexID, secondHexID: HexID)

    public var errorDescription: String? {
        switch self {
        case let .duplicateIdentifier(entity, id):
            "Duplicate \(entity) identifier \"\(id)\"."
        case let .missingReference(entity, id, reference):
            "\(entity) \"\(id)\" refers to missing \(reference)."
        case let .invalidNumber(field, value, minimum):
            "\(field) must be at least \(minimum), but is \(value)."
        case let .impassablePlacement(entity, hexID):
            "\(entity) cannot be placed on impassable hex \"\(hexID.rawValue)\"."
        case let .coordinateOutOfBounds(hexID, axis, value, minimum, maximum):
            "Map hex \"\(hexID.rawValue)\" has \(axis) = \(value), outside the map bounds \(minimum)...\(maximum)."
        case let .contradictoryHex(hexID):
            "Hex \"\(hexID.rawValue)\" is described differently by the map and the world."
        case let .asymmetricNeighborhood(hexID, neighborHexID):
            "Hex \"\(hexID.rawValue)\" lists \"\(neighborHexID.rawValue)\" as a neighbour, but not the other way round."
        case let .unsuitableCityPlacement(hexID, terrainID):
            "City cannot be placed on hex \"\(hexID.rawValue)\" with terrain \"\(terrainID.rawValue)\"."
        case let .invalidRiverBoundary(id, firstHexID, secondHexID):
            "River boundary \"\(id)\" must connect neighboring hexes, but \"\(firstHexID.rawValue)\" and \"\(secondHexID.rawValue)\" do not share a border."
        }
    }
}

public enum GameContentValidator {
    /// Rejects malformed data before it can be used to create a match.
    public static func validate(_ configuration: GameContentConfiguration) throws {
        try validateUniqueIdentifiers(configuration)
        try validateNumbers(configuration)
        try validateReferencesAndPassability(configuration)
    }

    private static func validateUniqueIdentifiers(_ configuration: GameContentConfiguration) throws {
        try validateUnique(configuration.terrain.map(\.id.rawValue), entity: "terrain")
        try validateUnique(configuration.units.map(\.id.rawValue), entity: "unit")
        try validateUnique(configuration.cityLevels.map(\.id.rawValue), entity: "city level")
        try validateUnique(configuration.buildings.map(\.id.rawValue), entity: "building type")
        try validateUnique(configuration.scenario.map.hexes.map(\.id.rawValue), entity: "map hex")
        try validateUnique(configuration.scenario.map.hexes.map { "\($0.coordinate.q),\($0.coordinate.r)" }, entity: "map coordinate")
        try validateUnique(configuration.scenario.map.neighborhoods.map(\.hexID.rawValue), entity: "map neighborhood")

        let world = configuration.scenario.world
        try validateUnique(world.players.map(\.id.rawValue), entity: "player")
        try validateUnique(world.hexes.map(\.id.rawValue), entity: "hex")
        try validateUnique(world.riverBoundaries.map(\.id.rawValue), entity: "river boundary")
        try validateUnique(world.armies.map(\.id.rawValue), entity: "army")
        try validateUnique(world.cities.map(\.id.rawValue), entity: "city")
        try validateUnique(world.buildings.map(\.id.rawValue), entity: "building")
    }

    private static func validateNumbers(_ configuration: GameContentConfiguration) throws {
        try validateMinimum(configuration.scenario.startingGold, field: "scenario starting gold", minimum: 0)
        try validateMinimum(configuration.scenario.world.players.count, field: "scenario player count", minimum: 2)

        for terrain in configuration.terrain {
            try validateMinimum(terrain.movementCost, field: "terrain \(terrain.id.rawValue) movement cost", minimum: 0)
            if terrain.isPassable {
                try validateMinimum(terrain.movementCost, field: "passable terrain \(terrain.id.rawValue) movement cost", minimum: 1)
            }
        }
        for unit in configuration.units {
            try validateMinimum(unit.recruitmentCost, field: "unit \(unit.id.rawValue) recruitment cost", minimum: 0)
            try validateMinimum(unit.upkeep, field: "unit \(unit.id.rawValue) upkeep", minimum: 0)
            try validateMinimum(unit.attack, field: "unit \(unit.id.rawValue) attack", minimum: 0)
            try validateMinimum(unit.defense, field: "unit \(unit.id.rawValue) defense", minimum: 0)
            try validateMinimum(unit.movement, field: "unit \(unit.id.rawValue) movement", minimum: 1)
        }
        for level in configuration.cityLevels {
            try validateMinimum(level.baseIncome, field: "city level \(level.id.rawValue) base income", minimum: 0)
            try validateMinimum(level.buildingSlots, field: "city level \(level.id.rawValue) building slots", minimum: 0)
        }
        for building in configuration.buildings {
            try validateMinimum(building.constructionCost, field: "building \(building.id.rawValue) construction cost", minimum: 0)
            try validateMinimum(building.upkeep, field: "building \(building.id.rawValue) upkeep", minimum: 0)
        }
        for army in configuration.scenario.world.armies {
            try validateMinimum(army.quantity, field: "army \(army.id.rawValue) quantity", minimum: 1)
        }
    }

    private static func validateReferencesAndPassability(_ configuration: GameContentConfiguration) throws {
        // Keeping the first entry per key rather than `uniqueKeysWithValues:`,
        // which traps on duplicates. Duplicate IDs are already reported by
        // validateUniqueIdentifiers, but a lookup table built here must not
        // crash the loader if that check is ever reordered or scoped down.
        let terrainByID = Dictionary(configuration.terrain.map { ($0.id, $0) }) { first, _ in first }
        let unitIDs = Set(configuration.units.map(\.id))
        let cityLevelIDs = Set(configuration.cityLevels.map(\.id))
        let buildingTypeIDs = Set(configuration.buildings.map(\.id))
        let world = configuration.scenario.world
        let playerIDs = Set(world.players.map(\.id))
        let hexByID = Dictionary(world.hexes.map { ($0.id, $0) }) { first, _ in first }
        let cityIDs = Set(world.cities.map(\.id))
        let map = configuration.scenario.map
        let mapHexIDs = Set(map.hexes.map(\.id))

        for level in configuration.cityLevels {
            for buildingID in level.requiredBuildingIDs {
                try validateReference(buildingID, in: buildingTypeIDs, entity: "city level", id: level.id.rawValue, reference: "required building")
            }
        }

        for hex in map.hexes {
            if !(map.bounds.minimumQ ... map.bounds.maximumQ).contains(hex.coordinate.q) {
                throw GameContentValidationError.coordinateOutOfBounds(
                    hexID: hex.id, axis: "q", value: hex.coordinate.q,
                    minimum: map.bounds.minimumQ, maximum: map.bounds.maximumQ
                )
            }
            if !(map.bounds.minimumR ... map.bounds.maximumR).contains(hex.coordinate.r) {
                throw GameContentValidationError.coordinateOutOfBounds(
                    hexID: hex.id, axis: "r", value: hex.coordinate.r,
                    minimum: map.bounds.minimumR, maximum: map.bounds.maximumR
                )
            }
            guard terrainByID[hex.terrainID] != nil else {
                throw GameContentValidationError.missingReference(entity: "map hex", id: hex.id.rawValue, reference: "terrain \"\(hex.terrainID.rawValue)\"")
            }
        }

        // The rules read terrain from world.hexes while the map and its
        // inspectors read map.hexes. The two describe the same board, so a
        // disagreement would render one terrain and resolve combat on another.
        for mapHex in map.hexes {
            guard let worldHex = hexByID[mapHex.id] else {
                throw GameContentValidationError.missingReference(entity: "map hex", id: mapHex.id.rawValue, reference: "matching world hex")
            }
            guard worldHex == mapHex else {
                throw GameContentValidationError.contradictoryHex(hexID: mapHex.id)
            }
        }
        for worldHex in world.hexes where !mapHexIDs.contains(worldHex.id) {
            throw GameContentValidationError.missingReference(entity: "world hex", id: worldHex.id.rawValue, reference: "matching map hex")
        }

        let neighborhoodHexIDs = Set(map.neighborhoods.map(\.hexID))
        let neighborsByHexID = Dictionary(map.neighborhoods.map { ($0.hexID, Set($0.neighborHexIDs)) }) { first, _ in first }

        for neighborhood in map.neighborhoods {
            guard mapHexIDs.contains(neighborhood.hexID) else {
                throw GameContentValidationError.missingReference(entity: "map neighborhood", id: neighborhood.hexID.rawValue, reference: "hex")
            }
            for neighborID in neighborhood.neighborHexIDs {
                guard mapHexIDs.contains(neighborID) else {
                    throw GameContentValidationError.missingReference(entity: "map neighborhood", id: neighborhood.hexID.rawValue, reference: "neighbor hex \"\(neighborID.rawValue)\"")
                }
                // Adjacency is mutual. A one-sided entry would let an army walk
                // one way down a corridor it cannot walk back.
                guard neighborsByHexID[neighborID]?.contains(neighborhood.hexID) == true else {
                    throw GameContentValidationError.asymmetricNeighborhood(hexID: neighborhood.hexID, neighborHexID: neighborID)
                }
            }
        }
        for hexID in mapHexIDs where !neighborhoodHexIDs.contains(hexID) {
            throw GameContentValidationError.missingReference(entity: "map", id: map.id, reference: "neighborhood for hex \"\(hexID.rawValue)\"")
        }

        for hex in world.hexes where terrainByID[hex.terrainID] == nil {
            throw GameContentValidationError.missingReference(
                entity: "hex",
                id: hex.id.rawValue,
                reference: "terrain \"\(hex.terrainID.rawValue)\""
            )
        }

        for river in world.riverBoundaries {
            guard hexByID[river.boundary.firstHexID] != nil else {
                throw GameContentValidationError.missingReference(
                    entity: "river boundary",
                    id: river.id.rawValue,
                    reference: "first hex \"\(river.boundary.firstHexID.rawValue)\""
                )
            }
            guard hexByID[river.boundary.secondHexID] != nil else {
                throw GameContentValidationError.missingReference(
                    entity: "river boundary",
                    id: river.id.rawValue,
                    reference: "second hex \"\(river.boundary.secondHexID.rawValue)\""
                )
            }
            let neighbors = map.neighborhoods.first { $0.hexID == river.boundary.firstHexID }?.neighborHexIDs ?? []
            guard neighbors.contains(river.boundary.secondHexID) else {
                throw GameContentValidationError.invalidRiverBoundary(
                    id: river.id.rawValue,
                    firstHexID: river.boundary.firstHexID,
                    secondHexID: river.boundary.secondHexID
                )
            }
        }
        for army in world.armies {
            try validateReference(army.ownerID, in: playerIDs, entity: "army", id: army.id.rawValue, reference: "owner")
            try validateReference(army.unitTypeID, in: unitIDs, entity: "army", id: army.id.rawValue, reference: "unit type")
            guard let hex = hexByID[army.hexID] else {
                throw GameContentValidationError.missingReference(entity: "army", id: army.id.rawValue, reference: "hex \"\(army.hexID.rawValue)\"")
            }
            guard terrainByID[hex.terrainID]?.isPassable == true else {
                throw GameContentValidationError.impassablePlacement(entity: "Army \"\(army.id.rawValue)\"", hexID: hex.id)
            }
        }
        for city in world.cities {
            if let ownerID = city.ownerID {
                try validateReference(ownerID, in: playerIDs, entity: "city", id: city.id.rawValue, reference: "owner")
            }
            try validateReference(city.levelID, in: cityLevelIDs, entity: "city", id: city.id.rawValue, reference: "city level")
            guard let hex = hexByID[city.hexID] else {
                throw GameContentValidationError.missingReference(entity: "city", id: city.id.rawValue, reference: "hex \"\(city.hexID.rawValue)\"")
            }
            guard terrainByID[hex.terrainID]?.isPassable == true else {
                throw GameContentValidationError.impassablePlacement(entity: "City \"\(city.id.rawValue)\"", hexID: hex.id)
            }
            guard let terrain = terrainByID[hex.terrainID], terrain.isCityBuildable else {
                throw GameContentValidationError.unsuitableCityPlacement(hexID: hex.id, terrainID: hex.terrainID)
            }
        }
        for building in world.buildings {
            try validateReference(building.cityID, in: cityIDs, entity: "building", id: building.id.rawValue, reference: "city")
            try validateReference(building.typeID, in: buildingTypeIDs, entity: "building", id: building.id.rawValue, reference: "building type")
        }
    }

    private static func validateUnique(_ identifiers: [String], entity: String) throws {
        var seen = Set<String>()
        for id in identifiers where !seen.insert(id).inserted {
            throw GameContentValidationError.duplicateIdentifier(entity: entity, id: id)
        }
    }

    private static func validateMinimum(_ value: Int, field: String, minimum: Int) throws {
        guard value >= minimum else {
            throw GameContentValidationError.invalidNumber(field: field, value: value, minimum: minimum)
        }
    }

    private static func validateReference<ID: Hashable>(
        _ identifier: ID,
        in identifiers: some SetAlgebra<ID>,
        entity: String,
        id: String,
        reference: String
    ) throws {
        guard identifiers.contains(identifier) else {
            throw GameContentValidationError.missingReference(entity: entity, id: id, reference: reference)
        }
    }
}
