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

    public init(
        number: Int,
        attackerRoll: Int,
        defenderRoll: Int,
        attackerDamage: Int,
        defenderDamage: Int,
        destroyedUnitIDs: [UnitID]
    ) {
        self.number = number
        self.attackerRoll = attackerRoll
        self.defenderRoll = defenderRoll
        self.attackerDamage = attackerDamage
        self.defenderDamage = defenderDamage
        self.destroyedUnitIDs = destroyedUnitIDs
    }
}

public struct BattleResult: Codable, Equatable, Sendable {
    public let outcome: BattleOutcome
    public let rounds: [BattleRound]
    public let attackerInitial: [BattleUnitState]
    public let defenderInitial: [BattleUnitState]
    public let attackerSurvivors: [BattleUnitState]
    public let defenderSurvivors: [BattleUnitState]

    public init(
        outcome: BattleOutcome,
        rounds: [BattleRound],
        attackerInitial: [BattleUnitState],
        defenderInitial: [BattleUnitState],
        attackerSurvivors: [BattleUnitState],
        defenderSurvivors: [BattleUnitState]
    ) {
        self.outcome = outcome
        self.rounds = rounds
        self.attackerInitial = attackerInitial
        self.defenderInitial = defenderInitial
        self.attackerSurvivors = attackerSurvivors
        self.defenderSurvivors = defenderSurvivors
    }

    public var attackerLosses: [UnitID] { attackerInitial.map(\.id).filter { id in !attackerSurvivors.contains(where: { $0.id == id }) } }
    public var defenderLosses: [UnitID] { defenderInitial.map(\.id).filter { id in !defenderSurvivors.contains(where: { $0.id == id }) } }
}

public enum AutomaticBattleError: Error, Equatable, LocalizedError, Sendable {
    case emptyArmy(BattleSide)
    case missingDefinition(UnitTypeID)
    case duplicateUnit(UnitID)

    public var errorDescription: String? {
        switch self {
        case let .emptyArmy(side):
            "The \(side.rawValue) side has no units to fight with."
        case let .missingDefinition(typeID):
            "Unit type \"\(typeID.rawValue)\" is not defined by the game content."
        case let .duplicateUnit(unitID):
            "Unit \"\(unitID.rawValue)\" takes part in the battle more than once."
        }
    }
}

public enum AutomaticBattle {
    /// A battle ends when one side is wiped out; the cap only exists so two
    /// armies that cannot finish each other off still terminate.
    private static let maximumRounds = 100

    /// Resolves a battle to completion without any UI, timers or frames.
    ///
    /// Each round runs in two stages — ranged units fire, then melee units
    /// strike. Within a stage both sides deal their damage simultaneously, so a
    /// unit that dies still lands the blow it was throwing; across stages the
    /// ranged casualties are already gone, which is what makes archers worth
    /// fielding. Damage is allocated to the weakest surviving defender first and
    /// spills over into the next one, so no damage is wasted on overkill.
    ///
    /// The per-round rolls are drawn from `seed` and recorded on each
    /// `BattleRound`. They do not alter damage here: the modifier layer that
    /// consumes them (terrain, fortification) arrives with battle context, and
    /// the sequence is fixed now so that adding it does not renumber existing
    /// saved battles.
    ///
    /// The result is a pure function of its arguments — same armies, same
    /// definitions and same seed always produce the same rounds and survivors.
    public static func resolve(
        attackers: [Unit],
        defenders: [Unit],
        definitions: [UnitDefinition],
        seed: UInt64
    ) -> Result<BattleResult, AutomaticBattleError> {
        guard !attackers.isEmpty else { return .failure(.emptyArmy(.attacker)) }
        guard !defenders.isEmpty else { return .failure(.emptyArmy(.defender)) }
        // Hit points are tracked per unit id, so a repeated id — the same unit
        // listed twice, or fielded by both sides — would silently share a health
        // pool. Content validation guarantees unique definition ids, so keeping
        // the first one there only avoids a trap on a broken catalogue.
        if let duplicate = firstDuplicateID(in: attackers + defenders) {
            return .failure(.duplicateUnit(duplicate))
        }
        let definitionByID = Dictionary(definitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let typeID = (attackers + defenders).map(\.typeID).first(where: { definitionByID[$0] == nil }) {
            return .failure(.missingDefinition(typeID))
        }
        let attackerInitial = attackers.map { BattleUnitState(id: $0.id, typeID: $0.typeID, hitPoints: $0.currentHitPoints) }
        let defenderInitial = defenders.map { BattleUnitState(id: $0.id, typeID: $0.typeID, hitPoints: $0.currentHitPoints) }
        var attackerHP = Dictionary(uniqueKeysWithValues: attackerInitial.map { ($0.id, $0.hitPoints) })
        var defenderHP = Dictionary(uniqueKeysWithValues: defenderInitial.map { ($0.id, $0.hitPoints) })
        var generator = SeededRandomNumberGenerator(seed: seed)
        var rounds: [BattleRound] = []

        // A `for … where` clause filters iterations rather than ending the loop,
        // so the termination conditions are spelled out here instead.
        while rounds.count < maximumRounds, !living(attackerHP).isEmpty, !living(defenderHP).isEmpty {
            let number = rounds.count + 1
            let attackerRoll = Int(generator.next() % 10)
            let defenderRoll = Int(generator.next() % 10)
            var attackerDamage = 0
            var defenderDamage = 0
            var destroyed: [UnitID] = []

            for ranged in [true, false] {
                let attackerStage = damage(from: attackers, hp: attackerHP, definitions: definitionByID, ranged: ranged)
                let defenderStage = damage(from: defenders, hp: defenderHP, definitions: definitionByID, ranged: ranged)
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
        return .success(BattleResult(outcome: outcome, rounds: rounds, attackerInitial: attackerInitial, defenderInitial: defenderInitial, attackerSurvivors: attackerSurvivors, defenderSurvivors: defenderSurvivors))
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

    private static func firstDuplicateID(in units: [Unit]) -> UnitID? {
        var seen: Set<UnitID> = []
        return units.first { !seen.insert($0.id).inserted }?.id
    }

    private static func survivors(_ initial: [BattleUnitState], hp: [UnitID: Int]) -> [BattleUnitState] {
        initial.compactMap { unit in
            guard let value = hp[unit.id], value > 0 else { return nil }
            return BattleUnitState(id: unit.id, typeID: unit.typeID, hitPoints: value)
        }
    }
}
