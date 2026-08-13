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

public struct Army: Codable, Equatable, Sendable, Identifiable {
    public let id: ArmyID
    public let ownerID: WorldPlayerID
    public let hexID: HexID
    public let unitTypeID: UnitTypeID
    public let quantity: Int

    public init(id: ArmyID, ownerID: WorldPlayerID, hexID: HexID, unitTypeID: UnitTypeID, quantity: Int) {
        self.id = id
        self.ownerID = ownerID
        self.hexID = hexID
        self.unitTypeID = unitTypeID
        self.quantity = quantity
    }
}

public struct City: Codable, Equatable, Sendable, Identifiable {
    public let id: CityID
    public let ownerID: WorldPlayerID?
    public let hexID: HexID
    public let levelID: CityLevelID

    public init(id: CityID, ownerID: WorldPlayerID?, hexID: HexID, levelID: CityLevelID) {
        self.id = id
        self.ownerID = ownerID
        self.hexID = hexID
        self.levelID = levelID
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
    case playerTurn
    case resolvingTurn
    case finished
}

/// The rendering-independent representation of a playable world.
public struct WorldState: Codable, Equatable, Sendable {
    public let players: [WorldPlayer]
    public let hexes: [Hex]
    public let riverBoundaries: [RiverBoundary]
    public let armies: [Army]
    public let cities: [City]
    public let buildings: [Building]
    public let phase: GamePhase

    public init(
        players: [WorldPlayer],
        hexes: [Hex],
        riverBoundaries: [RiverBoundary] = [],
        armies: [Army] = [],
        cities: [City] = [],
        buildings: [Building] = [],
        phase: GamePhase = .setup
    ) {
        if let violation = Self.invariantViolation(playerCount: players.count) {
            preconditionFailure(violation)
        }
        self.players = players
        self.hexes = hexes
        self.riverBoundaries = riverBoundaries
        self.armies = armies
        self.cities = cities
        self.buildings = buildings
        self.phase = phase
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
        armies = try container.decode([Army].self, forKey: .armies)
        cities = try container.decode([City].self, forKey: .cities)
        buildings = try container.decode([Building].self, forKey: .buildings)
        phase = try container.decode(GamePhase.self, forKey: .phase)
    }

    private static func invariantViolation(playerCount: Int) -> String? {
        (2 ... 4).contains(playerCount) ? nil : "A match supports two to four players."
    }
}
