import AppKit
import SwiftUI

struct MainMenuView: View {
    @ObservedObject var game: GameStore
    let onNewGame: ([GameSetupPlayer]) -> Void
    let onLoadGame: (UUID) -> Void
    @State private var isCreatingGame = false
    @State private var playerCount = 2
    @State private var names = ["Корона", "Союз", "Північ", "Південь"]
    @State private var errorMessage: String?
    @State private var showsSaves = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("MEDIEVAL").font(.system(size: 56, weight: .bold, design: .serif)).foregroundStyle(.brown)
            Text("Покрокова стратегія для одного Mac").foregroundStyle(.secondary)
            if isCreatingGame { wizard } else { menu }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(isPresented: $showsSaves) {
            SaveManagerView(game: game, allowsSaving: false) { id in
                showsSaves = false
                onLoadGame(id)
            }
        }
    }

    private var menu: some View {
        VStack(spacing: 12) {
            Button("Нова гра") { isCreatingGame = true }.buttonStyle(.borderedProminent)
            Button("Завантажити") {
                game.refreshSaves()
                showsSaves = true
            }
            Button("Налаштування") {}.disabled(true)
            Button("Вийти") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.large)
    }

    private var wizard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("Гравців: \(playerCount)", value: $playerCount, in: 2 ... 4)
            ForEach(0 ..< playerCount, id: \.self) { index in
                HStack {
                    TextField("Ім’я", text: $names[index]).textFieldStyle(.roundedBorder)
                    Text(PlayerColor.allCases[index].rawValue.capitalized).frame(width: 70)
                }
            }
            Text("Після старту гравці по черзі розміщують столиці.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Назад") { isCreatingGame = false }
                Button("Створити партію") { createGame() }.buttonStyle(.borderedProminent)
            }
        }
        .frame(width: 360)
    }

    private func createGame() {
        let setup = (0 ..< playerCount).map { GameSetupPlayer(name: names[$0], color: PlayerColor.allCases[$0]) }
        switch GameSetupRules.validate(setup) {
        case let .success(valid): onNewGame(valid)
        case let .failure(error): errorMessage = error.localizedDescription
        }
    }
}
