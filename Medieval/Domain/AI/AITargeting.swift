import Foundation

/// Picks what the opponent is playing towards.
public enum AITargeting {
    /// The enemy capital that costs the least movement to reach on land.
    ///
    /// Distance is measured with the pathfinder rather than by coordinates, so
    /// a capital two hexes away across a mountain range is correctly treated as
    /// further off than one five hexes away over plains. A capital with no land
    /// route at all is not a target: the opponent has no fleet, and marching at
    /// something it can never arrive at is how a turn loop stops making
    /// progress.
    ///
    /// Ties break on the city id so the same board always yields the same
    /// target — two capitals at equal cost must not depend on dictionary order.
    public static func nearestReachableEnemyCapital(
        from origin: HexID,
        for playerID: WorldPlayerID,
        world: WorldState,
        map: StaticHexMap,
        terrain: [TerrainDefinition]
    ) -> AITarget? {
        let enemyCapitals = world.cities.filter { city in
            city.isCapital && city.ownerID != nil && city.ownerID != playerID
        }
        guard !enemyCapitals.isEmpty else { return nil }

        let routes = StrategicPathfinder.reachableRoutes(
            from: origin,
            budget: unlimitedBudget,
            domain: .land,
            map: map,
            world: world,
            terrain: terrain
        )
        return enemyCapitals
            .compactMap { city -> AITarget? in
                guard let ownerID = city.ownerID, let route = routes[city.hexID] else { return nil }
                return AITarget(cityID: city.id, hexID: city.hexID, ownerID: ownerID, distance: route.cost)
            }
            .min { first, second in
                first.distance == second.distance
                    ? first.cityID.rawValue < second.cityID.rawValue
                    : first.distance < second.distance
            }
    }

    /// Large enough to span the map, so targeting sees the whole board rather
    /// than one turn's worth of movement. The search still stops at the edge of
    /// what land connects to the origin.
    static let unlimitedBudget = Int.max / 4
}
