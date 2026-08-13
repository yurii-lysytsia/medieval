import Foundation

public struct CityInspection: Equatable, Sendable {
    public let name: String
    public let owner: String
    public let level: String
    public let isCapital: Bool
    public let buildings: [String]
    public let income: Int
    public let recruitmentLimit: Int
}

public struct ArmyInspection: Equatable, Sendable, Identifiable {
    public let id: ArmyID
    public let owner: String
    public let units: [String]
    public let movement: String
}

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
            let cityBuildings = world.buildings.filter { $0.cityID == city.id }
            let definitions = cityBuildings.compactMap { building in content.buildings.first(where: { $0.id == building.typeID }) }
            return CityInspection(
                name: city.id.rawValue,
                owner: city.ownerID.flatMap { ownerID in world.players.first(where: { $0.id == ownerID })?.displayName } ?? "Немає власника",
                level: level?.displayName ?? city.levelID.rawValue,
                isCapital: city.isCapital,
                buildings: definitions.map(\.displayName),
                income: (level?.baseIncome ?? 0) + terrain.incomeModifier + definitions.map(\.incomeModifier).reduce(0, +),
                recruitmentLimit: level?.recruitmentLimit ?? 0
            )
        }
        let armies = world.armies.filter { $0.hexID == hexID }.map { army in
            let units = army.unitIDs.compactMap { unitID -> String? in
                guard let unit = world.units.first(where: { $0.id == unitID }) else { return nil }
                let name = content.units.first(where: { $0.id == unit.typeID })?.displayName ?? unit.typeID.rawValue
                return "\(name) \(unit.currentHitPoints) HP"
            }
            let maximumMovement = army.unitIDs.compactMap { id in
                world.units.first(where: { $0.id == id }).flatMap { unit in content.units.first(where: { $0.id == unit.typeID })?.movement }
            }.min() ?? 0
            return ArmyInspection(
                id: army.id,
                owner: world.players.first(where: { $0.id == army.ownerID })?.displayName ?? army.ownerID.rawValue,
                units: units,
                movement: army.hasMoved ? "Використано" : "\(maximumMovement) очок"
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
