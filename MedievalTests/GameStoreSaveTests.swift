import Foundation
@testable import Medieval
import Testing

/// A catalog that keeps saves in memory, so these tests never touch the folder
/// the player's real matches live in.
final class InMemorySaveCatalog: GameSaveCatalog, @unchecked Sendable {
    private var documents: [UUID: GameSaveDocument] = [:]
    var failsNextLoad = false

    func list() -> [SaveMetadata] {
        documents.values.map(\.metadata).sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ document: GameSaveDocument) throws {
        guard !document.metadata.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GameSaveError.invalidName
        }
        documents[document.metadata.id] = document
    }

    func load(_ id: UUID) throws -> GameSaveDocument {
        if failsNextLoad { throw GameSaveError.unreadableSave }
        guard let document = documents[id] else { throw GameSaveError.missingSave(id) }
        return document
    }

    func delete(_ id: UUID) throws {
        guard documents.removeValue(forKey: id) != nil else { throw GameSaveError.missingSave(id) }
    }
}

@MainActor
struct GameStoreSaveTests {
    @Test func savingListingLoadingAndDeletingKeepTheListInStep() throws {
        let catalog = InMemorySaveCatalog()
        let store = GameStore(saveCatalog: catalog)
        store.startNewGame(setup: [GameSetupPlayer(name: "Корона", color: .red), GameSetupPlayer(name: "Союз", color: .blue)])

        #expect(store.saves.isEmpty)
        #expect(store.createManualSave(named: "Перша"))
        #expect(store.saves.map(\.name) == ["Перша"])

        let saved = try #require(store.saves.first)
        #expect(saved.playerNames == ["Корона", "Союз"])
        #expect(saved.turn == store.state.turn)

        store.deleteSave(saved.id)
        #expect(store.saves.isEmpty)
    }

    @Test func loadingRestoresTheStateThatWasSaved() throws {
        let catalog = InMemorySaveCatalog()
        let store = GameStore(saveCatalog: catalog)
        store.startNewGame(setup: [GameSetupPlayer(name: "Корона", color: .red), GameSetupPlayer(name: "Союз", color: .blue)])
        #expect(store.createManualSave(named: "Контрольна"))
        let id = try #require(store.saves.first?.id)
        let savedState = store.state

        // Move on to a different match before loading the old one back.
        store.startNewGame(setup: [GameSetupPlayer(name: "Північ", color: .green), GameSetupPlayer(name: "Південь", color: .gold)])
        #expect(store.state.players.map(\.displayName) == ["Північ", "Південь"])

        #expect(store.loadSave(id))
        #expect(store.state == savedState)
        #expect(store.state.players.map(\.displayName) == ["Корона", "Союз"])
        #expect(store.saveError == nil)
    }

    @Test func aFailedLoadReportsWhyAndLeavesTheMatchAlone() throws {
        let catalog = InMemorySaveCatalog()
        let store = GameStore(saveCatalog: catalog)
        store.startNewGame(setup: [GameSetupPlayer(name: "Корона", color: .red), GameSetupPlayer(name: "Союз", color: .blue)])
        #expect(store.createManualSave(named: "Контрольна"))
        let id = try #require(store.saves.first?.id)
        let before = store.state
        catalog.failsNextLoad = true

        #expect(!store.loadSave(id))
        #expect(store.saveError != nil)
        #expect(store.state == before)
    }

    @Test func aSaveWithoutANameIsRejectedAndExplained() {
        let store = GameStore(saveCatalog: InMemorySaveCatalog())

        #expect(!store.createManualSave(named: "   "))
        #expect(store.saveError == GameSaveError.invalidName.localizedDescription)
        #expect(store.saves.isEmpty)
    }

    @Test func loadingAMatchDoesNotInheritTheNoticesOfThePreviousOne() throws {
        let catalog = InMemorySaveCatalog()
        let store = GameStore(saveCatalog: catalog)
        store.startNewGame(setup: [GameSetupPlayer(name: "Корона", color: .red), GameSetupPlayer(name: "Союз", color: .blue)])
        #expect(store.createManualSave(named: "Контрольна"))
        let id = try #require(store.saves.first?.id)

        #expect(store.loadSave(id))
        // Only the notice announcing the load itself.
        #expect(store.notices.count == 1)
    }
}

@MainActor
struct AutosaveTests {
    @Test func anOvertakenAutosaveIsDroppedInsteadOfLandingOutOfOrder() async throws {
        // Several actions in a row start several tasks, and tasks are not
        // delivered in the order they were created. Without the generation
        // check, an earlier match state could be written after a later one.
        let catalog = InMemorySaveCatalog()
        let service = AutosaveService(catalog: catalog)
        let older = makeAutosave(turn: 1)
        let newer = makeAutosave(turn: 9)

        let applied = await service.save(newer, generation: 2)
        let overtaken = await service.save(older, generation: 1)

        #expect(applied)
        #expect(!overtaken)

        #expect(try catalog.load(GameSaveDocument.autosaveID).game.turn == 9)
    }

    @Test func endingAMatchRemovesTheAutosaveSoNothingOffersToResumeIt() async throws {
        let catalog = InMemorySaveCatalog()
        let service = AutosaveService(catalog: catalog)
        let applied = await service.save(makeAutosave(turn: 3), generation: 1)
        #expect(applied)

        await service.discard(generation: 2)

        #expect(throws: GameSaveError.missingSave(GameSaveDocument.autosaveID)) {
            try catalog.load(GameSaveDocument.autosaveID)
        }
    }

    @Test func theAutosaveNeverTakesOverAManualSlot() async throws {
        let catalog = InMemorySaveCatalog()
        let service = AutosaveService(catalog: catalog)
        let manual = GameSaveDocument(name: "Ручне", game: makeGame(turn: 2), world: makeWorld(), economy: makeEconomy())
        try catalog.save(manual)

        let applied = await service.save(makeAutosave(turn: 5), generation: 1)
        let listed = await service.list()

        #expect(applied)
        #expect(try catalog.load(manual.metadata.id).metadata.name == "Ручне")
        #expect(listed.count == 2)
    }

    private func makeAutosave(turn: Int) -> GameSaveDocument {
        GameSaveDocument(
            id: GameSaveDocument.autosaveID,
            name: "Автозбереження",
            kind: .autosave,
            game: makeGame(turn: turn),
            world: makeWorld(),
            economy: makeEconomy()
        )
    }

    private func makeGame(turn: Int) -> GameState {
        GameState(players: [Player(displayName: "One", worldPlayerID: "one"), Player(displayName: "Two", worldPlayerID: "two")], seed: 42, turn: turn)
    }

    private func makeWorld() -> WorldState {
        WorldState(players: worldPlayers, hexes: [], phase: .economy)
    }

    private func makeEconomy() -> EconomyState {
        EconomyState(players: worldPlayers, startingGold: 100)
    }

    private let worldPlayers = [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")]
}
