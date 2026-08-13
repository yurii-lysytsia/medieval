import Foundation

public struct RecruitmentLedger: Codable, Equatable, Sendable {
    public private(set) var recruitedByCity: [CityID: Int]

    public init(recruitedByCity: [CityID: Int] = [:]) {
        self.recruitedByCity = recruitedByCity
    }

    public func recruited(in cityID: CityID) -> Int {
        recruitedByCity[cityID, default: 0]
    }

    mutating func recordRecruitment(in cityID: CityID) {
        recruitedByCity[cityID, default: 0] += 1
    }
}

public enum RecruitmentError: Error, Equatable, LocalizedError, Sendable {
    case invalidPhase(GamePhase)
    case cityNotOwned(CityID)
    case barracksRequired(CityID)
    case unknownUnitType(UnitTypeID)
    case navalUnitRequiresPort(UnitTypeID)
    case recruitmentLimitReached(CityID, limit: Int)
    case garrisonFull(CityID, limit: Int)
    case insufficientCoins(required: Int)
    case unknownCityLevel(CityLevelID)

    public var errorDescription: String? {
        switch self {
        case let .invalidPhase(phase): "Recruitment is unavailable during \(phase.rawValue)."
        case let .cityNotOwned(cityID): "The active player does not own city \"\(cityID.rawValue)\"."
        case let .barracksRequired(cityID): "City \"\(cityID.rawValue)\" needs barracks before recruiting land units."
        case let .unknownUnitType(typeID): "Unit type \"\(typeID.rawValue)\" is unknown."
        case let .navalUnitRequiresPort(typeID): "Naval unit \"\(typeID.rawValue)\" must be built by a city next to water."
        case let .recruitmentLimitReached(cityID, limit): "City \"\(cityID.rawValue)\" has used its recruitment limit of \(limit)."
        case let .garrisonFull(cityID, limit): "City \"\(cityID.rawValue)\" garrison is full (\(limit))."
        case let .insufficientCoins(required): "Recruitment requires \(required) coins."
        case let .unknownCityLevel(levelID): "City level \"\(levelID.rawValue)\" is not defined by the game content."
        }
    }
}

public struct RecruitmentResult: Equatable, Sendable {
    public let world: WorldState
    public let economy: EconomyState
    public let ledger: RecruitmentLedger
    public let unit: Unit
}

public enum RecruitmentRules {
    public static let maximumUnitsPerLandHex = 6

    public static func recruit(
        unitTypeID: UnitTypeID,
        in cityID: CityID,
        for playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        ledger: RecruitmentLedger,
        map: StaticHexMap,
        units: [UnitDefinition],
        cityLevels: [CityLevelDefinition]
    ) -> Result<RecruitmentResult, RecruitmentError> {
        guard world.phase == .construction else { return .failure(.invalidPhase(world.phase)) }
        guard let city = world.cities.first(where: { $0.id == cityID && $0.ownerID == playerID }) else { return .failure(.cityNotOwned(cityID)) }
        guard let definition = units.first(where: { $0.id == unitTypeID }) else { return .failure(.unknownUnitType(unitTypeID)) }
        // Reported as its own failure: an undefined city level is a broken
        // world, not a city that has already recruited its quota.
        guard let level = cityLevels.first(where: { $0.id == city.levelID }) else { return .failure(.unknownCityLevel(city.levelID)) }
        guard ledger.recruited(in: cityID) < level.recruitmentLimit else { return .failure(.recruitmentLimitReached(cityID, limit: level.recruitmentLimit)) }

        var recruitmentHexID = city.hexID
        if definition.domain == .land {
            guard world.buildings.contains(where: { $0.cityID == cityID && $0.typeID == "barracks" }) else {
                return .failure(.barracksRequired(cityID))
            }
            let garrisonCount = world.units.filter { $0.location == .garrison(cityID) && $0.condition != .destroyed }.count
            guard garrisonCount < level.recruitmentLimit else { return .failure(.garrisonFull(cityID, limit: level.recruitmentLimit)) }
        } else {
            let neighbors = map.neighborhoods.first(where: { $0.hexID == city.hexID })?.neighborHexIDs ?? []
            let waterIDs: Set<TerrainID> = ["shallows", "deep-water"]
            guard let waterHex = world.hexes.first(where: { neighbors.contains($0.id) && waterIDs.contains($0.terrainID) }) else {
                return .failure(.navalUnitRequiresPort(unitTypeID))
            }
            recruitmentHexID = waterHex.id
        }

        guard economy.canAfford(definition.recruitmentCost, for: playerID) else { return .failure(.insufficientCoins(required: definition.recruitmentCost)) }
        var nextWorld = world
        let sequence = nextWorld.reserveUnitNumber()
        let location: UnitLocation = definition.domain == .land ? .garrison(cityID) : .hex(recruitmentHexID)
        let unit = Unit(
            id: UnitID(rawValue: "unit-\(playerID.rawValue)-\(sequence)"),
            ownerID: playerID,
            typeID: unitTypeID,
            currentHitPoints: definition.hitPoints,
            location: location
        )
        nextWorld.addUnit(unit)
        var nextEconomy = economy
        _ = nextEconomy.spend(definition.recruitmentCost, for: playerID, kind: .recruitment, source: "unit:\(unit.id.rawValue)")
        var nextLedger = ledger
        nextLedger.recordRecruitment(in: cityID)
        return .success(RecruitmentResult(world: nextWorld, economy: nextEconomy, ledger: nextLedger, unit: unit))
    }
}
