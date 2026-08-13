import Foundation

public struct TurnHUDSnapshot: Equatable, Sendable {
    public let playerName: String
    public let playerColor: PlayerColor
    public let turn: Int
    public let phaseTitle: String
    public let coins: Int
    public let hint: String
    public let canAdvance: Bool

    public init(state: GameState, economy: EconomyState, hasBlockingPresentation: Bool = false) {
        playerName = state.activePlayer.displayName
        playerColor = state.activePlayer.color
        turn = state.turn
        phaseTitle = Self.title(for: state.phase)
        coins = state.activePlayer.worldPlayerID.flatMap(economy.coins) ?? 0
        hint = Self.hint(for: state.phase)
        canAdvance = !hasBlockingPresentation && ![.capitalPlacement, .handoff, .finished].contains(state.phase)
    }

    private static func title(for phase: GamePhase) -> String {
        switch phase {
        case .setup: "Підготовка"
        case .capitalPlacement: "Розміщення столиць"
        case .economy: "Економіка"
        case .construction: "Будівництво"
        case .movement: "Рух"
        case .combat: "Бій"
        case .handoff: "Передача ходу"
        case .playerTurn: "Хід гравця"
        case .resolvingTurn: "Підсумок ходу"
        case .finished: "Завершено"
        }
    }

    private static func hint(for phase: GamePhase) -> String {
        switch phase {
        case .capitalPlacement: "Оберіть придатний гекс і заснуйте столицю."
        case .economy: "Перевірте дохід і утримання перед переходом далі."
        case .construction: "Будуйте або поліпшуйте міста, чи пропустіть фазу."
        case .movement: "Оберіть свою армію, маршрут і підтвердьте рух."
        case .combat: "Завершіть доступні бої або передайте хід."
        case .handoff: "Передайте Mac наступному гравцеві."
        case .finished: "Партію завершено."
        default: "Виконайте доступну дію або перейдіть до наступної фази."
        }
    }
}
