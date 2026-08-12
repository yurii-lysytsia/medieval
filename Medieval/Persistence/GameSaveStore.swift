import Foundation
import MedievalDomain

/// Boundary for save storage. The concrete file-backed implementation arrives in MED-48.
protocol GameSaveStore {
    func loadMostRecent() throws -> GameState?
    func save(_ state: GameState) throws
}

final class InMemoryGameSaveStore: GameSaveStore {
    private var cachedState: GameState?

    func save(_ state: GameState) throws {
        cachedState = state
    }

    func loadMostRecent() throws -> GameState? {
        cachedState
    }
}
