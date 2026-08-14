import Foundation
@testable import Medieval
import Testing

struct CityConstructionRulesTests {
    @Test func buildingSpendsCoinsAndAppliesItsConfiguredEffect() throws {
        let result = try CityConstructionRules.construct(buildingTypeID: "town-hall", in: "capital", for: "crown", world: world(), economy: economy(), cityLevels: levels, buildings: buildings).get()

        #expect(result.economy.coins(for: "crown") == 55)
        #expect(result.world.buildings.map(\.typeID) == ["town-hall"])
        #expect(result.economy.journal.last?.kind == .construction)
    }

    @Test func unavailableConstructionLeavesStateUnchanged() {
        let blockedWorld = WorldState(players: players, hexes: [], cities: [City(id: "capital", ownerID: "crown", hexID: "home", levelID: "village", isCapital: true)], phase: .economy)
        let result = CityConstructionRules.construct(buildingTypeID: "town-hall", in: "capital", for: "crown", world: blockedWorld, economy: economy(), cityLevels: levels, buildings: buildings)

        #expect(result == .failure(.invalidPhase(.economy)))
        #expect(CityConstructionRules.construct(buildingTypeID: "market", in: "capital", for: "crown", world: world(), economy: EconomyState(players: players, startingGold: 10), cityLevels: levels, buildings: buildings) == .failure(.insufficientCoins(required: 60)))
    }

    @Test func cityUpgradeRequiresConfiguredBuildingsAndCoins() throws {
        let missing = CityConstructionRules.upgrade(cityID: "capital", for: "crown", world: world(), economy: economy(), cityLevels: levels)
        #expect(missing == .failure(.unmetRequirements(["town-hall"])))

        let built = try CityConstructionRules.construct(buildingTypeID: "town-hall", in: "capital", for: "crown", world: world(), economy: richEconomy(), cityLevels: levels, buildings: buildings).get()
        let upgraded = try CityConstructionRules.upgrade(cityID: "capital", for: "crown", world: built.world, economy: built.economy, cityLevels: levels).get()

        #expect(upgraded.world.cities.first?.levelID == "town")
        #expect(upgraded.economy.coins(for: "crown") == 0)
        #expect(upgraded.economy.journal.last?.kind == .cityUpgrade)
    }

    /// The way out of a city whose only slot holds the wrong building: the
    /// upgrade needs a town hall, and without demolition that match is over.
    @Test func demolishingFreesTheSlotWithoutRefunding() throws {
        let filled = try CityConstructionRules.construct(buildingTypeID: "market", in: "capital", for: "crown", world: world(), economy: richEconomy(), cityLevels: levels, buildings: buildings).get()
        #expect(CityConstructionRules.construct(buildingTypeID: "town-hall", in: "capital", for: "crown", world: filled.world, economy: filled.economy, cityLevels: levels, buildings: buildings) == .failure(.noBuildingSlots("capital")))

        let cleared = try CityConstructionRules.demolish(buildingTypeID: "market", in: "capital", for: "crown", world: filled.world).get()
        #expect(cleared.buildings.isEmpty)

        let rebuilt = try CityConstructionRules.construct(buildingTypeID: "town-hall", in: "capital", for: "crown", world: cleared, economy: filled.economy, cityLevels: levels, buildings: buildings).get()
        #expect(rebuilt.world.buildings.map(\.typeID) == ["town-hall"])
        // 145 − 60 for the market − 45 for the town hall: nothing came back
        // when the market went down.
        #expect(rebuilt.economy.coins(for: "crown") == 40)
    }

    @Test func demolitionIsRefusedOutsideTheConstructionPhaseAndForOthersCities() throws {
        let built = try CityConstructionRules.construct(buildingTypeID: "market", in: "capital", for: "crown", world: world(), economy: economy(), cityLevels: levels, buildings: buildings).get()
        var moving = built.world
        moving.setPhase(.movement)

        #expect(CityConstructionRules.demolish(buildingTypeID: "market", in: "capital", for: "crown", world: moving) == .failure(.invalidPhase(.movement)))
        #expect(CityConstructionRules.demolish(buildingTypeID: "market", in: "capital", for: "union", world: built.world) == .failure(.cityNotOwned("capital")))
        #expect(CityConstructionRules.demolish(buildingTypeID: "town-hall", in: "capital", for: "crown", world: built.world) == .failure(.notBuilt("town-hall")))
    }

    private let players = [WorldPlayer(id: "crown", displayName: "Crown"), WorldPlayer(id: "union", displayName: "Union")]
    private let levels = [
        CityLevelDefinition(id: "village", displayName: "Village", baseIncome: 4, buildingSlots: 1, upgradeCost: 0),
        CityLevelDefinition(id: "town", displayName: "Town", baseIncome: 8, buildingSlots: 4, upgradeCost: 100, requiredBuildingIDs: ["town-hall"]),
    ]
    private let buildings = [
        BuildingDefinition(id: "town-hall", displayName: "Town Hall", constructionCost: 45, upkeep: 1, incomeModifier: 1, defenseModifier: 0),
        BuildingDefinition(id: "market", displayName: "Market", constructionCost: 60, upkeep: 1, incomeModifier: 3, defenseModifier: 0),
    ]

    private func economy() -> EconomyState { EconomyState(players: players, startingGold: 100) }

    private func richEconomy() -> EconomyState { EconomyState(players: players, startingGold: 145) }

    private func world() -> WorldState {
        WorldState(players: players, hexes: [Hex(id: "home", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains")], cities: [City(id: "capital", ownerID: "crown", hexID: "home", levelID: "village", isCapital: true)], phase: .construction)
    }
}
