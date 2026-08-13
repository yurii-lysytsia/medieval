import Foundation
@testable import Medieval
import Testing

struct GameContentValidatorTests {
    @Test func duplicateIdentifiersAreRejectedWhileLoading() throws {
        let duplicate = UnitDefinition(
            id: "spearmen",
            displayName: "Spearmen II",
            recruitmentCost: 25,
            upkeep: 1,
            hitPoints: 10,
            damage: 4,
            attackRange: 1,
            movement: 2,
            domain: .land
        )
        let configuration = fixture(units: [unit(), duplicate])

        let error = try validationError(for: configuration)

        #expect(error == .duplicateIdentifier(entity: "unit", id: "spearmen"))
    }

    @Test func missingReferencesAreRejectedWhileLoading() throws {
        let army = Army(id: "army-1", ownerID: "one", hexID: "land", unitTypeID: "missing", quantity: 1)
        let configuration = fixture(world: world(armies: [army]))

        let error = try validationError(for: configuration)

        #expect(error == .missingReference(entity: "army", id: "army-1", reference: "unit type"))
    }

    @Test func invalidNumericRangesAreRejectedWhileLoading() throws {
        let invalidUnit = UnitDefinition(
            id: "spearmen",
            displayName: "Spearmen",
            recruitmentCost: -1,
            upkeep: 1,
            hitPoints: 10,
            damage: 4,
            attackRange: 1,
            movement: 2,
            domain: .land
        )
        let configuration = fixture(units: [invalidUnit])

        let error = try validationError(for: configuration)

        #expect(error == .invalidNumber(field: "unit spearmen recruitment cost", value: -1, minimum: 0))
    }

    @Test func unitsOnImpassableHexesAreRejectedWhileLoading() throws {
        let army = Army(id: "army-1", ownerID: "one", hexID: "sea", unitTypeID: "spearmen", quantity: 1)
        let configuration = fixture(world: world(hexes: [oceanHex()], armies: [army]))

        let error = try validationError(for: configuration)

        #expect(error == .impassablePlacement(entity: "Army \"army-1\"", hexID: "sea"))
    }

    @Test func hexOnUndefinedTerrainIsRejectedWhileLoading() throws {
        // Passability is read from terrain now, so a dangling terrain reference
        // is the only way a hex can fail to answer "can anyone stand here?".
        let orphan = Hex(id: "void", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "swamp")
        let configuration = fixture(world: world(hexes: [orphan]))

        let error = try validationError(for: configuration)

        #expect(error == .missingReference(entity: "map hex", id: "void", reference: "terrain \"swamp\""))
    }

    @Test func citiesOnUnsuitableTerrainAreRejectedWhileLoading() throws {
        let desert = Hex(id: "desert", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "desert")
        let city = City(id: "city-1", ownerID: "one", hexID: "desert", levelID: "village")
        let configuration = fixture(
            terrain: [
                TerrainDefinition(id: "plains", displayName: "Plains", movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: true),
                TerrainDefinition(id: "desert", displayName: "Desert", movementCost: 2, defenseModifier: 0, incomeModifier: -2, isPassable: true, isCityBuildable: false),
            ],
            world: world(hexes: [desert], cities: [city])
        )

        let error = try validationError(for: configuration)

        #expect(error == .unsuitableCityPlacement(hexID: "desert", terrainID: "desert"))
    }

    @Test func riversMustConnectNeighboringHexes() throws {
        let first = landHex()
        let second = Hex(id: "far", coordinate: HexCoordinate(q: 2, r: 0), terrainID: "plains")
        let river = RiverBoundary(id: "river", boundary: HexBoundary(firstHexID: "land", secondHexID: "far"))
        let configuration = fixture(
            map: map(hexes: [first, second], neighborhoods: [HexNeighborhood(hexID: "land", neighborHexIDs: []), HexNeighborhood(hexID: "far", neighborHexIDs: [])]),
            world: world(hexes: [first, second], riverBoundaries: [river])
        )

        let error = try validationError(for: configuration)

        // HexBoundary stores its ends in a canonical order, so the error names
        // them sorted rather than in the order the content author wrote them.
        #expect(error == .invalidRiverBoundary(id: "river", firstHexID: "far", secondHexID: "land"))
    }

    private func validationError(for configuration: GameContentConfiguration) throws -> GameContentValidationError {
        let data = try JSONEncoder().encode(configuration)
        do {
            _ = try GameContentLoader.decode(data)
            #expect(Bool(false), "The invalid configuration was accepted.")
            return .invalidNumber(field: "test", value: 0, minimum: 1)
        } catch let error as GameContentValidationError {
            return error
        }
    }

    @Test func mapAndWorldDisagreeingAboutAHexIsRejectedWhileLoading() throws {
        // Same hex ID, different terrain on each side of the configuration.
        let worldHex = Hex(id: "land", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "ocean")
        var configuration = fixture()
        configuration = GameContentConfiguration(
            terrain: configuration.terrain,
            units: configuration.units,
            cityLevels: configuration.cityLevels,
            buildings: configuration.buildings,
            scenario: ScenarioConfiguration(
                id: configuration.scenario.id,
                displayName: configuration.scenario.displayName,
                startingGold: configuration.scenario.startingGold,
                map: configuration.scenario.map,
                world: WorldState(players: configuration.scenario.world.players, hexes: [worldHex])
            )
        )

        let error = try validationError(for: configuration)

        #expect(error == .contradictoryHex(hexID: "land"))
    }

    @Test func hexOutsideTheMapBoundsIsRejectedWhileLoading() throws {
        let outside = Hex(id: "land", coordinate: HexCoordinate(q: 9, r: 0), terrainID: "plains")
        var configuration = fixture(world: world(hexes: [outside]))
        configuration = GameContentConfiguration(
            terrain: configuration.terrain,
            units: configuration.units,
            cityLevels: configuration.cityLevels,
            buildings: configuration.buildings,
            scenario: ScenarioConfiguration(
                id: configuration.scenario.id,
                displayName: configuration.scenario.displayName,
                startingGold: configuration.scenario.startingGold,
                map: StaticHexMap(
                    id: "map",
                    displayName: "Map",
                    bounds: HexMapBounds(minimumQ: 0, maximumQ: 1, minimumR: 0, maximumR: 1),
                    hexes: [outside],
                    neighborhoods: [HexNeighborhood(hexID: "land", neighborHexIDs: [])]
                ),
                world: configuration.scenario.world
            )
        )

        let error = try validationError(for: configuration)

        #expect(error == .coordinateOutOfBounds(hexID: "land", axis: "q", value: 9, minimum: 0, maximum: 1))
    }

    @Test func oneSidedNeighbourhoodIsRejectedWhileLoading() throws {
        let first = Hex(id: "a", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains")
        let second = Hex(id: "b", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "plains")
        var configuration = fixture(world: world(hexes: [first, second]))
        configuration = GameContentConfiguration(
            terrain: configuration.terrain,
            units: configuration.units,
            cityLevels: configuration.cityLevels,
            buildings: configuration.buildings,
            scenario: ScenarioConfiguration(
                id: configuration.scenario.id,
                displayName: configuration.scenario.displayName,
                startingGold: configuration.scenario.startingGold,
                map: StaticHexMap(
                    id: "map",
                    displayName: "Map",
                    bounds: HexMapBounds(minimumQ: 0, maximumQ: 1, minimumR: 0, maximumR: 0),
                    hexes: [first, second],
                    neighborhoods: [
                        HexNeighborhood(hexID: "a", neighborHexIDs: ["b"]),
                        HexNeighborhood(hexID: "b", neighborHexIDs: []),
                    ]
                ),
                world: configuration.scenario.world
            )
        )

        let error = try validationError(for: configuration)

        #expect(error == .asymmetricNeighborhood(hexID: "a", neighborHexID: "b"))
    }

    private func fixture(
        terrain: [TerrainDefinition]? = nil,
        units: [UnitDefinition]? = nil,
        map: StaticHexMap? = nil,
        world: WorldState? = nil
    ) -> GameContentConfiguration {
        let resolvedWorld = world ?? self.world()
        return GameContentConfiguration(
            terrain: terrain ?? [
                TerrainDefinition(id: "plains", displayName: "Plains", movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: true),
                TerrainDefinition(id: "ocean", displayName: "Ocean", movementCost: 0, defenseModifier: 0, incomeModifier: 0, isPassable: false, isCityBuildable: false),
            ],
            units: units ?? [unit()],
            cityLevels: [CityLevelDefinition(id: "village", displayName: "Village", baseIncome: 1, buildingSlots: 1, upgradeCost: 0)],
            buildings: [BuildingDefinition(id: "market", displayName: "Market", constructionCost: 1, upkeep: 0, incomeModifier: 0, defenseModifier: 0)],
            scenario: ScenarioConfiguration(
                id: "test",
                displayName: "Test",
                startingGold: 0,
                map: map ?? self.map(mirroring: resolvedWorld.hexes),
                world: resolvedWorld
            )
        )
    }

    /// The map and the world describe the same board, so fixtures derive one
    /// from the other instead of keeping a second hand-written list in step.
    /// Every hex neighbours every other, which is symmetric by construction.
    private func map(mirroring hexes: [Hex]) -> StaticHexMap {
        let ids = hexes.map(\.id)
        return StaticHexMap(
            id: "map",
            displayName: "Map",
            bounds: HexMapBounds(
                minimumQ: hexes.map(\.coordinate.q).min() ?? 0,
                maximumQ: hexes.map(\.coordinate.q).max() ?? 0,
                minimumR: hexes.map(\.coordinate.r).min() ?? 0,
                maximumR: hexes.map(\.coordinate.r).max() ?? 0
            ),
            hexes: hexes,
            neighborhoods: hexes.map { hex in
                HexNeighborhood(hexID: hex.id, neighborHexIDs: ids.filter { $0 != hex.id })
            }
        )
    }

    private func unit() -> UnitDefinition {
        UnitDefinition(
            id: "spearmen",
            displayName: "Spearmen",
            recruitmentCost: 25,
            upkeep: 1,
            hitPoints: 10,
            damage: 4,
            attackRange: 1,
            movement: 2,
            domain: .land
        )
    }

    private func map(hexes: [Hex], neighborhoods: [HexNeighborhood]) -> StaticHexMap {
        StaticHexMap(
            id: "map",
            displayName: "Map",
            bounds: HexMapBounds(minimumQ: 0, maximumQ: 2, minimumR: 0, maximumR: 0),
            hexes: hexes,
            neighborhoods: neighborhoods
        )
    }

    private func world(
        hexes: [Hex]? = nil,
        riverBoundaries: [RiverBoundary] = [],
        armies: [Army] = [],
        cities: [City] = []
    ) -> WorldState {
        WorldState(
            players: [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")],
            hexes: hexes ?? [landHex()],
            riverBoundaries: riverBoundaries,
            armies: armies,
            cities: cities
        )
    }

    private func landHex() -> Hex {
        Hex(id: "land", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains")
    }

    private func oceanHex() -> Hex {
        Hex(id: "sea", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "ocean")
    }
}
