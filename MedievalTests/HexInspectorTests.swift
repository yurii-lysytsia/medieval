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

        let inspection = try #require(HexInspection.inspect("h-0-0", map: content.scenario.map, world: world, content: content))

        #expect(inspection.terrain == "Рівнина")
        #expect(inspection.riverCount == 1)
        #expect(inspection.city?.owner == "Корона")
        #expect(inspection.city?.buildings == ["Ринок"])
        // Village 8, plains +2, market +5.
        #expect(inspection.city?.income == 15)
        #expect(inspection.armies.first?.units.map(\.name) == ["Піхота"])
        #expect(inspection.armies.first?.units.map(\.hitPoints) == [8])
        #expect(inspection.armies.first?.movementPoints == 2)
        #expect(inspection.armies.first?.hasMoved == false)
    }

    @Test func missingObjectsAreExplicitlyRepresentedAsEmpty() throws {
        let content = try GameContentLoader.loadMVP()
        let inspection = HexInspection.inspect("h-1-1", map: content.scenario.map, world: content.scenario.world, content: content)

        #expect(inspection?.city == nil)
        #expect(inspection?.armies.isEmpty == true)
        #expect(inspection?.riverCount == 0)
    }

    @Test func unknownOwnerAndUndefinedLevelAreReportedAsMissingRatherThanGuessed() throws {
        // A city level the content does not define makes the income unknowable;
        // reporting a number would quietly drop the level's base income.
        let content = try GameContentLoader.loadMVP()
        let world = WorldState(
            players: [WorldPlayer(id: "crown", displayName: "Корона"), WorldPlayer(id: "union", displayName: "Союз")],
            hexes: content.scenario.map.hexes,
            cities: [City(id: "ruin", ownerID: nil, hexID: "h-0-0", levelID: "metropolis")],
            phase: .movement
        )

        let city = try #require(HexInspection.inspect("h-0-0", map: content.scenario.map, world: world, content: content)?.city)

        #expect(city.owner == nil)
        #expect(city.income == nil)
        #expect(city.recruitmentLimit == nil)
        #expect(city.level == "metropolis")
    }

    @Test func anArmyMovesAtThePaceOfItsSlowestUnit() throws {
        let content = try GameContentLoader.loadMVP()
        let world = WorldState(
            players: [WorldPlayer(id: "crown", displayName: "Корона"), WorldPlayer(id: "union", displayName: "Союз")],
            hexes: content.scenario.map.hexes,
            units: [
                Unit(id: "foot", ownerID: "crown", typeID: "infantry", currentHitPoints: 10, location: .hex("h-0-0")),
                Unit(id: "horse", ownerID: "crown", typeID: "cavalry", currentHitPoints: 9, location: .hex("h-0-0")),
            ],
            armies: [Army(id: "a1", ownerID: "crown", hexID: "h-0-0", unitIDs: ["foot", "horse"], hasMoved: true)],
            phase: .movement
        )

        let army = try #require(HexInspection.inspect("h-0-0", map: content.scenario.map, world: world, content: content)?.armies.first)

        #expect(army.movementPoints == 2)
        #expect(army.hasMoved)
    }
}
