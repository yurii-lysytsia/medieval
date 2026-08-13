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

    init(
        state: GameState = GameState(players: [Player(displayName: "Корона"), Player(displayName: "Союз")]),
        content: GameContentConfiguration? = nil
    ) {
        let loadedContent = content ?? Self.loadBundledContent()
        self.state = state
        self.content = loadedContent
        world = loadedContent.scenario.world
        economy = EconomyState(players: loadedContent.scenario.world.players, startingGold: loadedContent.scenario.startingGold)
    }

    var hud: TurnHUDSnapshot {
        TurnHUDSnapshot(state: state, economy: economy, hasBlockingPresentation: battleReport != nil || pendingEncounter != nil)
    }

    var selectedInspection: HexInspection? {
        selectedHexID.flatMap { HexInspection.inspect($0, map: content.scenario.map, world: world, content: content) }
    }

    @discardableResult
    func send(_ action: GameAction) -> Bool {
        guard case let .success(next) = GameRules.apply(action, to: state) else { return false }
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
        else { return }
        world = nextWorld
        if world.phase == .economy {
            state.finishCapitalPlacement()
        } else {
            state.advanceCapitalPlacement()
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
        guard case let .success(resolution) = result else { return }
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
        let seed = AutomaticBattle.seed(match: state.seed, turn: state.turn, encounter: encounter)
        guard case let .success(report) = AutomaticBattle.resolve(attackers: attackers, defenders: defenders, definitions: content.units, seed: seed, context: context) else { return }
        var journaledGame = state
        journaledGame.record(.battleResolved(report))
        guard case let .success(resolution) = BattleConsequences.apply(report, encounter: encounter, game: journaledGame, world: world) else { return }
        state = resolution.game
        world = resolution.world
        battleReport = report
        pendingEncounter = nil
    }

    func dismissBattleReport() {
        battleReport = nil
    }

    func startNewGame(setup: [GameSetupPlayer]? = nil) {
        content = Self.loadBundledContent()
        world = content.scenario.world
        selectedHexID = nil
        clearMovementPreview()
        pendingEncounter = nil
        battleReport = nil
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

    private static func loadBundledContent() -> GameContentConfiguration {
        do {
            return try GameContentLoader.loadMVP()
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}
