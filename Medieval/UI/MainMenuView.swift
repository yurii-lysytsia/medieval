import AppKit
import SwiftUI

struct MainMenuView: View {
    @ObservedObject var game: GameStore
    let onNewGame: ([GameSetupPlayer]) -> Void
    let onLoadGame: (UUID) -> Void
    @State private var isCreatingGame = false
    @State private var playerCount = 2
    @State private var names = ["Корона", "Союз", "Північ", "Південь"]
    @State private var colors = PlayerColor.allCases
    @State private var errorMessage: String?
    @State private var showsSaves = false
    @State private var dismissedAutosave = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("MEDIEVAL").font(.system(size: 56, weight: .bold, design: .serif)).foregroundStyle(.brown)
            Text("Покрокова стратегія для одного Mac").foregroundStyle(.secondary)
            if let autosave = game.resumableAutosave, !dismissedAutosave, !isCreatingGame {
                VStack(spacing: 8) {
                    Text("Продовжити незавершену партію?").font(.headline)
                    Text("Хід \(autosave.turn) · \(autosave.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Продовжити") { onLoadGame(autosave.id) }.buttonStyle(.borderedProminent)
                        Button("Не зараз") { dismissedAutosave = true }
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            if isCreatingGame { wizard } else { menu }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(isPresented: $showsSaves) {
            // Loading switches the route, which takes the whole menu — and this
            // sheet — away. Dismissing here instead would hide the panel before
            // a failed load could report why.
            SaveManagerView(game: game, allowsSaving: false, onLoad: onLoadGame)
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
            Stepper("Гравців: \(playerCount)", value: $playerCount, in: GameSetupRules.supportedPlayerCount)
            ForEach(0 ..< playerCount, id: \.self) { index in
                HStack {
                    TextField("Ім’я", text: $names[index]).textFieldStyle(.roundedBorder)
                    Picker("", selection: $colors[index]) {
                        ForEach(PlayerColor.allCases, id: \.self) { color in
                            Text(colorName(color)).tag(color)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
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
        let setup = (0 ..< playerCount).map { GameSetupPlayer(name: names[$0], color: colors[$0]) }
        switch GameSetupRules.validate(setup) {
        case let .success(valid):
            errorMessage = nil
            onNewGame(valid)
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    private func colorName(_ color: PlayerColor) -> String {
        switch color {
        case .red: "Червоний"
        case .blue: "Синій"
        case .green: "Зелений"
        case .gold: "Золотий"
        }
    }
}
