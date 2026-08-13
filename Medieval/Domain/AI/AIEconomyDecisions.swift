import Foundation

/// What the opponent does with its coins during the construction phase.
///
/// Every candidate is offered to the rule that would carry it out, and only an
/// accepted one is kept. The rule hands back the world and treasury it would
/// leave behind, and the next candidate is judged against those — so a phase's
/// worth of spending is planned against a running balance rather than against
/// the balance it started with. That is what stops the opponent planning three
/// purchases it can only afford one of.
enum AIEconomyDecisions {
    /// How close an enemy army has to be, in movement cost, before the capital
    /// counts as threatened and defence outranks growth.
    static let threatRange = 6
    /// A stop on the planning loop. The rules already bound spending — slots,
    /// recruitment limits, coins — so this only exists so a rule that started
    /// accepting the same move forever could not hang a turn.
    static let maximumSteps = 12

    static func steps(
        for playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        content: GameContentConfiguration
    ) -> [AIStep] {
        var steps: [AIStep] = []
        var world = world
        var economy = economy
        var ledger = RecruitmentLedger()
        let threatened = isCapitalThreatened(for: playerID, world: world, content: content)

        while steps.count < maximumSteps {
            guard let decision = bestDecision(
                for: playerID,
                world: world,
                economy: economy,
                ledger: ledger,
                content: content,
                threatened: threatened
            ) else { break }
            steps.append(decision.step)
            world = decision.world
            economy = decision.economy
            ledger = decision.ledger
        }
        return steps
    }

    private struct Decision {
        let step: AIStep
        let world: WorldState
        let economy: EconomyState
        let ledger: RecruitmentLedger
    }

    /// Weighs one purchase, highest priority first.
    ///
    /// A threatened capital reverses the usual order: walls bought a turn late
    /// are walls bought after the capital fell, and the match ends there.
    private static func bestDecision(
        for playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        ledger: RecruitmentLedger,
        content: GameContentConfiguration,
        threatened: Bool
    ) -> Decision? {
        let cities = world.cities.filter { $0.ownerID == playerID }.sorted { $0.id.rawValue < $1.id.rawValue }
        if threatened {
            for city in cities {
                if let decision = fortification(city, playerID: playerID, world: world, economy: economy, ledger: ledger, content: content) { return decision }
                if let decision = recruitment(city, playerID: playerID, world: world, economy: economy, ledger: ledger, content: content) { return decision }
            }
        }
        for city in cities {
            if let decision = growth(city, playerID: playerID, world: world, economy: economy, ledger: ledger, content: content) { return decision }
        }
        for city in cities {
            if let decision = recruitment(city, playerID: playerID, world: world, economy: economy, ledger: ledger, content: content) { return decision }
        }
        return nil
    }

    /// Defence, best first. Only buildings the content gives a defence value to
    /// count, so renaming "walls" in the content changes nothing here.
    private static func fortification(
        _ city: City,
        playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        ledger: RecruitmentLedger,
        content: GameContentConfiguration
    ) -> Decision? {
        let candidates = content.buildings
            .filter { $0.defenseModifier > 0 }
            .sorted { first, second in
                first.defenseModifier == second.defenseModifier
                    ? first.id.rawValue < second.id.rawValue
                    : first.defenseModifier > second.defenseModifier
            }
        return candidates.lazy.compactMap { definition in
            construct(definition.id, in: city, priority: .capitalSurvival, playerID: playerID, world: world, economy: economy, ledger: ledger, content: content)
        }.first
    }

    /// Growth, in the order that actually compounds:
    ///
    /// 1. a building the next city level requires — without it the city cannot
    ///    grow at all, and a village has one slot to spend, so filling it with
    ///    a market walls the city in at its starting size;
    /// 2. the upgrade itself, which raises base income and frees slots;
    /// 3. otherwise whichever affordable building pays the most.
    private static func growth(
        _ city: City,
        playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        ledger: RecruitmentLedger,
        content: GameContentConfiguration
    ) -> Decision? {
        let built = Set(world.buildings.filter { $0.cityID == city.id }.map(\.typeID))
        if let nextLevel = nextLevel(after: city.levelID, in: content.cityLevels) {
            let missing = nextLevel.requiredBuildingIDs
                .filter { !built.contains($0) }
                .sorted { first, second in first.rawValue < second.rawValue }
            for buildingTypeID in missing {
                if let decision = construct(buildingTypeID, in: city, priority: .income, playerID: playerID, world: world, economy: economy, ledger: ledger, content: content) {
                    return decision
                }
            }
            let upgrade = CityConstructionRules.upgrade(cityID: city.id, for: playerID, world: world, economy: economy, cityLevels: content.cityLevels)
            if case let .success(result) = upgrade {
                return Decision(
                    step: AIStep(priority: .income, intent: .upgradeCity(cityID: city.id)),
                    world: result.world,
                    economy: result.economy,
                    ledger: ledger
                )
            }
        }

        let earners = content.buildings
            .filter { $0.incomeModifier > 0 }
            .sorted { first, second in
                first.incomeModifier == second.incomeModifier
                    ? first.constructionCost < second.constructionCost
                    : first.incomeModifier > second.incomeModifier
            }
        return earners.lazy.compactMap { definition in
            construct(definition.id, in: city, priority: .income, playerID: playerID, world: world, economy: economy, ledger: ledger, content: content)
        }.first
    }

    /// Troops, sturdiest first. Only land units: the opponent has no naval
    /// behaviour, and a ship it never sails is upkeep it pays for nothing.
    private static func recruitment(
        _ city: City,
        playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        ledger: RecruitmentLedger,
        content: GameContentConfiguration
    ) -> Decision? {
        let candidates = content.units
            .filter { $0.domain == .land }
            .sorted { first, second in
                let firstWorth = first.hitPoints + first.damage
                let secondWorth = second.hitPoints + second.damage
                if firstWorth != secondWorth { return firstWorth > secondWorth }
                if first.recruitmentCost != second.recruitmentCost { return first.recruitmentCost < second.recruitmentCost }
                return first.id.rawValue < second.id.rawValue
            }

        for definition in candidates {
            let result = RecruitmentRules.recruit(
                unitTypeID: definition.id,
                in: city.id,
                for: playerID,
                world: world,
                economy: economy,
                ledger: ledger,
                map: content.scenario.map,
                terrain: content.terrain,
                units: content.units,
                cityLevels: content.cityLevels
            )
            if case let .success(recruitment) = result {
                return Decision(
                    step: AIStep(priority: .recruitment, intent: .recruit(unitTypeID: definition.id, cityID: city.id)),
                    world: recruitment.world,
                    economy: recruitment.economy,
                    ledger: recruitment.ledger
                )
            }
        }
        return nil
    }

    private static func construct(
        _ buildingTypeID: BuildingTypeID,
        in city: City,
        priority: AIPriority,
        playerID: WorldPlayerID,
        world: WorldState,
        economy: EconomyState,
        ledger: RecruitmentLedger,
        content: GameContentConfiguration
    ) -> Decision? {
        let result = CityConstructionRules.construct(
            buildingTypeID: buildingTypeID,
            in: city.id,
            for: playerID,
            world: world,
            economy: economy,
            cityLevels: content.cityLevels,
            buildings: content.buildings
        )
        guard case let .success(construction) = result else { return nil }
        return Decision(
            step: AIStep(priority: priority, intent: .construct(buildingTypeID: buildingTypeID, cityID: city.id)),
            world: construction.world,
            economy: construction.economy,
            ledger: ledger
        )
    }

    private static func nextLevel(after levelID: CityLevelID, in levels: [CityLevelDefinition]) -> CityLevelDefinition? {
        guard let index = levels.firstIndex(where: { $0.id == levelID }), levels.indices.contains(index + 1) else { return nil }
        return levels[index + 1]
    }

    /// Whether an enemy army is close enough to the capital to matter this turn.
    ///
    /// Measured in movement cost from the capital outwards, so terrain counts:
    /// an army two hexes off behind a mountain range is not the same threat as
    /// one two hexes off across open plains.
    static func isCapitalThreatened(
        for playerID: WorldPlayerID,
        world: WorldState,
        content: GameContentConfiguration
    ) -> Bool {
        guard let capital = world.cities.first(where: { $0.isCapital && $0.ownerID == playerID }) else { return false }
        let reachable = StrategicPathfinder.reachableRoutes(
            from: capital.hexID,
            budget: threatRange,
            domain: .land,
            map: content.scenario.map,
            world: world,
            terrain: content.terrain
        )
        return world.armies.contains { army in
            army.ownerID != playerID && reachable[army.hexID] != nil
        }
    }
}
