import Foundation
@testable import Medieval
import Testing

struct UnitModelsTests {
    @Test func fourMVPUnitTypesLoadWithConfiguredCharacteristics() throws {
        let definitions = try GameContentLoader.loadMVP().units
        let byID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id.rawValue, $0) })

        #expect(Set(byID.keys) == ["infantry", "archers", "cavalry", "ship"])
        #expect(byID["infantry"]?.hitPoints == 10)
        #expect(byID["archers"]?.attackRange == 3)
        #expect(byID["cavalry"]?.movement == 4)
        #expect(byID["ship"]?.domain == .navalTransport)
        #expect(byID["ship"]?.cargoCapacity == 3)
    }

    @Test func unitInstanceStoresOwnerConditionAndLocationWithoutDuplicatingStats() throws {
        let unit = Unit(
            id: "unit-1",
            ownerID: "crown",
            typeID: "infantry",
            currentHitPoints: 10,
            condition: .ready,
            location: .hex("capital")
        )

        let decoded = try JSONDecoder().decode(Unit.self, from: JSONEncoder().encode(unit))

        #expect(decoded == unit)
        #expect(decoded.typeID == "infantry")
        #expect(decoded.location == .hex("capital"))
    }
}
