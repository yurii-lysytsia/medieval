import Foundation

public enum MovementDomain: Equatable, Sendable {
    case land
    case naval
}

public struct MovementRoute: Equatable, Sendable {
    public let hexIDs: [HexID]
    public let cost: Int

    public init(hexIDs: [HexID], cost: Int) {
        self.hexIDs = hexIDs
        self.cost = cost
    }
}

public enum StrategicPathfinder {
    /// Finds the deterministic cheapest route within the supplied movement budget.
    public static func route(
        from origin: HexID,
        to destination: HexID,
        budget: Int,
        domain: MovementDomain,
        map: StaticHexMap,
        world: WorldState,
        terrain: [TerrainDefinition]
    ) -> MovementRoute? {
        reachableRoutes(from: origin, budget: budget, domain: domain, map: map, world: world, terrain: terrain)[destination]
    }

    public static func reachableRoutes(
        from origin: HexID,
        budget: Int,
        domain: MovementDomain,
        map: StaticHexMap,
        world: WorldState,
        terrain: [TerrainDefinition]
    ) -> [HexID: MovementRoute] {
        guard budget >= 0,
              let originHex = world.hexes.first(where: { $0.id == origin }),
              canOccupy(originHex, domain: domain)
        else { return [:] }
        let neighbors = Dictionary(uniqueKeysWithValues: map.neighborhoods.map { ($0.hexID, $0.neighborHexIDs) })
        let terrainByID = Dictionary(uniqueKeysWithValues: terrain.map { ($0.id, $0) })
        let hexByID = Dictionary(uniqueKeysWithValues: world.hexes.map { ($0.id, $0) })
        var routes: [HexID: MovementRoute] = [origin: MovementRoute(hexIDs: [origin], cost: 0)]
        var frontier: [HexID] = [origin]

        while !frontier.isEmpty {
            frontier.sort { first, second in
                let firstRoute = routes[first]!
                let secondRoute = routes[second]!
                return firstRoute.cost == secondRoute.cost ? first.rawValue < second.rawValue : firstRoute.cost < secondRoute.cost
            }
            let current = frontier.removeFirst()
            guard let currentRoute = routes[current] else { continue }

            for candidate in (neighbors[current] ?? []).sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let stepCost = movementCost(
                    from: current,
                    to: candidate,
                    domain: domain,
                    world: world,
                    hexByID: hexByID,
                    terrainByID: terrainByID
                ) else { continue }
                let total = currentRoute.cost + stepCost
                guard total <= budget else { continue }
                let proposed = MovementRoute(hexIDs: currentRoute.hexIDs + [candidate], cost: total)
                if let existing = routes[candidate], !isBetter(proposed, than: existing) { continue }
                routes[candidate] = proposed
                if !frontier.contains(candidate) { frontier.append(candidate) }
            }
        }

        return routes
    }

    private static func movementCost(
        from origin: HexID,
        to destination: HexID,
        domain: MovementDomain,
        world: WorldState,
        hexByID: [HexID: Hex],
        terrainByID: [TerrainID: TerrainDefinition]
    ) -> Int? {
        guard let hex = hexByID[destination] else { return nil }
        switch domain {
        case .land:
            guard hex.terrainID != "deep-water",
                  let definition = terrainByID[hex.terrainID],
                  definition.isPassable
            else { return nil }
            return definition.movementCost + (RiverRules.crossesRiver(from: origin, to: destination, in: world) ? 1 : 0)
        case .naval:
            guard hex.terrainID == "shallows" || hex.terrainID == "deep-water" else { return nil }
            return 1
        }
    }

    private static func canOccupy(_ hex: Hex, domain: MovementDomain) -> Bool {
        switch domain {
        case .land: hex.terrainID != "deep-water" && hex.isPassable
        case .naval: hex.terrainID == "shallows" || hex.terrainID == "deep-water"
        }
    }

    private static func isBetter(_ proposed: MovementRoute, than existing: MovementRoute) -> Bool {
        if proposed.cost != existing.cost { return proposed.cost < existing.cost }
        return proposed.hexIDs.map(\.rawValue).joined(separator: "/") < existing.hexIDs.map(\.rawValue).joined(separator: "/")
    }
}
