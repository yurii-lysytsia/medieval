import Foundation

actor AutosaveService {
    private let catalog: any GameSaveCatalog

    init(catalog: any GameSaveCatalog) {
        self.catalog = catalog
    }

    func save(_ document: GameSaveDocument) -> Bool {
        do {
            try catalog.save(document)
            return true
        } catch {
            return false
        }
    }
}
