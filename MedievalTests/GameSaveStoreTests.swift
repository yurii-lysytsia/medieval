import Foundation
@testable import Medieval
import Testing

struct GameSaveStoreTests {
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

    @Test func autosaveUsesDedicatedSlotWithoutReplacingManualSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = FileGameSaveCatalog(directory: directory)
        let manual = makeDocument(name: "Manual")
        let worldPlayers = manual.world.players
        let autosave = GameSaveDocument(
            id: GameSaveDocument.autosaveID,
            name: "Autosave",
            kind: .autosave,
            game: manual.game,
            world: manual.world,
            economy: EconomyState(players: worldPlayers, startingGold: 120)
        )

        try catalog.save(manual)
        try catalog.save(autosave)

        #expect(Set(catalog.list().map(\.kind)) == [.manual, .autosave])
        let loadedManual = try catalog.load(manual.metadata.id)
        #expect(loadedManual.metadata.name == "Manual")
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
