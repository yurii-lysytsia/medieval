@testable import Medieval
import Testing

struct StrategicPathfinderTests {
    @Test func landRouteUsesTerrainAndRiverCostsWithinBudget() throws {
        let route = try #require(StrategicPathfinder.route(from: "plain", to: "forest", budget: 5, domain: .land, map: map, world: world, terrain: terrain))

        #expect(route.hexIDs == ["plain", "shallows", "forest"])
        #expect(route.cost == 5)
        #expect(StrategicPathfinder.route(from: "plain", to: "forest", budget: 4, domain: .land, map: map, world: world, terrain: terrain) == nil)
    }

    @Test func landCannotEnterDeepWaterButCanEnterShallows() {
        let reachable = StrategicPathfinder.reachableRoutes(from: "plain", budget: 5, domain: .land, map: map, world: world, terrain: terrain)

        #expect(reachable["shallows"]?.cost == 2)
        #expect(reachable["deep"] == nil)
    }

    @Test func shipStaysOnWaterAndReachesDeepWater() {
        let reachable = StrategicPathfinder.reachableRoutes(from: "shallows", budget: 2, domain: .naval, map: map, world: world, terrain: terrain)

        #expect(reachable["deep"]?.hexIDs == ["shallows", "deep"])
        #expect(reachable["plain"] == nil)
        #expect(reachable["forest"] == nil)
        #expect(StrategicPathfinder.reachableRoutes(from: "plain", budget: 2, domain: .naval, map: map, world: world, terrain: terrain).isEmpty)
    }

    private let terrain = [
        TerrainDefinition(id: "plains", displayName: "Plains", movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: true),
        TerrainDefinition(id: "forest", displayName: "Forest", movementCost: 2, defenseModifier: 20, incomeModifier: 0, isPassable: true, isCityBuildable: true),
        TerrainDefinition(id: "shallows", displayName: "Shallows", movementCost: 2, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: false),
        TerrainDefinition(id: "deep-water", displayName: "Deep", movementCost: 0, defenseModifier: 0, incomeModifier: 0, isPassable: false, isCityBuildable: false),
    ]

    private var map: StaticHexMap {
        StaticHexMap(
            id: "route-map",
            displayName: "Route Map",
            bounds: HexMapBounds(minimumQ: 0, maximumQ: 3, minimumR: 0, maximumR: 0),
            hexes: hexes,
            neighborhoods: [
                HexNeighborhood(hexID: "plain", neighborHexIDs: ["shallows"]),
                HexNeighborhood(hexID: "shallows", neighborHexIDs: ["plain", "forest", "deep"]),
                HexNeighborhood(hexID: "forest", neighborHexIDs: ["shallows", "deep"]),
                HexNeighborhood(hexID: "deep", neighborHexIDs: ["shallows", "forest"]),
            ]
        )
    }

    private var hexes: [Hex] {
        [
            Hex(id: "plain", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"),
            Hex(id: "shallows", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "shallows"),
            Hex(id: "forest", coordinate: HexCoordinate(q: 2, r: 0), terrainID: "forest"),
            Hex(id: "deep", coordinate: HexCoordinate(q: 3, r: 0), terrainID: "deep-water"),
        ]
    }

    private var world: WorldState {
        WorldState(
            players: [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")],
            hexes: hexes,
            riverBoundaries: [RiverBoundary(id: "river", boundary: HexBoundary(firstHexID: "shallows", secondHexID: "forest"))],
            phase: .movement
        )
    }
}
