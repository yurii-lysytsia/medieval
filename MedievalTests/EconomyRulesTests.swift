import Foundation
@testable import Medieval
import Testing

struct EconomyRulesTests {
    @Test func economyAppliesCityIncomeAndPermanentCostsWithJournal() throws {
        let world = WorldState(
            players: players,
            hexes: [Hex(id: "home", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains")],
            armies: [Army(id: "army", ownerID: "crown", hexID: "home", unitTypeID: "spearmen", quantity: 2)],
            cities: [City(id: "capital", ownerID: "crown", hexID: "home", levelID: "town", isCapital: true)],
            buildings: [Building(id: "market", cityID: "capital", typeID: "market")],
            phase: .economy
        )
        let economy = EconomyState(players: players, startingGold: 10)

        let resolution = try EconomyRules.resolve(
            for: "crown",
            in: world,
            economy: economy,
            terrain: [TerrainDefinition(id: "plains", displayName: "Plains", movementCost: 1, defenseModifier: 0, incomeModifier: 2, isPassable: true, isCityBuildable: true)],
            cityLevels: [CityLevelDefinition(id: "town", displayName: "Town", baseIncome: 8, buildingSlots: 2)],
            units: [UnitDefinition(id: "spearmen", displayName: "Spearmen", recruitmentCost: 1, upkeep: 1, attack: 1, defense: 1, movement: 1)],
            buildings: [BuildingDefinition(id: "market", displayName: "Market", constructionCost: 1, upkeep: 1, incomeModifier: 3, defenseModifier: 0)]
        ).get()

        #expect(resolution.economy.coins(for: "crown") == 20)
        #expect(resolution.entries.map(\.amount) == [10, 3, -1, -2])
        #expect(resolution.economy.journal == resolution.entries)
        #expect(resolution.world.phase == .construction)
    }

    @Test func economyCannotResolveOutsideItsPhaseAndAffordabilityIsExplicit() {
        let world = WorldState(players: players, hexes: [], phase: .construction)
        let economy = EconomyState(players: players, startingGold: 5)

        let result = EconomyRules.resolve(for: "crown", in: world, economy: economy, terrain: [], cityLevels: [], units: [], buildings: [])

        #expect(result == .failure(.invalidPhase(.construction)))
        #expect(economy.canAfford(5, for: "crown"))
        #expect(!economy.canAfford(6, for: "crown"))
    }

    @Test func repeatedResolutionsProduceDistinctJournalEntries() throws {
        // Player, kind and source repeat every turn the same city pays out, so
        // identity has to come from somewhere else.
        let terrain = [TerrainDefinition(id: "plains", displayName: "Plains", movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: true)]
        let cityLevels = [CityLevelDefinition(id: "village", displayName: "Village", baseIncome: 4, buildingSlots: 1)]
        let hexes = [Hex(id: "home", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains")]
        let cities = [City(id: "capital", ownerID: "crown", hexID: "home", levelID: "village", isCapital: true)]
        var economy = EconomyState(players: players, startingGold: 0)

        for _ in 0 ..< 3 {
            let world = WorldState(players: players, hexes: hexes, cities: cities, phase: .economy)
            economy = try EconomyRules.resolve(
                for: "crown",
                in: world,
                economy: economy,
                terrain: terrain,
                cityLevels: cityLevels,
                units: [],
                buildings: []
            ).get().economy
        }

        #expect(economy.journal.count == 3)
        #expect(Set(economy.journal.map(\.id)).count == 3)
    }

    private let players = [WorldPlayer(id: "crown", displayName: "Crown"), WorldPlayer(id: "union", displayName: "Union")]
}
