import Foundation
@testable import Medieval
import Testing

struct AIMovementDecisionsTests {
    @Test func anArmyWalksTowardsTheEnemyCapitalAndArrivesInTheEnd() throws {
        // The scenario the ticket asks for: left alone, the opponent has to get
        // there. Each turn moves it as far as its movement allows.
        var world = world()
        var game = game(phase: .movement)
        var visited: [HexID] = ["hex-0"]

        for _ in 0 ..< 10 {
            let steps = AIMovementDecisions.steps(for: "ai", game: game, world: world, content: content(world: world), target: target)
            guard case let .moveArmy(armyID, route)? = steps.first?.intent else { break }
            let resolution = try StrategicMovementRules.confirmArmyMovement(armyID: armyID, route: route, game: game, world: world, map: map, terrain: terrain, units: units).get()
            game = resolution.game
            world = resolution.world
            visited.append(route.hexIDs.last ?? "hex-0")
            // A new turn: the army may move again.
            world.resetMovementCommands(for: "ai")
            if visited.last == "hex-8" { break }
        }

        #expect(visited.last == "hex-8")
        #expect(visited.count > 1)
    }

    @Test func everyPlannedMoveIsOneTheRulesAccept() throws {
        let world = world()
        let steps = AIMovementDecisions.steps(for: "ai", game: game(phase: .movement), world: world, content: content(world: world), target: target)
        let step = try #require(steps.first)
        guard case let .moveArmy(armyID, route) = step.intent else {
            Issue.record("expected a move")
            return
        }

        let result = StrategicMovementRules.confirmArmyMovement(armyID: armyID, route: route, game: game(phase: .movement), world: world, map: map, terrain: terrain, units: units)

        #expect(throws: Never.self) { try result.get() }
        #expect(step.priority == .advance)
    }

    @Test func deepWaterIsNeverPlannedThrough() {
        // No fleet: the preview the opponent chooses from searches on land, so
        // the sea is not among its options at all.
        let world = strandedWorld()
        let steps = AIMovementDecisions.steps(
            for: "ai",
            game: game(phase: .movement),
            world: world,
            content: content(world: world, map: strandedMap),
            target: AITarget(cityID: "rival-capital", hexID: "island", ownerID: "rival", distance: 2)
        )

        #expect(steps.isEmpty)
    }

    @Test func aFightIsPickedWhenItCanBeWonAndDeclinedWhenItCannot() throws {
        // Same board, different defender: the opponent walks into a garrison it
        // outmatches and stops short of one it does not.
        let weak = adjacentEnemyWorld(defenderHitPoints: 1)
        let strong = adjacentEnemyWorld(defenderHitPoints: 500)

        let attacking = AIMovementDecisions.steps(for: "ai", game: game(phase: .movement), world: weak, content: content(world: weak), target: target)
        let declining = AIMovementDecisions.steps(for: "ai", game: game(phase: .movement), world: strong, content: content(world: strong), target: target)

        guard case let .moveArmy(_, route)? = attacking.first?.intent else {
            Issue.record("expected an attack")
            return
        }
        #expect(route.hexIDs.last == "hex-1")
        #expect(attacking.first?.priority == .attack)
        #expect(declining.isEmpty)
    }

    @Test func aDefendedTargetCapitalIsStormedAnyway() {
        // An opponent that only ever fought battles it was winning would circle
        // a defended capital forever, and the match would never end.
        let world = adjacentEnemyWorld(defenderHitPoints: 500, defenderAt: "hex-8", capitalAt: "hex-8")
        let steps = AIMovementDecisions.steps(
            for: "ai",
            game: game(phase: .movement),
            world: world,
            content: content(world: world),
            target: AITarget(cityID: "rival-capital", hexID: "hex-8", ownerID: "rival", distance: 8)
        )

        // The army is eight hexes away, so it advances rather than arriving; the
        // point is that a strong defender does not stop it from setting out.
        #expect(!steps.isEmpty)
    }

    @Test func onlyOneBattleIsStartedPerPhase() throws {
        // The match tracks one outstanding encounter, so a second army planning
        // its own fight in the same phase would have nowhere to put it.
        let world = twoArmiesAgainstTwoEnemiesWorld()
        let steps = AIMovementDecisions.steps(for: "ai", game: game(phase: .movement), world: world, content: content(world: world), target: target)

        #expect(steps.filter { $0.priority == .attack }.count <= 1)
    }

    @Test func anArmyThatCannotGetCloserStaysPut() {
        // Nothing to gain is not a reason to shuffle: a move that does not close
        // the gap is standing still with extra steps.
        let world = world(armyAt: "hex-8")
        let steps = AIMovementDecisions.steps(for: "ai", game: game(phase: .movement), world: world, content: content(world: world), target: target)

        #expect(steps.isEmpty)
    }

    // MARK: - Fixture

    private let target = AITarget(cityID: "rival-capital", hexID: "hex-8", ownerID: "rival", distance: 8)
    private let worldPlayers = [WorldPlayer(id: "ai", displayName: "ШІ"), WorldPlayer(id: "rival", displayName: "Суперник")]
    private let terrain = [
        TerrainDefinition(id: "plains", displayName: "Plains", domain: .land, movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: true),
        TerrainDefinition(id: "deep-water", displayName: "Deep water", domain: .deepWater, movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: false),
    ]
    private let units = [UnitDefinition(id: "infantry", displayName: "Infantry", recruitmentCost: 20, upkeep: 2, hitPoints: 10, damage: 4, attackRange: 1, movement: 2, domain: .land)]
    private let cityLevels = [CityLevelDefinition(id: "village", displayName: "Village", baseIncome: 4, buildingSlots: 1, upgradeCost: 0)]

    private var corridor: [Hex] {
        (0 ... 8).map { Hex(id: HexID(rawValue: "hex-\($0)"), coordinate: HexCoordinate(q: $0, r: 0), terrainID: "plains") }
    }

    private var map: StaticHexMap {
        StaticHexMap(
            id: "corridor",
            displayName: "Corridor",
            bounds: HexMapBounds(minimumQ: 0, maximumQ: 8, minimumR: 0, maximumR: 0),
            hexes: corridor,
            neighborhoods: corridor.enumerated().map { index, hex in
                HexNeighborhood(
                    hexID: hex.id,
                    neighborHexIDs: (index > 0 ? [corridor[index - 1].id] : []) + (index + 1 < corridor.count ? [corridor[index + 1].id] : [])
                )
            }
        )
    }

    private var strandedMap: StaticHexMap {
        let hexes = [
            Hex(id: "shore", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"),
            Hex(id: "sea", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "deep-water"),
            Hex(id: "island", coordinate: HexCoordinate(q: 2, r: 0), terrainID: "plains"),
        ]
        return StaticHexMap(
            id: "stranded",
            displayName: "Stranded",
            bounds: HexMapBounds(minimumQ: 0, maximumQ: 2, minimumR: 0, maximumR: 0),
            hexes: hexes,
            neighborhoods: [
                HexNeighborhood(hexID: "shore", neighborHexIDs: ["sea"]),
                HexNeighborhood(hexID: "sea", neighborHexIDs: ["shore", "island"]),
                HexNeighborhood(hexID: "island", neighborHexIDs: ["sea"]),
            ]
        )
    }

    private func game(phase: GamePhase) -> GameState {
        GameState(
            players: [Player(displayName: "ШІ", worldPlayerID: "ai"), Player(displayName: "Суперник", worldPlayerID: "rival")],
            seed: 1,
            phase: phase
        )
    }

    private func world(armyAt hexID: HexID = "hex-0") -> WorldState {
        WorldState(
            players: worldPlayers,
            hexes: corridor,
            units: [Unit(id: "ai-unit", ownerID: "ai", typeID: "infantry", currentHitPoints: 10, location: .hex(hexID))],
            armies: [Army(id: "ai-army", ownerID: "ai", hexID: hexID, unitIDs: ["ai-unit"])],
            cities: [City(id: "rival-capital", ownerID: "rival", hexID: "hex-8", levelID: "village", isCapital: true)],
            phase: .movement
        )
    }

    private func strandedWorld() -> WorldState {
        WorldState(
            players: worldPlayers,
            hexes: strandedMap.hexes,
            units: [Unit(id: "ai-unit", ownerID: "ai", typeID: "infantry", currentHitPoints: 10, location: .hex("shore"))],
            armies: [Army(id: "ai-army", ownerID: "ai", hexID: "shore", unitIDs: ["ai-unit"])],
            cities: [City(id: "rival-capital", ownerID: "rival", hexID: "island", levelID: "village", isCapital: true)],
            phase: .movement
        )
    }

    private func adjacentEnemyWorld(defenderHitPoints: Int, defenderAt: HexID = "hex-1", capitalAt: HexID = "hex-8") -> WorldState {
        WorldState(
            players: worldPlayers,
            hexes: corridor,
            units: [
                Unit(id: "ai-unit", ownerID: "ai", typeID: "infantry", currentHitPoints: 10, location: .hex("hex-0")),
                Unit(id: "rival-unit", ownerID: "rival", typeID: "infantry", currentHitPoints: defenderHitPoints, location: .hex(defenderAt)),
            ],
            armies: [
                Army(id: "ai-army", ownerID: "ai", hexID: "hex-0", unitIDs: ["ai-unit"]),
                Army(id: "rival-army", ownerID: "rival", hexID: defenderAt, unitIDs: ["rival-unit"]),
            ],
            cities: [City(id: "rival-capital", ownerID: "rival", hexID: capitalAt, levelID: "village", isCapital: true)],
            phase: .movement
        )
    }

    private func twoArmiesAgainstTwoEnemiesWorld() -> WorldState {
        WorldState(
            players: worldPlayers,
            hexes: corridor,
            units: [
                Unit(id: "ai-unit-1", ownerID: "ai", typeID: "infantry", currentHitPoints: 10, location: .hex("hex-0")),
                Unit(id: "ai-unit-2", ownerID: "ai", typeID: "infantry", currentHitPoints: 10, location: .hex("hex-2")),
                Unit(id: "rival-unit-1", ownerID: "rival", typeID: "infantry", currentHitPoints: 1, location: .hex("hex-1")),
                Unit(id: "rival-unit-2", ownerID: "rival", typeID: "infantry", currentHitPoints: 1, location: .hex("hex-3")),
            ],
            armies: [
                Army(id: "ai-army-1", ownerID: "ai", hexID: "hex-0", unitIDs: ["ai-unit-1"]),
                Army(id: "ai-army-2", ownerID: "ai", hexID: "hex-2", unitIDs: ["ai-unit-2"]),
                Army(id: "rival-army-1", ownerID: "rival", hexID: "hex-1", unitIDs: ["rival-unit-1"]),
                Army(id: "rival-army-2", ownerID: "rival", hexID: "hex-3", unitIDs: ["rival-unit-2"]),
            ],
            cities: [City(id: "rival-capital", ownerID: "rival", hexID: "hex-8", levelID: "village", isCapital: true)],
            phase: .movement
        )
    }

    private func content(world: WorldState, map: StaticHexMap? = nil) -> GameContentConfiguration {
        GameContentConfiguration(
            terrain: terrain,
            units: units,
            cityLevels: cityLevels,
            buildings: [],
            scenario: ScenarioConfiguration(id: "fixture", displayName: "Fixture", startingGold: 100, map: map ?? self.map, world: world)
        )
    }
}
