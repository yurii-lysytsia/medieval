import Foundation

/// Rules for a transition across a shared hex boundary.
public enum RiverRules {
    /// The defender receives one point of defense only when the attacker crosses a river.
    public static let defenderBonus = 1

    /// Used by movement and combat to identify crossings in either direction.
    public static func crossesRiver(from originHexID: HexID, to destinationHexID: HexID, in world: WorldState) -> Bool {
        world.riverBoundary(between: originHexID, and: destinationHexID) != nil
    }

    public static func defenderBonus(
        whenAttackedFrom attackerHexID: HexID,
        defending destinationHexID: HexID,
        in world: WorldState
    ) -> Int {
        crossesRiver(from: attackerHexID, to: destinationHexID, in: world) ? defenderBonus : 0
    }
}
