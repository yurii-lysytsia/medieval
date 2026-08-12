import SwiftUI

struct ContentView: View {
    @ObservedObject var game: GameStore

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
                    game.send(.endTurn)
                }
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding()

            Divider()

            GameView(state: game.state, onAction: game.send)
                .accessibilityLabel("Ігрове поле")
        }
    }
}
