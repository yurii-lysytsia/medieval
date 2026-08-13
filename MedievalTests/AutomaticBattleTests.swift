@testable import Medieval
import Testing

struct AutomaticBattleTests {
    @Test func basicDuelProducesWinnerLossesAndRounds() throws {
        let result = try AutomaticBattle.resolve(attackers: [unit("a", hp: 10)], defenders: [unit("d", hp: 10)], definitions: definitions, seed: 42).get()
        #expect(result.outcome == .draw)
        #expect(!result.rounds.isEmpty)
        #expect(result.attackerLosses == ["a"])
        #expect(result.defenderLosses == ["d"])
    }

    @Test func sameInputAndSeedAlwaysProduceSameResult() throws {
        let attackers = [unit("a1", hp: 10), unit("a2", hp: 10, type: "archers")]
        let defenders = [unit("d1", hp: 10), unit("d2", hp: 10)]
        let first = try AutomaticBattle.resolve(attackers: attackers, defenders: defenders, definitions: definitions, seed: 7).get()
        let second = try AutomaticBattle.resolve(attackers: attackers, defenders: defenders, definitions: definitions, seed: 7).get()
        #expect(first == second)
    }

    @Test func archersDealDamageBeforeMeleeUnits() throws {
        let result = try AutomaticBattle.resolve(attackers: [unit("archer", hp: 7, type: "archers")], defenders: [unit("infantry", hp: 3)], definitions: definitions, seed: 1).get()
        #expect(result.rounds.count == 1)
        #expect(result.outcome == .victory(.attacker))
        #expect(result.attackerSurvivors.first?.hitPoints == 7)
    }

    @Test func aBattleStopsAtTheRoundCapInsteadOfRunningForever() throws {
        // Two armies that cannot finish each other off: harmless units grind on
        // until the cap, and the survivors on both sides make it a draw.
        let feeble = [UnitDefinition(id: "feeble", displayName: "Feeble", recruitmentCost: 1, upkeep: 0, hitPoints: 400, damage: 1, attackRange: 1, movement: 1, domain: .land)]
        let result = try AutomaticBattle.resolve(
            attackers: [unit("a", hp: 400, type: "feeble")],
            defenders: [unit("d", hp: 400, type: "feeble")],
            definitions: feeble,
            seed: 3
        ).get()

        #expect(result.rounds.count == 100)
        #expect(result.rounds.map(\.number) == Array(1 ... 100))
        #expect(result.outcome == .draw)
        #expect(result.attackerLosses.isEmpty)
        #expect(result.defenderLosses.isEmpty)
    }

    @Test func aUnitCannotFightTwiceInTheSameBattle() {
        // Hit points are tracked per id, so a repeated unit would share a health
        // pool with itself and quietly soak twice the damage.
        let twice = AutomaticBattle.resolve(attackers: [unit("a", hp: 10), unit("a", hp: 10)], defenders: [unit("d", hp: 10)], definitions: definitions, seed: 1)
        let bothSides = AutomaticBattle.resolve(attackers: [unit("a", hp: 10)], defenders: [unit("a", hp: 10)], definitions: definitions, seed: 1)

        #expect(twice == .failure(.duplicateUnit("a")))
        #expect(bothSides == .failure(.duplicateUnit("a")))
    }

    @Test func emptyArmiesAndUnknownUnitTypesAreReportedRatherThanFought() {
        #expect(AutomaticBattle.resolve(attackers: [], defenders: [unit("d", hp: 10)], definitions: definitions, seed: 1) == .failure(.emptyArmy(.attacker)))
        #expect(AutomaticBattle.resolve(attackers: [unit("a", hp: 10)], defenders: [], definitions: definitions, seed: 1) == .failure(.emptyArmy(.defender)))
        #expect(AutomaticBattle.resolve(attackers: [unit("a", hp: 10, type: "dragons")], defenders: [unit("d", hp: 10)], definitions: definitions, seed: 1) == .failure(.missingDefinition("dragons")))
    }

    private let definitions = [
        UnitDefinition(id: "infantry", displayName: "Infantry", recruitmentCost: 20, upkeep: 2, hitPoints: 10, damage: 4, attackRange: 1, movement: 2, domain: .land),
        UnitDefinition(id: "archers", displayName: "Archers", recruitmentCost: 25, upkeep: 2, hitPoints: 7, damage: 3, attackRange: 3, movement: 2, domain: .land),
    ]
    private func unit(_ id: UnitID, hp: Int, type: UnitTypeID = "infantry") -> Unit {
        Unit(id: id, ownerID: id.rawValue.hasPrefix("a") ? "one" : "two", typeID: type, currentHitPoints: hp, location: .hex("h"))
    }
}
