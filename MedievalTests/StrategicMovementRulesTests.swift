import Foundation
@testable import Medieval
import Testing

struct StrategicMovementRulesTests {
    @Test func confirmedMoveIsAtomicAndRecorded() throws {
        let route = try route(to: "empty")
        let resolution = try StrategicMovementRules.confirmArmyMovement(armyID: "army", route: route, game: game, world: world, map: map, terrain: terrain, units: units).get()

        #expect(resolution.world.armies.first(where: { $0.id == "army" })?.hexID == "empty")
        #expect(resolution.game.journal.last?.event == .armyMoved(armyID: "army", from: "origin", to: "empty", cost: 1))
    }

    @Test func friendlyDestinationMergesWithoutDuplicatingUnits() throws {
        let route = try route(to: "friendly")
        let resolution = try StrategicMovementRules.confirmArmyMovement(armyID: "army", route: route, game: game, world: world, map: map, terrain: terrain, units: units).get()

        let merged = try #require(resolution.world.armies.first(where: { $0.id == "friend" }))
        #expect(Set(merged.unitIDs) == ["unit", "friend-unit"])
        #expect(resolution.world.armies.contains(where: { $0.id == "army" }) == false)
    }

    @Test func enemyDestinationStartsEncounterWithoutOverlappingArmies() throws {
        let route = try route(to: "enemy")
        let resolution = try StrategicMovementRules.confirmArmyMovement(armyID: "army", route: route, game: game, world: world, map: map, terrain: terrain, units: units).get()

        #expect(resolution.encounter == PendingEncounter(attackerID: "army", defenderID: "enemy-army", destination: "enemy", route: route))
        #expect(resolution.world.armies.first(where: { $0.id == "army" })?.hexID == "origin")
        #expect(resolution.world.armies.first(where: { $0.id == "army" })?.hasMoved == true)
        #expect(resolution.game.journal.last?.event == .encounterStarted(attackerID: "army", defenderID: "enemy-army", hexID: "enemy"))
    }

    @Test func invalidCommandDoesNotMutateEitherState() {
        let invalid = MovementRoute(hexIDs: ["origin", "enemy"], cost: 1)
        let result = StrategicMovementRules.confirmArmyMovement(armyID: "army", route: invalid, game: game, world: world, map: map, terrain: terrain, units: units)

        #expect(result == .failure(.invalidRoute))
        #expect(game.journal.isEmpty)
        #expect(world.armies.first(where: { $0.id == "army" })?.hasMoved == false)
    }

    private func route(to destination: HexID) throws -> MovementRoute {
        try #require(StrategicPathfinder.route(from: "origin", to: destination, budget: 3, domain: .land, map: map, world: world, terrain: terrain))
    }

    private let terrain = [TerrainDefinition(id: "plains", displayName: "Plains", movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: true)]
    private let units = [UnitDefinition(id: "infantry", displayName: "Infantry", recruitmentCost: 20, upkeep: 2, hitPoints: 10, damage: 4, attackRange: 1, movement: 3, domain: .land)]
    private var game: GameState {
        GameState(players: [
            Player(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "One", worldPlayerID: "one"),
            Player(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, displayName: "Two", worldPlayerID: "two"),
        ], seed: 42, phase: .movement)
    }

    private var hexes: [Hex] {
        [
            Hex(id: "origin", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"),
            Hex(id: "empty", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "plains"),
            Hex(id: "friendly", coordinate: HexCoordinate(q: 0, r: 1), terrainID: "plains"),
            Hex(id: "enemy", coordinate: HexCoordinate(q: 1, r: 1), terrainID: "plains"),
        ]
    }

    private var map: StaticHexMap {
        StaticHexMap(id: "map", displayName: "Map", bounds: HexMapBounds(minimumQ: 0, maximumQ: 1, minimumR: 0, maximumR: 1), hexes: hexes, neighborhoods: [
            HexNeighborhood(hexID: "origin", neighborHexIDs: ["empty", "friendly"]),
            HexNeighborhood(hexID: "empty", neighborHexIDs: ["origin", "enemy"]),
            HexNeighborhood(hexID: "friendly", neighborHexIDs: ["origin", "enemy"]),
            HexNeighborhood(hexID: "enemy", neighborHexIDs: ["empty", "friendly"]),
        ])
    }

    private var world: WorldState {
        WorldState(
            players: [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")],
            hexes: hexes,
            units: [
                Unit(id: "unit", ownerID: "one", typeID: "infantry", currentHitPoints: 10, location: .hex("origin")),
                Unit(id: "friend-unit", ownerID: "one", typeID: "infantry", currentHitPoints: 10, location: .hex("friendly")),
                Unit(id: "enemy-unit", ownerID: "two", typeID: "infantry", currentHitPoints: 10, location: .hex("enemy")),
            ],
            armies: [
                Army(id: "army", ownerID: "one", hexID: "origin", unitIDs: ["unit"]),
                Army(id: "friend", ownerID: "one", hexID: "friendly", unitIDs: ["friend-unit"]),
                Army(id: "enemy-army", ownerID: "two", hexID: "enemy", unitIDs: ["enemy-unit"]),
            ],
            phase: .movement
        )
    }
}
