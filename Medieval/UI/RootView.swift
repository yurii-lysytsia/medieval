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
                    world: game.content.scenario.world,
                    selectedHexID: game.selectedHexID,
                    cameraResetToken: game.cameraResetToken,
                    onSelectHex: game.selectHex
                )
                .accessibilityLabel("Ігрове поле")

                Divider()

                HStack(spacing: 0) {
                    GameView(
                        state: coordinator.game.state,
                        map: coordinator.game.content.scenario.map,
                        world: coordinator.game.world,
                        selectedHexID: coordinator.game.selectedHexID,
                        reachableHexIDs: Set(coordinator.game.movementPreview.map { Array($0.routes.keys) } ?? []),
                        encounterHexIDs: coordinator.game.movementPreview?.encounterHexIDs ?? [],
                        previewRoute: coordinator.game.previewRoute,
                        cameraResetToken: coordinator.game.cameraResetToken,
                        onSelectHex: coordinator.game.selectHex
                    )
                    .accessibilityLabel("Ігрове поле")

                    Divider()
                    mapInspector
                }
            }
            if let report = coordinator.game.battleReport {
                battleReport(report)
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
            Text("Наступний хід: \(coordinator.game.state.activePlayer.displayName)")
                .font(.title3)
            Text("Ігрове поле та попередній вибір приховано.")
                .foregroundStyle(.secondary)
            Button("Почати хід") {
                coordinator.game.confirmHandoff()
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
            if case let .winner(playerID) = coordinator.game.state.result,
               let winner = coordinator.game.state.players.first(where: { $0.id == playerID })
            {
                Text("Переможець: \(winner.displayName)")
                    .font(.title2)
            } else {
                Text("Нічия")
                    .font(.title2)
            }
            Button("Повернутися до меню") {
                coordinator.showMenu()
            }
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
            } else {
                Text("Виберіть гекс на мапі.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(width: 230)
        .padding()
    }

    private func battleReport(_ report: BattleResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Звіт автоматичного бою").font(.title2.bold())
            Text("Раундів: \(report.rounds.count)")
            Text("Сили: \(report.attackerInitial.count) проти \(report.defenderInitial.count)")
            Text("Втрати: \(report.attackerLosses.count) / \(report.defenderLosses.count)")
            ForEach(Array(report.context.defenderModifiers.enumerated()), id: \.offset) { _, modifier in
                Text("\(modifier.name): +\(modifier.percent)% оборони")
            }
            Text(reportOutcome(report.outcome)).font(.headline)
            Button("Продовжити") { coordinator.game.dismissBattleReport() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 390)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(radius: 20)
    }

    private func reportOutcome(_ outcome: BattleOutcome) -> String {
        switch outcome {
        case .victory(.attacker): "Переміг атакувальник"
        case .victory(.defender): "Переміг захисник"
        case .draw: "Обидві сторони знищено"
        }
    }

    private func playerColor(_ color: PlayerColor) -> Color {
        switch color {
        case .red: .red
        case .blue: .blue
        case .green: .green
        case .gold: .yellow
        }
    }

    private func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }
}
