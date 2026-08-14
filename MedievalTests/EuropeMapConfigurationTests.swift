import Foundation
@testable import Medieval
import Testing

struct EuropeMapConfigurationTests {
    @Test func bundledEuropeMapCreatesCompletePlayableGrid() throws {
        let configuration = try GameContentLoader.loadEuropeMap()
        let map = configuration.scenario.map

        #expect(map.id == "europe-full")
        #expect(map.hexes.count == 1200)
        #expect(map.neighborhoods.count == 1200)
        #expect(configuration.scenario.world.hexes == map.hexes)
        #expect(map.hexes.contains { $0.terrainID == "deep-water" })
        #expect(map.hexes.contains { $0.terrainID == "mountains" })
    }

    /// The campaign has one kind of water. Coastal tiles used to become
    /// shallows, which drew a pale ring around every coast that read as rivers
    /// the map does not have.
    @Test func everyWaterHexIsDeepWater() throws {
        let map = try GameContentLoader.loadEuropeMap().scenario.map

        #expect(!map.hexes.contains { $0.terrainID == "shallows" })
    }

    /// A coastal city can still build ships: recruitment asks for water next
    /// door, and deep water is water.
    @Test func coastalLandStillHasWaterNeighbors() throws {
        let configuration = try GameContentLoader.loadEuropeMap()
        let map = configuration.scenario.map
        let terrainByHex = Dictionary(uniqueKeysWithValues: map.hexes.map { ($0.id, $0.terrainID) })
        let waterDomains = Set(configuration.terrain.filter(\.domain.isWater).map(\.id))

        let coastalLand = map.neighborhoods.filter { neighborhood in
            terrainByHex[neighborhood.hexID].map { !waterDomains.contains($0) } == true
                && neighborhood.neighborHexIDs.contains { terrainByHex[$0].map(waterDomains.contains) == true }
        }

        #expect(!coastalLand.isEmpty)
    }

    @Test func generatedNeighborhoodsAreSymmetric() throws {
        let map = try GameContentLoader.loadEuropeMap().scenario.map
        let neighbors = Dictionary(uniqueKeysWithValues: map.neighborhoods.map { ($0.hexID, Set($0.neighborHexIDs)) })

        for (hexID, adjacent) in neighbors {
            for neighborID in adjacent {
                #expect(neighbors[neighborID]?.contains(hexID) == true)
            }
        }
    }
}
