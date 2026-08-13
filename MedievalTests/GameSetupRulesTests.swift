@testable import MedievalDomain
import Testing

struct GameSetupRulesTests {
    @Test func validSetupTrimsNames() throws {
        let setup = try GameSetupRules.validate([GameSetupPlayer(name: " One ", color: .red), GameSetupPlayer(name: "Two", color: .blue)]).get()
        #expect(setup.map(\.name) == ["One", "Two"])
    }

    @Test func duplicateAndEmptyNamesAreRejected() {
        #expect(GameSetupRules.validate([GameSetupPlayer(name: "One", color: .red), GameSetupPlayer(name: "one", color: .blue)]) == .failure(.duplicateName("one")))
        #expect(GameSetupRules.validate([GameSetupPlayer(name: "", color: .red), GameSetupPlayer(name: "Two", color: .blue)]) == .failure(.emptyName(0)))
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
