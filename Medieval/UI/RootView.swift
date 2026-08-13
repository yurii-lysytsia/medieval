import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        switch coordinator.route {
        case .menu:
            MainMenuView(onNewGame: coordinator.startNewGame(_:))
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
    @State private var showsJournal = false

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
        ZStack {
            playBoard
            if let report = game.battleReport {
                battleReport(report)
            }
            if let notice = game.criticalNotice {
                criticalNotice(notice)
            }
        }
        .sheet(isPresented: $showsJournal) { journalView }
    }

    private var playBoard: some View {
        VStack(spacing: 0) {
            turnHUD
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

    /// Who is playing, what phase they are in, what it costs, and what to do
    /// next — the row is laid out so it stays legible when the window is at its
    /// minimum width: the hint truncates first, the controls never do.
    private var turnHUD: some View {
        let hud = game.hud
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                turnHUDStatus(hud)
                Divider().frame(height: 32)
                turnHUDCoins(hud)
                Text(hud.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 12)
                turnHUDControls(hud)
            }
            HStack(spacing: 12) {
                turnHUDStatus(hud)
                turnHUDCoins(hud)
                Spacer(minLength: 8)
                turnHUDControls(hud)
            }
        }
    }

    private func turnHUDStatus(_ hud: TurnHUDSnapshot) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(playerColor(hud.playerColor))
                .frame(width: 16, height: 16)
                .accessibilityLabel("Колір гравця")
            VStack(alignment: .leading, spacing: 3) {
                Text("\(hud.playerName) · хід \(hud.turn)")
                    .font(.headline)
                Text(hud.phaseTitle)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func turnHUDCoins(_ hud: TurnHUDSnapshot) -> some View {
        Label("\(hud.coins)", systemImage: "dollarsign.circle.fill")
            .font(.headline)
            .foregroundStyle(.yellow)
            .accessibilityLabel("Монети: \(hud.coins)")
    }

    private func turnHUDControls(_ hud: TurnHUDSnapshot) -> some View {
        HStack {
            Button("Скасувати вибір") { game.cancelSelection() }
                .disabled(game.selectedHexID == nil)
            Button(game.state.phase == .combat ? "Завершити хід" : "Наступна фаза") {
                if game.state.phase == .combat {
                    game.endTurn()
                } else {
                    game.advancePhase()
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!hud.canAdvance)
            Button("Огляд мапи") { game.resetMapCamera() }
            Button("Журнал") { showsJournal = true }
            Button("До меню", action: onShowMenu)
        }
        .fixedSize()
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
            Button("Вийти з гри") { NSApplication.shared.terminate(nil) }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mapInspector: some View {
        let selected = game.selectedInspection
        return VStack(alignment: .leading, spacing: 10) {
            Text("Інспектор гекса")
                .font(.headline)
            if let selected {
                Text(selected.id.rawValue).font(.system(.body, design: .monospaced))
                Text("Координати: \(selected.coordinate.q), \(selected.coordinate.r)")
                Text("Місцевість: \(selected.terrain)")
                Text("Рух: \(selected.movementCost) · Захист: \(signed(selected.defenseModifier)) · Дохід: \(signed(selected.incomeModifier))")
                Text(selected.riverCount == 0 ? "Річки: немає" : "Річки на межах: \(selected.riverCount)")
                Divider()
                cityInspector(selected.city)
                Divider()
                armyInspector(selected.armies)
                if game.state.phase == .capitalPlacement {
                    Text("Столицю розміщує: \(game.state.activePlayer.displayName)")
                        .fontWeight(.semibold)
                    Button("Заснувати столицю") {
                        game.placeCapital()
                    }
                    .buttonStyle(.borderedProminent)
                }
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
                Button("Розрахувати бій") {
                    game.resolvePendingBattle()
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .frame(width: 230)
        .padding()
    }

    /// Anything the hex does not have is stated outright rather than left blank,
    /// so an empty panel never reads as a panel that failed to load.
    @ViewBuilder
    private func cityInspector(_ city: CityInspection?) -> some View {
        if let city {
            Text(city.isCapital ? "Столиця · \(city.level)" : city.level).font(.headline)
            Text("Власник: \(city.owner ?? "нічия")")
            Text("Дохід: \(city.income.map(String.init) ?? "невідомо") · Найм за хід: \(city.recruitmentLimit.map(String.init) ?? "невідомо")")
            Text(city.buildings.isEmpty ? "Будівлі: немає" : "Будівлі: \(city.buildings.joined(separator: ", "))")
        } else {
            Text("Місто: немає").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func armyInspector(_ armies: [ArmyInspection]) -> some View {
        if armies.isEmpty {
            Text("Армії: немає").foregroundStyle(.secondary)
        } else {
            ForEach(armies) { army in
                Text("Армія · \(army.owner)").font(.headline)
                Text(army.units.isEmpty ? "Юніти: немає" : army.units.map { "\($0.name) \($0.hitPoints) HP" }.joined(separator: ", "))
                Text(army.hasMoved ? "Запас руху: використано" : "Запас руху: \(army.movementPoints)")
            }
        }
    }

    private func battleReport(_ report: BattleResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Звіт автоматичного бою").font(.title2.bold())
            Text("Раундів: \(report.rounds.count)")
            Text("Сили: \(report.attackerInitial.count) проти \(report.defenderInitial.count)")
            Text("Втрати: \(report.attackerLosses.count) / \(report.defenderLosses.count)")
            ForEach(Array(report.context.defenderModifiers.enumerated()), id: \.offset) { _, modifier in
                Text("\(modifierName(modifier.kind)): +\(modifier.percent)% оборони")
            }
            Text(reportOutcome(report.outcome)).font(.headline)
            Button("Продовжити") { game.dismissBattleReport() }
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
        // Not always mutual destruction: a battle that runs into the round cap
        // also ends without a winner, with both armies still on the map.
        case .draw: "Жодна сторона не перемогла"
        }
    }

    /// The report stores what a bonus was, not what to call it, so the wording
    /// lives here in the interface rather than inside a saved match.
    private func modifierName(_ kind: BattleModifierKind) -> String {
        switch kind {
        case .terrain: "Місцевість"
        case .river: "Річка"
        case .fortifications: "Укріплення"
        case .garrison: "Гарнізон"
        }
    }

    private var journalView: some View {
        NavigationStack {
            List {
                Section("Повідомлення") {
                    if game.notices.isEmpty {
                        Text("Поки що порожньо.").foregroundStyle(.secondary)
                    }
                    ForEach(game.notices.reversed()) { notice in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(notice.text)
                            Text("Хід \(notice.turn) · \(notice.phase.displayTitle) · \(notice.date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Події партії") {
                    if game.journalItems.isEmpty {
                        Text("Подій ще не було.").foregroundStyle(.secondary)
                    }
                    ForEach(game.journalItems.reversed()) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.text)
                            Text("Хід \(item.turn) · \(item.phase.displayTitle)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Журнал подій")
            .frame(minWidth: 560, minHeight: 420)
        }
    }

    private func criticalNotice(_ notice: GameNotice) -> some View {
        VStack(spacing: 12) {
            Label("Дія не виконана", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.red)
            Text(notice.text)
            Button("Зрозуміло") { game.dismissCriticalNotice() }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 16)
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
