import Foundation
@testable import MedievalDomain
import Testing

struct RecruitmentRulesTests {
    @Test func successfulRecruitmentSpendsCoinsAndCreatesVisibleGarrisonUnit() throws {
        let result = try RecruitmentRules.recruit(
            unitTypeID: "infantry",
            in: "capital",
            for: "crown",
            world: world(),
            economy: economy(),
            ledger: RecruitmentLedger(),
            map: map,
            units: units,
            cityLevels: levels
        ).get()

        #expect(result.economy.coins(for: "crown") == 80)
        #expect(result.unit.location == .garrison("capital"))
        #expect(result.world.units == [result.unit])
        #expect(result.ledger.recruited(in: "capital") == 1)
    }

    @Test func recruitmentRejectsMissingConditionsWithExplanation() {
        let noBarracks = RecruitmentRules.recruit(unitTypeID: "infantry", in: "capital", for: "crown", world: world(includeBarracks: false), economy: economy(), ledger: RecruitmentLedger(), map: map, units: units, cityLevels: levels)
        let noCoins = RecruitmentRules.recruit(unitTypeID: "infantry", in: "capital", for: "crown", world: world(), economy: EconomyState(players: players, startingGold: 10), ledger: RecruitmentLedger(), map: map, units: units, cityLevels: levels)

        #expect(noBarracks == .failure(.barracksRequired("capital")))
        #expect(noCoins == .failure(.insufficientCoins(required: 20)))
    }

    @Test func recruitmentHonorsPerTurnLimit() throws {
        let first = try RecruitmentRules.recruit(unitTypeID: "infantry", in: "capital", for: "crown", world: world(), economy: economy(), ledger: RecruitmentLedger(), map: map, units: units, cityLevels: levels).get()
        let second = RecruitmentRules.recruit(unitTypeID: "infantry", in: "capital", for: "crown", world: first.world, economy: first.economy, ledger: first.ledger, map: map, units: units, cityLevels: levels)

        #expect(second == .failure(.recruitmentLimitReached("capital", limit: 1)))
    }

    private let players = [WorldPlayer(id: "crown", displayName: "Crown"), WorldPlayer(id: "union", displayName: "Union")]
    private let levels = [CityLevelDefinition(id: "village", displayName: "Village", baseIncome: 4, buildingSlots: 1, recruitmentLimit: 1, upgradeCost: 0)]
    private let units = [UnitDefinition(id: "infantry", displayName: "Infantry", recruitmentCost: 20, upkeep: 2, hitPoints: 10, damage: 4, attackRange: 1, movement: 2, domain: .land)]
    private let map = StaticHexMap(
        id: "map",
        displayName: "Map",
        bounds: HexMapBounds(minimumQ: 0, maximumQ: 0, minimumR: 0, maximumR: 0),
        hexes: [Hex(id: "home", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains", isPassable: true)],
        neighborhoods: [HexNeighborhood(hexID: "home", neighborHexIDs: [])]
    )

    private func economy() -> EconomyState { EconomyState(players: players, startingGold: 100) }

    private func world(includeBarracks: Bool = true) -> WorldState {
        WorldState(
            players: players,
            hexes: map.hexes,
            cities: [City(id: "capital", ownerID: "crown", hexID: "home", levelID: "village", isCapital: true)],
            buildings: includeBarracks ? [Building(id: "capital-barracks", cityID: "capital", typeID: "barracks")] : [],
            phase: .construction
        )
    }
}
