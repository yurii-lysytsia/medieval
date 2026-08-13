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
    private let autosaveService: AutosaveService
    private var autosaveGeneration = 0

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
        autosaveService = AutosaveService(catalog: saveCatalog)
        refreshSaves()
    }

    var hud: TurnHUDSnapshot {
        TurnHUDSnapshot(state: state, economy: economy, hasBlockingPresentation: battleReport != nil || pendingEncounter != nil)
    }

    var selectedInspection: HexInspection? {
        selectedHexID.flatMap { HexInspection.inspect($0, map: content.scenario.map, world: world, content: content) }
    }

    var journalItems: [JournalItem] {
        state.journal.enumerated().map { JournalItem(entry: $0.element, index: $0.offset, players: state.players) }
    }

    var resumableAutosave: SaveMetadata? {
        saves.first { $0.kind == .autosave }
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
        guard state.phase == .economy, let playerID = state.activePlayer.worldPlayerID else {
            send(.advancePhase(playerID: state.activePlayer.id))
            return
        }
        // Income and upkeep are settled on the way out of the economy phase, so
        // nobody can walk past their own upkeep. If the economy cannot resolve —
        // a content reference it cannot follow — the phase stays put: advancing
        // anyway would quietly cost the player a turn's income.
        guard case let .success(resolution) = EconomyRules.resolve(
            for: playerID,
            in: world,
            economy: economy,
            terrain: content.terrain,
            cityLevels: content.cityLevels,
            units: content.units,
            buildings: content.buildings
        ) else { return }
        guard send(.advancePhase(playerID: state.activePlayer.id)) else { return }
        world = resolution.world
        economy = resolution.economy
        let delta = resolution.entries.map(\.amount).reduce(0, +)
        present("Економіку підраховано: \(delta >= 0 ? "+" : "")\(delta) монет.", severity: .success)
        scheduleAutosave()
    }

    func endTurn() {
        if send(.endTurn(playerID: state.activePlayer.id)) {
            selectedHexID = nil
            scheduleAutosave()
        }
    }

    func confirmHandoff() {
        if send(.confirmHandoff(playerID: state.activePlayer.id)),
           let playerID = state.activePlayer.worldPlayerID
        {
            world.resetMovementCommands(for: playerID)
            present("Хід гравця \(state.activePlayer.displayName) розпочато.", severity: .information)
            scheduleAutosave()
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
                  terrain: content.terrain,
                  cityLevels: content.cityLevels
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
        scheduleAutosave()
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
        scheduleAutosave()
    }

    func resolvePendingBattle() {
        guard let encounter = pendingEncounter,
              let attacker = world.armies.first(where: { $0.id == encounter.attackerID }),
              let defender = world.armies.first(where: { $0.id == encounter.defenderID })
        else { return }
        let attackers = attacker.unitIDs.compactMap { id in world.units.first(where: { $0.id == id }) }
        let defenders = defender.unitIDs.compactMap { id in world.units.first(where: { $0.id == id }) }
        let context = BattleContextRules.context(attacker: attacker, defender: defender, destination: encounter.destination, world: world, terrain: content.terrain, units: content.units, buildings: content.buildings)
        let seed = AutomaticBattle.seed(match: state.seed, turn: state.turn, encounter: encounter)
        guard case let .success(report) = AutomaticBattle.resolve(attackers: attackers, defenders: defenders, definitions: content.units, seed: seed, context: context) else { return }
        var journaledGame = state
        journaledGame.record(.battleResolved(report))
        guard case let .success(resolution) = BattleConsequences.apply(report, encounter: encounter, game: journaledGame, world: world) else { return }
        state = resolution.game
        world = resolution.world
        battleReport = report
        pendingEncounter = nil
        present("Бій завершено. Звіт додано до журналу.", severity: .success)
        scheduleAutosave()
    }

    func dismissBattleReport() {
        battleReport = nil
    }

    func dismissCriticalNotice() {
        criticalNotice = nil
    }

    /// Rereads the catalog. Called for actions the player took deliberately —
    /// saving, deleting, opening the panel — which already do their file work
    /// here, so the list is refreshed in step with them. The autosave path uses
    /// the actor instead, because it fires on its own and must not stall a turn.
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
            // The running commentary belongs to the match that was on screen,
            // not to the one being loaded.
            notices = []
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
        // The wizard validates before it gets here and reports what is wrong;
        // re-validating would only give us a second, silent answer, and the
        // fallback it used to take started a different match than the one the
        // player set up.
        let choices = setup ?? world.players.enumerated().map { index, player in
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

    /// Records something worth telling the player about, and puts an error in
    /// front of them rather than only in the log. The backlog is capped because
    /// it is a running commentary, not the match record — the match keeps its
    /// own journal in `GameState`.
    private func present(_ text: String, severity: NoticeSeverity) {
        let notice = GameNotice(turn: state.turn, phase: state.phase, severity: severity, text: text)
        notices.append(notice)
        if notices.count > Self.retainedNotices { notices.removeFirst(notices.count - Self.retainedNotices) }
        if severity == .error { criticalNotice = notice }
    }

    private static let retainedNotices = 50

    /// Writes the match down without making the player wait for it.
    ///
    /// Each attempt carries a number so the service can drop one that has been
    /// overtaken: several actions in quick succession start several tasks, and
    /// tasks are not delivered in the order they were created, so an older match
    /// could otherwise land on disk after a newer one.
    private func scheduleAutosave() {
        // A finished match is not something to resume. Leaving the last
        // autosave in place would have the menu offer to continue a game that
        // already has a winner.
        guard state.phase != .finished else {
            let generation = nextAutosaveGeneration()
            Task { [autosaveService] in
                await autosaveService.discard(generation: generation)
                saves = await autosaveService.list()
            }
            return
        }
        let document = GameSaveDocument(
            id: GameSaveDocument.autosaveID,
            name: "Автозбереження",
            kind: .autosave,
            game: state,
            world: world,
            economy: economy,
            selectedHexID: selectedHexID
        )
        let generation = nextAutosaveGeneration()
        Task { [autosaveService] in
            await autosaveService.save(document, generation: generation)
            saves = await autosaveService.list()
        }
    }

    private func nextAutosaveGeneration() -> Int {
        autosaveGeneration += 1
        return autosaveGeneration
    }

    private static func loadBundledContent() -> GameContentConfiguration {
        do {
            // The Europe campaign is the map the game ships with. It is built
            // on top of the MVP catalogue, so terrain, units, city levels and
            // buildings all still come from the bundled content file.
            return try GameContentLoader.loadEuropeMap()
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}
