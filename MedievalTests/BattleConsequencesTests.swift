import Foundation
@testable import Medieval
import Testing

struct BattleConsequencesTests {
    @Test func attackerVictoryRemovesDefenderAndOccupiesHex() throws {
        let report = result(.victory(.attacker), attacker: [BattleUnitState(id: "a-unit", typeID: "infantry", hitPoints: 6)], defender: [])
        let resolution = try BattleConsequences.apply(report, encounter: encounter, game: game(threePlayers: true), world: world(capital: false)).get()
        #expect(resolution.world.armies.first(where: { $0.id == "attacker" })?.hexID == "target")
        #expect(resolution.world.armies.contains(where: { $0.id == "defender" }) == false)
        #expect(resolution.world.units.first(where: { $0.id == "a-unit" })?.currentHitPoints == 6)
    }

    @Test func mutualDestructionLeavesNoContradictoryArmies() throws {
        let report = result(.draw, attacker: [], defender: [])
        let resolution = try BattleConsequences.apply(report, encounter: encounter, game: game(threePlayers: false), world: world(capital: false)).get()
        #expect(resolution.world.armies.isEmpty)
        #expect(resolution.world.units.isEmpty)
    }

    @Test func capitalLossEliminatesOwnerAndTriggersVictory() throws {
        let report = result(.victory(.attacker), attacker: [BattleUnitState(id: "a-unit", typeID: "infantry", hitPoints: 6)], defender: [])
        let resolution = try BattleConsequences.apply(report, encounter: encounter, game: game(threePlayers: false), world: world(capital: true)).get()
        #expect(resolution.game.result == .winner(playerID: oneID))
        #expect(resolution.world.phase == .finished)
        #expect(resolution.world.cities.isEmpty)
    }

    private let oneID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let twoID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private var encounter: PendingEncounter { PendingEncounter(attackerID: "attacker", defenderID: "defender", destination: "target", route: MovementRoute(hexIDs: ["origin", "target"], cost: 1)) }
    private func result(_ outcome: BattleOutcome, attacker: [BattleUnitState], defender: [BattleUnitState]) -> BattleResult {
        BattleResult(outcome: outcome, rounds: [], attackerInitial: [BattleUnitState(id: "a-unit", typeID: "infantry", hitPoints: 10)], defenderInitial: [BattleUnitState(id: "d-unit", typeID: "infantry", hitPoints: 10)], attackerSurvivors: attacker, defenderSurvivors: defender, context: BattleContext())
    }

    private func game(threePlayers: Bool) -> GameState {
        var players = [Player(id: oneID, displayName: "One", worldPlayerID: "one"), Player(id: twoID, displayName: "Two", worldPlayerID: "two")]
        if threePlayers { players.append(Player(displayName: "Three", worldPlayerID: "three")) }
        return GameState(players: players, seed: 1, phase: .combat)
    }

    private func world(capital: Bool) -> WorldState {
        var players = [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")]
        if !capital { players.append(WorldPlayer(id: "three", displayName: "Three")) }
        return WorldState(players: players, hexes: [Hex(id: "origin", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"), Hex(id: "target", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "plains")], units: [
            Unit(id: "a-unit", ownerID: "one", typeID: "infantry", currentHitPoints: 10, location: .hex("origin")),
            Unit(id: "d-unit", ownerID: "two", typeID: "infantry", currentHitPoints: 10, location: .hex("target")),
        ], armies: [Army(id: "attacker", ownerID: "one", hexID: "origin", unitIDs: ["a-unit"]), Army(id: "defender", ownerID: "two", hexID: "target", unitIDs: ["d-unit"])], cities: capital ? [City(id: "capital", ownerID: "two", hexID: "target", levelID: "level-0", isCapital: true)] : [], phase: .combat)
    }
}
