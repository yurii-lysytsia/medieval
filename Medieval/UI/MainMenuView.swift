import SwiftUI

struct MainMenuView: View {
    let onNewGame: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("MEDIEVAL")
                .font(.system(size: 56, weight: .bold, design: .serif))
                .foregroundStyle(.brown)

            Text("Покрокова стратегія для одного Mac")
                .foregroundStyle(.secondary)

            Button("Нова гра", action: onNewGame)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])

            Text("Почніть тестову партію двох гравців.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
