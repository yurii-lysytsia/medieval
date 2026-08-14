import Foundation

/// What to tell the player when the rules say no.
///
/// The domain reports what went wrong as a value; the wording is the
/// interface's, in the one language the game speaks. It lives in one place so a
/// disabled button and the notice from pressing the same action anyway cannot
/// drift apart, and so no wording is written twice.
///
/// The domain's own `LocalizedError` text stays as it is: it is written for a
/// developer reading a log, not for someone playing a match.
enum RuleWording {
    static func text(for error: CityConstructionError, content: GameContentConfiguration) -> String {
        switch error {
        case .invalidPhase: "Лише у фазі будівництва"
        case .cityNotOwned: "Місто не ваше"
        case .unknownBuilding, .unknownCityLevel: "Невідомо в контенті гри"
        case .alreadyBuilt: "Уже побудовано"
        case .noBuildingSlots: "Немає вільних слотів"
        case let .insufficientCoins(required): "Потрібно \(required) монет"
        case .noNextLevel: "Максимальний рівень"
        case let .unmetRequirements(ids): "Потрібно: \(names(ids, content: content))"
        }
    }

    static func text(for error: RecruitmentError, content _: GameContentConfiguration) -> String {
        switch error {
        case .invalidPhase: "Лише у фазі найму"
        case .cityNotOwned: "Місто не ваше"
        case .barracksRequired: "Потрібні казарми"
        case .unknownUnitType, .unknownCityLevel: "Невідомо в контенті гри"
        case .navalUnitRequiresPort: "Потрібен вихід до води"
        case let .recruitmentLimitReached(_, limit): "Ліміт найму за хід: \(limit)"
        case let .garrisonFull(_, limit): "Гарнізон заповнений (\(limit))"
        case let .insufficientCoins(required): "Потрібно \(required) монет"
        }
    }

    static func text(for error: ArmyOperationError, content _: GameContentConfiguration) -> String {
        switch error {
        case .invalidPhase: "Лише у фазі руху"
        case let .armyCapacityExceeded(limit): "В армії щонайбільше \(limit) юнітів"
        case .alreadyMoved: "Армія вже рухалася цього ходу"
        case .incompatibleOwner, .incompatibleLocation, .invalidComposition: "Ці юніти не можуть скласти одну армію"
        case let .movementExceeded(required, available): "Потрібно \(required) руху, доступно \(available)"
        case .deepWaterRequiresTransport: "Без корабля глибоку воду не перейти"
        case .navalRouteRequired: "Кораблю потрібен шлях по воді"
        case .embarkationPointRequired: "Посадка й висадка можливі лише біля берега"
        case let .shipCapacityExceeded(limit): "Корабель бере щонайбільше \(limit) юнітів"
        case .shipAlreadyMoved: "Корабель уже рухався цього ходу"
        case .armyNotFound, .armyIDAlreadyInUse, .shipNotFound, .unitNotFound, .invalidRoute:
            "Дію неможливо виконати"
        }
    }

    private static func names(_ ids: [BuildingTypeID], content: GameContentConfiguration) -> String {
        ids
            .map { id in content.buildings.first(where: { $0.id == id })?.displayName ?? id.rawValue }
            .joined(separator: ", ")
    }
}
