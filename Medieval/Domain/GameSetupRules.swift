import Foundation

public struct GameSetupPlayer: Equatable, Sendable {
    public let name: String
    public let color: PlayerColor

    public init(name: String, color: PlayerColor) {
        self.name = name
        self.color = color
    }
}

public enum GameSetupError: Error, Equatable, LocalizedError, Sendable {
    case invalidPlayerCount
    case emptyName(Int)
    case duplicateName(String)
    case duplicateColor(PlayerColor)

    public var errorDescription: String? {
        switch self {
        case .invalidPlayerCount: "Оберіть від 2 до 4 гравців."
        case let .emptyName(index): "Вкажіть ім’я гравця №\(index + 1)."
        case let .duplicateName(name): "Ім’я «\(name)» повторюється."
        case .duplicateColor: "Кольори гравців мають відрізнятися."
        }
    }
}

public enum GameSetupRules {
    public static func validate(_ players: [GameSetupPlayer]) -> Result<[GameSetupPlayer], GameSetupError> {
        guard (2 ... 4).contains(players.count) else { return .failure(.invalidPlayerCount) }
        let normalized = players.enumerated().map { index, player in
            (index, GameSetupPlayer(name: player.name.trimmingCharacters(in: .whitespacesAndNewlines), color: player.color))
        }
        if let empty = normalized.first(where: { $0.1.name.isEmpty }) { return .failure(.emptyName(empty.0)) }
        var names = Set<String>()
        for (_, player) in normalized {
            let key = player.name.lowercased()
            guard names.insert(key).inserted else { return .failure(.duplicateName(player.name)) }
        }
        guard Set(normalized.map(\.1.color)).count == players.count else { return .failure(.duplicateColor(players[0].color)) }
        return .success(normalized.map(\.1))
    }
}
