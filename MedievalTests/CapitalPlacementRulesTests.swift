import Foundation
@testable import Medieval
import Testing

struct CapitalPlacementRulesTests {
    @Test func everyPlayerPlacesOneCapitalBeforeEconomyBegins() throws {
        let initial = world()
        let afterFirst = try CapitalPlacementRules.placeCapital(for: "one", at: "plains", in: initial, terrain: terrain, cityLevels: cityLevels).get()
        let afterSecond = try CapitalPlacementRules.placeCapital(for: "two", at: "forest", in: afterFirst, terrain: terrain, cityLevels: cityLevels).get()

        #expect(afterFirst.phase == .capitalPlacement)
        #expect(afterSecond.phase == .economy)
        #expect(afterSecond.cities.map(\.isCapital).allSatisfy { $0 })
        #expect(afterSecond.cities.map(\.ownerID) == ["one", "two"])
    }

    @Test func unsuitableAndOccupiedHexesExplainWhyPlacementFails() throws {
        let initial = world()
        let afterFirst = try CapitalPlacementRules.placeCapital(for: "one", at: "plains", in: initial, terrain: terrain, cityLevels: cityLevels).get()

        let occupied = CapitalPlacementRules.placeCapital(for: "two", at: "plains", in: afterFirst, terrain: terrain, cityLevels: cityLevels)
        let unsuitable = CapitalPlacementRules.placeCapital(for: "two", at: "mountain", in: afterFirst, terrain: terrain, cityLevels: cityLevels)

        #expect(occupied == .failure(.occupiedHex("plains")))
        #expect(unsuitable == .failure(.unsuitableTerrain("mountain", "mountains")))
    }

    @Test func capitalCannotBePlacedTwiceOrOutsidePlacementPhase() throws {
        let initial = world()
        let afterFirst = try CapitalPlacementRules.placeCapital(for: "one", at: "plains", in: initial, terrain: terrain, cityLevels: cityLevels).get()

        #expect(CapitalPlacementRules.placeCapital(for: "one", at: "forest", in: afterFirst, terrain: terrain, cityLevels: cityLevels) == .failure(.capitalAlreadyPlaced("one")))

        let completed = try CapitalPlacementRules.placeCapital(for: "two", at: "forest", in: afterFirst, terrain: terrain, cityLevels: cityLevels).get()
        #expect(CapitalPlacementRules.placeCapital(for: "one", at: "mountain", in: completed, terrain: terrain, cityLevels: cityLevels) == .failure(.invalidPhase(.economy)))
    }

    @Test func capitalCannotUseACityLevelTheContentDoesNotDefine() {
        // Content validation only sees what was loaded from the file, so a city
        // added mid-match has to check its own references.
        let result = CapitalPlacementRules.placeCapital(
            for: "one",
            at: "plains",
            in: world(),
            terrain: terrain,
            cityLevels: cityLevels,
            initialLevelID: "metropolis"
        )

        #expect(result == .failure(.unknownCityLevel("metropolis")))
    }

    private let cityLevels = [
        CityLevelDefinition(id: "village", displayName: "Village", baseIncome: 1, buildingSlots: 1),
    ]

    private let terrain = [
        TerrainDefinition(id: "plains", displayName: "Plains", movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: true),
        TerrainDefinition(id: "forest", displayName: "Forest", movementCost: 2, defenseModifier: 1, incomeModifier: 0, isPassable: true, isCityBuildable: true),
        TerrainDefinition(id: "mountains", displayName: "Mountains", movementCost: 3, defenseModifier: 2, incomeModifier: 0, isPassable: true, isCityBuildable: false),
    ]

    private func world() -> WorldState {
        WorldState(
            players: [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")],
            hexes: [
                Hex(id: "plains", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"),
                Hex(id: "forest", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "forest"),
                Hex(id: "mountain", coordinate: HexCoordinate(q: 0, r: 1), terrainID: "mountains"),
            ],
            phase: .capitalPlacement
        )
    }
}
