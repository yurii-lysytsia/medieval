import Foundation

public enum CityConstructionError: Error, Equatable, LocalizedError, Sendable {
    case invalidPhase(GamePhase)
    case cityNotOwned(CityID)
    case unknownBuilding(BuildingTypeID)
    case alreadyBuilt(BuildingTypeID)
    case noBuildingSlots(CityID)
    case insufficientCoins(required: Int)
    case noNextLevel(CityID)
    case unknownCityLevel(CityLevelID)
    case unmetRequirements([BuildingTypeID])

    public var errorDescription: String? {
        switch self {
        case let .invalidPhase(phase): "Construction is unavailable during \(phase.rawValue)."
        case let .cityNotOwned(cityID): "The active player does not own city \"\(cityID.rawValue)\"."
        case let .unknownBuilding(typeID): "Building \"\(typeID.rawValue)\" is unknown."
        case let .alreadyBuilt(typeID): "Building \"\(typeID.rawValue)\" already exists in this city."
        case let .noBuildingSlots(cityID): "City \"\(cityID.rawValue)\" has no free building slots."
        case let .insufficientCoins(required): "This action requires \(required) coins."
        case let .noNextLevel(cityID): "City \"\(cityID.rawValue)\" is already at its highest level."
        case let .unknownCityLevel(levelID): "City level \"\(levelID.rawValue)\" is not defined by the game content."
        case let .unmetRequirements(ids): "Missing required buildings: \(ids.map(\.rawValue).joined(separator: ", "))."
        }
    }
}

public struct CityConstructionResult: Equatable, Sendable {
    public let world: WorldState
    public let economy: EconomyState
}

public enum CityConstructionRules {
    public static func construct(
        buildingTypeID: BuildingTypeID,
        in cityID: CityID,
        for playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        cityLevels: [CityLevelDefinition],
        buildings: [BuildingDefinition]
    ) -> Result<CityConstructionResult, CityConstructionError> {
        guard world.phase == .construction else { return .failure(.invalidPhase(world.phase)) }
        guard let city = world.cities.first(where: { $0.id == cityID && $0.ownerID == playerID }) else { return .failure(.cityNotOwned(cityID)) }
        guard let definition = buildings.first(where: { $0.id == buildingTypeID }) else { return .failure(.unknownBuilding(buildingTypeID)) }
        guard !world.buildings.contains(where: { $0.cityID == cityID && $0.typeID == buildingTypeID }) else { return .failure(.alreadyBuilt(buildingTypeID)) }
        // A city whose level nothing defines is a broken world, not a full one.
        guard let level = cityLevels.first(where: { $0.id == city.levelID }) else {
            return .failure(.unknownCityLevel(city.levelID))
        }
        guard world.buildings.filter({ $0.cityID == cityID }).count < level.buildingSlots else {
            return .failure(.noBuildingSlots(cityID))
        }
        guard economy.canAfford(definition.constructionCost, for: playerID) else { return .failure(.insufficientCoins(required: definition.constructionCost)) }

        var nextWorld = world
        nextWorld.addBuilding(Building(id: BuildingID(rawValue: "\(cityID.rawValue)-\(buildingTypeID.rawValue)"), cityID: cityID, typeID: buildingTypeID))
        var nextEconomy = economy
        nextEconomy.spend(definition.constructionCost, for: playerID, kind: .construction, source: "building:\(cityID.rawValue):\(buildingTypeID.rawValue)")
        return .success(CityConstructionResult(world: nextWorld, economy: nextEconomy))
    }

    public static func upgrade(
        cityID: CityID,
        for playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        cityLevels: [CityLevelDefinition]
    ) -> Result<CityConstructionResult, CityConstructionError> {
        guard world.phase == .construction else { return .failure(.invalidPhase(world.phase)) }
        guard let city = world.cities.first(where: { $0.id == cityID && $0.ownerID == playerID }) else {
            return .failure(.cityNotOwned(cityID))
        }
        // Reported separately: the player does own this city, its level is the
        // thing the content does not describe.
        guard let currentIndex = cityLevels.firstIndex(where: { $0.id == city.levelID }) else {
            return .failure(.unknownCityLevel(city.levelID))
        }
        guard cityLevels.indices.contains(currentIndex + 1) else { return .failure(.noNextLevel(cityID)) }
        let nextLevel = cityLevels[currentIndex + 1]
        let built = Set(world.buildings.filter { $0.cityID == cityID }.map(\.typeID))
        let missing = nextLevel.requiredBuildingIDs.filter { !built.contains($0) }
        guard missing.isEmpty else { return .failure(.unmetRequirements(missing)) }
        guard economy.canAfford(nextLevel.upgradeCost, for: playerID) else { return .failure(.insufficientCoins(required: nextLevel.upgradeCost)) }

        var nextWorld = world
        nextWorld.setCityLevel(nextLevel.id, for: cityID)
        var nextEconomy = economy
        nextEconomy.spend(nextLevel.upgradeCost, for: playerID, kind: .cityUpgrade, source: "city:\(cityID.rawValue):\(nextLevel.id.rawValue)")
        return .success(CityConstructionResult(world: nextWorld, economy: nextEconomy))
    }
}
