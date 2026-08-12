import MedievalDomain
import SwiftUI

struct RootView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        switch coordinator.route {
        case .menu:
            MainMenuView(onNewGame: coordinator.startNewGame)
        case .game:
            gameScreen
        }
    }

    private var gameScreen: some View {
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
                    coordinator.game.endTurn()
                }
                .keyboardShortcut(.return, modifiers: [])
                Button("До меню") {
                    coordinator.showMenu()
                }
            }
            .padding()

            Divider()

            GameView(state: coordinator.game.state, onEndTurn: coordinator.game.endTurn)
                .accessibilityLabel("Ігрове поле")
        }
    }
}
