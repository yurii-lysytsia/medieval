import Foundation
@testable import MedievalDomain
import Testing

struct GameContentConfigurationTests {
    @Test func completeMVPConfigurationLoadsFromItsResource() throws {
        let configuration = try GameContentLoader.loadMVP()

        #expect(configuration.terrain.count == 8)
        #expect(configuration.units.count == 4)
        #expect(configuration.cityLevels.count == 3)
        #expect(configuration.buildings.count == 4)
        #expect(configuration.scenario.startingGold == 120)
        #expect(configuration.scenario.world.players.count == 2)
    }

    @Test func editedBalanceValueIsReadFromConfigurationData() throws {
        let data = Data("""
        {
          "terrain": [],
          "units": [],
          "cityLevels": [],
          "buildings": [],
          "scenario": {
            "id": "test",
            "displayName": "Test",
            "startingGold": 999,
            "world": {
              "players": [
                { "id": "one", "displayName": "One" },
                { "id": "two", "displayName": "Two" }
              ],
              "hexes": [],
              "riverBoundaries": [],
              "armies": [],
              "cities": [],
              "buildings": [],
              "phase": "setup"
            }
          }
        }
        """.utf8)

        let configuration = try GameContentLoader.decode(data)

        #expect(configuration.scenario.startingGold == 999)
    }
}
