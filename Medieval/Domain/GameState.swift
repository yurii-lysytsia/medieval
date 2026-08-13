import Foundation

public enum PlayerStatus: String, Codable, Equatable, Sendable {
    case active
    case eliminated
}

public struct Player: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let worldPlayerID: WorldPlayerID?
    public let status: PlayerStatus

    public init(id: UUID = UUID(), displayName: String, worldPlayerID: WorldPlayerID? = nil, status: PlayerStatus = .active) {
        self.id = id
        self.displayName = displayName
        self.worldPlayerID = worldPlayerID
        self.status = status
    }
}

public enum MatchResult: Codable, Equatable, Sendable {
    case winner(playerID: UUID)
    case draw(playerIDs: [UUID])
}

public enum MatchJournalEvent: Codable, Equatable, Sendable {
    case playerEliminated(playerID: UUID)
    case matchFinished(MatchResult)
    case armyMoved(armyID: ArmyID, from: HexID, to: HexID, cost: Int)
    case encounterStarted(attackerID: ArmyID, defenderID: ArmyID, hexID: HexID)
    case battleResolved(BattleResult)
}

public struct MatchJournalEntry: Codable, Equatable, Sendable {
    public let turn: Int
    public let phase: GamePhase
    public let event: MatchJournalEvent

    public init(turn: Int, phase: GamePhase, event: MatchJournalEvent) {
        self.turn = turn
        self.phase = phase
        self.event = event
    }
}

/// The complete UI-independent state of a match.
public struct GameState: Codable, Equatable, Sendable {
    public let seed: UInt64
    public private(set) var players: [Player]
    public private(set) var activePlayerIndex: Int
    public private(set) var turn: Int

    public init(
        players: [Player],
        seed: UInt64 = UInt64.random(in: .min ... .max),
        activePlayerIndex: Int = 0,
        turn: Int = 1
    ) {
        if let violation = Self.invariantViolation(
            players: players,
            activePlayerIndex: activePlayerIndex,
            turn: turn
        ) {
            preconditionFailure(violation)
        }
        self.seed = seed
        self.players = players
        self.activePlayerIndex = activePlayerIndex
        self.turn = turn
    }

    /// Decoded state comes from files we do not control, so the invariants that
    /// `init` treats as programmer errors have to be recoverable errors here.
    /// Without this, synthesized `Codable` would write the stored properties
    /// directly and hand back a state whose `activePlayer` traps.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let players = try container.decode([Player].self, forKey: .players)
        let activePlayerIndex = try container.decode(Int.self, forKey: .activePlayerIndex)
        let turn = try container.decode(Int.self, forKey: .turn)

        if let violation = Self.invariantViolation(
            players: players,
            activePlayerIndex: activePlayerIndex,
            turn: turn
        ) {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: container.codingPath, debugDescription: violation)
            )
        }

        seed = try container.decode(UInt64.self, forKey: .seed)
        self.players = players
        self.activePlayerIndex = activePlayerIndex
        self.turn = turn
    }

    public var activePlayer: Player {
        players[activePlayerIndex]
    }

    mutating func advanceTurn() {
        activePlayerIndex = (activePlayerIndex + 1) % players.count
        if activePlayerIndex == 0 {
            turn += 1
        }
    }

    /// What every `GameState` must satisfy, shared by `init` and `init(from:)`.
    /// Returns a description of the first violation, or `nil` when sound.
    private static func invariantViolation(
        players: [Player],
        activePlayerIndex: Int,
        turn: Int
    ) -> String? {
        if players.isEmpty {
            return "A game needs at least one player."
        }
        if !players.indices.contains(activePlayerIndex) {
            return "Active player must be in the game."
        }
        if turn <= 0 {
            return "Turn number must be positive."
        }
        return nil
    }

    mutating func completeHandoff(using action: GameAction) {
        phase = .economy
        actionHistory.append(action)
    }

    mutating func eliminate(_ playerID: UUID, using action: GameAction) {
        guard let index = players.firstIndex(where: { $0.id == playerID }) else { return }
        let player = players[index]
        players[index] = Player(id: player.id, displayName: player.displayName, worldPlayerID: player.worldPlayerID, status: .eliminated)
        journal.append(MatchJournalEntry(turn: turn, phase: phase, event: .playerEliminated(playerID: playerID)))
        actionHistory.append(action)

        let survivors = activePlayers
        if survivors.count == 1 {
            let result = MatchResult.winner(playerID: survivors[0].id)
            self.result = result
            phase = .finished
            journal.append(MatchJournalEntry(turn: turn, phase: .finished, event: .matchFinished(result)))
        }
    }

    mutating func record(_ event: MatchJournalEvent) {
        journal.append(MatchJournalEntry(turn: turn, phase: phase, event: event))
    }
}

/// A portable record that reproduces a match from the original seed and actions.
public struct GameReplay: Codable, Equatable, Sendable {
    public let seed: UInt64
    public let players: [Player]
    public let actions: [GameAction]

    public init(seed: UInt64, players: [Player], actions: [GameAction]) {
        self.seed = seed
        self.players = players
        self.actions = actions
    }

    /// Rebuilds the match from the seed and the recorded actions.
    ///
    /// Throws on the first action the rules reject. A replay that skipped bad
    /// actions would still return a state, and that state would be a plausible
    /// but different match — the one failure mode a reproduction record must
    /// not have.
    public func replayedState() throws -> GameState {
        try actions.reduce(GameState(players: players, seed: seed)) { state, action in
            try GameRules.apply(action, to: state).get()
        }
    }
}
