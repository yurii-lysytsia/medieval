@testable import Medieval
import Testing

struct BattleContextRulesTests {
    @Test func terrainRiverFortificationsAndGarrisonHelpOnlyDefender() {
        let context = BattleContextRules.context(attacker: attacker, defender: defender, destination: "east", world: world, terrain: terrain, units: units, buildings: buildings)

        #expect(context.attackerRollBonus == 0)
        #expect(context.defenderRollBonus == 2)
        #expect(context.defenderModifiers == [
            BattleModifier(kind: .terrain, percent: 10),
            BattleModifier(kind: .river, percent: 10),
            BattleModifier(kind: .fortifications, percent: 50),
            BattleModifier(kind: .garrison, percent: 10),
        ])
        #expect(context.defenderDamageReduction == 80)
    }

    @Test func defenseValuesUseTheSameScaleAsTheGameContent() throws {
        // Content states defence in points — forest 1, walls 4 — and reading
        // those as percentages made every terrain bonus a rounding error.
        let content = try GameContentLoader.loadMVP()
        let forest = try #require(content.terrain.first { $0.id == "forest" })
        let walls = try #require(content.buildings.first { $0.id == "walls" })

        #expect(forest.defenseModifier == 1)
        #expect(walls.defenseModifier == 4)
        #expect(forest.defenseModifier * BattleContextRules.percentPerDefensePoint == 10)
        #expect(walls.defenseModifier * BattleContextRules.percentPerDefensePoint == 40)
    }

    @Test func anAttackerGetsNothingFromTheDefendersHex() {
        // The mirror case: attacking out of the same forest, across the same
        // river, from a hex the attacker also holds a city on.
        let context = BattleContextRules.context(attacker: defender, defender: attacker, destination: "west", world: world, terrain: terrain, units: units, buildings: buildings)

        #expect(context.defenderModifiers == [BattleModifier(kind: .terrain, percent: 10), BattleModifier(kind: .river, percent: 10)])
        #expect(context.attackerRollBonus == 0)
    }

    @Test func aDefenderWithoutRangedUnitsDoesNotShootFirst() {
        let melee = Army(id: "d", ownerID: "two", hexID: "east", unitIDs: ["spear"])
        let context = BattleContextRules.context(attacker: attacker, defender: melee, destination: "east", world: world, terrain: terrain, units: units, buildings: buildings)

        #expect(context.defenderRollBonus == 0)
    }

    @Test func anEnemyCityOnTheHexDoesNotShelterTheDefender() {
        // The city on "east" belongs to "two"; an army of "one" defending there
        // is standing in somebody else's fortress.
        let intruder = Army(id: "i", ownerID: "one", hexID: "east", unitIDs: [])
        let context = BattleContextRules.context(attacker: defender, defender: intruder, destination: "east", world: world, terrain: terrain, units: units, buildings: buildings)

        #expect(context.defenderModifiers.map(\.kind) == [.terrain])
    }

    private let attacker = Army(id: "a", ownerID: "one", hexID: "west", unitIDs: ["cav"])
    private let defender = Army(id: "d", ownerID: "two", hexID: "east", unitIDs: ["archer"])
    private let terrain = [TerrainDefinition(id: "forest", displayName: "Forest", domain: .land, movementCost: 2, defenseModifier: 1, incomeModifier: 0, isPassable: true, isCityBuildable: true)]
    private let units = [
        UnitDefinition(id: "cavalry", displayName: "Cavalry", recruitmentCost: 35, upkeep: 3, hitPoints: 9, damage: 6, attackRange: 1, movement: 4, domain: .land),
        UnitDefinition(id: "archers", displayName: "Archers", recruitmentCost: 25, upkeep: 2, hitPoints: 7, damage: 3, attackRange: 3, movement: 2, domain: .land),
    ]
    private let buildings = [
        BuildingDefinition(id: "walls", displayName: "Walls", constructionCost: 1, upkeep: 1, incomeModifier: 0, defenseModifier: 4),
        BuildingDefinition(id: "barracks", displayName: "Barracks", constructionCost: 1, upkeep: 1, incomeModifier: 0, defenseModifier: 1),
    ]
    private var world: WorldState {
        WorldState(players: [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")], hexes: [
            Hex(id: "west", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "forest"),
            Hex(id: "east", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "forest"),
        ], riverBoundaries: [RiverBoundary(id: "r", boundary: HexBoundary(firstHexID: "west", secondHexID: "east"))], units: [
            Unit(id: "cav", ownerID: "one", typeID: "cavalry", currentHitPoints: 9, location: .hex("west")),
            Unit(id: "spear", ownerID: "two", typeID: "cavalry", currentHitPoints: 9, location: .hex("east")),
            Unit(id: "archer", ownerID: "two", typeID: "archers", currentHitPoints: 7, location: .hex("east")),
            Unit(id: "guard", ownerID: "two", typeID: "archers", currentHitPoints: 7, location: .garrison("capital")),
        ], armies: [attacker, defender], cities: [City(id: "capital", ownerID: "two", hexID: "east", levelID: "level-1", isCapital: true)], buildings: [
            Building(id: "wall", cityID: "capital", typeID: "walls"),
            Building(id: "barrack", cityID: "capital", typeID: "barracks"),
        ], phase: .combat)
    }
}
