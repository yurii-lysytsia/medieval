import Foundation

public enum GameContentValidationError: Error, Equatable, LocalizedError, Sendable {
    case duplicateIdentifier(entity: String, id: String)
    case missingReference(entity: String, id: String, reference: String)
    case invalidNumber(field: String, value: Int, minimum: Int)
    case impassablePlacement(entity: String, hexID: HexID)

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
