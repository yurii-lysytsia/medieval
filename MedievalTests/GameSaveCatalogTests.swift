import Foundation
@testable import Medieval
import Testing

struct GameSaveCatalogTests {
    @Test func atomicallySavesListsAndLoadsCompleteVersionedState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = FileGameSaveCatalog(directory: directory)
        let fixture = makeDocument(name: "Кампанія")

        try catalog.save(fixture)
        let loaded = try catalog.load(fixture.metadata.id)

        #expect(loaded == fixture)
        #expect(loaded.formatVersion == 1)
        #expect(catalog.list() == [fixture.metadata])
    }

    @Test func aFailedWriteLeavesThePreviousSaveIntact() throws {
        // The whole point of writing atomically: a save that does not complete
        // must not take the last good one with it.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = FileGameSaveCatalog(directory: directory)
        let good = makeDocument(name: "Кампанія")
        try catalog.save(good)

        let rejected = GameSaveDocument(id: good.metadata.id, name: "   ", updatedAt: Date(), game: good.game, world: good.world, economy: good.economy)
        #expect(throws: GameSaveError.invalidName) { try catalog.save(rejected) }

        #expect(try catalog.load(good.metadata.id) == good)
        #expect(catalog.list().map(\.name) == ["Кампанія"])
    }

    @Test func aSaveThisBuildCannotOpenIsStillListedAndReportsItsVersion() throws {
        // Hiding it from the list is indistinguishable from losing it; the
        // player should see the save and be told why it will not open.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let future = """
        {
          "formatVersion" : 99,
          "metadata" : {
            "id" : "\(id.uuidString)",
            "kind" : "manual",
            "name" : "З майбутнього",
            "playerNames" : ["One", "Two"],
            "turn" : 7,
            "updatedAt" : "2026-08-13T10:00:00Z"
          }
        }
        """
        try Data(future.utf8).write(to: directory.appendingPathComponent(id.uuidString).appendingPathExtension(FileGameSaveCatalog.fileExtension))
        let catalog = FileGameSaveCatalog(directory: directory)

        #expect(catalog.list().map(\.name) == ["З майбутнього"])
        #expect(throws: GameSaveError.unsupportedVersion(99)) { try catalog.load(id) }
    }

    @Test func corruptedFilesAreSkippedAndDoNotCrashCatalog() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("broken.medievalsave"))

        #expect(FileGameSaveCatalog(directory: directory).list().isEmpty)
    }

    @Test func deletionUpdatesCatalog() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = FileGameSaveCatalog(directory: directory)
        let fixture = makeDocument(name: "Delete")
        try catalog.save(fixture)

        try catalog.delete(fixture.metadata.id)

        #expect(catalog.list().isEmpty)
    }

    private func makeDocument(name: String) -> GameSaveDocument {
        let worldPlayers = [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")]
        let game = GameState(players: [Player(displayName: "One", worldPlayerID: "one"), Player(displayName: "Two", worldPlayerID: "two")], seed: 42)
        let world = WorldState(players: worldPlayers, hexes: [], phase: .economy)
        return GameSaveDocument(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000049")!,
            name: name,
            updatedAt: Date(timeIntervalSince1970: 100),
            game: game,
            world: world,
            economy: EconomyState(players: worldPlayers, startingGold: 120)
        )
    }
}
