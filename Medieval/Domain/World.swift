import Foundation

/// A stable, human-readable identifier used by map content.
///
/// `Subject` is a phantom type: it carries no storage, it only stops a `CityID`
/// from being accepted where a `HexID` belongs. One generic wrapper replaces a
/// wall of identical per-entity structs.
public struct Identifier<Subject>: Codable, Equatable, Hashable, Sendable,
    RawRepresentable, ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// Phantom tags. Empty enums cannot be instantiated, so they exist purely to
/// keep the identifier types distinct at compile time.
public enum HexTag {}
public enum WorldPlayerTag {}
public enum ArmyTag {}
public enum CityTag {}
public enum BuildingTag {}
public enum UnitTag {}
public enum UnitTypeTag {}
public enum TerrainTag {}
public enum CityLevelTag {}
public enum BuildingTypeTag {}
public enum RiverBoundaryTag {}

public typealias HexID = Identifier<HexTag>
public typealias WorldPlayerID = Identifier<WorldPlayerTag>
public typealias ArmyID = Identifier<ArmyTag>
public typealias CityID = Identifier<CityTag>
public typealias BuildingID = Identifier<BuildingTag>
public typealias UnitID = Identifier<UnitTag>
public typealias UnitTypeID = Identifier<UnitTypeTag>
public typealias TerrainID = Identifier<TerrainTag>
public typealias CityLevelID = Identifier<CityLevelTag>
public typealias BuildingTypeID = Identifier<BuildingTypeTag>
public typealias RiverBoundaryID = Identifier<RiverBoundaryTag>

/// Axial coordinates keep the map independent from any rendering technology.
public struct HexCoordinate: Codable, Equatable, Hashable, Sendable {
    public let q: Int
    public let r: Int

    public init(q: Int, r: Int) {
        self.q = q
        self.r = r
    }
}

/// A single map tile.
///
/// Passability is not stored here. It is a property of the hex's terrain, and
/// keeping a copy on the hex meant the two could disagree — a contradiction
/// content validation had to police rather than one the model made impossible.
/// Ask the terrain definition instead: `configuration.terrain(for: hex)`.
public struct Hex: Codable, Equatable, Sendable, Identifiable {
    public let id: HexID
    public let coordinate: HexCoordinate
    public let terrainID: TerrainID

    public init(id: HexID, coordinate: HexCoordinate, terrainID: TerrainID) {
        self.id = id
        self.coordinate = coordinate
        self.terrainID = terrainID
    }
}

public struct HexMapBounds: Codable, Equatable, Sendable {
    public let minimumQ: Int
    public let maximumQ: Int
    public let minimumR: Int
    public let maximumR: Int

    public init(minimumQ: Int, maximumQ: Int, minimumR: Int, maximumR: Int) {
        self.minimumQ = minimumQ
        self.maximumQ = maximumQ
        self.minimumR = minimumR
        self.maximumR = maximumR
    }
}

public struct HexNeighborhood: Codable, Equatable, Sendable, Identifiable {
    public let hexID: HexID
    public let neighborHexIDs: [HexID]

    public var id: HexID { hexID }

    public init(hexID: HexID, neighborHexIDs: [HexID]) {
        self.hexID = hexID
        self.neighborHexIDs = neighborHexIDs
    }
}

/// A replaceable static map dataset, described entirely with axial coordinates.
public struct StaticHexMap: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let bounds: HexMapBounds
    public let hexes: [Hex]
    public let neighborhoods: [HexNeighborhood]

    public init(id: String, displayName: String, bounds: HexMapBounds, hexes: [Hex], neighborhoods: [HexNeighborhood]) {
        self.id = id
        self.displayName = displayName
        self.bounds = bounds
        self.hexes = hexes
        self.neighborhoods = neighborhoods
    }
}

/// The shared edge between two hexes.
///
/// An edge has no direction, so the two hex IDs are stored in a canonical
/// order. Without it, the same edge written from either side would compare
/// unequal and hash differently, and a `Set<HexBoundary>` would hold it twice.
public struct HexBoundary: Codable, Equatable, Hashable, Sendable {
    public let firstHexID: HexID
    public let secondHexID: HexID

    public init(firstHexID: HexID, secondHexID: HexID) {
        if firstHexID.rawValue <= secondHexID.rawValue {
            self.firstHexID = firstHexID
            self.secondHexID = secondHexID
        } else {
            self.firstHexID = secondHexID
            self.secondHexID = firstHexID
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            firstHexID: try container.decode(HexID.self, forKey: .firstHexID),
            secondHexID: try container.decode(HexID.self, forKey: .secondHexID)
        )
    }

    /// A boundary has no direction: it is the same shared edge from either hex.
    public func connects(_ first: HexID, _ second: HexID) -> Bool {
        (firstHexID == first && secondHexID == second) || (firstHexID == second && secondHexID == first)
    }
}

public struct RiverBoundary: Codable, Equatable, Sendable, Identifiable {
    public let id: RiverBoundaryID
    public let boundary: HexBoundary

    public init(id: RiverBoundaryID, boundary: HexBoundary) {
        self.id = id
        self.boundary = boundary
    }
}

public struct WorldPlayer: Codable, Equatable, Sendable, Identifiable {
    public let id: WorldPlayerID
    public let displayName: String

    public init(id: WorldPlayerID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public enum UnitCondition: String, Codable, Equatable, Sendable {
    case ready
    case moved
    case embarked
    case destroyed
}

public enum UnitLocation: Codable, Equatable, Sendable {
    case hex(HexID)
    case garrison(CityID)
    case cargo(UnitID)
}

public struct Unit: Codable, Equatable, Sendable, Identifiable {
    public let id: UnitID
    public let ownerID: WorldPlayerID
    public let typeID: UnitTypeID
    public let currentHitPoints: Int
    public let condition: UnitCondition
    public let location: UnitLocation

    public init(
        id: UnitID,
        ownerID: WorldPlayerID,
        typeID: UnitTypeID,
        currentHitPoints: Int,
        condition: UnitCondition = .ready,
        location: UnitLocation
    ) {
        self.id = id
        self.ownerID = ownerID
        self.typeID = typeID
        self.currentHitPoints = currentHitPoints
        self.condition = condition
        self.location = location
    }
}

public struct Army: Codable, Equatable, Sendable, Identifiable {
    public let id: ArmyID
    public let ownerID: WorldPlayerID
    public let hexID: HexID
    public let unitIDs: [UnitID]
    public let hasMoved: Bool
    public let embarkedOnShipID: UnitID?

    public init(
        id: ArmyID,
        ownerID: WorldPlayerID,
        hexID: HexID,
        unitIDs: [UnitID],
        hasMoved: Bool = false,
        embarkedOnShipID: UnitID? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.hexID = hexID
        self.unitIDs = unitIDs
        self.hasMoved = hasMoved
        self.embarkedOnShipID = embarkedOnShipID
    }
}

public struct City: Codable, Equatable, Sendable, Identifiable {
    public let id: CityID
    public let ownerID: WorldPlayerID?
    public let hexID: HexID
    public let levelID: CityLevelID
    public let isCapital: Bool

    public init(id: CityID, ownerID: WorldPlayerID?, hexID: HexID, levelID: CityLevelID, isCapital: Bool = false) {
        self.id = id
        self.ownerID = ownerID
        self.hexID = hexID
        self.levelID = levelID
        self.isCapital = isCapital
    }
}

public struct Building: Codable, Equatable, Sendable, Identifiable {
    public let id: BuildingID
    public let cityID: CityID
    public let typeID: BuildingTypeID

    public init(id: BuildingID, cityID: CityID, typeID: BuildingTypeID) {
        self.id = id
        self.cityID = cityID
        self.typeID = typeID
    }
}

public enum GamePhase: String, Codable, Equatable, Sendable {
    case setup
    case capitalPlacement
    case economy
    case construction
    case movement
    case combat
    case handoff
    case playerTurn
    case resolvingTurn
    case finished
}

/// The rendering-independent representation of a playable world.
public struct WorldState: Codable, Equatable, Sendable {
    public private(set) var players: [WorldPlayer]
    public private(set) var hexes: [Hex]
    public private(set) var riverBoundaries: [RiverBoundary]
    public private(set) var units: [Unit]
    public private(set) var armies: [Army]
    public private(set) var cities: [City]
    public private(set) var buildings: [Building]
    public private(set) var phase: GamePhase
    /// Monotonic across the match. Numbering a recruit from the current unit
    /// count reuses ids as soon as a unit dies and leaves a gap in the sequence.
    public private(set) var nextUnitNumber: Int

    public init(
        players: [WorldPlayer],
        hexes: [Hex],
        riverBoundaries: [RiverBoundary] = [],
        units: [Unit] = [],
        armies: [Army] = [],
        cities: [City] = [],
        buildings: [Building] = [],
        phase: GamePhase = .setup,
        nextUnitNumber: Int? = nil
    ) {
        if let violation = Self.invariantViolation(playerCount: players.count) {
            preconditionFailure(violation)
        }
        self.players = players
        self.hexes = hexes
        self.riverBoundaries = riverBoundaries
        self.units = units
        self.armies = armies
        self.cities = cities
        self.buildings = buildings
        self.phase = phase
        self.nextUnitNumber = nextUnitNumber ?? units.count + 1
    }

    /// Decoded worlds come from content files and saves we do not control, so
    /// the player-count rule has to be a recoverable error here rather than the
    /// trap `init` uses for programmer mistakes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let players = try container.decode([WorldPlayer].self, forKey: .players)

        if let violation = Self.invariantViolation(playerCount: players.count) {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: container.codingPath, debugDescription: violation)
            )
        }

        self.players = players
        hexes = try container.decode([Hex].self, forKey: .hexes)
        riverBoundaries = try container.decode([RiverBoundary].self, forKey: .riverBoundaries)
        units = try container.decodeIfPresent([Unit].self, forKey: .units) ?? []
        armies = try container.decode([Army].self, forKey: .armies)
        cities = try container.decode([City].self, forKey: .cities)
        buildings = try container.decode([Building].self, forKey: .buildings)
        phase = try container.decode(GamePhase.self, forKey: .phase)
        // Saves written before the counter existed fall back to the old
        // behaviour, which is correct for any match that has lost no units.
        nextUnitNumber = try container.decodeIfPresent(Int.self, forKey: .nextUnitNumber) ?? units.count + 1
    }

    private static func invariantViolation(playerCount: Int) -> String? {
        (2 ... 4).contains(playerCount) ? nil : "A match supports two to four players."
    }

    public func riverBoundary(between firstHexID: HexID, and secondHexID: HexID) -> RiverBoundary? {
        riverBoundaries.first { $0.boundary.connects(firstHexID, secondHexID) }
    }

    mutating func addCapital(for playerID: WorldPlayerID, at hexID: HexID, levelID: CityLevelID) {
        cities.append(City(id: CityID(rawValue: "capital-\(playerID.rawValue)"), ownerID: playerID, hexID: hexID, levelID: levelID, isCapital: true))
        if cities.filter(\.isCapital).count == players.count {
            phase = .economy
        }
    }

    mutating func advanceFromEconomy() {
        phase = .construction
    }

    mutating func addBuilding(_ building: Building) {
        buildings.append(building)
    }

    mutating func setCityLevel(_ levelID: CityLevelID, for cityID: CityID) {
        guard let index = cities.firstIndex(where: { $0.id == cityID }) else { return }
        let city = cities[index]
        cities[index] = City(id: city.id, ownerID: city.ownerID, hexID: city.hexID, levelID: levelID, isCapital: city.isCapital)
    }

    /// Hands out the next unit number and moves the counter on.
    mutating func reserveUnitNumber() -> Int {
        defer { nextUnitNumber += 1 }
        return nextUnitNumber
    }

    mutating func addUnit(_ unit: Unit) {
        units.append(unit)
    }

    mutating func replaceUnit(_ unit: Unit) {
        guard let index = units.firstIndex(where: { $0.id == unit.id }) else { return }
        units[index] = unit
    }

    mutating func addArmy(_ army: Army) {
        armies.append(army)
    }

    mutating func replaceArmy(_ army: Army) {
        guard let index = armies.firstIndex(where: { $0.id == army.id }) else { return }
        armies[index] = army
    }

    mutating func removeArmy(_ armyID: ArmyID) {
        armies.removeAll { $0.id == armyID }
    }

    mutating func removeCapital(for playerID: WorldPlayerID) {
        let cityIDs = Set(cities.filter { $0.ownerID == playerID }.map(\.id))
        cities.removeAll { cityIDs.contains($0.id) }
        buildings.removeAll { cityIDs.contains($0.cityID) }
    }

    mutating func removeForces(for playerID: WorldPlayerID) {
        armies.removeAll { $0.ownerID == playerID }
        units.removeAll { $0.ownerID == playerID }
    }

    mutating func markFinished() {
        phase = .finished
    }

    mutating func setPhase(_ phase: GamePhase) {
        self.phase = phase
    }

    mutating func markArmyCommanded(_ armyID: ArmyID) {
        guard let army = armies.first(where: { $0.id == armyID }) else { return }
        replaceArmy(Army(id: army.id, ownerID: army.ownerID, hexID: army.hexID, unitIDs: army.unitIDs, hasMoved: true, embarkedOnShipID: army.embarkedOnShipID))
        for id in army.unitIDs {
            guard let unit = units.first(where: { $0.id == id }) else { continue }
            replaceUnit(Unit(id: unit.id, ownerID: unit.ownerID, typeID: unit.typeID, currentHitPoints: unit.currentHitPoints, condition: .moved, location: unit.location))
        }
    }
}
