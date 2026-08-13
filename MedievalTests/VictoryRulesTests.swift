import Foundation
@testable import Medieval
import Testing

struct VictoryRulesTests {
    private let crownID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let unionID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test func lastPlayerWinsAfterEnemyCapitalIsDestroyed() throws {
        let resolution = try VictoryRules.resolveCapitalLoss(of: "union", game: game, world: worldWithoutUnionCapital).get()

        #expect(resolution.game.players.first(where: { $0.id == unionID })?.status == .eliminated)
        #expect(resolution.game.result == .winner(playerID: crownID))
        #expect(resolution.game.phase == .finished)
        #expect(resolution.world.phase == .finished)
        #expect(resolution.world.units.allSatisfy { $0.ownerID != "union" })
        #expect(resolution.world.armies.allSatisfy { $0.ownerID != "union" })
        #expect(resolution.game.journal.map(\.event) == [
            .playerEliminated(playerID: unionID),
            .matchFinished(.winner(playerID: crownID)),
        ])
    }

    @Test func noActionCanChangeFinishedGame() throws {
        let finished = try VictoryRules.resolveCapitalLoss(of: "union", game: game, world: worldWithoutUnionCapital).get().game

        #expect(GameRules.apply(.advancePhase(playerID: crownID), to: finished) == .failure(.gameIsFinished))
        #expect(GameRules.apply(.endTurn(playerID: crownID), to: finished) == .failure(.gameIsFinished))
    }

    @Test func standingCapitalCannotEliminateItsOwner() {
        var standing = worldWithoutUnionCapital
        standing.addCapital(for: "union", at: "union-home", levelID: "level-0")

        #expect(VictoryRules.resolveCapitalLoss(of: "union", game: game, world: standing) == .failure(.capitalStillStanding("union")))
    }

    private var game: GameState {
        GameState(players: [
            Player(id: crownID, displayName: "Crown", worldPlayerID: "crown"),
            Player(id: unionID, displayName: "Union", worldPlayerID: "union"),
        ], seed: 42, phase: .combat)
    }

    private var worldWithoutUnionCapital: WorldState {
        WorldState(
            players: [WorldPlayer(id: "crown", displayName: "Crown"), WorldPlayer(id: "union", displayName: "Union")],
            hexes: [
                Hex(id: "crown-home", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"),
                Hex(id: "union-home", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "plains"),
            ],
            units: [Unit(id: "union-unit", ownerID: "union", typeID: "infantry", currentHitPoints: 10, location: .hex("union-home"))],
            armies: [Army(id: "union-army", ownerID: "union", hexID: "union-home", unitIDs: ["union-unit"])],
            cities: [City(id: "capital-crown", ownerID: "crown", hexID: "crown-home", levelID: "level-0", isCapital: true)],
            phase: .combat
        )
    }
}
