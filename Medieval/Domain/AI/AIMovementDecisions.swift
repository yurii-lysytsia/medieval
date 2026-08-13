import Foundation

/// How the opponent marches, and when it decides to hit something.
enum AIMovementDecisions {
    static func steps(
        for playerID: WorldPlayerID,
        game: GameState,
        world: WorldState,
        content: GameContentConfiguration,
        target: AITarget?
    ) -> [AIStep] {
        guard let target else { return [] }
        // How far every hex is from the target, worked out once. The field is
        // measured outwards *from* the target, so it is the cost of walking
        // back from it rather than of walking to it; the two differ only where
        // neighbouring terrain costs differ, which is close enough to steer by
        // and immeasurably cheaper than a search per candidate hex.
        let guidance = StrategicPathfinder.reachableRoutes(
            from: target.hexID,
            budget: AITargeting.unlimitedBudget,
            domain: .land,
            map: content.scenario.map,
            world: world,
            terrain: content.terrain
        )

        var steps: [AIStep] = []
        var game = game
        var world = world
        // Only one encounter can be outstanding at a time, so the opponent
        // commits to one fight per phase and walks the rest of its armies.
        var hasCommittedToBattle = false

        for army in world.armies.filter({ $0.ownerID == playerID }).sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            guard let decision = advance(
                army,
                playerID: playerID,
                game: game,
                world: world,
                content: content,
                target: target,
                guidance: guidance,
                avoidingBattle: hasCommittedToBattle
            ) else { continue }
            steps.append(decision.step)
            game = decision.game
            world = decision.world
            hasCommittedToBattle = hasCommittedToBattle || decision.startsBattle
        }
        return steps
    }

    private struct Decision {
        let step: AIStep
        let game: GameState
        let world: WorldState
        let startsBattle: Bool
    }

    /// Moves one army as close to the target as this turn's movement allows.
    ///
    /// Candidates come from `MovementPreviewRules` — the same preview the
    /// player's own map draws — so the opponent is choosing from exactly the
    /// hexes a person could choose from. Deep water never appears among them:
    /// the preview searches on land, and the opponent has no fleet.
    private static func advance(
        _ army: Army,
        playerID: WorldPlayerID,
        game: GameState,
        world: WorldState,
        content: GameContentConfiguration,
        target: AITarget,
        guidance: [HexID: MovementRoute],
        avoidingBattle: Bool
    ) -> Decision? {
        guard let preview = MovementPreviewRules.preview(
            armyID: army.id,
            playerID: playerID,
            world: world,
            map: content.scenario.map,
            terrain: content.terrain,
            units: content.units
        ) else { return nil }

        let current = guidance[army.hexID]?.cost ?? Int.max
        let candidates = preview.routes
            .filter { hexID, route in
                guard hexID != army.hexID, route.hexIDs.count > 1 else { return false }
                // Standing still is not a move; anything that does not close the
                // gap is standing still with extra steps.
                guard let distance = guidance[hexID]?.cost, distance < current else { return false }
                guard preview.encounterHexIDs.contains(hexID) else { return true }
                return !avoidingBattle && isWorthEngaging(at: hexID, army: army, world: world, content: content, target: target)
            }
            .sorted { first, second in
                let firstDistance = guidance[first.key]?.cost ?? Int.max
                let secondDistance = guidance[second.key]?.cost ?? Int.max
                if firstDistance != secondDistance { return firstDistance < secondDistance }
                if first.value.cost != second.value.cost { return first.value.cost > second.value.cost }
                return first.key.rawValue < second.key.rawValue
            }

        for (hexID, route) in candidates {
            let result = StrategicMovementRules.confirmArmyMovement(
                armyID: army.id,
                route: route,
                game: game,
                world: world,
                map: content.scenario.map,
                terrain: content.terrain,
                units: content.units
            )
            guard case let .success(resolution) = result else { continue }
            let startsBattle = resolution.encounter != nil
            return Decision(
                step: AIStep(priority: startsBattle ? .attack : .advance, intent: .moveArmy(armyID: army.id, route: route)),
                game: resolution.game,
                world: resolution.world,
                startsBattle: startsBattle
            )
        }
        return nil
    }

    /// Whether walking into that hex is a fight worth having.
    ///
    /// Favourable or unavoidable, in the ticket's words: the opponent attacks
    /// when it brings at least as much to the fight as the defender does, and
    /// it attacks the target capital regardless — taking it ends the match, and
    /// an opponent that only ever fought battles it was winning would circle a
    /// defended capital forever.
    private static func isWorthEngaging(
        at hexID: HexID,
        army: Army,
        world: WorldState,
        content: GameContentConfiguration,
        target: AITarget
    ) -> Bool {
        if hexID == target.hexID { return true }
        let defenders = world.armies.filter { $0.hexID == hexID && $0.ownerID != army.ownerID }
        guard !defenders.isEmpty else { return true }
        let defence = defenders.reduce(0) { total, defender in total + strength(of: defender, world: world, content: content) }
        return strength(of: army, world: world, content: content) >= defence
    }

    /// What an army brings to a fight: the health it can lose plus the damage it
    /// can deal, which are the two numbers the battle actually runs on.
    private static func strength(of army: Army, world: WorldState, content: GameContentConfiguration) -> Int {
        army.unitIDs.reduce(0) { total, unitID in
            guard let unit = world.units.first(where: { $0.id == unitID }) else { return total }
            let damage = content.units.first(where: { $0.id == unit.typeID })?.damage ?? 0
            return total + unit.currentHitPoints + damage
        }
    }
}
