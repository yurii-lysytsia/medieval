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

    @Test func terrainDefinitionsContainTheEightMVPTypesAndTheirRules() throws {
        let terrain = try GameContentLoader.loadMVP().terrain
        let definitions = Dictionary(uniqueKeysWithValues: terrain.map { ($0.id.rawValue, $0) })

        #expect(Set(definitions.keys) == ["plains", "desert", "forest", "hills", "mountains", "swamp", "shallows", "deep-water"])
        #expect(definitions["plains"]?.movementCost == 1)
        #expect(definitions["forest"]?.defenseModifier == 1)
        #expect(definitions["mountains"]?.defenseModifier == 2)
        #expect(definitions["deep-water"]?.isPassable == false)
        #expect(definitions["plains"]?.isCityBuildable == true)
        #expect(definitions["swamp"]?.isCityBuildable == false)
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
            "map": {
              "id": "map",
              "displayName": "Map",
              "bounds": { "minimumQ": 0, "maximumQ": 0, "minimumR": 0, "maximumR": 0 },
              "hexes": [],
              "neighborhoods": []
            },
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
