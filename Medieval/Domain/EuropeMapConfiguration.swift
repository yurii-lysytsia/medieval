import Foundation

private struct EuropeMapManifest: Decodable {
    let rows: Int
    let columns: Int
    let tiles: [EuropeMapTile]
}

private struct EuropeMapTile: Decodable {
    let id: String
    let q: Int
    let r: Int
    let terrain: String
}

public extension GameContentLoader {
    static let europeMapResourceName = "hex-map"

    /// Builds the playable Europe scenario from the raster-map manifest.
    ///
    /// The manifest is the single source of truth for both rendering and game
    /// rules: its row/column IDs match the PNG names, while its axial
    /// coordinates generate movement neighborhoods without duplicating 1200
    /// cells in the balance configuration.
    static func decodeEuropeMap(
        _ data: Data,
        basedOn base: GameContentConfiguration
    ) throws -> GameContentConfiguration {
        let manifest: EuropeMapManifest
        do {
            manifest = try JSONDecoder().decode(EuropeMapManifest.self, from: data)
        } catch {
            throw GameContentLoadingError.invalidJSON(error.localizedDescription)
        }

        guard manifest.rows > 0,
              manifest.columns > 0,
              manifest.tiles.count == manifest.rows * manifest.columns
        else {
            throw GameContentLoadingError.invalidJSON("Europe map dimensions do not match its tiles.")
        }

        let tileByCoordinate = Dictionary(uniqueKeysWithValues: manifest.tiles.map {
            (HexCoordinate(q: $0.q, r: $0.r), $0)
        })
        let directions = [
            HexCoordinate(q: 1, r: 0),
            HexCoordinate(q: 1, r: -1),
            HexCoordinate(q: 0, r: -1),
            HexCoordinate(q: -1, r: 0),
            HexCoordinate(q: -1, r: 1),
            HexCoordinate(q: 0, r: 1),
        ]
        let hexes = manifest.tiles.map { tile in
            let coordinate = HexCoordinate(q: tile.q, r: tile.r)
            return Hex(
                id: HexID(rawValue: tile.id),
                coordinate: coordinate,
                terrainID: TerrainID(
                    rawValue: terrainID(
                        for: tile,
                        at: coordinate,
                        tileByCoordinate: tileByCoordinate,
                        directions: directions
                    )
                )
            )
        }
        let idByCoordinate = Dictionary(uniqueKeysWithValues: hexes.map { ($0.coordinate, $0.id) })
        let neighborhoods = hexes.map { hex in
            let neighbors = directions.compactMap { direction in
                idByCoordinate[
                    HexCoordinate(
                        q: hex.coordinate.q + direction.q,
                        r: hex.coordinate.r + direction.r
                    )
                ]
            }
            return HexNeighborhood(hexID: hex.id, neighborHexIDs: neighbors)
        }
        let qValues = hexes.map(\.coordinate.q)
        let rValues = hexes.map(\.coordinate.r)
        guard let minimumQ = qValues.min(),
              let maximumQ = qValues.max(),
              let minimumR = rValues.min(),
              let maximumR = rValues.max()
        else {
            throw GameContentLoadingError.invalidJSON("Europe map contains no tiles.")
        }

        let map = StaticHexMap(
            id: "europe-full",
            displayName: "Європа — велика кампанія",
            bounds: HexMapBounds(
                minimumQ: minimumQ,
                maximumQ: maximumQ,
                minimumR: minimumR,
                maximumR: maximumR
            ),
            hexes: hexes,
            neighborhoods: neighborhoods
        )
        let world = WorldState(
            players: base.scenario.world.players,
            hexes: hexes,
            phase: .capitalPlacement
        )
        let scenario = ScenarioConfiguration(
            id: "europe-grand-campaign",
            displayName: "Європа — велика кампанія",
            startingGold: base.scenario.startingGold,
            map: map,
            world: world
        )
        let configuration = GameContentConfiguration(
            terrain: base.terrain,
            units: base.units,
            cityLevels: base.cityLevels,
            buildings: base.buildings,
            scenario: scenario
        )
        try GameContentValidator.validate(configuration)
        return configuration
    }

    static func loadEuropeMap() throws -> GameContentConfiguration {
        let base = try loadMVP()
        guard let url = Bundle.main.url(forResource: europeMapResourceName, withExtension: "json") else {
            throw GameContentLoadingError.missingResource(europeMapResourceName)
        }
        guard let data = try? Data(contentsOf: url) else {
            throw GameContentLoadingError.unreadableData(europeMapResourceName)
        }
        return try decodeEuropeMap(data, basedOn: base)
    }

    private static func terrainID(
        for tile: EuropeMapTile,
        at coordinate: HexCoordinate,
        tileByCoordinate: [HexCoordinate: EuropeMapTile],
        directions: [HexCoordinate]
    ) -> String {
        guard tile.terrain == "water" else { return tile.terrain }
        let touchesLand = directions.contains { direction in
            tileByCoordinate[
                HexCoordinate(q: coordinate.q + direction.q, r: coordinate.r + direction.r)
            ]?.terrain != "water"
        }
        return touchesLand ? "shallows" : "deep-water"
    }
}
