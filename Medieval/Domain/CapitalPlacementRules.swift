import Foundation

public enum CapitalPlacementError: Error, Equatable, LocalizedError, Sendable {
    case invalidPhase(GamePhase)
    case unknownPlayer(WorldPlayerID)
    case capitalAlreadyPlaced(WorldPlayerID)
    case unknownHex(HexID)
    case occupiedHex(HexID)
    case unsuitableTerrain(HexID, TerrainID)
    case unknownCityLevel(CityLevelID)

    public var errorDescription: String? {
        switch self {
        case let .invalidPhase(phase):
            "Capitals can only be placed during capital placement, not \(phase.rawValue)."
        case let .unknownPlayer(playerID):
            "Player \"\(playerID.rawValue)\" is not part of this match."
        case let .capitalAlreadyPlaced(playerID):
            "Player \"\(playerID.rawValue)\" has already placed a capital."
        case let .unknownHex(hexID):
            "Hex \"\(hexID.rawValue)\" does not exist."
        case let .occupiedHex(hexID):
            "Hex \"\(hexID.rawValue)\" already contains a city."
        case let .unsuitableTerrain(hexID, terrainID):
            "Hex \"\(hexID.rawValue)\" has terrain \"\(terrainID.rawValue)\", which cannot host a capital."
        case let .unknownCityLevel(levelID):
            "City level \"\(levelID.rawValue)\" is not defined by the game content."
        }
    }
}

public enum CapitalPlacementRules {
    /// Places a player's capital.
    ///
    /// `cityLevels` is required rather than defaulted: a capital created with a
    /// level the content does not define would be a dangling reference that
    /// content validation cannot catch, because validation only sees what was
    /// loaded from the file, not cities added while playing.
    public static func placeCapital(
        for playerID: WorldPlayerID,
        at hexID: HexID,
        in world: WorldState,
        terrain: [TerrainDefinition],
        cityLevels: [CityLevelDefinition],
        initialLevelID: CityLevelID = "village"
    ) -> Result<WorldState, CapitalPlacementError> {
        guard world.phase == .capitalPlacement else { return .failure(.invalidPhase(world.phase)) }
        guard world.players.contains(where: { $0.id == playerID }) else { return .failure(.unknownPlayer(playerID)) }
        guard !world.cities.contains(where: { $0.ownerID == playerID && $0.isCapital }) else {
            return .failure(.capitalAlreadyPlaced(playerID))
        }
        guard let hex = world.hexes.first(where: { $0.id == hexID }) else { return .failure(.unknownHex(hexID)) }
        guard !world.cities.contains(where: { $0.hexID == hexID }) else { return .failure(.occupiedHex(hexID)) }
        guard let terrain = terrain.first(where: { $0.id == hex.terrainID }), terrain.isCityBuildable else {
            return .failure(.unsuitableTerrain(hexID, hex.terrainID))
        }
        guard cityLevels.contains(where: { $0.id == initialLevelID }) else {
            return .failure(.unknownCityLevel(initialLevelID))
        }

        var next = world
        next.addCapital(for: playerID, at: hexID, levelID: initialLevelID)
        return .success(next)
    }
}
