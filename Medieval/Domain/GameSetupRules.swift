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
        case let .duplicateColor(color): "Колір «\(color.rawValue)» обрано двічі."
        }
    }
}

public enum GameSetupRules {
    public static let supportedPlayerCount = 2 ... 4

    /// Checks a wizard's worth of choices and hands back the normalised players.
    ///
    /// Names come back trimmed, because the difference between `"Корона"` and
    /// `"Корона "` is invisible on screen but makes two players look like one.
    /// Names are compared case-insensitively for the same reason.
    public static func validate(_ players: [GameSetupPlayer]) -> Result<[GameSetupPlayer], GameSetupError> {
        guard supportedPlayerCount.contains(players.count) else { return .failure(.invalidPlayerCount) }
        let normalized = players.map {
            GameSetupPlayer(name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), color: $0.color)
        }
        if let index = normalized.firstIndex(where: { $0.name.isEmpty }) { return .failure(.emptyName(index)) }

        var names: Set<String> = []
        for player in normalized where !names.insert(player.name.lowercased()).inserted {
            return .failure(.duplicateName(player.name))
        }
        var colors: Set<PlayerColor> = []
        for player in normalized where !colors.insert(player.color).inserted {
            // The colour that actually collided, not the first player's — the
            // message names it, so it has to be the right one.
            return .failure(.duplicateColor(player.color))
        }
        return .success(normalized)
    }
}
