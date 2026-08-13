import Foundation

public enum BattleSide: String, Codable, Equatable, Sendable {
    case attacker
    case defender
}

public enum BattleOutcome: Codable, Equatable, Sendable {
    case victory(BattleSide)
    case draw
}

public struct BattleUnitState: Codable, Equatable, Sendable {
    public let id: UnitID
    public let typeID: UnitTypeID
    public let hitPoints: Int

    public init(id: UnitID, typeID: UnitTypeID, hitPoints: Int) {
        self.id = id
        self.typeID = typeID
        self.hitPoints = hitPoints
    }
}

public struct BattleRound: Codable, Equatable, Sendable {
    public let number: Int
    public let attackerRoll: Int
    public let defenderRoll: Int
    public let attackerDamage: Int
    public let defenderDamage: Int
    public let destroyedUnitIDs: [UnitID]
}

public struct BattleModifier: Codable, Equatable, Sendable {
    public let name: String
    public let percent: Int

    public init(name: String, percent: Int) {
        self.name = name
        self.percent = percent
    }
}

public struct BattleContext: Codable, Equatable, Sendable {
    public let attackerRollBonus: Int
    public let defenderRollBonus: Int
    public let defenderModifiers: [BattleModifier]

    public init(attackerRollBonus: Int = 0, defenderRollBonus: Int = 0, defenderModifiers: [BattleModifier] = []) {
        self.attackerRollBonus = attackerRollBonus
        self.defenderRollBonus = defenderRollBonus
        self.defenderModifiers = defenderModifiers
    }

    public var defenderDamageReduction: Int { min(90, max(-90, defenderModifiers.reduce(0) { $0 + $1.percent })) }
}

public struct BattleResult: Codable, Equatable, Sendable {
    public let outcome: BattleOutcome
    public let rounds: [BattleRound]
    public let attackerInitial: [BattleUnitState]
    public let defenderInitial: [BattleUnitState]
    public let attackerSurvivors: [BattleUnitState]
    public let defenderSurvivors: [BattleUnitState]
    public let context: BattleContext

    public var attackerLosses: [UnitID] { attackerInitial.map(\.id).filter { id in !attackerSurvivors.contains(where: { $0.id == id }) } }
    public var defenderLosses: [UnitID] { defenderInitial.map(\.id).filter { id in !defenderSurvivors.contains(where: { $0.id == id }) } }
}

public enum AutomaticBattleError: Error, Equatable, Sendable {
    case emptyArmy(BattleSide)
    case missingDefinition(UnitTypeID)
}

public enum AutomaticBattle {
    public static func resolve(
        attackers: [Unit],
        defenders: [Unit],
        definitions: [UnitDefinition],
        seed: UInt64,
        context: BattleContext = BattleContext()
    ) -> Result<BattleResult, AutomaticBattleError> {
        guard !attackers.isEmpty else { return .failure(.emptyArmy(.attacker)) }
        guard !defenders.isEmpty else { return .failure(.emptyArmy(.defender)) }
        let definitionByID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        if let typeID = (attackers + defenders).map(\.typeID).first(where: { definitionByID[$0] == nil }) {
            return .failure(.missingDefinition(typeID))
        }
        let attackerInitial = attackers.map { BattleUnitState(id: $0.id, typeID: $0.typeID, hitPoints: $0.currentHitPoints) }
        let defenderInitial = defenders.map { BattleUnitState(id: $0.id, typeID: $0.typeID, hitPoints: $0.currentHitPoints) }
        var attackerHP = Dictionary(uniqueKeysWithValues: attackerInitial.map { ($0.id, $0.hitPoints) })
        var defenderHP = Dictionary(uniqueKeysWithValues: defenderInitial.map { ($0.id, $0.hitPoints) })
        var generator = SeededRandomNumberGenerator(seed: seed)
        var rounds: [BattleRound] = []

        for number in 1 ... 100 where !living(attackerHP).isEmpty && !living(defenderHP).isEmpty {
            let attackerRoll = Int(generator.next() % 10) + context.attackerRollBonus
            let defenderRoll = Int(generator.next() % 10) + context.defenderRollBonus
            let rollModifier = min(45, max(-45, (attackerRoll - defenderRoll) * 5))
            var attackerDamage = 0
            var defenderDamage = 0
            var destroyed: [UnitID] = []

            for ranged in [true, false] {
                let attackerBase = damage(from: attackers, hp: attackerHP, definitions: definitionByID, ranged: ranged)
                let defenderBase = damage(from: defenders, hp: defenderHP, definitions: definitionByID, ranged: ranged)
                let attackerStage = adjusted(attackerBase, percent: rollModifier - context.defenderDamageReduction)
                let defenderStage = adjusted(defenderBase, percent: -rollModifier)
                attackerDamage += attackerStage
                defenderDamage += defenderStage
                destroyed += apply(attackerStage, to: &defenderHP)
                destroyed += apply(defenderStage, to: &attackerHP)
            }
            rounds.append(BattleRound(number: number, attackerRoll: attackerRoll, defenderRoll: defenderRoll, attackerDamage: attackerDamage, defenderDamage: defenderDamage, destroyedUnitIDs: destroyed))
            if attackerDamage == 0, defenderDamage == 0 { break }
        }
        let attackerSurvivors = survivors(attackerInitial, hp: attackerHP)
        let defenderSurvivors = survivors(defenderInitial, hp: defenderHP)
        let outcome: BattleOutcome = if attackerSurvivors.isEmpty, defenderSurvivors.isEmpty {
            .draw
        } else if defenderSurvivors.isEmpty {
            .victory(.attacker)
        } else if attackerSurvivors.isEmpty {
            .victory(.defender)
        } else {
            .draw
        }
        return .success(BattleResult(outcome: outcome, rounds: rounds, attackerInitial: attackerInitial, defenderInitial: defenderInitial, attackerSurvivors: attackerSurvivors, defenderSurvivors: defenderSurvivors, context: context))
    }

    private static func damage(from units: [Unit], hp: [UnitID: Int], definitions: [UnitTypeID: UnitDefinition], ranged: Bool) -> Int {
        units.filter { (hp[$0.id] ?? 0) > 0 && ((definitions[$0.typeID]?.attackRange ?? 0) > 1) == ranged }
            .reduce(0) { $0 + (definitions[$1.typeID]?.damage ?? 0) }
    }

    private static func apply(_ damage: Int, to hitPoints: inout [UnitID: Int]) -> [UnitID] {
        var remaining = damage
        var destroyed: [UnitID] = []
        while remaining > 0, let target = living(hitPoints).min(by: { lhs, rhs in
            let left = hitPoints[lhs] ?? 0, right = hitPoints[rhs] ?? 0
            return left == right ? lhs.rawValue < rhs.rawValue : left < right
        }) {
            let hp = hitPoints[target] ?? 0
            let applied = min(hp, remaining)
            hitPoints[target] = hp - applied
            remaining -= applied
            if hitPoints[target] == 0 { destroyed.append(target) }
        }
        return destroyed
    }

    private static func living(_ hp: [UnitID: Int]) -> [UnitID] { hp.filter { $0.value > 0 }.map(\.key) }
    private static func adjusted(_ damage: Int, percent: Int) -> Int {
        max(0, Int((Double(damage) * Double(100 + percent) / 100).rounded()))
    }

    private static func survivors(_ initial: [BattleUnitState], hp: [UnitID: Int]) -> [BattleUnitState] {
        initial.compactMap { unit in
            guard let value = hp[unit.id], value > 0 else { return nil }
            return BattleUnitState(id: unit.id, typeID: unit.typeID, hitPoints: value)
        }
    }
}
