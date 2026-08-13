import Combine
import Foundation

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var state: GameState
    @Published private(set) var content: GameContentConfiguration
    @Published private(set) var selectedHexID: HexID?
    @Published private(set) var cameraResetToken = 0

    init(
        state: GameState = GameState(players: [Player(displayName: "Корона"), Player(displayName: "Союз")]),
        content: GameContentConfiguration? = nil
    ) {
        self.state = state
        self.content = content ?? Self.loadBundledContent()
    }

    func send(_ action: GameAction) {
        guard case let .success(next) = GameRules.apply(action, to: state) else { return }
        state = next
    }

    func endTurn() {
        send(.endTurn(playerID: state.activePlayer.id))
    }

    func selectHex(_ id: HexID?) {
        selectedHexID = id
    }

    func resetMapCamera() {
        cameraResetToken += 1
    }

    func startNewGame() {
        content = Self.loadBundledContent()
        selectedHexID = nil
        state = GameState(players: content.scenario.world.players.map { Player(displayName: $0.displayName) })
    }

    private static func loadBundledContent() -> GameContentConfiguration {
        do {
            return try GameContentLoader.loadMVP()
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}
