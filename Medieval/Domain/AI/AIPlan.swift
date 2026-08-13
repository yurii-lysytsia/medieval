import Foundation

/// What the opponent weighs, in the order it weighs it.
///
/// The order is the model: a lower `rawValue` is considered first and wins any
/// tie. Keeping it in one declaration is what makes the opponent's behaviour
/// something you can read rather than reconstruct from scattered conditionals.
public enum AIPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    /// Nothing else matters if the capital falls: losing it ends the match.
    case capitalSurvival = 0
    /// Income compounds, so a turn spent growing it pays for later turns.
    case income = 1
    /// Troops are what eventually take a capital, and they cost upkeep, so they
    /// come after the income that sustains them.
    case recruitment = 2
    /// Closing on the target: worthless without an army, hence after recruiting.
    case advance = 3
    /// Striking is last because it is the one decision that cannot be undone.
    case attack = 4

    public static func < (lhs: AIPriority, rhs: AIPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One thing the opponent means to do.
///
/// Every case names an operation the existing rules already expose, and carries
/// exactly the arguments that rule needs. The opponent cannot express a move the
/// player could not make, because there is no case for one.
public enum AIIntent: Equatable, Sendable {
    case placeCapital(hexID: HexID)
    case construct(buildingTypeID: BuildingTypeID, cityID: CityID)
    case upgradeCity(cityID: CityID)
    case recruit(unitTypeID: UnitTypeID, cityID: CityID)
    case moveArmy(armyID: ArmyID, route: MovementRoute)
    case resolveBattle(encounter: PendingEncounter)
    case confirmHandoff
    case advancePhase
    case endTurn
}

/// An intent together with the reason it was chosen.
///
/// The reason is carried rather than inferred so a plan can be asserted on in
/// tests and read in the journal: "recruited because recruitment outranked
/// advancing" is a claim about the model, not about one line of code.
public struct AIStep: Equatable, Sendable {
    public let priority: AIPriority
    public let intent: AIIntent

    public init(priority: AIPriority, intent: AIIntent) {
        self.priority = priority
        self.intent = intent
    }
}

/// The opponent's decision for one phase.
///
/// A plan is always non-empty: every phase ends with the step that leaves it, so
/// an opponent that finds nothing worth doing still hands the turn on rather
/// than stalling the match.
public struct AIPlan: Equatable, Sendable {
    public let playerID: WorldPlayerID
    public let phase: GamePhase
    public let target: AITarget?
    public let steps: [AIStep]

    public init(playerID: WorldPlayerID, phase: GamePhase, target: AITarget?, steps: [AIStep]) {
        self.playerID = playerID
        self.phase = phase
        self.target = target
        self.steps = steps
    }

    public var intents: [AIIntent] { steps.map(\.intent) }
}

/// The enemy capital the opponent is playing towards, and how far off it is.
public struct AITarget: Equatable, Sendable {
    public let cityID: CityID
    public let hexID: HexID
    public let ownerID: WorldPlayerID
    /// Movement cost of the cheapest land route to it, from wherever the
    /// opponent measured — not a straight-line distance, so mountains and
    /// rivers count.
    public let distance: Int

    public init(cityID: CityID, hexID: HexID, ownerID: WorldPlayerID, distance: Int) {
        self.cityID = cityID
        self.hexID = hexID
        self.ownerID = ownerID
        self.distance = distance
    }
}
