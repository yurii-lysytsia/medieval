import Foundation
@testable import Medieval
import Testing

struct BasicAIPlannerTests {
    @Test func theSameBoardAlwaysProducesTheSamePlan() {
        // The opponent has to be replayable: a saved match that replays its
        // turns must fight the same battles it fought the first time.
        let world = world(phase: .movement)
        let first = plan(in: world)
        let second = plan(in: world)

        #expect(first == second)
    }

    @Test func everyPhaseEndsWithTheStepThatLeavesIt() {
        // An opponent that finds nothing worth doing still has to hand the turn
        // on. A phase it cannot finish stalls the match for every player.
        for phase in [GamePhase.economy, .construction, .movement] {
            #expect(plan(in: world(phase: phase)).intents.last == .advancePhase, "\(phase.rawValue)")
        }
        #expect(plan(in: world(phase: .combat)).intents.last == .endTurn)
        #expect(plan(in: world(phase: .handoff)).intents == [.confirmHandoff])
    }

    @Test func aFinishedMatchIsNotGivenSomethingToDo() {
        #expect(plan(in: world(phase: .finished)).steps.isEmpty)
    }

    @Test func theCapitalGoesOnTheMostValuableHexTheRulesAccept() throws {
        // "hills" pays the most income here, so it outranks plains even though
        // plains sorts first by id.
        let plan = plan(in: world(phase: .capitalPlacement))

        #expect(plan.steps.map(\.priority) == [.capitalSurvival])
        #expect(plan.intents == [.placeCapital(hexID: "hills")])
    }

    @Test func aPlannedPlacementIsOneTheRulesWouldAccept() throws {
        // The plan is only worth anything if the rule agrees, so the check is
        // the rule itself rather than a second opinion in the planner.
        let world = world(phase: .capitalPlacement)
        let plan = plan(in: world)
        guard case let .placeCapital(hexID) = try #require(plan.intents.first) else {
            Issue.record("expected a placement")
            return
        }

        let placement = CapitalPlacementRules.placeCapital(for: "ai", at: hexID, in: world, terrain: terrain, cityLevels: cityLevels)

        #expect(throws: Never.self) { try placement.get() }
    }

    @Test func nowhereToBuildMeansNoPlacementRatherThanAnIllegalOne() {
        // Every hex is deep water: there is no legal placement, and inventing
        // one would hand the rules a move they must reject.
        let drowned = WorldState(
            players: worldPlayers,
            hexes: [Hex(id: "sea", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "deep-water")],
            phase: .capitalPlacement
        )

        #expect(plan(in: drowned).steps.isEmpty)
    }

    @Test func theTargetIsTheNearestEnemyCapitalByRouteNotByLine() throws {
        // "near" sits one hex away behind mountains; "far" is three cheap hexes
        // off. Straight-line distance would pick the wrong one.
        let plan = plan(in: world(phase: .movement))
        let target = try #require(plan.target)

        #expect(target.cityID == "far-capital")
        #expect(target.ownerID == "rival")
    }

    @Test func aCapitalWithNoLandRouteIsNotATarget() {
        // The opponent has no fleet; marching at something it can never arrive
        // at is how a turn loop stops making progress.
        let island = WorldState(
            players: worldPlayers,
            hexes: [
                Hex(id: "home", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"),
                Hex(id: "strait", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "deep-water"),
                Hex(id: "island", coordinate: HexCoordinate(q: 2, r: 0), terrainID: "plains"),
            ],
            cities: [
                City(id: "ai-capital", ownerID: "ai", hexID: "home", levelID: "village", isCapital: true),
                City(id: "island-capital", ownerID: "rival", hexID: "island", levelID: "village", isCapital: true),
            ],
            phase: .movement
        )

        #expect(plan(in: island, map: islandMap).target == nil)
    }

    @Test func anEncounterStartedBySomebodyElseIsNotResolvedOnTheirBehalf() {
        let world = world(phase: .combat)
        let theirs = PendingEncounter(attackerID: "rival-army", defenderID: "ai-army", destination: "plains", route: MovementRoute(hexIDs: ["near", "plains"], cost: 1))
        let ours = PendingEncounter(attackerID: "ai-army", defenderID: "rival-army", destination: "near", route: MovementRoute(hexIDs: ["plains", "near"], cost: 1))

        #expect(plan(in: world, encounter: theirs).intents == [.endTurn])
        #expect(plan(in: world, encounter: ours).intents == [.resolveBattle(encounter: ours), .endTurn])
    }

    @Test func prioritiesAreOrderedSurvivalIncomeRecruitmentAdvanceAttack() {
        // The order is the model, so it is asserted rather than assumed.
        #expect(AIPriority.allCases == [.capitalSurvival, .income, .recruitment, .advance, .attack])
        #expect(AIPriority.capitalSurvival < AIPriority.income)
        #expect(AIPriority.income < AIPriority.recruitment)
        #expect(AIPriority.recruitment < AIPriority.advance)
        #expect(AIPriority.advance < AIPriority.attack)
    }

    // MARK: - Fixture

    private let worldPlayers = [WorldPlayer(id: "ai", displayName: "ШІ"), WorldPlayer(id: "rival", displayName: "Суперник")]
    private let terrain = [
        TerrainDefinition(id: "plains", displayName: "Plains", domain: .land, movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: true),
        TerrainDefinition(id: "hills", displayName: "Hills", domain: .land, movementCost: 1, defenseModifier: 1, incomeModifier: 2, isPassable: true, isCityBuildable: true),
        TerrainDefinition(id: "mountains", displayName: "Mountains", domain: .land, movementCost: 9, defenseModifier: 2, incomeModifier: 0, isPassable: true, isCityBuildable: false),
        TerrainDefinition(id: "deep-water", displayName: "Deep water", domain: .deepWater, movementCost: 1, defenseModifier: 0, incomeModifier: 0, isPassable: true, isCityBuildable: false),
    ]
    private let cityLevels = [CityLevelDefinition(id: "village", displayName: "Village", baseIncome: 4, buildingSlots: 1, upgradeCost: 0)]
    private let units = [UnitDefinition(id: "infantry", displayName: "Infantry", recruitmentCost: 20, upkeep: 2, hitPoints: 10, damage: 4, attackRange: 1, movement: 2, domain: .land)]

    /// `plains` — the opponent's seat. `near` is adjacent but mountainous, so it
    /// costs 9 to enter; `far` is three plains hexes around the long way.
    private var hexes: [Hex] {
        [
            Hex(id: "plains", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"),
            Hex(id: "hills", coordinate: HexCoordinate(q: 0, r: 1), terrainID: "hills"),
            Hex(id: "near", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "mountains"),
            Hex(id: "step-1", coordinate: HexCoordinate(q: 0, r: -1), terrainID: "plains"),
            Hex(id: "step-2", coordinate: HexCoordinate(q: 1, r: -1), terrainID: "plains"),
            Hex(id: "far", coordinate: HexCoordinate(q: 2, r: -1), terrainID: "plains"),
        ]
    }

    private var map: StaticHexMap {
        StaticHexMap(
            id: "fixture",
            displayName: "Fixture",
            bounds: HexMapBounds(minimumQ: 0, maximumQ: 2, minimumR: -1, maximumR: 1),
            hexes: hexes,
            neighborhoods: [
                HexNeighborhood(hexID: "plains", neighborHexIDs: ["hills", "near", "step-1"]),
                HexNeighborhood(hexID: "hills", neighborHexIDs: ["plains"]),
                HexNeighborhood(hexID: "near", neighborHexIDs: ["plains", "far"]),
                HexNeighborhood(hexID: "step-1", neighborHexIDs: ["plains", "step-2"]),
                HexNeighborhood(hexID: "step-2", neighborHexIDs: ["step-1", "far"]),
                HexNeighborhood(hexID: "far", neighborHexIDs: ["step-2", "near"]),
            ]
        )
    }

    private var islandMap: StaticHexMap {
        StaticHexMap(
            id: "island",
            displayName: "Island",
            bounds: HexMapBounds(minimumQ: 0, maximumQ: 2, minimumR: 0, maximumR: 0),
            hexes: [
                Hex(id: "home", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"),
                Hex(id: "strait", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "deep-water"),
                Hex(id: "island", coordinate: HexCoordinate(q: 2, r: 0), terrainID: "plains"),
            ],
            neighborhoods: [
                HexNeighborhood(hexID: "home", neighborHexIDs: ["strait"]),
                HexNeighborhood(hexID: "strait", neighborHexIDs: ["home", "island"]),
                HexNeighborhood(hexID: "island", neighborHexIDs: ["strait"]),
            ]
        )
    }

    private func world(phase: GamePhase) -> WorldState {
        WorldState(
            players: worldPlayers,
            hexes: hexes,
            units: [
                Unit(id: "ai-unit", ownerID: "ai", typeID: "infantry", currentHitPoints: 10, location: .hex("plains")),
                Unit(id: "rival-unit", ownerID: "rival", typeID: "infantry", currentHitPoints: 10, location: .hex("near")),
            ],
            armies: [
                Army(id: "ai-army", ownerID: "ai", hexID: "plains", unitIDs: ["ai-unit"]),
                Army(id: "rival-army", ownerID: "rival", hexID: "near", unitIDs: ["rival-unit"]),
            ],
            cities: phase == .capitalPlacement ? [] : [
                City(id: "ai-capital", ownerID: "ai", hexID: "plains", levelID: "village", isCapital: true),
                City(id: "far-capital", ownerID: "rival", hexID: "far", levelID: "village", isCapital: true),
            ],
            phase: phase
        )
    }

    private func plan(in world: WorldState, map: StaticHexMap? = nil, encounter: PendingEncounter? = nil) -> AIPlan {
        BasicAIPlanner.plan(
            for: "ai",
            game: GameState(players: [Player(displayName: "ШІ", worldPlayerID: "ai"), Player(displayName: "Суперник", worldPlayerID: "rival")], seed: 1, phase: world.phase),
            world: world,
            economy: EconomyState(players: worldPlayers, startingGold: 100),
            content: content(map: map ?? self.map, world: world),
            pendingEncounter: encounter
        )
    }

    private func content(map: StaticHexMap, world: WorldState) -> GameContentConfiguration {
        GameContentConfiguration(
            terrain: terrain,
            units: units,
            cityLevels: cityLevels,
            buildings: [],
            scenario: ScenarioConfiguration(id: "fixture", displayName: "Fixture", startingGold: 100, map: map, world: world)
        )
    }
}
