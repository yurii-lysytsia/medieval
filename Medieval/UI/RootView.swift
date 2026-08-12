import MedievalDomain
import SwiftUI

struct RootView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        switch coordinator.route {
        case .menu:
            MainMenuView(onNewGame: coordinator.startNewGame)
        case .game:
            // The game screen observes the store directly. Reaching through
            // `coordinator.game` from a view that only observes the coordinator
            // would subscribe to the wrong publisher: GameStore's @Published
            // changes announce themselves on GameStore, so ending a turn or
            // selecting a hex would change state that never redraws.
            GameScreen(game: coordinator.game, onShowMenu: coordinator.showMenu)
        }
    }
}

struct GameScreen: View {
    @ObservedObject var game: GameStore
    let onShowMenu: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Medieval")
                        .font(.title2.weight(.bold))
                    Text("Стратегічна гра")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Завершити хід") {
                    game.endTurn()
                }
                .keyboardShortcut(.return, modifiers: [])
                Button("До меню", action: onShowMenu)
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                GameView(
                    state: game.state,
                    map: game.content.scenario.map,
                    world: game.content.scenario.world,
                    selectedHexID: game.selectedHexID,
                    onSelectHex: game.selectHex
                )
                .accessibilityLabel("Ігрове поле")

                Divider()
                mapInspector
            }
        }
    }

    private var mapInspector: some View {
        let selected = game.content.scenario.map.hexes.first { $0.id == game.selectedHexID }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Інспектор гекса")
                .font(.headline)
            if let selected {
                Text(selected.id.rawValue).font(.system(.body, design: .monospaced))
                Text("Координати: \(selected.coordinate.q), \(selected.coordinate.r)")
                Text("Місцевість: \(selected.terrainID.rawValue)")
                Text(game.content.isPassable(selected) ? "Прохідний" : "Непрохідний")
            } else {
                Text("Виберіть гекс на мапі.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(width: 230)
        .padding()
    }
}
