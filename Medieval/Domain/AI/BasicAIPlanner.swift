import Foundation

/// Decides what the opponent does, without doing any of it.
///
/// Planning is separated from applying for two reasons. It makes the opponent
/// testable — a plan is a value you can assert on, where a sequence of mutations
/// is not — and it keeps the opponent honest: every candidate is put through the
/// same rule the player's own interface calls, and an intent is only planned if
/// that rule accepted it. There is no path by which the opponent can make a move
/// the player could not.
///
/// The plan is a pure function of the state it is given. Nothing is drawn at
/// random and every choice breaks ties on an identifier, so the same board
/// always produces the same plan — which is what makes a replayed match replay.
public enum BasicAIPlanner {
    public static func plan(
        for playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        content: GameContentConfiguration,
        pendingEncounter: PendingEncounter? = nil
    ) -> AIPlan {
        let target = target(for: playerID, world: world, content: content)

        switch world.phase {
        case .capitalPlacement:
            return AIPlan(playerID: playerID, phase: world.phase, target: target, steps: capitalPlacementSteps(for: playerID, world: world, content: content))
        case .handoff:
            return AIPlan(playerID: playerID, phase: world.phase, target: target, steps: [AIStep(priority: .capitalSurvival, intent: .confirmHandoff)])
        case .economy:
            // Income is settled by the rules on the way out of the phase; there
            // is nothing here for the opponent to weigh.
            return AIPlan(playerID: playerID, phase: world.phase, target: target, steps: [AIStep(priority: .income, intent: .advancePhase)])
        case .construction:
            return AIPlan(playerID: playerID, phase: world.phase, target: target, steps: constructionSteps(for: playerID, world: world, economy: economy, content: content) + [AIStep(priority: .income, intent: .advancePhase)])
        case .movement:
            return AIPlan(playerID: playerID, phase: world.phase, target: target, steps: movementSteps(for: playerID, world: world, content: content, target: target) + [AIStep(priority: .advance, intent: .advancePhase)])
        case .combat:
            // A battle this player did not start is not this player's to
            // resolve; ending the turn on top of somebody else's encounter
            // would settle it behind their back.
            var steps: [AIStep] = []
            if let encounter = pendingEncounter,
               world.armies.contains(where: { $0.id == encounter.attackerID && $0.ownerID == playerID })
            {
                steps.append(AIStep(priority: .attack, intent: .resolveBattle(encounter: encounter)))
            }
            steps.append(AIStep(priority: .attack, intent: .endTurn))
            return AIPlan(playerID: playerID, phase: world.phase, target: target, steps: steps)
        case .setup, .playerTurn, .resolvingTurn, .finished:
            // Nothing is asked of a player in these phases, and a finished match
            // is over. An empty plan is the honest answer, not a made-up move.
            return AIPlan(playerID: playerID, phase: world.phase, target: target, steps: [])
        }
    }

    /// Measured from the opponent's own capital, or from wherever its first army
    /// stands before it has one, so targeting works during placement too.
    private static func target(
        for playerID: WorldPlayerID,
        world: WorldState,
        content: GameContentConfiguration
    ) -> AITarget? {
        let capital = world.cities.first { $0.isCapital && $0.ownerID == playerID }
        let army = world.armies.filter { $0.ownerID == playerID }.min { $0.id.rawValue < $1.id.rawValue }
        guard let origin = capital?.hexID ?? army?.hexID else { return nil }
        return AITargeting.nearestReachableEnemyCapital(
            from: origin,
            for: playerID,
            world: world,
            map: content.scenario.map,
            terrain: content.terrain
        )
    }

    /// Founds the capital where it will be worth defending.
    ///
    /// The hex is scored on what the content says it is worth — income first,
    /// then defence — because those are the two numbers a capital lives on. The
    /// candidate is then put through `CapitalPlacementRules`, so an unsuitable
    /// or occupied hex is rejected by the same rule that would reject the
    /// player, rather than by a second opinion here that could drift from it.
    private static func capitalPlacementSteps(
        for playerID: WorldPlayerID,
        world: WorldState,
        content: GameContentConfiguration
    ) -> [AIStep] {
        let terrainByID = Dictionary(content.terrain.map { ($0.id, $0) }) { first, _ in first }
        let ranked = world.hexes
            .compactMap { hex -> (Hex, TerrainDefinition)? in
                guard let definition = terrainByID[hex.terrainID], definition.isCityBuildable else { return nil }
                return (hex, definition)
            }
            .sorted { first, second in
                let firstScore = (first.1.incomeModifier, first.1.defenseModifier)
                let secondScore = (second.1.incomeModifier, second.1.defenseModifier)
                if firstScore != secondScore { return firstScore > secondScore }
                return first.0.id.rawValue < second.0.id.rawValue
            }

        for (hex, _) in ranked {
            let placement = CapitalPlacementRules.placeCapital(
                for: playerID,
                at: hex.id,
                in: world,
                terrain: content.terrain,
                cityLevels: content.cityLevels
            )
            if case .success = placement {
                return [AIStep(priority: .capitalSurvival, intent: .placeCapital(hexID: hex.id))]
            }
        }
        return []
    }

    private static func constructionSteps(
        for playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        content: GameContentConfiguration
    ) -> [AIStep] {
        AIEconomyDecisions.steps(for: playerID, world: world, economy: economy, content: content)
    }

    /// Marching and attacking arrive with MED-55.
    private static func movementSteps(
        for _: WorldPlayerID,
        world _: WorldState,
        content _: GameContentConfiguration,
        target _: AITarget?
    ) -> [AIStep] {
        []
    }
}
