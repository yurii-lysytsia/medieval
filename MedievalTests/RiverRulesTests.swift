import Foundation
@testable import Medieval
import Testing

struct RiverRulesTests {
    @Test func crossingIsDetectedInEitherDirection() {
        let world = worldWithRiver()

        #expect(RiverRules.crossesRiver(from: "west", to: "east", in: world))
        #expect(RiverRules.crossesRiver(from: "east", to: "west", in: world))
        #expect(!RiverRules.crossesRiver(from: "west", to: "north", in: world))
    }

    @Test func defenderGetsBonusOnlyForAttackAcrossRiver() {
        let world = worldWithRiver()

        #expect(RiverRules.defenderBonus(whenAttackedFrom: "west", defending: "east", in: world) == 1)
        #expect(RiverRules.defenderBonus(whenAttackedFrom: "east", defending: "west", in: world) == 1)
        #expect(RiverRules.defenderBonus(whenAttackedFrom: "west", defending: "north", in: world) == 0)
    }

    private func worldWithRiver() -> WorldState {
        WorldState(
            players: [WorldPlayer(id: "one", displayName: "One"), WorldPlayer(id: "two", displayName: "Two")],
            hexes: [],
            riverBoundaries: [RiverBoundary(id: "river", boundary: HexBoundary(firstHexID: "west", secondHexID: "east"))]
        )
    }
}
