import Combine
import Foundation

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var state: GameState
    @Published private(set) var content: GameContentConfiguration
    @Published private(set) var world: WorldState
    @Published private(set) var economy: EconomyState
    @Published private(set) var selectedHexID: HexID?
    @Published private(set) var movementPreview: MovementPreview?
    @Published private(set) var previewRoute: MovementRoute?
    @Published private(set) var pendingEncounter: PendingEncounter?
    @Published private(set) var battleReport: BattleResult?
    @Published private(set) var cameraResetToken = 0
    @Published private(set) var notices: [GameNotice] = []
    @Published private(set) var criticalNotice: GameNotice?
    @Published private(set) var saves: [SaveMetadata] = []
    @Published private(set) var saveError: String?
    private let saveCatalog: any GameSaveCatalog

    init(
        state: GameState = GameState(players: [Player(displayName: "Корона"), Player(displayName: "Союз")]),
        content: GameContentConfiguration? = nil,
        saveCatalog: any GameSaveCatalog = FileGameSaveCatalog()
    ) {
        let loadedContent = content ?? Self.loadBundledContent()
        self.state = state
        self.content = loadedContent
        world = loadedContent.scenario.world
        economy = EconomyState(players: loadedContent.scenario.world.players, startingGold: loadedContent.scenario.startingGold)
        self.saveCatalog = saveCatalog
        refreshSaves()
    }

    var hud: TurnHUDSnapshot {
        TurnHUDSnapshot(state: state, economy: economy, hasBlockingPresentation: battleReport != nil || pendingEncounter != nil)
    }

    var selectedInspection: HexInspection? {
        selectedHexID.flatMap { HexInspection.inspect($0, map: content.scenario.map, world: world, content: content) }
    }

    var journalItems: [JournalItem] {
        state.journal.enumerated().map { JournalItem(entry: $0.element, index: $0.offset) }
    }

    @discardableResult
    func send(_ action: GameAction) -> Bool {
        let result = GameRules.apply(action, to: state)
        guard case let .success(next) = result else {
            if case let .failure(error) = result { present(error.localizedDescription, severity: .error) }
            return false
        }
        state = next
        world.setPhase(next.phase)
        return true
    }

    func advancePhase() {
        guard hud.canAdvance else { return }
        if state.phase == .economy,
           let playerID = state.activePlayer.worldPlayerID,
           case let .success(resolution) = EconomyRules.resolve(
               for: playerID,
               in: world,
               economy: economy,
               terrain: content.terrain,
               cityLevels: content.cityLevels,
               units: content.units,
               buildings: content.buildings
           ),
           send(.advancePhase(playerID: state.activePlayer.id))
        {
            world = resolution.world
            economy = resolution.economy
            let delta = resolution.entries.map(\.amount).reduce(0, +)
            present("Економіку підраховано: \(delta >= 0 ? "+" : "")\(delta) монет.", severity: .success)
            return
        }
        send(.advancePhase(playerID: state.activePlayer.id))
    }

    func endTurn() {
        if send(.endTurn(playerID: state.activePlayer.id)) {
            selectedHexID = nil
        }
    }

    func confirmHandoff() {
        if send(.confirmHandoff(playerID: state.activePlayer.id)),
           let playerID = state.activePlayer.worldPlayerID
        {
            world.resetMovementCommands(for: playerID)
            present("Хід гравця \(state.activePlayer.displayName) розпочато.", severity: .information)
        }
    }

    func selectHex(_ id: HexID?) {
        selectedHexID = id
        guard state.phase == .movement, let id else {
            clearMovementPreview()
            return
        }
        if let movementPreview, let route = movementPreview.routes[id] {
            previewRoute = route
            return
        }
        guard let playerID = state.activePlayer.worldPlayerID,
              let army = world.armies.first(where: { $0.hexID == id && $0.ownerID == playerID })
        else {
            clearMovementPreview()
            return
        }
        movementPreview = MovementPreviewRules.preview(
            armyID: army.id,
            playerID: playerID,
            world: world,
            map: content.scenario.map,
            terrain: content.terrain,
            units: content.units
        )
        previewRoute = nil
    }

    func placeCapital() {
        guard state.phase == .capitalPlacement,
              let hexID = selectedHexID,
              let playerID = state.activePlayer.worldPlayerID,
              case let .success(nextWorld) = CapitalPlacementRules.placeCapital(
                  for: playerID,
                  at: hexID,
                  in: world,
                  terrain: content.terrain
              )
        else {
            present("Неможливо заснувати столицю на вибраному гексі.", severity: .error)
            return
        }
        world = nextWorld
        if world.phase == .economy {
            state.finishCapitalPlacement()
            present("Усі столиці розміщено. Починається економічна фаза.", severity: .success)
        } else {
            state.advanceCapitalPlacement()
            present("Столицю засновано. Хід наступного гравця.", severity: .success)
        }
        selectedHexID = nil
    }

    func resetMapCamera() {
        cameraResetToken += 1
    }

    func cancelSelection() {
        selectedHexID = nil
        clearMovementPreview()
    }

    func confirmMovement() {
        guard let armyID = movementPreview?.armyID, let previewRoute else { return }
        let result = StrategicMovementRules.confirmArmyMovement(
            armyID: armyID,
            route: previewRoute,
            game: state,
            world: world,
            map: content.scenario.map,
            terrain: content.terrain,
            units: content.units
        )
        guard case let .success(resolution) = result else {
            present("Маршрут більше недоступний. Оберіть рух ще раз.", severity: .error)
            return
        }
        state = resolution.game
        world = resolution.world
        pendingEncounter = resolution.encounter
        selectedHexID = resolution.encounter?.destination ?? previewRoute.hexIDs.last
        clearMovementPreview()
    }

    func resolvePendingBattle() {
        guard let encounter = pendingEncounter,
              let attacker = world.armies.first(where: { $0.id == encounter.attackerID }),
              let defender = world.armies.first(where: { $0.id == encounter.defenderID })
        else { return }
        let attackers = attacker.unitIDs.compactMap { id in world.units.first(where: { $0.id == id }) }
        let defenders = defender.unitIDs.compactMap { id in world.units.first(where: { $0.id == id }) }
        let context = BattleContextRules.context(attacker: attacker, defender: defender, destination: encounter.destination, world: world, terrain: content.terrain, units: content.units, buildings: content.buildings)
        guard case let .success(report) = AutomaticBattle.resolve(attackers: attackers, defenders: defenders, definitions: content.units, seed: state.seed ^ UInt64(state.turn), context: context) else { return }
        var journaledGame = state
        journaledGame.record(.battleResolved(report))
        guard case let .success(resolution) = BattleConsequences.apply(report, encounter: encounter, game: journaledGame, world: world) else { return }
        state = resolution.game
        world = resolution.world
        battleReport = report
        pendingEncounter = nil
        present("Бій завершено. Звіт додано до журналу.", severity: .success)
    }

    func dismissBattleReport() {
        battleReport = nil
    }

    func dismissCriticalNotice() {
        criticalNotice = nil
    }

    func refreshSaves() {
        saves = saveCatalog.list()
    }

    @discardableResult
    func createManualSave(named name: String) -> Bool {
        do {
            try saveCatalog.save(GameSaveDocument(name: name, game: state, world: world, economy: economy, selectedHexID: selectedHexID))
            saveError = nil
            refreshSaves()
            present("Партію «\(name.trimmingCharacters(in: .whitespacesAndNewlines))» збережено.", severity: .success)
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func loadSave(_ id: UUID) -> Bool {
        do {
            let document = try saveCatalog.load(id)
            content = Self.loadBundledContent()
            state = document.game
            world = document.world
            economy = document.economy
            selectedHexID = document.selectedHexID
            clearMovementPreview()
            pendingEncounter = nil
            battleReport = nil
            criticalNotice = nil
            saveError = nil
            refreshSaves()
            present("Збереження «\(document.metadata.name)» завантажено.", severity: .success)
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    func deleteSave(_ id: UUID) {
        do {
            try saveCatalog.delete(id)
            saveError = nil
            refreshSaves()
        } catch {
            saveError = error.localizedDescription
        }
    }

    func startNewGame(setup: [GameSetupPlayer]? = nil) {
        content = Self.loadBundledContent()
        world = content.scenario.world
        selectedHexID = nil
        clearMovementPreview()
        pendingEncounter = nil
        battleReport = nil
        notices = []
        criticalNotice = nil
        let configured: [GameSetupPlayer]?
        if let setup, case let .success(valid) = GameSetupRules.validate(setup) {
            configured = valid
        } else {
            configured = nil
        }
        let choices = configured ?? world.players.enumerated().map { index, player in
            GameSetupPlayer(name: player.displayName, color: PlayerColor.allCases[index])
        }
        let worldPlayers = choices.enumerated().map { index, choice in
            WorldPlayer(id: WorldPlayerID(rawValue: "player-\(index + 1)"), displayName: choice.name)
        }
        world.configurePlayers(worldPlayers)
        economy = EconomyState(players: worldPlayers, startingGold: content.scenario.startingGold)
        let players = worldPlayers.enumerated().map { index, worldPlayer in
            Player(displayName: choices[index].name, worldPlayerID: worldPlayer.id, color: choices[index].color)
        }
        state = GameState(players: players, phase: world.phase)
    }

    private func clearMovementPreview() {
        movementPreview = nil
        previewRoute = nil
    }

    private func present(_ text: String, severity: NoticeSeverity) {
        let notice = GameNotice(turn: state.turn, phase: state.phase, severity: severity, text: text)
        notices.append(notice)
        if notices.count > 50 { notices.removeFirst(notices.count - 50) }
        if severity == .error { criticalNotice = notice }
    }

    private static func loadBundledContent() -> GameContentConfiguration {
        do {
            return try GameContentLoader.loadMVP()
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}
