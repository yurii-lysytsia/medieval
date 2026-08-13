import Foundation

/// Everything the header row shows, derived in one place from the match state.
///
/// This lives in the interface layer, not the domain: it decides what a phase is
/// *called* and what to advise the player, both of which are presentation, and
/// both of which are written in one language. The domain stays free of display
/// text so a saved match never carries wording with it.
public struct TurnHUDSnapshot: Equatable, Sendable {
    public let playerName: String
    public let playerColor: PlayerColor
    public let turn: Int
    public let phaseTitle: String
    public let coins: Int
    public let hint: String
    public let canAdvance: Bool

    /// `hasBlockingPresentation` covers anything the player has to deal with
    /// before the turn can move on — an unresolved encounter, a battle report
    /// still on screen. It has no default: forgetting to pass it would offer a
    /// "next phase" button that skips over the thing being shown.
    public init(state: GameState, economy: EconomyState, hasBlockingPresentation: Bool) {
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
