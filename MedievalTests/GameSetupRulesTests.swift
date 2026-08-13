@testable import Medieval
import Testing

struct GameSetupRulesTests {
    @Test func validSetupTrimsNames() throws {
        let setup = try GameSetupRules.validate([GameSetupPlayer(name: " One ", color: .red), GameSetupPlayer(name: "Two", color: .blue)]).get()
        #expect(setup.map(\.name) == ["One", "Two"])
    }

    @Test func duplicateAndEmptyNamesAreRejected() {
        #expect(GameSetupRules.validate([GameSetupPlayer(name: "One", color: .red), GameSetupPlayer(name: "one", color: .blue)]) == .failure(.duplicateName("one")))
        #expect(GameSetupRules.validate([GameSetupPlayer(name: "", color: .red), GameSetupPlayer(name: "Two", color: .blue)]) == .failure(.emptyName(0)))
        // Whitespace is trimmed before comparing, so a padded name is a repeat.
        #expect(GameSetupRules.validate([GameSetupPlayer(name: "One", color: .red), GameSetupPlayer(name: " One ", color: .blue)]) == .failure(.duplicateName("One")))
        #expect(GameSetupRules.validate([GameSetupPlayer(name: "One", color: .red), GameSetupPlayer(name: "   ", color: .blue)]) == .failure(.emptyName(1)))
    }

    @Test func aRepeatedColorNamesTheColorThatCollided() {
        // The message quotes the colour, so reporting the first player's colour
        // would tell the player to change the wrong one.
        let setup = [
            GameSetupPlayer(name: "One", color: .red),
            GameSetupPlayer(name: "Two", color: .green),
            GameSetupPlayer(name: "Three", color: .green),
        ]

        #expect(GameSetupRules.validate(setup) == .failure(.duplicateColor(.green)))
    }

    @Test func aMatchNeedsTwoToFourPlayers() {
        let one = [GameSetupPlayer(name: "One", color: .red)]
        let five = PlayerColor.allCases.map { GameSetupPlayer(name: $0.rawValue, color: $0) } + [GameSetupPlayer(name: "Five", color: .red)]

        #expect(GameSetupRules.validate([]) == .failure(.invalidPlayerCount))
        #expect(GameSetupRules.validate(one) == .failure(.invalidPlayerCount))
        #expect(GameSetupRules.validate(five) == .failure(.invalidPlayerCount))
    }

    @Test func supportsFourPlayersWithUniqueColors() throws {
        let setup = [
            GameSetupPlayer(name: "One", color: .red),
            GameSetupPlayer(name: "Two", color: .blue),
            GameSetupPlayer(name: "Three", color: .green),
            GameSetupPlayer(name: "Four", color: .gold),
        ]
        let validated = try GameSetupRules.validate(setup).get()
        #expect(validated == setup)
    }
}
