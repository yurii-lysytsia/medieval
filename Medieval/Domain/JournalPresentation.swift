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

    public init(entry: MatchJournalEntry, index: Int) {
        id = "match-\(index)"
        turn = entry.turn
        phase = entry.phase
        switch entry.event {
        case .playerEliminated: text = "Гравця усунено з партії."
        case let .matchFinished(result):
            switch result {
            case .winner: text = "Партію завершено перемогою."
            case .draw: text = "Партію завершено нічиєю."
            }
        case let .armyMoved(armyID, from, to, cost): text = "Армія \(armyID.rawValue): \(from.rawValue) → \(to.rawValue), витрачено \(cost) руху."
        case let .encounterStarted(attackerID, defenderID, hexID): text = "Зіткнення \(attackerID.rawValue) з \(defenderID.rawValue) на \(hexID.rawValue)."
        case let .battleResolved(report): text = "Автоматичний бій завершено за \(report.rounds.count) раундів."
        }
    }
}
