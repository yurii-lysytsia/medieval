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
    private static func makeEuropeMap(
        from manifest: EuropeMapManifest,
        basedOn base: GameContentConfiguration
    ) throws -> GameContentConfiguration {
        guard manifest.rows > 0,
              manifest.columns > 0,
              manifest.tiles.count == manifest.rows * manifest.columns
        else {
            throw GameContentLoadingError.invalidJSON("Europe map dimensions do not match its tiles.")
        }

        // Two tiles on one coordinate would be a broken manifest, and a broken
        // manifest is reported, not crashed on — everything else in content
        // loading throws rather than trapping.
        let tileByCoordinate = Dictionary(manifest.tiles.map { (HexCoordinate(q: $0.q, r: $0.r), $0) }) { first, _ in first }
        guard tileByCoordinate.count == manifest.tiles.count else {
            throw GameContentLoadingError.invalidJSON("Europe map has more than one tile on the same coordinate.")
        }
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
                terrainID: TerrainID(rawValue: tile.terrain)
            )
        }
        let idByCoordinate = Dictionary(hexes.map { ($0.coordinate, $0.id) }) { first, _ in first }
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
        let columns = 40
        guard europeTerrainRows.allSatisfy({ $0.count == columns }) else {
            throw GameContentLoadingError.invalidJSON("Europe terrain rows have inconsistent widths.")
        }

        let tiles = try europeTerrainRows.enumerated().flatMap { row, terrainRow in
            try terrainRow.enumerated().map { column, marker in
                guard let terrain = terrainName(for: marker) else {
                    throw GameContentLoadingError.invalidJSON("Unknown Europe terrain marker: \(marker).")
                }
                return EuropeMapTile(
                    id: String(format: "r%02d-c%02d", row, column),
                    q: column - (row - row % 2) / 2,
                    r: row,
                    terrain: terrain
                )
            }
        }
        let manifest = EuropeMapManifest(
            rows: europeTerrainRows.count,
            columns: columns,
            tiles: tiles
        )
        return try makeEuropeMap(from: manifest, basedOn: base)
    }

    /// Compact, code-owned terrain layout for the 40×30 Europe campaign.
    /// Rendering is intentionally independent from the removed MapHexes tiles:
    /// each marker selects one of the reusable textures in Assets/Hexes.
    private static let europeTerrainRows = [
        "~~~~~~~~~~~mmmmfhfpp~~~pfp~~ppppfffffppp",
        "~~~~~~~~~~~mmpppfppp~~~~~pfffpfffppfffpp",
        "~~~~m~~~~~~~pp~~pppp~~~~ffffppfppppfffff",
        "~~~pmp~~~~~~~~pphpp~~~~~~ff~hppppfpfpppf",
        "~~~~pf~~~~~~~~p~~p~~~~~ffpphpppppppfpfff",
        "~mp~mp~~~~~~~~p~~~~~~~~fhpppmppppfppfffp",
        "~pp~~pp~~~~~~~~pf~~pppffhppppppfpppffffh",
        "~fp~fppp~~~phppfpppfpphppppppppppppfffhf",
        "~pp~pppp~~~phpppppppppppppfpfppfpppffphf",
        "~~~~ppfp~pppppfppfpppfpppppfffpppfpfpfhf",
        "~~~~~~~~~fpppppppppppppppppppppppppfhpfp",
        "~~~~~~~ppppppfpppfffpffpppppppppppppfhhf",
        "~~~~~pfpfpfpppppfppfppppfffpppppfppfffpf",
        "~~~~~~ppppppmppmmmmfppppmpfppppppp~phhpp",
        "~~~~~~~pppppmpmmmmppmmpppppmpmppp~~~pppp",
        "~~~~~~~fpppfmmmmpp~ffmppffpmff~~pp~pfmpp",
        "~~~~~~~~pppfpmpppp~~ffmppfmppp~~pp~~pfmm",
        "~~~~~~mfmmppp~~fpf~~fmfpmmfpp~~~~~~~~ffm",
        "~~fpppdfffm~~~p~ppp~~~mmppppf~~~~~~~~~ff",
        "~ffpddfdpp~~~~~~~ppp~~mpmffpp~~fpff~~pfm",
        "~~fpppmpp~~~~~p~~~~ppp~mpf~~~pffdpmpffff",
        "~~ppdddpp~~~~~p~~~~f~~mp~~~ppfmmpdmmmmfm",
        "~~ppddddd~~~~~p~~~~~p~~mp~~pppddppddddpp",
        "~~pffmmd~~~~~~~~~pmp~~~mp~~pdppp~pmpfm~m",
        "~~fppmmd~~~~~~~p~~~p~~~~m~~~pfpfpfpppdpd",
        "~~~~m~~~~dpppppdp~~~~~~~~~~~~p~pp~~pfdfm",
        "~~~~~~~~~pddddddmd~~~~~~~mp~~~~~~~~ddddd",
        "~~~~p~~~ddmmmmmmp~~~~~~~~~~~~~~~~~dddddm",
        "~~~~pfdppdddpmddp~~~~~~~~~~~~~~~~~~pddfd",
        "~~~mmmmmmmmmmmmmmmmm~~mmm~~~~~~~~~mmmmmm",
    ]

    /// Every water marker is deep water.
    ///
    /// The coast used to be turned into `shallows`, which drew a pale band
    /// around every landmass that read as a river system the campaign does not
    /// have — Europe carries no river boundaries at all. The shallows rules
    /// stay in the content for scenarios that do use them.
    private static func terrainName(for marker: Character) -> String? {
        switch marker {
        case "~": "deep-water"
        case "p": "plains"
        case "f": "forest"
        case "h": "hills"
        case "m": "mountains"
        case "d": "desert"
        default: nil
        }
    }
}
