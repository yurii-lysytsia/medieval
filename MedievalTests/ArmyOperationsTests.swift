import Foundation
@testable import Medieval
import Testing

struct ArmyOperationsTests {
    @Test func armiesFormSplitAndMergeWithoutDuplicatingUnits() throws {
        let formed = try ArmyOperations.formArmy(id: "army", ownerID: "crown", unitIDs: ["u1", "u2"], world: world(), map: map, definitions: definitions).get()
        let split = try ArmyOperations.split("army", moving: ["u2"], into: "scouts", world: formed).get()

        #expect(split.armies.count == 2)
        #expect(Set(split.armies.flatMap(\.unitIDs)) == ["u1", "u2"])
        #expect(split.armies.flatMap(\.unitIDs).count == 2)

        let merged = try ArmyOperations.merge("scouts", into: "army", world: split).get()
        #expect(merged.armies.count == 1)
        #expect(Set(merged.armies[0].unitIDs) == ["u1", "u2"])
    }

    @Test func landArmyCannotUseAnyRouteContainingDeepWater() throws {
        let formed = try ArmyOperations.formArmy(id: "army", ownerID: "crown", unitIDs: ["u1", "u2"], world: world(), map: map, definitions: definitions).get()

        let result = ArmyOperations.moveArmy("army", along: ["land", "shallows", "deep"], world: formed, map: map, terrain: terrain, units: definitions)

        #expect(result == .failure(.deepWaterRequiresTransport("deep")))
    }

    @Test func embarkationPreservesCompositionAndHonorsShipCapacity() throws {
        let formed = try ArmyOperations.formArmy(id: "army", ownerID: "crown", unitIDs: ["u1", "u2"], world: world(), map: map, definitions: definitions).get()
        let embarked = try ArmyOperations.embark("army", on: "ship", world: formed, map: map, definitions: definitions).get()

        #expect(embarked.armies[0].unitIDs == ["u1", "u2"])
        #expect(embarked.armies[0].embarkedOnShipID == "ship")
        #expect(embarked.units.first(where: { $0.id == "u1" })?.location == .cargo("ship"))

        let overloaded = try ArmyOperations.formArmy(id: "large", ownerID: "crown", unitIDs: ["u1", "u2", "u3", "u4"], world: world(), map: map, definitions: definitions).get()
        #expect(ArmyOperations.embark("large", on: "ship", world: overloaded, map: map, definitions: definitions) == .failure(.shipCapacityExceeded(limit: 3)))
    }

    @Test func shipMovesCargoAndDisembarkationRestoresLandArmy() throws {
        let formed = try ArmyOperations.formArmy(id: "army", ownerID: "crown", unitIDs: ["u1", "u2"], world: world(), map: map, definitions: definitions).get()
        let embarked = try ArmyOperations.embark("army", on: "ship", world: formed, map: map, definitions: definitions).get()
        let sailed = try ArmyOperations.moveShip("ship", along: ["shallows", "deep"], world: embarked, map: map, definitions: definitions).get()

        #expect(sailed.armies[0].hexID == "deep")
        #expect(sailed.units.first(where: { $0.id == "u1" })?.location == .cargo("ship"))
        #expect(ArmyOperations.moveShip("ship", along: ["deep", "shallows"], world: sailed, map: map, definitions: definitions) == .failure(.shipAlreadyMoved("ship")))

        let disembarked = try ArmyOperations.disembark("army", to: "land", world: embarked, map: map).get()
        #expect(disembarked.armies[0].embarkedOnShipID == nil)
        #expect(disembarked.armies[0].hexID == "land")
        #expect(disembarked.units.first(where: { $0.id == "u1" })?.location == .hex("land"))
    }

    @Test func shipRouteRejectsLandAtAnyStepAndDestroyedArmyRemovesItsUnits() throws {
        let invalidRoute = ArmyOperations.moveShip("ship", along: ["shallows", "deep", "far-land"], world: world(), map: map, definitions: definitions)
        #expect(invalidRoute == .failure(.navalRouteRequired("far-land")))

        let formed = try ArmyOperations.formArmy(id: "army", ownerID: "crown", unitIDs: ["u1", "u2"], world: world(), map: map, definitions: definitions).get()
        let destroyed = try ArmyOperations.destroy("army", world: formed).get()
        #expect(destroyed.armies.isEmpty)
        #expect(destroyed.units.filter { ["u1", "u2"].contains($0.id) }.allSatisfy { $0.condition == .destroyed })
    }

    private let definitions = [
        UnitDefinition(id: "infantry", displayName: "Infantry", recruitmentCost: 20, upkeep: 2, hitPoints: 10, damage: 4, attackRange: 1, movement: 3, domain: .land),
        UnitDefinition(id: "ship", displayName: "Ship", recruitmentCost: 40, upkeep: 3, hitPoints: 0, damage: 0, attackRange: 0, movement: 4, domain: .navalTransport, cargoCapacity: 3),
    ]
    private let terrain = [
        TerrainDefinition(id: "plains", displayName: "Plains", movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: true),
        TerrainDefinition(id: "shallows", displayName: "Shallows", movementCost: 2, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: false),
        TerrainDefinition(id: "deep-water", displayName: "Deep Water", movementCost: 0, defenseModifier: 0, incomeModifier: 0, isPassable: false, isCityBuildable: false),
    ]
    private var map: StaticHexMap {
        StaticHexMap(
            id: "map",
            displayName: "Map",
            bounds: HexMapBounds(minimumQ: 0, maximumQ: 3, minimumR: 0, maximumR: 0),
            hexes: [
                Hex(id: "land", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"),
                Hex(id: "shallows", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "shallows"),
                Hex(id: "deep", coordinate: HexCoordinate(q: 2, r: 0), terrainID: "deep-water"),
                Hex(id: "far-land", coordinate: HexCoordinate(q: 3, r: 0), terrainID: "plains"),
            ],
            neighborhoods: [
                HexNeighborhood(hexID: "land", neighborHexIDs: ["shallows"]),
                HexNeighborhood(hexID: "shallows", neighborHexIDs: ["land", "deep"]),
                HexNeighborhood(hexID: "deep", neighborHexIDs: ["shallows", "far-land"]),
                HexNeighborhood(hexID: "far-land", neighborHexIDs: ["deep"]),
            ]
        )
    }

    private func world() -> WorldState {
        let players = [WorldPlayer(id: "crown", displayName: "Crown"), WorldPlayer(id: "union", displayName: "Union")]
        let units = [
            Unit(id: "u1", ownerID: "crown", typeID: "infantry", currentHitPoints: 10, location: .hex("land")),
            Unit(id: "u2", ownerID: "crown", typeID: "infantry", currentHitPoints: 10, location: .hex("land")),
            Unit(id: "u3", ownerID: "crown", typeID: "infantry", currentHitPoints: 10, location: .hex("land")),
            Unit(id: "u4", ownerID: "crown", typeID: "infantry", currentHitPoints: 10, location: .hex("land")),
            Unit(id: "ship", ownerID: "crown", typeID: "ship", currentHitPoints: 0, location: .hex("shallows")),
        ]
        return WorldState(players: players, hexes: map.hexes, units: units, phase: .movement)
    }
}
