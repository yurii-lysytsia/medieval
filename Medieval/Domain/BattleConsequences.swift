import Foundation

public struct BattleResolution: Equatable, Sendable {
    public let game: GameState
    public let world: WorldState
    public let report: BattleResult
}

public enum BattleConsequenceError: Error, Equatable, Sendable {
    case armyNotFound(ArmyID)
    case destinationMismatch
    case victory(VictoryRuleError)
}

public enum BattleConsequences {
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
            nextWorld.removeUnits(Set(report.defenderLosses))
            nextWorld.removeArmy(defender.id)
            update(report.attackerSurvivors, army: attacker, at: encounter.destination, in: &nextWorld)
            if nextWorld.cities.contains(where: { $0.hexID == encounter.destination && $0.isCapital && $0.ownerID == defender.ownerID }) {
                nextWorld.removeCapital(for: defender.ownerID)
                let victory = VictoryRules.resolveCapitalLoss(of: defender.ownerID, game: game, world: nextWorld)
                guard case let .success(resolution) = victory else {
                    guard case let .failure(error) = victory else { preconditionFailure() }
                    return .failure(.victory(error))
                }
                return .success(BattleResolution(game: resolution.game, world: resolution.world, report: report))
            }
        case .victory(.defender):
            nextWorld.removeUnits(Set(report.attackerLosses))
            nextWorld.removeArmy(attacker.id)
            update(report.defenderSurvivors, army: defender, at: defender.hexID, in: &nextWorld)
        case .draw:
            nextWorld.removeUnits(Set(attacker.unitIDs + defender.unitIDs))
            nextWorld.removeArmy(attacker.id)
            nextWorld.removeArmy(defender.id)
        }
        return .success(BattleResolution(game: game, world: nextWorld, report: report))
    }

    private static func update(_ survivors: [BattleUnitState], army: Army, at destination: HexID, in world: inout WorldState) {
        let survivorIDs = Set(survivors.map(\.id))
        world.removeUnits(Set(army.unitIDs).subtracting(survivorIDs))
        for survivor in survivors {
            guard let unit = world.units.first(where: { $0.id == survivor.id }) else { continue }
            world.replaceUnit(Unit(id: unit.id, ownerID: unit.ownerID, typeID: unit.typeID, currentHitPoints: survivor.hitPoints, condition: .moved, location: .hex(destination)))
        }
        world.replaceArmy(Army(id: army.id, ownerID: army.ownerID, hexID: destination, unitIDs: survivors.map(\.id), hasMoved: true))
    }
}
