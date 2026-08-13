import Foundation

/// Serialises writes to the save catalog off the main actor.
///
/// Autosaves are fired from the interface after phase changes and moves, so
/// they must neither stall the window nor race each other. Attempts are
/// numbered: a write that has already been overtaken by a newer one is dropped
/// rather than applied out of order.
actor AutosaveService {
    private let catalog: any GameSaveCatalog
    private var lastAppliedGeneration = 0

    init(catalog: any GameSaveCatalog) {
        self.catalog = catalog
    }

    func list() -> [SaveMetadata] {
        catalog.list()
    }

    @discardableResult
    func save(_ document: GameSaveDocument, generation: Int) -> Bool {
        guard generation > lastAppliedGeneration else { return false }
        lastAppliedGeneration = generation
        do {
            try catalog.save(document)
            return true
        } catch {
            return false
        }
    }

    /// Drops the autosave — used when the match ends, so nothing offers to
    /// resume a game that is over.
    func discard(generation: Int) {
        guard generation > lastAppliedGeneration else { return }
        lastAppliedGeneration = generation
        try? catalog.delete(GameSaveDocument.autosaveID)
    }
}
