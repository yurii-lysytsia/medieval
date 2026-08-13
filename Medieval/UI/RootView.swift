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
        if game.state.phase == .finished {
            victoryScreen
        } else if game.state.phase == .handoff {
            handoffScreen
        } else {
            playScreen
        }
    }

    private var playScreen: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Medieval")
                        .font(.title2.weight(.bold))
                    Text("Стратегічна гра")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(game.state.phase == .combat ? "Завершити хід" : "Наступна фаза") {
                    if game.state.phase == .combat {
                        game.endTurn()
                    } else {
                        game.advancePhase()
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                Button("Огляд мапи") {
                    game.resetMapCamera()
                }
                Button("До меню", action: onShowMenu)
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                GameView(
                    state: game.state,
                    map: game.content.scenario.map,
                    world: game.world,
                    selectedHexID: game.selectedHexID,
                    reachableHexIDs: Set(game.movementPreview.map { Array($0.routes.keys) } ?? []),
                    encounterHexIDs: game.movementPreview?.encounterHexIDs ?? [],
                    previewRoute: game.previewRoute,
                    cameraResetToken: game.cameraResetToken,
                    onSelectHex: game.selectHex
                )
                .accessibilityLabel("Ігрове поле")

                Divider()
                mapInspector
            }
        }
    }

    private var handoffScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 56))
                .foregroundStyle(.brown)
            Text("Передайте пристрій")
                .font(.largeTitle.bold())
            Text("Наступний хід: \(game.state.activePlayer.displayName)")
                .font(.title3)
            Text("Ігрове поле та попередній вибір приховано.")
                .foregroundStyle(.secondary)
            Button("Почати хід") {
                game.confirmHandoff()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var victoryScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "trophy.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("Партію завершено")
                .font(.largeTitle.bold())
            if case let .winner(playerID) = game.state.result,
               let winner = game.state.players.first(where: { $0.id == playerID })
            {
                Text("Переможець: \(winner.displayName)")
                    .font(.title2)
            } else {
                Text("Нічия")
                    .font(.title2)
            }
            Button("Повернутися до меню", action: onShowMenu)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                if let route = game.previewRoute {
                    Text("Маршрут: \(route.cost) руху")
                        .fontWeight(.semibold)
                    Button(game.movementPreview?.encounterHexIDs.contains(selected.id) == true ? "Почати бій" : "Підтвердити рух") {
                        game.confirmMovement()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Виберіть гекс на мапі.").foregroundStyle(.secondary)
            }
            if let encounter = game.pendingEncounter {
                Divider()
                Label("Бій: \(encounter.attackerID.rawValue) → \(encounter.defenderID.rawValue)", systemImage: "burst.fill")
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .frame(width: 230)
        .padding()
    }
}
