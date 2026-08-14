import Foundation

/// One thing the player can buy in a city, already priced and already judged.
///
/// `disabledReason` is filled in from the rules themselves rather than from a
/// second opinion written in the interface: the panel asks the domain what
/// would happen and reports the answer, so an offer on screen and the action
/// behind it can never disagree.
public struct CityActionOption: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let cost: Int
    /// The upkeep and modifiers, phrased for the panel.
    public let detail: String
    public let disabledReason: String?

    public var isEnabled: Bool { disabledReason == nil }
}

/// Everything the city panel shows and offers for one city.
public struct CityManagement: Equatable, Sendable {
    public let cityID: CityID
    public let name: String
    public let levelName: String
    public let isCapital: Bool
    /// Whether the player whose turn it is holds this city. A city belonging to
    /// somebody else is described, never acted on.
    public let isCommandable: Bool
    public let coins: Int
    public let income: Int?
    public let usedBuildingSlots: Int
    public let buildingSlots: Int
    public let recruitedThisTurn: Int
    public let recruitmentLimit: Int
    public let built: [String]
    public let garrison: [UnitInspection]
    public let buildings: [CityActionOption]
    public let upgrade: CityActionOption?
    public let recruits: [CityActionOption]

    public static func inspect(
        cityID: CityID,
        activePlayerID: WorldPlayerID?,
        world: WorldState,
        economy: EconomyState,
        ledger: RecruitmentLedger,
        map: StaticHexMap,
        content: GameContentConfiguration
    ) -> CityManagement? {
        guard let city = world.cities.first(where: { $0.id == cityID }),
              let hex = world.hexes.first(where: { $0.id == city.hexID }),
              let terrain = content.terrain.first(where: { $0.id == hex.terrainID })
        else { return nil }

        let level = content.cityLevels.first(where: { $0.id == city.levelID })
        let built = world.buildings.filter { $0.cityID == cityID }
        let builtDefinitions = built.compactMap { building in
            content.buildings.first(where: { $0.id == building.typeID })
        }
        let isCommandable = activePlayerID != nil && city.ownerID == activePlayerID
        let garrison = world.units
            .filter { $0.location == .garrison(cityID) && $0.condition != .destroyed }
            .map { unit in
                UnitInspection(
                    id: unit.id,
                    name: content.units.first(where: { $0.id == unit.typeID })?.displayName ?? unit.typeID.rawValue,
                    hitPoints: unit.currentHitPoints
                )
            }

        // Only the player holding the city is offered anything: for anyone else
        // every rule would fail on ownership, and a list of identical refusals
        // is noise.
        let buildings: [CityActionOption]
        let upgrade: CityActionOption?
        let recruits: [CityActionOption]
        if isCommandable, let playerID = activePlayerID {
            let builtIDs = Set(built.map(\.typeID))
            buildings = content.buildings
                .filter { !builtIDs.contains($0.id) }
                .map { definition in
                    CityActionOption(
                        id: definition.id.rawValue,
                        name: definition.displayName,
                        cost: definition.constructionCost,
                        detail: buildingDetail(definition),
                        disabledReason: constructionReason(
                            buildingTypeID: definition.id,
                            cityID: cityID,
                            playerID: playerID,
                            world: world,
                            economy: economy,
                            content: content
                        )
                    )
                }
            upgrade = upgradeOption(
                city: city,
                playerID: playerID,
                world: world,
                economy: economy,
                content: content
            )
            recruits = content.units.map { definition in
                CityActionOption(
                    id: definition.id.rawValue,
                    name: definition.displayName,
                    cost: definition.recruitmentCost,
                    detail: recruitDetail(definition),
                    disabledReason: recruitmentReason(
                        unitTypeID: definition.id,
                        cityID: cityID,
                        playerID: playerID,
                        world: world,
                        economy: economy,
                        ledger: ledger,
                        map: map,
                        content: content
                    )
                )
            }
        } else {
            buildings = []
            upgrade = nil
            recruits = []
        }

        return CityManagement(
            cityID: cityID,
            name: city.id.rawValue,
            levelName: level?.displayName ?? city.levelID.rawValue,
            isCapital: city.isCapital,
            isCommandable: isCommandable,
            coins: activePlayerID.flatMap(economy.coins) ?? 0,
            income: level.map { $0.baseIncome + terrain.incomeModifier + builtDefinitions.map(\.incomeModifier).reduce(0, +) },
            usedBuildingSlots: built.count,
            buildingSlots: level?.buildingSlots ?? 0,
            recruitedThisTurn: ledger.recruited(in: cityID),
            recruitmentLimit: level?.recruitmentLimit ?? 0,
            built: builtDefinitions.map(\.displayName),
            garrison: garrison,
            buildings: buildings,
            upgrade: upgrade,
            recruits: recruits
        )
    }

    private static func upgradeOption(
        city: City,
        playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        content: GameContentConfiguration
    ) -> CityActionOption? {
        guard let currentIndex = content.cityLevels.firstIndex(where: { $0.id == city.levelID }),
              content.cityLevels.indices.contains(currentIndex + 1)
        else { return nil }
        let next = content.cityLevels[currentIndex + 1]
        let result = CityConstructionRules.upgrade(
            cityID: city.id,
            for: playerID,
            world: world,
            economy: economy,
            cityLevels: content.cityLevels
        )
        let disabledReason: String? = switch result {
        case .success: nil
        case let .failure(error): RuleWording.text(for: error, content: content)
        }
        return CityActionOption(
            id: next.id.rawValue,
            name: next.displayName,
            cost: next.upgradeCost,
            detail: "дохід \(next.baseIncome) · слотів \(next.buildingSlots) · найм \(next.recruitmentLimit)",
            disabledReason: disabledReason
        )
    }

    private static func constructionReason(
        buildingTypeID: BuildingTypeID,
        cityID: CityID,
        playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        content: GameContentConfiguration
    ) -> String? {
        let result = CityConstructionRules.construct(
            buildingTypeID: buildingTypeID,
            in: cityID,
            for: playerID,
            world: world,
            economy: economy,
            cityLevels: content.cityLevels,
            buildings: content.buildings
        )
        return switch result {
        case .success: nil
        case let .failure(error): RuleWording.text(for: error, content: content)
        }
    }

    private static func recruitmentReason(
        unitTypeID: UnitTypeID,
        cityID: CityID,
        playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        ledger: RecruitmentLedger,
        map: StaticHexMap,
        content: GameContentConfiguration
    ) -> String? {
        let result = RecruitmentRules.recruit(
            unitTypeID: unitTypeID,
            in: cityID,
            for: playerID,
            world: world,
            economy: economy,
            ledger: ledger,
            map: map,
            terrain: content.terrain,
            units: content.units,
            cityLevels: content.cityLevels
        )
        return switch result {
        case .success: nil
        case let .failure(error): RuleWording.text(for: error, content: content)
        }
    }

    private static func buildingDetail(_ definition: BuildingDefinition) -> String {
        "утримання \(definition.upkeep) · дохід \(signed(definition.incomeModifier)) · захист \(signed(definition.defenseModifier))"
    }

    private static func recruitDetail(_ definition: UnitDefinition) -> String {
        "утримання \(definition.upkeep) · HP \(definition.hitPoints) · шкода \(definition.damage) · рух \(definition.movement)"
    }

    private static func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }
}
