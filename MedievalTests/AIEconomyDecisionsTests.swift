import Foundation
@testable import Medieval
import Testing

struct AIEconomyDecisionsTests {
    @Test func aPhaseOfSpendingNeverOutrunsTheTreasury() throws {
        // Every purchase is planned against the balance the previous one would
        // leave, so the opponent cannot plan three things it can afford one of.
        let steps = steps(gold: 150)
        var world = world()
        var economy = EconomyState(players: worldPlayers, startingGold: 150)
        var ledger = RecruitmentLedger()

        for step in steps {
            switch step.intent {
            case let .construct(buildingTypeID, cityID):
                let result = try CityConstructionRules.construct(buildingTypeID: buildingTypeID, in: cityID, for: "ai", world: world, economy: economy, cityLevels: cityLevels, buildings: buildings).get()
                world = result.world
                economy = result.economy
            case let .upgradeCity(cityID):
                let result = try CityConstructionRules.upgrade(cityID: cityID, for: "ai", world: world, economy: economy, cityLevels: cityLevels).get()
                world = result.world
                economy = result.economy
            case let .recruit(unitTypeID, cityID):
                let result = try RecruitmentRules.recruit(unitTypeID: unitTypeID, in: cityID, for: "ai", world: world, economy: economy, ledger: ledger, map: map, terrain: terrain, units: units, cityLevels: cityLevels).get()
                world = result.world
                economy = result.economy
                ledger = result.ledger
            default:
                Issue.record("construction planned \(step.intent)")
            }
            #expect((economy.coins(for: "ai") ?? -1) >= 0)
        }
        #expect(!steps.isEmpty)
    }

    @Test func aVillageBuildsWhatItNeedsToGrowBeforeWhatPaysMost() {
        // A village has one building slot. The market pays three times what the
        // town hall does, but the town hall is what "town" requires — spending
        // the only slot on the market walls the city in at its starting size.
        let steps = steps(gold: 150)

        #expect(steps.first?.intent == .construct(buildingTypeID: "town-hall", cityID: "ai-capital"))
        #expect(steps.first?.priority == .income)
    }

    @Test func aThreatenedCapitalFortifiesBeforeItGrows() {
        // Walls bought a turn late are walls bought after the capital fell.
        let threatened = steps(gold: 300, enemyAt: "hex-1")

        #expect(threatened.first?.priority == .capitalSurvival)
        #expect(threatened.first?.intent == .construct(buildingTypeID: "walls", cityID: "ai-capital"))
    }

    @Test func theThreatRangeHasAnEdgeAndItIsMeasuredInMovement() {
        // A corridor of plains, one movement each: the army at the far end sits
        // just past the range and does not turn the turn into a defensive one.
        #expect(AIEconomyDecisions.isCapitalThreatened(for: "ai", world: world(enemyAt: "hex-6"), content: content(gold: 300, world: world(enemyAt: "hex-6"))))
        #expect(!AIEconomyDecisions.isCapitalThreatened(for: "ai", world: world(enemyAt: "hex-7"), content: content(gold: 300, world: world(enemyAt: "hex-7"))))

        let calm = steps(gold: 300, enemyAt: "hex-7")
        #expect(calm.first?.priority == .income)
    }

    @Test func nothingAffordableMeansNoStepsRatherThanIllegalOnes() {
        // Ten coins buys nothing here. The phase still ends — the planner adds
        // the step that leaves it — but no purchase is invented.
        #expect(steps(gold: 10).isEmpty)
    }

    @Test func recruitmentWaitsForBarracksAndThenPicksTheSturdiestUnit() throws {
        // Recruitment needs barracks, so a village without them cannot recruit
        // at all; the rule says so and the planner does not argue.
        let withoutBarracks = steps(gold: 500)
        #expect(!withoutBarracks.contains { if case .recruit = $0.intent { true } else { false } })

        let garrisoned = steps(gold: 500, buildings: [Building(id: "b", cityID: "ai-capital", typeID: "barracks")], level: "town")
        let recruited = try #require(garrisoned.first { if case .recruit = $0.intent { true } else { false } })

        #expect(recruited.intent == .recruit(unitTypeID: "knights", cityID: "ai-capital"))
        #expect(recruited.priority == .recruitment)
    }

    @Test func planningStopsWhenThereIsNothingLeftToBuy() {
        // With money for everything, the loop still has to end: the rules run
        // out of slots, levels and recruitment allowance.
        let rich = steps(gold: 100_000)

        #expect(rich.count < AIEconomyDecisions.maximumSteps)
    }

    // MARK: - Fixture

    private let worldPlayers = [WorldPlayer(id: "ai", displayName: "ШІ"), WorldPlayer(id: "rival", displayName: "Суперник")]
    private let terrain = [
        TerrainDefinition(id: "plains", displayName: "Plains", domain: .land, movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: true),
    ]
    private let buildings = [
        BuildingDefinition(id: "town-hall", displayName: "Town Hall", constructionCost: 45, upkeep: 1, incomeModifier: 1, defenseModifier: 0),
        BuildingDefinition(id: "market", displayName: "Market", constructionCost: 60, upkeep: 1, incomeModifier: 3, defenseModifier: 0),
        BuildingDefinition(id: "barracks", displayName: "Barracks", constructionCost: 75, upkeep: 2, incomeModifier: 0, defenseModifier: 1),
        BuildingDefinition(id: "walls", displayName: "Walls", constructionCost: 100, upkeep: 1, incomeModifier: 0, defenseModifier: 4),
    ]
    private let cityLevels = [
        CityLevelDefinition(id: "village", displayName: "Village", baseIncome: 4, buildingSlots: 1, recruitmentLimit: 1, upgradeCost: 0, requiredBuildingIDs: []),
        CityLevelDefinition(id: "town", displayName: "Town", baseIncome: 8, buildingSlots: 4, recruitmentLimit: 2, upgradeCost: 100, requiredBuildingIDs: ["town-hall"]),
    ]
    private let units = [
        UnitDefinition(id: "infantry", displayName: "Infantry", recruitmentCost: 20, upkeep: 2, hitPoints: 10, damage: 4, attackRange: 1, movement: 2, domain: .land),
        UnitDefinition(id: "knights", displayName: "Knights", recruitmentCost: 40, upkeep: 3, hitPoints: 14, damage: 6, attackRange: 1, movement: 3, domain: .land),
        UnitDefinition(id: "ship", displayName: "Ship", recruitmentCost: 30, upkeep: 2, hitPoints: 30, damage: 2, attackRange: 1, movement: 4, domain: .navalTransport, cargoCapacity: 2),
    ]

    /// A straight corridor of plains: entering each costs one, so the hex
    /// number is also its distance from the capital at "home".
    private var hexes: [Hex] {
        [Hex(id: "home", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains")]
            + (1 ... 8).map { Hex(id: HexID(rawValue: "hex-\($0)"), coordinate: HexCoordinate(q: $0, r: 0), terrainID: "plains") }
    }

    private var map: StaticHexMap {
        StaticHexMap(
            id: "fixture",
            displayName: "Fixture",
            bounds: HexMapBounds(minimumQ: 0, maximumQ: 8, minimumR: 0, maximumR: 0),
            hexes: hexes,
            neighborhoods: hexes.enumerated().map { index, hex in
                let previous = index > 0 ? [hexes[index - 1].id] : []
                let next = index + 1 < hexes.count ? [hexes[index + 1].id] : []
                return HexNeighborhood(hexID: hex.id, neighborHexIDs: previous + next)
            }
        )
    }

    private func world(enemyAt hexID: HexID? = nil, buildings: [Building] = [], level: CityLevelID = "village") -> WorldState {
        WorldState(
            players: worldPlayers,
            hexes: hexes,
            units: hexID.map { [Unit(id: "rival-unit", ownerID: "rival", typeID: "infantry", currentHitPoints: 10, location: .hex($0))] } ?? [],
            armies: hexID.map { [Army(id: "rival-army", ownerID: "rival", hexID: $0, unitIDs: ["rival-unit"])] } ?? [],
            cities: [City(id: "ai-capital", ownerID: "ai", hexID: "home", levelID: level, isCapital: true)],
            buildings: buildings,
            phase: .construction
        )
    }

    private func steps(gold: Int, enemyAt hexID: HexID? = nil, buildings: [Building] = [], level: CityLevelID = "village") -> [AIStep] {
        let world = world(enemyAt: hexID, buildings: buildings, level: level)
        return AIEconomyDecisions.steps(
            for: "ai",
            world: world,
            economy: EconomyState(players: worldPlayers, startingGold: gold),
            content: content(gold: gold, world: world)
        )
    }

    private func content(gold: Int, world: WorldState) -> GameContentConfiguration {
        GameContentConfiguration(
            terrain: terrain,
            units: units,
            cityLevels: cityLevels,
            buildings: buildings,
            scenario: ScenarioConfiguration(id: "fixture", displayName: "Fixture", startingGold: gold, map: map, world: world)
        )
    }
}
