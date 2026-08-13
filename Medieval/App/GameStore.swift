import Combine
import Foundation

@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var state: GameState
    @Published private(set) var content: GameContentConfiguration
    @Published private(set) var world: WorldState
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
    }

    @discardableResult
    func send(_ action: GameAction) -> Bool {
        guard case let .success(next) = GameRules.apply(action, to: state) else { return false }
        state = next
        world.setPhase(next.phase)
        return true
    }

    func advancePhase() {
        guard battleReport == nil else { return }
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

    func resetMapCamera() {
        cameraResetToken += 1
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
        guard case let .success(report) = AutomaticBattle.resolve(attackers: attackers, defenders: defenders, definitions: content.units, seed: state.seed ^ UInt64(state.turn), context: context) else { return }
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

    func startNewGame() {
        content = Self.loadBundledContent()
        world = content.scenario.world
        selectedHexID = nil
        clearMovementPreview()
        pendingEncounter = nil
        battleReport = nil
        state = GameState(players: content.scenario.world.players.map { Player(displayName: $0.displayName, worldPlayerID: $0.id) }, phase: world.phase)
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
