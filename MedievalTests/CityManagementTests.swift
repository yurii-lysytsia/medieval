import Foundation
@testable import Medieval
import Testing

struct CityManagementTests {
    @Test func describesTheCityAndPricesEveryOffer() throws {
        let panel = try #require(management())

        #expect(panel.levelName == "Village")
        #expect(panel.isCapital)
        #expect(panel.isCommandable)
        #expect(panel.coins == 100)
        // Village income 4, plains +2, and the barracks that is already up.
        #expect(panel.income == 6)
        #expect(panel.usedBuildingSlots == 1)
        #expect(panel.buildingSlots == 2)
        #expect(panel.built == ["Barracks"])
        #expect(panel.recruitedThisTurn == 0)
        #expect(panel.recruitmentLimit == 1)
        #expect(panel.buildings.map(\.name) == ["Town Hall"])
        #expect(panel.buildings.first?.cost == 45)
        #expect(panel.recruits.map(\.name) == ["Infantry", "Ship"])
    }

    /// The panel refuses exactly what the rules refuse: it asks them, rather
    /// than keeping a second copy of the conditions in the interface.
    @Test func disablesAnOfferForTheReasonTheRulesGive() throws {
        let poor = try #require(management(economy: EconomyState(players: players, startingGold: 10)))

        let townHall = try #require(poor.buildings.first { $0.name == "Town Hall" })
        #expect(!townHall.isEnabled)
        #expect(townHall.disabledReason == "Потрібно 45 монет")

        let upgrade = try #require(poor.upgrade)
        #expect(!upgrade.isEnabled)
        #expect(upgrade.disabledReason == "Потрібно: Town Hall")
    }

    @Test func offersNothingWhenTheCityIsNotTheActivePlayers() throws {
        let panel = try #require(management(activePlayerID: "union"))

        #expect(!panel.isCommandable)
        #expect(panel.buildings.isEmpty)
        #expect(panel.recruits.isEmpty)
        #expect(panel.upgrade == nil)
        // Still described, though: an opponent's city is worth reading.
        #expect(panel.levelName == "Village")
    }

    @Test func offersNothingOutsideTheConstructionPhase() throws {
        let panel = try #require(management(phase: .movement))

        #expect(panel.buildings.allSatisfy { $0.disabledReason == "Лише у фазі будівництва" })
        #expect(panel.recruits.allSatisfy { $0.disabledReason == "Лише у фазі найму" })
    }

    @Test func showsTheGarrisonAndTheRecruitmentAlreadySpent() throws {
        let recruited = try RecruitmentRules.recruit(
            unitTypeID: "infantry",
            in: "capital",
            for: "crown",
            world: world(),
            economy: EconomyState(players: players, startingGold: 100),
            ledger: RecruitmentLedger(),
            map: map,
            terrain: content.terrain,
            units: content.units,
            cityLevels: content.cityLevels
        ).get()

        let panel = try #require(
            CityManagement.inspect(
                cityID: "capital",
                activePlayerID: "crown",
                world: recruited.world,
                economy: recruited.economy,
                ledger: recruited.ledger,
                map: map,
                content: content
            )
        )

        #expect(panel.garrison.map(\.name) == ["Infantry"])
        #expect(panel.recruitedThisTurn == 1)
        let infantry = try #require(panel.recruits.first { $0.name == "Infantry" })
        #expect(infantry.disabledReason == "Ліміт найму за хід: 1")
    }

    /// A land-locked city cannot lay down a hull, and says so instead of
    /// hiding the option.
    @Test func explainsWhyAShipCannotBeBuiltInland() throws {
        let panel = try #require(management())
        let ship = try #require(panel.recruits.first { $0.name == "Ship" })

        #expect(ship.disabledReason == "Потрібен вихід до води")
    }

    private func management(
        activePlayerID: WorldPlayerID? = "crown",
        phase: GamePhase = .construction,
        economy: EconomyState = EconomyState(players: [WorldPlayer(id: "crown", displayName: "Crown"), WorldPlayer(id: "union", displayName: "Union")], startingGold: 100)
    ) -> CityManagement? {
        CityManagement.inspect(
            cityID: "capital",
            activePlayerID: activePlayerID,
            world: world(phase: phase),
            economy: economy,
            ledger: RecruitmentLedger(),
            map: map,
            content: content
        )
    }

    private let players = [WorldPlayer(id: "crown", displayName: "Crown"), WorldPlayer(id: "union", displayName: "Union")]

    private func world(phase: GamePhase = .construction) -> WorldState {
        WorldState(
            players: players,
            hexes: map.hexes,
            cities: [City(id: "capital", ownerID: "crown", hexID: "home", levelID: "village", isCapital: true)],
            buildings: [Building(id: "capital-barracks", cityID: "capital", typeID: "barracks")],
            phase: phase
        )
    }

    private let map = StaticHexMap(
        id: "map",
        displayName: "Map",
        bounds: HexMapBounds(minimumQ: 0, maximumQ: 0, minimumR: 0, maximumR: 0),
        hexes: [Hex(id: "home", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains")],
        neighborhoods: [HexNeighborhood(hexID: "home", neighborHexIDs: [])]
    )

    private let content = GameContentConfiguration(
        terrain: [TerrainDefinition(id: "plains", displayName: "Plains", domain: .land, movementCost: 1, defenseModifier: 0, incomeModifier: 2, isPassable: true, isCityBuildable: true)],
        units: [
            UnitDefinition(id: "infantry", displayName: "Infantry", recruitmentCost: 20, upkeep: 2, hitPoints: 10, damage: 4, attackRange: 1, movement: 2, domain: .land),
            UnitDefinition(id: "ship", displayName: "Ship", recruitmentCost: 40, upkeep: 3, hitPoints: 0, damage: 0, attackRange: 0, movement: 4, domain: .navalTransport, cargoCapacity: 3),
        ],
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
            startingGold: 100,
            map: StaticHexMap(
                id: "map",
                displayName: "Map",
                bounds: HexMapBounds(minimumQ: 0, maximumQ: 0, minimumR: 0, maximumR: 0),
                hexes: [Hex(id: "home", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains")],
                neighborhoods: [HexNeighborhood(hexID: "home", neighborHexIDs: [])]
            ),
            world: WorldState(
                players: [WorldPlayer(id: "crown", displayName: "Crown"), WorldPlayer(id: "union", displayName: "Union")],
                hexes: [Hex(id: "home", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains")]
            )
        )
    )
}
