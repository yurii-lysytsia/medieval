@testable import Medieval
import Testing

struct HexInspectorTests {
    @Test func exposesTerrainRiverCityBuildingsIncomeAndArmyMovement() throws {
        let content = try GameContentLoader.loadMVP()
        let world = WorldState(
            players: [WorldPlayer(id: "crown", displayName: "Корона"), WorldPlayer(id: "union", displayName: "Союз")],
            hexes: content.scenario.map.hexes,
            riverBoundaries: [RiverBoundary(id: "river", boundary: HexBoundary(firstHexID: "h-0-0", secondHexID: "h-1-0"))],
            units: [Unit(id: "u1", ownerID: "crown", typeID: "infantry", currentHitPoints: 8, location: .hex("h-0-0"))],
            armies: [Army(id: "a1", ownerID: "crown", hexID: "h-0-0", unitIDs: ["u1"])],
            cities: [City(id: "capital", ownerID: "crown", hexID: "h-0-0", levelID: "village", isCapital: true)],
            buildings: [Building(id: "market", cityID: "capital", typeID: "market")],
            phase: .movement
        )

        let inspection = HexInspection.inspect("h-0-0", map: content.scenario.map, world: world, content: content)

        #expect(inspection?.terrain == "Рівнина")
        #expect(inspection?.riverCount == 1)
        #expect(inspection?.city?.owner == "Корона")
        #expect(inspection?.city?.buildings == ["Market"])
        #expect(inspection?.city?.income == 9)
        #expect(inspection?.armies.first?.units == ["Піхота 8 HP"])
        #expect(inspection?.armies.first?.movement == "2 очок")
    }

    @Test func missingObjectsAreExplicitlyRepresentedAsEmpty() throws {
        let content = try GameContentLoader.loadMVP()
        let inspection = HexInspection.inspect("h-1-1", map: content.scenario.map, world: content.scenario.world, content: content)

        #expect(inspection?.city == nil)
        #expect(inspection?.armies.isEmpty == true)
    }
}
