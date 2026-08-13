import Foundation
@testable import Medieval
import Testing

/// A catalog that keeps saves in memory, so these tests never touch the folder
/// the player's real matches live in.
private final class InMemorySaveCatalog: GameSaveCatalog, @unchecked Sendable {
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
