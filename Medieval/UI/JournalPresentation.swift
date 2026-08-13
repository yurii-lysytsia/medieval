import Foundation

public enum NoticeSeverity: String, Equatable, Sendable {
    case information
    case success
    case error
}

public struct GameNotice: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let turn: Int
    public let phase: GamePhase
    public let severity: NoticeSeverity
    public let text: String

    public init(id: UUID = UUID(), date: Date = Date(), turn: Int, phase: GamePhase, severity: NoticeSeverity, text: String) {
        self.id = id
        self.date = date
        self.turn = turn
        self.phase = phase
        self.severity = severity
        self.text = text
    }
}

public struct JournalItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let turn: Int
    public let phase: GamePhase
    public let text: String

    /// `players` lets an entry name who it is about. Without them the journal
    /// could only say that *someone* was knocked out, which is the one detail
    /// worth reading back.
    public init(entry: MatchJournalEntry, index: Int, players: [Player]) {
        id = "match-\(index)"
        turn = entry.turn
        phase = entry.phase
        func name(_ playerID: UUID) -> String {
            players.first { $0.id == playerID }?.displayName ?? "невідомий гравець"
        }
        switch entry.event {
        case let .playerEliminated(playerID): text = "\(name(playerID)) вибуває з партії."
        case let .matchFinished(result):
            switch result {
            case let .winner(playerID): text = "Партію завершено. Переміг \(name(playerID))."
            case .draw: text = "Партію завершено нічиєю."
            }
        case let .armyMoved(armyID, from, to, cost): text = "Армія \(armyID.rawValue): \(from.rawValue) → \(to.rawValue), витрачено \(cost) руху."
        case let .encounterStarted(attackerID, defenderID, hexID): text = "Зіткнення \(attackerID.rawValue) з \(defenderID.rawValue) на \(hexID.rawValue)."
        case let .battleResolved(report): text = "Автоматичний бій завершено за \(report.rounds.count) раундів."
        }
    }
}
