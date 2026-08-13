@testable import MedievalDomain
import Testing

struct MovementPreviewTests {
    @Test func previewMatchesPathfinderAndMarksEnemyWithoutChangingWorld() throws {
        let initial = world
        let preview = try #require(MovementPreviewRules.preview(armyID: "army", playerID: "one", world: initial, map: map, terrain: terrain, units: units))

        #expect(preview.routes["target"]?.cost == 1)
        #expect(preview.encounterHexIDs == ["target"])
        #expect(initial == world)
    }

    @Test func previewRejectsWrongOwnerPhaseAndMovedArmy() {
        #expect(MovementPreviewRules.preview(armyID: "army", playerID: "two", world: world, map: map, terrain: terrain, units: units) == nil)
        var moved = world
        moved.replaceArmy(Army(id: "army", ownerID: "one", hexID: "origin", unitIDs: ["unit"], hasMoved: true))
        #expect(MovementPreviewRules.preview(armyID: "army", playerID: "one", world: moved, map: map, terrain: terrain, units: units) == nil)
    }

    private let terrain = [TerrainDefinition(id: "plains", displayName: "Plains", movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: true)]
    private let units = [UnitDefinition(id: "infantry", displayName: "Infantry", recruitmentCost: 20, upkeep: 2, hitPoints: 10, damage: 4, attackRange: 1, movement: 2, domain: .land)]
    private var hexes: [Hex] {
        [Hex(id: "origin", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains", isPassable: true), Hex(id: "target", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "plains", isPassable: true)]
    }

    private var map: StaticHexMap {
        StaticHexMap(id: "map", displayName: "Map", bounds: HexMapBounds(minimumQ: 0, maximumQ: 1, minimumR: 0, maximumR: 0), hexes: hexes, neighborhoods: [HexNeighborhood(hexID: "origin", neighborHexIDs: ["target"]), HexNeighborhood(hexID: "target", neighborHexIDs: ["origin"])])
    }

    private var world: WorldState {
        WorldState(
            players: [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")],
            hexes: hexes,
            units: [Unit(id: "unit", ownerID: "one", typeID: "infantry", currentHitPoints: 10, location: .hex("origin")), Unit(id: "enemy-unit", ownerID: "two", typeID: "infantry", currentHitPoints: 10, location: .hex("target"))],
            armies: [Army(id: "army", ownerID: "one", hexID: "origin", unitIDs: ["unit"]), Army(id: "enemy", ownerID: "two", hexID: "target", unitIDs: ["enemy-unit"])],
            phase: .movement
        )
    }
}
