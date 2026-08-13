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

/// Where a defence bonus came from.
///
/// The report stores the kind rather than a display string, because battle
/// reports are saved with the match: a label written into the save would freeze
/// the language the match was played in.
public enum BattleModifierKind: String, Codable, Equatable, Sendable {
    case terrain
    case river
    case fortifications
    case garrison
}

public struct BattleModifier: Codable, Equatable, Sendable {
    public let kind: BattleModifierKind
    public let percent: Int

    public init(kind: BattleModifierKind, percent: Int) {
        self.kind = kind
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

    /// Never reaches 100%: a defender who cannot be hurt at all would make a
    /// fortified city unwinnable rather than expensive.
    public var defenderDamageReduction: Int {
        min(Self.maximumReduction, max(-Self.maximumReduction, defenderModifiers.reduce(0) { $0 + $1.percent }))
    }

    private static let maximumReduction = 90
}

public struct BattleResult: Codable, Equatable, Sendable {
    public let outcome: BattleOutcome
    public let rounds: [BattleRound]
    public let attackerInitial: [BattleUnitState]
    public let defenderInitial: [BattleUnitState]
    public let attackerSurvivors: [BattleUnitState]
    public let defenderSurvivors: [BattleUnitState]
    public let context: BattleContext

    public init(
        outcome: BattleOutcome,
        rounds: [BattleRound],
        attackerInitial: [BattleUnitState],
        defenderInitial: [BattleUnitState],
        attackerSurvivors: [BattleUnitState],
        defenderSurvivors: [BattleUnitState],
        context: BattleContext
    ) {
        self.outcome = outcome
        self.rounds = rounds
        self.attackerInitial = attackerInitial
        self.defenderInitial = defenderInitial
        self.attackerSurvivors = attackerSurvivors
        self.defenderSurvivors = defenderSurvivors
        self.context = context
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
    /// How much damage one point of advantage on the round roll is worth.
    private static let percentPerRollPoint = 5
    /// Caps what the roll alone can swing, so a lucky round cannot decide a
    /// battle that army composition should decide.
    private static let maximumRollSwing = 45

    /// Resolves a battle to completion without any UI, timers or frames.
    ///
    /// Each round runs in two stages — ranged units fire, then melee units
    /// strike. Within a stage both sides deal their damage simultaneously, so a
    /// unit that dies still lands the blow it was throwing; across stages the
    /// ranged casualties are already gone, which is what makes archers worth
    /// fielding. Damage is allocated to the weakest surviving defender first and
    /// spills over into the next one, so no damage is wasted on overkill.
    ///
    /// Each round both sides roll from `seed`; the difference between the rolls
    /// swings damage by `percentPerRollPoint` per point, bounded by
    /// `maximumRollSwing`. `context` biases those rolls and reduces the damage
    /// reaching the defender, and travels on the result so the report can name
    /// every bonus that was in play.
    ///
    /// The result is a pure function of its arguments — same armies, same
    /// definitions and same seed always produce the same rounds and survivors.
    public static func resolve(
        attackers: [Unit],
        defenders: [Unit],
        definitions: [UnitDefinition],
        seed: UInt64,
        context: BattleContext = BattleContext()
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
            let attackerRoll = Int(generator.next() % 10) + context.attackerRollBonus
            let defenderRoll = Int(generator.next() % 10) + context.defenderRollBonus
            let rollModifier = min(maximumRollSwing, max(-maximumRollSwing, (attackerRoll - defenderRoll) * percentPerRollPoint))
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

    /// Derives the seed for one battle from the match and the encounter itself.
    ///
    /// Mixing in only the turn would hand every battle fought in the same turn
    /// the same rolls. The fold is spelled out rather than reaching for
    /// `hashValue`, because Swift seeds its hashing per process and a replayed
    /// match has to produce the battles it produced the first time.
    public static func seed(match: UInt64, turn: Int, encounter: PendingEncounter) -> UInt64 {
        let text = "\(turn):\(encounter.attackerID.rawValue)>\(encounter.defenderID.rawValue)@\(encounter.destination.rawValue)"
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return match ^ hash
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
