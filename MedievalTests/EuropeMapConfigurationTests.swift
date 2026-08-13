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
