import Foundation
@testable import Medieval
import Testing

struct WorldTests {
    @Test func worldStateRoundTripsThroughJSON() throws {
        let world = WorldState(
            players: [
                WorldPlayer(id: "crown", displayName: "Crown"),
                WorldPlayer(id: "union", displayName: "Union"),
            ],
            hexes: [
                Hex(id: "h-0-0", coordinate: HexCoordinate(q: 0, r: 0), terrainID: "plains"),
                Hex(id: "h-1-0", coordinate: HexCoordinate(q: 1, r: 0), terrainID: "forest"),
            ],
            riverBoundaries: [
                RiverBoundary(id: "river-0", boundary: HexBoundary(firstHexID: "h-0-0", secondHexID: "h-1-0")),
            ],
            armies: [Army(id: "army-1", ownerID: "crown", hexID: "h-0-0", unitTypeID: "spearmen", quantity: 3)],
            cities: [City(id: "city-1", ownerID: "crown", hexID: "h-0-0", levelID: "town", isCapital: true)],
            buildings: [Building(id: "building-1", cityID: "city-1", typeID: "market")],
            phase: .playerTurn
        )

        let decoded = try JSONDecoder().decode(WorldState.self, from: JSONEncoder().encode(world))

        #expect(decoded == world)
    }

    @Test func worldStateSupportsTheLargestMatch() {
        let players = (1 ... 4).map { WorldPlayer(id: WorldPlayerID(rawValue: "player-\($0)"), displayName: "Player \($0)") }

        let world = WorldState(players: players, hexes: [])

        #expect(world.players.count == 4)
        #expect(world.phase == .setup)
    }

    @Test func hexBoundaryIgnoresTheOrderItWasWrittenIn() {
        let forward = HexBoundary(firstHexID: "h-0-0", secondHexID: "h-1-0")
        let reversed = HexBoundary(firstHexID: "h-1-0", secondHexID: "h-0-0")

        #expect(forward == reversed)
        #expect(forward.hashValue == reversed.hashValue)
        #expect(Set([forward, reversed]).count == 1)
    }

    @Test func decodedBoundaryIsAlsoNormalised() throws {
        let reversed = """
        {"firstHexID":"h-1-0","secondHexID":"h-0-0"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(HexBoundary.self, from: reversed)

        #expect(decoded == HexBoundary(firstHexID: "h-0-0", secondHexID: "h-1-0"))
    }

    @Test func decodingRejectsAMatchOutsideTheSupportedPlayerCount() {
        let lonePlayer = """
        {"players":[{"id":"crown","displayName":"Crown"}],"hexes":[],
         "riverBoundaries":[],"armies":[],"cities":[],"buildings":[],"phase":"setup"}
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WorldState.self, from: lonePlayer)
        }
    }

    @Test func riverBoundaryIsFoundFromBothSides() {
        let world = WorldState(
            players: [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")],
            hexes: [],
            riverBoundaries: [RiverBoundary(id: "river", boundary: HexBoundary(firstHexID: "left", secondHexID: "right"))]
        )

        #expect(world.riverBoundary(between: "left", and: "right")?.id == "river")
        #expect(world.riverBoundary(between: "right", and: "left")?.id == "river")
    }
}
