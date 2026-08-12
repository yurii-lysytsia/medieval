import Foundation

public struct TerrainDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: TerrainID
    public let displayName: String
    public let movementCost: Int
    public let incomeModifier: Int
    public let isPassable: Bool

    public init(id: TerrainID, displayName: String, movementCost: Int, incomeModifier: Int, isPassable: Bool) {
        self.id = id
        self.displayName = displayName
        self.movementCost = movementCost
        self.incomeModifier = incomeModifier
        self.isPassable = isPassable
    }
}

public struct UnitDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: UnitTypeID
    public let displayName: String
    public let recruitmentCost: Int
    public let upkeep: Int
    public let attack: Int
    public let defense: Int
    public let movement: Int

    public init(
        id: UnitTypeID,
        displayName: String,
        recruitmentCost: Int,
        upkeep: Int,
        attack: Int,
        defense: Int,
        movement: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.recruitmentCost = recruitmentCost
        self.upkeep = upkeep
        self.attack = attack
        self.defense = defense
        self.movement = movement
    }
}

public struct CityLevelDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: CityLevelID
    public let displayName: String
    public let baseIncome: Int
    public let buildingSlots: Int

    public init(id: CityLevelID, displayName: String, baseIncome: Int, buildingSlots: Int) {
        self.id = id
        self.displayName = displayName
        self.baseIncome = baseIncome
        self.buildingSlots = buildingSlots
    }
}

public struct BuildingDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: BuildingTypeID
    public let displayName: String
    public let constructionCost: Int
    public let incomeModifier: Int
    public let defenseModifier: Int

    public init(
        id: BuildingTypeID,
        displayName: String,
        constructionCost: Int,
        incomeModifier: Int,
        defenseModifier: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.constructionCost = constructionCost
        self.incomeModifier = incomeModifier
        self.defenseModifier = defenseModifier
    }
}

public struct ScenarioConfiguration: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let startingGold: Int
    public let world: WorldState

    public init(id: String, displayName: String, startingGold: Int, world: WorldState) {
        self.id = id
        self.displayName = displayName
        self.startingGold = startingGold
        self.world = world
    }
}

/// All balanceable data for a game setup. Values live in a JSON resource, not in game rules.
public struct GameContentConfiguration: Codable, Equatable, Sendable {
    public let terrain: [TerrainDefinition]
    public let units: [UnitDefinition]
    public let cityLevels: [CityLevelDefinition]
    public let buildings: [BuildingDefinition]
    public let scenario: ScenarioConfiguration

    public init(
        terrain: [TerrainDefinition],
        units: [UnitDefinition],
        cityLevels: [CityLevelDefinition],
        buildings: [BuildingDefinition],
        scenario: ScenarioConfiguration
    ) {
        self.terrain = terrain
        self.units = units
        self.cityLevels = cityLevels
        self.buildings = buildings
        self.scenario = scenario
    }
}

public extension GameContentConfiguration {
    /// The terrain a hex sits on, or `nil` for a dangling reference. Validated
    /// content never dangles — `GameContentValidator` rejects it first.
    func terrainDefinition(for hex: Hex) -> TerrainDefinition? {
        terrain.first { $0.id == hex.terrainID }
    }

    /// Whether units may occupy this hex. Unknown terrain is impassable, so a
    /// caller that skipped validation fails closed instead of letting armies
    /// walk onto tiles nobody defined.
    func isPassable(_ hex: Hex) -> Bool {
        terrainDefinition(for: hex)?.isPassable ?? false
    }
}

public enum GameContentLoadingError: Error, Equatable, LocalizedError, Sendable {
    case missingResource(String)
    case unreadableData(String)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case let .missingResource(name):
            "Game content resource \"\(name)\" is missing."
        case let .unreadableData(name):
            "Game content resource \"\(name)\" could not be read."
        case let .invalidJSON(message):
            "Game content JSON is invalid: \(message)"
        }
    }
}

public enum GameContentLoader {
    public static let mvpResourceName = "MVPConfiguration"

    public static func decode(_ data: Data) throws -> GameContentConfiguration {
        let configuration: GameContentConfiguration
        do {
            configuration = try JSONDecoder().decode(GameContentConfiguration.self, from: data)
        } catch {
            throw GameContentLoadingError.invalidJSON(error.localizedDescription)
        }
        try GameContentValidator.validate(configuration)
        return configuration
    }

    /// Loads the bundled MVP configuration.
    ///
    /// The resource belongs to this package, so it is read from `Bundle.module`
    /// rather than from whichever bundle a caller happens to pass. Letting the
    /// app read its own copy out of `Bundle.main` meant the configuration
    /// shipped twice, and tests exercised a different file than the game did.
    public static func loadMVP() throws -> GameContentConfiguration {
        guard let url = Bundle.module.url(forResource: mvpResourceName, withExtension: "json") else {
            throw GameContentLoadingError.missingResource(mvpResourceName)
        }
        guard let data = try? Data(contentsOf: url) else {
            throw GameContentLoadingError.unreadableData(mvpResourceName)
        }
        return try decode(data)
    }
}
