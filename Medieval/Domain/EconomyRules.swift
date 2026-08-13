import Foundation

public struct PlayerTreasury: Codable, Equatable, Sendable, Identifiable {
    public let id: WorldPlayerID
    public fileprivate(set) var coins: Int

    public init(id: WorldPlayerID, coins: Int) {
        self.id = id
        self.coins = coins
    }
}

public enum EconomyEntryKind: String, Codable, Equatable, Sendable {
    case cityIncome
    case buildingIncome
    case armyUpkeep
    case buildingUpkeep
}

public struct EconomyJournalEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let playerID: WorldPlayerID
    public let kind: EconomyEntryKind
    public let source: String
    public let amount: Int

    public init(id: String, playerID: WorldPlayerID, kind: EconomyEntryKind, source: String, amount: Int) {
        self.id = id
        self.playerID = playerID
        self.kind = kind
        self.source = source
        self.amount = amount
    }
}

public struct EconomyState: Codable, Equatable, Sendable {
    public private(set) var treasuries: [PlayerTreasury]
    public private(set) var journal: [EconomyJournalEntry]
    /// Monotonic across the whole match, so journal entries stay distinct when
    /// the same city pays out again next turn.
    private var nextEntryNumber: Int

    public init(players: [WorldPlayer], startingGold: Int) {
        precondition(startingGold >= 0, "Starting gold cannot be negative.")
        treasuries = players.map { PlayerTreasury(id: $0.id, coins: startingGold) }
        journal = []
        nextEntryNumber = 0
    }

    public func coins(for playerID: WorldPlayerID) -> Int? {
        treasuries.first(where: { $0.id == playerID })?.coins
    }

    public func canAfford(_ amount: Int, for playerID: WorldPlayerID) -> Bool {
        amount >= 0 && (coins(for: playerID) ?? -1) >= amount
    }

    /// Numbers the entries as it records them and returns them as stored.
    ///
    /// Identity is assigned here, in one place, because the natural key —
    /// player, kind and source — repeats every turn the same city pays out.
    /// Two entries sharing an id break `Identifiable`, and a `ForEach` over the
    /// journal with duplicate ids misbehaves.
    mutating func apply(_ entries: [EconomyJournalEntry], for playerID: WorldPlayerID) -> [EconomyJournalEntry] {
        guard let index = treasuries.firstIndex(where: { $0.id == playerID }) else { return [] }

        let recorded = entries.enumerated().map { offset, entry in
            EconomyJournalEntry(
                id: "\(nextEntryNumber + offset)-\(entry.playerID.rawValue)-\(entry.kind.rawValue)-\(entry.source)",
                playerID: entry.playerID,
                kind: entry.kind,
                source: entry.source,
                amount: entry.amount
            )
        }
        nextEntryNumber += recorded.count
        treasuries[index].coins += recorded.map(\.amount).reduce(0, +)
        journal.append(contentsOf: recorded)
        return recorded
    }
}

public struct EconomyResolution: Codable, Equatable, Sendable {
    public let world: WorldState
    public let economy: EconomyState
    public let entries: [EconomyJournalEntry]
}

public enum EconomyRuleError: Error, Equatable, LocalizedError, Sendable {
    case invalidPhase(GamePhase)
    case unknownPlayer(WorldPlayerID)
    case missingDefinition(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidPhase(phase):
            "Economy can only resolve during the economy phase, not \(phase.rawValue)."
        case let .unknownPlayer(playerID):
            "Player \"\(playerID.rawValue)\" has no treasury."
        case let .missingDefinition(reference):
            "Economy is missing required definition \(reference)."
        }
    }
}

public enum EconomyRules {
    public static func resolve(
        for playerID: WorldPlayerID,
        in world: WorldState,
        economy: EconomyState,
        terrain: [TerrainDefinition],
        cityLevels: [CityLevelDefinition],
        units: [UnitDefinition],
        buildings: [BuildingDefinition]
    ) -> Result<EconomyResolution, EconomyRuleError> {
        guard world.phase == .economy else { return .failure(.invalidPhase(world.phase)) }
        guard economy.coins(for: playerID) != nil else { return .failure(.unknownPlayer(playerID)) }

        let ownedCities = world.cities.filter { $0.ownerID == playerID }
        var entries: [EconomyJournalEntry] = []

        for city in ownedCities {
            guard let level = cityLevels.first(where: { $0.id == city.levelID }),
                  let hex = world.hexes.first(where: { $0.id == city.hexID }),
                  let terrainDefinition = terrain.first(where: { $0.id == hex.terrainID })
            else { return .failure(.missingDefinition("city \(city.id.rawValue)")) }
            entries.append(entry(playerID, .cityIncome, "city:\(city.id.rawValue)", level.baseIncome + terrainDefinition.incomeModifier))
        }

        for building in world.buildings {
            // Another player's building is not this player's business; a
            // building whose type nothing defines is a broken world, and is
            // reported rather than quietly dropped from the balance.
            guard ownedCities.contains(where: { $0.id == building.cityID }) else { continue }
            guard let definition = buildings.first(where: { $0.id == building.typeID }) else {
                return .failure(.missingDefinition("building type \(building.typeID.rawValue)"))
            }
            if definition.incomeModifier != 0 {
                entries.append(entry(playerID, .buildingIncome, "building:\(building.id.rawValue)", definition.incomeModifier))
            }
            if definition.upkeep > 0 {
                entries.append(entry(playerID, .buildingUpkeep, "building:\(building.id.rawValue)", -definition.upkeep))
            }
        }

        for army in world.armies where army.ownerID == playerID {
            guard let unit = units.first(where: { $0.id == army.unitTypeID }) else {
                return .failure(.missingDefinition("unit \(army.unitTypeID.rawValue)"))
            }
            let upkeep = unit.upkeep * army.quantity
            if upkeep > 0 {
                entries.append(entry(playerID, .armyUpkeep, "army:\(army.id.rawValue)", -upkeep))
            }
        }

        var nextWorld = world
        nextWorld.advanceFromEconomy()
        var nextEconomy = economy
        let recorded = nextEconomy.apply(entries, for: playerID)
        return .success(EconomyResolution(world: nextWorld, economy: nextEconomy, entries: recorded))
    }

    private static func entry(
        _ playerID: WorldPlayerID,
        _ kind: EconomyEntryKind,
        _ source: String,
        _ amount: Int
    ) -> EconomyJournalEntry {
        // The id here is a placeholder: EconomyState.apply numbers entries as
        // it records them, because only it knows the running sequence.
        EconomyJournalEntry(id: source, playerID: playerID, kind: kind, source: source, amount: amount)
    }
}
