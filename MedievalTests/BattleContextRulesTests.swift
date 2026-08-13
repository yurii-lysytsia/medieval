@testable import Medieval
import Testing

struct BattleContextRulesTests {
    @Test func terrainRiverWallsAndGarrisonHelpOnlyDefender() {
        let context = BattleContextRules.context(attacker: attacker, defender: defender, destination: "east", world: world, terrain: terrain, units: units, buildings: buildings)
        #expect(context.attackerRollBonus == 2)
        #expect(context.defenderRollBonus == 2)
        #expect(context.defenderModifiers == [
            BattleModifier(name: "Місцевість", percent: 20),
            BattleModifier(name: "Річка", percent: 20),
            BattleModifier(name: "Стіни", percent: 35),
            BattleModifier(name: "Гарнізон", percent: 10),
        ])
    }

    private let attacker = Army(id: "a", ownerID: "one", hexID: "west", unitIDs: ["cav"])
    private let defender = Army(id: "d", ownerID: "two", hexID: "east", unitIDs: ["archer"])
    private let terrain = [TerrainDefinition(id: "forest", displayName: "Forest", movementCost: 2, defenseModifier: 20, incomeModifier: 0, isPassable: true, isCityBuildable: true)]
    private let units = [
        UnitDefinition(id: "cavalry", displayName: "Cavalry", recruitmentCost: 35, upkeep: 3, hitPoints: 9, damage: 6, attackRange: 1, movement: 4, domain: .land),
        UnitDefinition(id: "archers", displayName: "Archers", recruitmentCost: 25, upkeep: 2, hitPoints: 7, damage: 3, attackRange: 3, movement: 2, domain: .land),
    ]
    private let buildings = [BuildingDefinition(id: "walls", displayName: "Walls", constructionCost: 1, upkeep: 1, incomeModifier: 0, defenseModifier: 35)]
    private var world: WorldState {
        WorldState(players: [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")], hexes: [
            Hex(id: "west", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "forest"),
            Hex(id: "east", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "forest"),
        ], riverBoundaries: [RiverBoundary(id: "r", boundary: HexBoundary(firstHexID: "west", secondHexID: "east"))], units: [
            Unit(id: "cav", ownerID: "one", typeID: "cavalry", currentHitPoints: 9, location: .hex("west")),
            Unit(id: "archer", ownerID: "two", typeID: "archers", currentHitPoints: 7, location: .hex("east")),
            Unit(id: "guard", ownerID: "two", typeID: "archers", currentHitPoints: 7, location: .garrison("capital")),
        ], armies: [attacker, defender], cities: [City(id: "capital", ownerID: "two", hexID: "east", levelID: "level-1", isCapital: true)], buildings: [Building(id: "wall", cityID: "capital", typeID: "walls")], phase: .combat)
    }
}
