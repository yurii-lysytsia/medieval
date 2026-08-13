import Combine
import Foundation

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var state: GameState
    @Published private(set) var content: GameContentConfiguration
    @Published private(set) var selectedHexID: HexID?
    @Published private(set) var movementPreview: MovementPreview?
    @Published private(set) var previewRoute: MovementRoute?
    @Published private(set) var cameraResetToken = 0

    init(
        state: GameState = GameState(players: [Player(displayName: "Корона"), Player(displayName: "Союз")]),
        content: GameContentConfiguration? = nil
    ) {
        self.state = state
        self.content = content ?? Self.loadBundledContent()
    }

    @discardableResult
    func send(_ action: GameAction) -> Bool {
        guard case let .success(next) = GameRules.apply(action, to: state) else { return false }
        state = next
        return true
    }

    func advancePhase() {
        send(.advancePhase(playerID: state.activePlayer.id))
    }

    func endTurn() {
        if send(.endTurn(playerID: state.activePlayer.id)) {
            selectedHexID = nil
        }
    }

    func confirmHandoff() {
        send(.confirmHandoff(playerID: state.activePlayer.id))
    }

    func selectHex(_ id: HexID?) {
        selectedHexID = id
        guard state.phase == .movement, let id else {
            clearMovementPreview()
            return
        }
        if let movementPreview, let route = movementPreview.routes[id] {
            previewRoute = route
            return
        }
        guard let playerID = state.activePlayer.worldPlayerID,
              let army = content.scenario.world.armies.first(where: { $0.hexID == id && $0.ownerID == playerID })
        else {
            clearMovementPreview()
            return
        }
        movementPreview = MovementPreviewRules.preview(
            armyID: army.id,
            playerID: playerID,
            world: content.scenario.world,
            map: content.scenario.map,
            terrain: content.terrain,
            units: content.units
        )
        previewRoute = nil
    }

    func resetMapCamera() {
        cameraResetToken += 1
    }

    func startNewGame() {
        content = Self.loadBundledContent()
        selectedHexID = nil
        clearMovementPreview()
        state = GameState(players: content.scenario.world.players.map { Player(displayName: $0.displayName, worldPlayerID: $0.id) })
    }

    private func clearMovementPreview() {
        movementPreview = nil
        previewRoute = nil
    }

    private static func loadBundledContent() -> GameContentConfiguration {
        do {
            return try GameContentLoader.loadMVP()
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}
