import Foundation
@testable import Medieval
import Testing

struct BattleConsequencesTests {
    @Test func attackerVictoryRemovesDefenderAndOccupiesHex() throws {
        let report = result(.victory(.attacker), attacker: [BattleUnitState(id: "a-unit", typeID: "infantry", hitPoints: 6)], defender: [])
        let resolution = try BattleConsequences.apply(report, encounter: encounter, game: game(threePlayers: true), world: world(city: .none)).get()

        #expect(resolution.world.armies.first(where: { $0.id == "attacker" })?.hexID == "target")
        #expect(resolution.world.armies.contains(where: { $0.id == "defender" }) == false)
        #expect(resolution.world.units.first(where: { $0.id == "a-unit" })?.currentHitPoints == 6)
        #expect(resolution.world.units.contains(where: { $0.id == "d-unit" }) == false)
    }

    @Test func mutualDestructionLeavesNoContradictoryArmies() throws {
        let report = result(.draw, attacker: [], defender: [])
        let resolution = try BattleConsequences.apply(report, encounter: encounter, game: game(threePlayers: false), world: world(city: .none)).get()

        #expect(resolution.world.armies.isEmpty)
        #expect(resolution.world.units.isEmpty)
    }

    @Test func aDrawWithSurvivorsLeavesBothArmiesWhereTheyStood() throws {
        // A battle that runs into the round cap ends in a draw with both sides
        // alive. Reading every draw as mutual annihilation killed units the
        // battle never touched.
        let report = result(
            .draw,
            attacker: [BattleUnitState(id: "a-unit", typeID: "infantry", hitPoints: 3)],
            defender: [BattleUnitState(id: "d-unit", typeID: "infantry", hitPoints: 4)]
        )
        let resolution = try BattleConsequences.apply(report, encounter: encounter, game: game(threePlayers: false), world: world(city: .none)).get()

        #expect(resolution.world.armies.first(where: { $0.id == "attacker" })?.hexID == "origin")
        #expect(resolution.world.armies.first(where: { $0.id == "defender" })?.hexID == "target")
        #expect(resolution.world.units.first(where: { $0.id == "a-unit" })?.currentHitPoints == 3)
        #expect(resolution.world.units.first(where: { $0.id == "d-unit" })?.currentHitPoints == 4)
    }

    @Test func takingAnOrdinaryCityTransfersItInsteadOfLeavingItWithTheLoser() throws {
        // The winner standing on a hex whose city still belongs to the loser is
        // exactly the contradictory composition this rule has to prevent.
        let report = result(.victory(.attacker), attacker: [BattleUnitState(id: "a-unit", typeID: "infantry", hitPoints: 6)], defender: [])
        let resolution = try BattleConsequences.apply(report, encounter: encounter, game: game(threePlayers: true), world: world(city: .ordinary)).get()

        let city = try #require(resolution.world.cities.first)
        #expect(city.ownerID == "one")
        #expect(city.levelID == "level-0")
        #expect(resolution.world.buildings.map(\.id) == ["market"])
        // The garrison never joined the field battle and cannot serve the taker.
        #expect(resolution.world.units.contains(where: { $0.id == "garrison" }) == false)
        #expect(resolution.game.result == nil)
    }

    @Test func capitalLossEliminatesOwnerAndTriggersVictory() throws {
        let report = result(.victory(.attacker), attacker: [BattleUnitState(id: "a-unit", typeID: "infantry", hitPoints: 6)], defender: [])
        let resolution = try BattleConsequences.apply(report, encounter: encounter, game: game(threePlayers: false), world: world(city: .capital)).get()

        #expect(resolution.game.result == .winner(playerID: oneID))
        #expect(resolution.world.phase == .finished)
        #expect(resolution.world.cities.isEmpty)
    }

    @Test func anEncounterThatNoLongerMatchesTheMapIsRejected() {
        let report = result(.draw, attacker: [], defender: [])
        let missing = PendingEncounter(attackerID: "ghost", defenderID: "defender", destination: "target", route: MovementRoute(hexIDs: ["origin", "target"], cost: 1))
        let elsewhere = PendingEncounter(attackerID: "attacker", defenderID: "defender", destination: "origin", route: MovementRoute(hexIDs: ["origin"], cost: 0))

        #expect(BattleConsequences.apply(report, encounter: missing, game: game(threePlayers: false), world: world(city: .none)) == .failure(.armyNotFound("ghost")))
        #expect(BattleConsequences.apply(report, encounter: elsewhere, game: game(threePlayers: false), world: world(city: .none)) == .failure(.destinationMismatch))
    }

    private enum CityOnTarget { case none, ordinary, capital }

    private let oneID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let twoID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private var encounter: PendingEncounter { PendingEncounter(attackerID: "attacker", defenderID: "defender", destination: "target", route: MovementRoute(hexIDs: ["origin", "target"], cost: 1)) }

    private func result(_ outcome: BattleOutcome, attacker: [BattleUnitState], defender: [BattleUnitState]) -> BattleResult {
        BattleResult(
            outcome: outcome,
            rounds: [],
            attackerInitial: [BattleUnitState(id: "a-unit", typeID: "infantry", hitPoints: 10)],
            defenderInitial: [BattleUnitState(id: "d-unit", typeID: "infantry", hitPoints: 10)],
            attackerSurvivors: attacker,
            defenderSurvivors: defender,
            context: BattleContext()
        )
    }

    private func game(threePlayers: Bool) -> GameState {
        var players = [Player(id: oneID, displayName: "One", worldPlayerID: "one"), Player(id: twoID, displayName: "Two", worldPlayerID: "two")]
        if threePlayers { players.append(Player(displayName: "Three", worldPlayerID: "three")) }
        return GameState(players: players, seed: 1, phase: .combat)
    }

    private func world(city: CityOnTarget) -> WorldState {
        var players = [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")]
        if city != .capital { players.append(WorldPlayer(id: "three", displayName: "Three")) }
        var units = [
            Unit(id: "a-unit", ownerID: "one", typeID: "infantry", currentHitPoints: 10, location: .hex("origin")),
            Unit(id: "d-unit", ownerID: "two", typeID: "infantry", currentHitPoints: 10, location: .hex("target")),
        ]
        if city == .ordinary {
            units.append(Unit(id: "garrison", ownerID: "two", typeID: "infantry", currentHitPoints: 10, location: .garrison("town")))
        }
        return WorldState(
            players: players,
            hexes: [
                Hex(id: "origin", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"),
                Hex(id: "target", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "plains"),
            ],
            units: units,
            armies: [
                Army(id: "attacker", ownerID: "one", hexID: "origin", unitIDs: ["a-unit"]),
                Army(id: "defender", ownerID: "two", hexID: "target", unitIDs: ["d-unit"]),
            ],
            cities: cities(city),
            buildings: city == .ordinary ? [Building(id: "market", cityID: "town", typeID: "market")] : [],
            phase: .combat
        )
    }

    private func cities(_ city: CityOnTarget) -> [City] {
        switch city {
        case .none: []
        case .ordinary: [City(id: "town", ownerID: "two", hexID: "target", levelID: "level-0")]
        case .capital: [City(id: "capital", ownerID: "two", hexID: "target", levelID: "level-0", isCapital: true)]
        }
    }
}
