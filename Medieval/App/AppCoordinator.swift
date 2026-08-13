import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    enum Route {
        case menu
        case game
    }

    @Published private(set) var route: Route = .menu
    let game = GameStore()

    func startNewGame(_ setup: [GameSetupPlayer]) {
        game.startNewGame(setup: setup)
        route = .game
    }

    func loadGame(_ id: UUID) {
        if game.loadSave(id) { route = .game }
    }

    func showMenu() {
        route = .menu
    }
}
