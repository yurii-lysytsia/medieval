import Foundation

/// Turns the situation on the map into the bonuses a defender fights with.
public enum BattleContextRules {
    /// What one point of defence is worth as damage reduction.
    ///
    /// Content states defence in points — forest 1, mountains 2, walls 4 — the
    /// same scale `RiverRules.defenderBonus` uses, while the battle works in
    /// percentages. Converting in one place keeps every source on that one
    /// scale; reading the points as percentages made forest worth 1% and walls
    /// 4%, which is indistinguishable from no bonus at all.
    public static let percentPerDefensePoint = 10
    /// A city defended from inside its own walls, in defence points.
    public static let garrisonDefensePoints = 1
    /// Ranged defenders shoot at an approaching enemy before it closes.
    public static let rangedDefenderRollBonus = 2

    /// Collects the defender's bonuses for an attack on `destination`.
    ///
    /// Everything here helps the defender only. That is what makes a river
    /// worth defending behind: the same crossing that costs the attacker
    /// movement also costs it damage, and never the other way round.
    public static func context(
        attacker: Army,
        defender: Army,
        destination: HexID,
        world: WorldState,
        terrain: [TerrainDefinition],
        units: [UnitDefinition],
        buildings: [BuildingDefinition]
    ) -> BattleContext {
        let unitByID = Dictionary(world.units.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let definitionByID = Dictionary(units.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Derived from the unit's stats, not from its type id: content is free
        // to rename "archers" or add a second ranged unit, and nothing here has
        // to be edited to keep up.
        let defenderShootsFirst = defender.unitIDs.contains { id in
            guard let typeID = unitByID[id]?.typeID else { return false }
            return (definitionByID[typeID]?.attackRange ?? 0) > 1
        }

        var modifiers: [BattleModifier] = []
        if let terrainID = world.hexes.first(where: { $0.id == destination })?.terrainID,
           let points = terrain.first(where: { $0.id == terrainID })?.defenseModifier,
           points != 0
        {
            modifiers.append(BattleModifier(kind: .terrain, percent: points * percentPerDefensePoint))
        }
        let riverPoints = RiverRules.defenderBonus(whenAttackedFrom: attacker.hexID, defending: destination, in: world)
        if riverPoints != 0 {
            modifiers.append(BattleModifier(kind: .river, percent: riverPoints * percentPerDefensePoint))
        }
        if let city = world.cities.first(where: { $0.hexID == destination && $0.ownerID == defender.ownerID }) {
            let buildingByID = Dictionary(buildings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // Any building the content gives a defence value to counts, not just
            // walls by name — that is what `BuildingDefinition.defenseModifier`
            // is for.
            let fortificationPoints = world.buildings
                .filter { $0.cityID == city.id }
                .compactMap { buildingByID[$0.typeID]?.defenseModifier }
                .reduce(0, +)
            if fortificationPoints > 0 {
                modifiers.append(BattleModifier(kind: .fortifications, percent: fortificationPoints * percentPerDefensePoint))
            }
            if world.units.contains(where: { $0.ownerID == defender.ownerID && $0.location == .garrison(city.id) }) {
                modifiers.append(BattleModifier(kind: .garrison, percent: garrisonDefensePoints * percentPerDefensePoint))
            }
        }
        return BattleContext(
            defenderRollBonus: defenderShootsFirst ? rangedDefenderRollBonus : 0,
            defenderModifiers: modifiers
        )
    }
}
