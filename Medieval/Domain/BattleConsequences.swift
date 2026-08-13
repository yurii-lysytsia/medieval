import Foundation

public struct BattleResolution: Equatable, Sendable {
    public let game: GameState
    public let world: WorldState
    public let report: BattleResult
}

public enum BattleConsequenceError: Error, Equatable, LocalizedError, Sendable {
    case armyNotFound(ArmyID)
    case destinationMismatch
    case victory(VictoryRuleError)

    public var errorDescription: String? {
        switch self {
        case let .armyNotFound(armyID):
            "Army \"\(armyID.rawValue)\" is no longer on the map."
        case .destinationMismatch:
            "The defending army is not standing on the hex that was attacked."
        case let .victory(error):
            "The capital that fell could not be resolved: \(error)."
        }
    }
}

/// Settles the map once a battle has been fought.
public enum BattleConsequences {
    /// Applies `report` to the world the encounter was fought in.
    ///
    /// Every unit the battle killed leaves the map, the winner ends up holding
    /// the hex it fought over, and a city on that hex changes hands. Losing a
    /// capital is the one consequence that reaches past the map into the match
    /// itself, so it is handed to `VictoryRules`.
    public static func apply(
        _ report: BattleResult,
        encounter: PendingEncounter,
        game: GameState,
        world: WorldState
    ) -> Result<BattleResolution, BattleConsequenceError> {
        guard let attacker = world.armies.first(where: { $0.id == encounter.attackerID }) else { return .failure(.armyNotFound(encounter.attackerID)) }
        guard let defender = world.armies.first(where: { $0.id == encounter.defenderID }) else { return .failure(.armyNotFound(encounter.defenderID)) }
        guard defender.hexID == encounter.destination else { return .failure(.destinationMismatch) }
        var nextWorld = world

        switch report.outcome {
        case .victory(.attacker):
            settle(defender, survivors: report.defenderSurvivors, at: defender.hexID, in: &nextWorld)
            settle(attacker, survivors: report.attackerSurvivors, at: encounter.destination, in: &nextWorld)
            return capture(
                encounter.destination,
                from: defender.ownerID,
                by: attacker.ownerID,
                report: report,
                game: game,
                world: nextWorld
            )
        case .victory(.defender):
            settle(attacker, survivors: report.attackerSurvivors, at: attacker.hexID, in: &nextWorld)
            settle(defender, survivors: report.defenderSurvivors, at: defender.hexID, in: &nextWorld)
        case .draw:
            // A draw is not always mutual annihilation: a battle that runs into
            // the round cap ends with both armies still standing. Each side is
            // settled on the hex it started from, so the attacker does not walk
            // into a hex it failed to take.
            settle(attacker, survivors: report.attackerSurvivors, at: attacker.hexID, in: &nextWorld)
            settle(defender, survivors: report.defenderSurvivors, at: defender.hexID, in: &nextWorld)
        }
        return .success(BattleResolution(game: game, world: nextWorld, report: report))
    }

    /// Removes the army's dead and leaves whatever survived standing on `hexID`.
    ///
    /// An army with nothing left is removed outright rather than kept as an
    /// empty stack, which is what would otherwise leave a hex holding an army
    /// belonging to a side that lost every unit on it.
    private static func settle(_ army: Army, survivors: [BattleUnitState], at hexID: HexID, in world: inout WorldState) {
        let survivorIDs = Set(survivors.map(\.id))
        world.removeUnits(Set(army.unitIDs).subtracting(survivorIDs))
        guard !survivors.isEmpty else {
            world.removeArmy(army.id)
            return
        }
        for survivor in survivors {
            guard let unit = world.units.first(where: { $0.id == survivor.id }) else { continue }
            world.replaceUnit(Unit(id: unit.id, ownerID: unit.ownerID, typeID: unit.typeID, currentHitPoints: survivor.hitPoints, condition: .moved, location: .hex(hexID)))
        }
        world.replaceArmy(Army(id: army.id, ownerID: army.ownerID, hexID: hexID, unitIDs: survivors.map(\.id), hasMoved: true))
    }

    /// Hands over a city standing on the hex the attacker just took.
    ///
    /// A capital ends its owner's match, so that decision belongs to
    /// `VictoryRules`. Any other city simply changes owner — leaving it with
    /// the loser would put an enemy city under the winner's army, which is the
    /// contradictory hex this rule exists to prevent.
    private static func capture(
        _ hexID: HexID,
        from loserID: WorldPlayerID,
        by winnerID: WorldPlayerID,
        report: BattleResult,
        game: GameState,
        world: WorldState
    ) -> Result<BattleResolution, BattleConsequenceError> {
        var nextWorld = world
        guard let city = nextWorld.cities.first(where: { $0.hexID == hexID && $0.ownerID == loserID }) else {
            return .success(BattleResolution(game: game, world: nextWorld, report: report))
        }
        guard city.isCapital else {
            // The garrison falls with the city: those units never joined the
            // field battle, and they cannot go on serving the new owner.
            nextWorld.removeUnits(Set(nextWorld.units.filter { $0.location == .garrison(city.id) }.map(\.id)))
            nextWorld.transferCity(city.id, to: winnerID)
            return .success(BattleResolution(game: game, world: nextWorld, report: report))
        }
        nextWorld.removeCapital(for: loserID)
        return VictoryRules.resolveCapitalLoss(of: loserID, game: game, world: nextWorld)
            .map { BattleResolution(game: $0.game, world: $0.world, report: report) }
            .mapError(BattleConsequenceError.victory)
    }
}
