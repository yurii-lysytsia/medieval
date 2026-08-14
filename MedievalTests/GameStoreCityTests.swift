import Foundation
@testable import Medieval
import Testing

@MainActor
struct GameStoreCityTests {
    @Test func buildingAndRecruitingSpendCoinsAndShowUpInTheCity() throws {
        let store = makeStore()

        store.construct("town-hall", in: "capital")
        store.recruit("infantry", in: "capital")

        #expect(store.world.buildings.contains { $0.cityID == "capital" && $0.typeID == "town-hall" })
        #expect(store.economy.coins(for: "crown") == 200 - 45 - 20)
        #expect(store.recruitment.recruited(in: "capital") == 1)
        #expect(store.world.units.contains { $0.location == .garrison("capital") })

        let panel = try #require(cityPanel(store))
        #expect(panel.garrison.map(\.name) == ["Infantry"])
        #expect(panel.usedBuildingSlots == 2)
    }

    @Test func aRefusedActionChangesNothingAndSaysWhy() throws {
        let store = makeStore(startingGold: 10)

        store.construct("town-hall", in: "capital")

        #expect(store.world.buildings.filter { $0.cityID == "capital" }.count == 1)
        #expect(store.economy.coins(for: "crown") == 10)
        #expect(store.criticalNotice?.text == "Потрібно 45 монет")
    }

    @Test func recruitmentStopsAtTheCityLimitForTheTurn() {
        let store = makeStore()

        store.recruit("infantry", in: "capital")
        store.recruit("infantry", in: "capital")

        #expect(store.recruitment.recruited(in: "capital") == 1)
        #expect(store.criticalNotice?.text == "Ліміт найму за хід: 1")
    }

    @Test func upgradingRaisesTheCityLevelOnceItsRequirementsAreMet() throws {
        let store = makeStore()

        store.upgradeCity("capital")
        #expect(store.world.cities.first?.levelID == "village")

        store.construct("town-hall", in: "capital")
        store.upgradeCity("capital")

        #expect(store.world.cities.first?.levelID == "town")
        #expect(store.economy.coins(for: "crown") == 200 - 45 - 100)
    }

    @Test func theRecruitmentTallySurvivesSaveAndLoad() throws {
        let catalog = InMemorySaveCatalog()
        let store = makeStore(catalog: catalog)
        store.recruit("infantry", in: "capital")
        #expect(store.createManualSave(named: "Після найму"))
        let id = try #require(store.saves.first?.id)

        let reopened = makeStore(catalog: catalog)
        #expect(reopened.recruitment.recruited(in: "capital") == 0)
        #expect(reopened.loadSave(id))

        #expect(reopened.recruitment.recruited(in: "capital") == 1)
    }

    /// A quota belongs to a turn, and a turn belongs to a player: the tally is
    /// released when its owner's next turn begins, not when the round moves on
    /// to somebody else.
    @Test func theTallyIsClearedWhenTheOwnersTurnComesRound() {
        let store = makeStore()
        store.recruit("infantry", in: "capital")

        store.advancePhase() // movement
        store.advancePhase() // combat
        store.endTurn()
        #expect(store.recruitment.recruited(in: "capital") == 1)

        store.confirmHandoff() // the opponent's turn starts
        #expect(store.recruitment.recruited(in: "capital") == 1)

        store.advancePhase()
        store.advancePhase()
        store.advancePhase()
        store.endTurn()
        store.confirmHandoff() // back to the city's owner

        #expect(store.recruitment.recruited(in: "capital") == 0)
    }

    private func cityPanel(_ store: GameStore) -> CityManagement? {
        CityManagement.inspect(
            cityID: "capital",
            activePlayerID: "crown",
            world: store.world,
            economy: store.economy,
            ledger: store.recruitment,
            map: store.content.scenario.map,
            content: store.content
        )
    }

    private func makeStore(startingGold: Int = 200, catalog: any GameSaveCatalog = InMemorySaveCatalog()) -> GameStore {
        GameStore(
            state: GameState(
                players: [
                    Player(displayName: "Корона", worldPlayerID: "crown", color: .red),
                    Player(displayName: "Союз", worldPlayerID: "union", color: .blue),
                ],
                phase: .construction
            ),
            content: content(startingGold: startingGold),
            saveCatalog: catalog
        )
    }

    private let players = [WorldPlayer(id: "crown", displayName: "Корона"), WorldPlayer(id: "union", displayName: "Союз")]

    private var hexes: [Hex] {
        [
            Hex(id: "home", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"),
            Hex(id: "away", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "plains"),
        ]
    }

    private var map: StaticHexMap {
        StaticHexMap(
            id: "map",
            displayName: "Map",
            bounds: HexMapBounds(minimumQ: 0, maximumQ: 1, minimumR: 0, maximumR: 0),
            hexes: hexes,
            neighborhoods: [
                HexNeighborhood(hexID: "home", neighborHexIDs: ["away"]),
                HexNeighborhood(hexID: "away", neighborHexIDs: ["home"]),
            ]
        )
    }

    private func content(startingGold: Int) -> GameContentConfiguration {
        GameContentConfiguration(
            terrain: [TerrainDefinition(id: "plains", displayName: "Plains", domain: .land, movementCost: 1, defenseModifier: 0, incomeModifier: 2, isPassable: true, isCityBuildable: true)],
            units: [UnitDefinition(id: "infantry", displayName: "Infantry", recruitmentCost: 20, upkeep: 2, hitPoints: 10, damage: 4, attackRange: 1, movement: 2, domain: .land)],
            cityLevels: [
                CityLevelDefinition(id: "village", displayName: "Village", baseIncome: 4, buildingSlots: 2, recruitmentLimit: 1, upgradeCost: 0),
                CityLevelDefinition(id: "town", displayName: "Town", baseIncome: 8, buildingSlots: 4, recruitmentLimit: 2, upgradeCost: 100, requiredBuildingIDs: ["town-hall"]),
            ],
            buildings: [
                BuildingDefinition(id: "town-hall", displayName: "Town Hall", constructionCost: 45, upkeep: 1, incomeModifier: 1, defenseModifier: 0),
                BuildingDefinition(id: "barracks", displayName: "Barracks", constructionCost: 75, upkeep: 2, incomeModifier: 0, defenseModifier: 1),
            ],
            scenario: ScenarioConfiguration(
                id: "test",
                displayName: "Test",
                startingGold: startingGold,
                map: map,
                world: WorldState(
                    players: players,
                    hexes: hexes,
                    cities: [
                        City(id: "capital", ownerID: "crown", hexID: "home", levelID: "village", isCapital: true),
                        City(id: "rival", ownerID: "union", hexID: "away", levelID: "village", isCapital: true),
                    ],
                    buildings: [Building(id: "capital-barracks", cityID: "capital", typeID: "barracks")],
                    phase: .construction
                )
            )
        )
    }
}
