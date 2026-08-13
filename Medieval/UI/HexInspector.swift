import Foundation

public struct UnitInspection: Equatable, Sendable, Identifiable {
    public let id: UnitID
    public let name: String
    public let hitPoints: Int
}

public struct CityInspection: Equatable, Sendable {
    public let name: String
    /// `nil` for a city nobody owns, so the panel can say so instead of
    /// pretending some player holds it.
    public let owner: String?
    public let level: String
    public let isCapital: Bool
    public let buildings: [String]
    /// `nil` when the content does not define the city's level: the income
    /// cannot be worked out, and showing a number that silently left out the
    /// base income would be worse than saying it is unknown.
    public let income: Int?
    public let recruitmentLimit: Int?
}

public struct ArmyInspection: Equatable, Sendable, Identifiable {
    public let id: ArmyID
    public let owner: String
    public let units: [UnitInspection]
    /// How far the army can go — its slowest unit sets the pace.
    public let movementPoints: Int
    public let hasMoved: Bool
}

/// Everything the side panel shows about the selected hex, gathered in one pass.
///
/// This is a view model, so it lives in the interface layer: it exists to spare
/// the panel from digging through the world for each line, not to define any
/// rule. It carries values rather than sentences, and the view does the wording.
public struct HexInspection: Equatable, Sendable {
    public let id: HexID
    public let coordinate: HexCoordinate
    public let terrain: String
    public let movementCost: Int
    public let defenseModifier: Int
    public let incomeModifier: Int
    public let riverCount: Int
    public let city: CityInspection?
    public let armies: [ArmyInspection]

    public static func inspect(_ hexID: HexID, map: StaticHexMap, world: WorldState, content: GameContentConfiguration) -> HexInspection? {
        guard let hex = map.hexes.first(where: { $0.id == hexID }),
              let terrain = content.terrain.first(where: { $0.id == hex.terrainID })
        else { return nil }

        let city = world.cities.first(where: { $0.hexID == hexID }).map { city in
            let level = content.cityLevels.first(where: { $0.id == city.levelID })
            let definitions = world.buildings
                .filter { $0.cityID == city.id }
                .compactMap { building in content.buildings.first(where: { $0.id == building.typeID }) }
            return CityInspection(
                name: city.id.rawValue,
                owner: city.ownerID.flatMap { ownerID in world.players.first(where: { $0.id == ownerID })?.displayName },
                level: level?.displayName ?? city.levelID.rawValue,
                isCapital: city.isCapital,
                buildings: definitions.map(\.displayName),
                income: level.map { $0.baseIncome + terrain.incomeModifier + definitions.map(\.incomeModifier).reduce(0, +) },
                recruitmentLimit: level?.recruitmentLimit
            )
        }

        let armies = world.armies.filter { $0.hexID == hexID }.map { army in
            let units = army.unitIDs.compactMap { unitID -> UnitInspection? in
                guard let unit = world.units.first(where: { $0.id == unitID }) else { return nil }
                let name = content.units.first(where: { $0.id == unit.typeID })?.displayName ?? unit.typeID.rawValue
                return UnitInspection(id: unit.id, name: name, hitPoints: unit.currentHitPoints)
            }
            let movementPoints = army.unitIDs.compactMap { id in
                world.units.first(where: { $0.id == id }).flatMap { unit in content.units.first(where: { $0.id == unit.typeID })?.movement }
            }.min() ?? 0
            return ArmyInspection(
                id: army.id,
                owner: world.players.first(where: { $0.id == army.ownerID })?.displayName ?? army.ownerID.rawValue,
                units: units,
                movementPoints: movementPoints,
                hasMoved: army.hasMoved
            )
        }
        let riverCount = world.riverBoundaries.filter { $0.boundary.firstHexID == hexID || $0.boundary.secondHexID == hexID }.count

        return HexInspection(
            id: hex.id,
            coordinate: hex.coordinate,
            terrain: terrain.displayName,
            movementCost: terrain.movementCost,
            defenseModifier: terrain.defenseModifier,
            incomeModifier: terrain.incomeModifier,
            riverCount: riverCount,
            city: city,
            armies: armies
        )
    }
}
