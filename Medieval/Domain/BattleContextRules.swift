import Foundation

public enum BattleContextRules {
    public static func context(
        attacker: Army,
        defender: Army,
        destination: HexID,
        world: WorldState,
        terrain: [TerrainDefinition],
        units: [UnitDefinition],
        buildings: [BuildingDefinition]
    ) -> BattleContext {
        let unitByID = Dictionary(uniqueKeysWithValues: world.units.map { ($0.id, $0) })
        let definitionByID = Dictionary(uniqueKeysWithValues: units.map { ($0.id, $0) })
        let attackerRollBonus = attacker.unitIDs.contains { id in unitByID[id]?.typeID == "cavalry" } ? 2 : 0
        let defenderRollBonus = defender.unitIDs.contains { id in
            guard let typeID = unitByID[id]?.typeID else { return false }
            return typeID == "archers" || (definitionByID[typeID]?.attackRange ?? 0) > 1
        } ? 2 : 0
        var modifiers: [BattleModifier] = []
        if let terrainID = world.hexes.first(where: { $0.id == destination })?.terrainID,
           let value = terrain.first(where: { $0.id == terrainID })?.defenseModifier,
           value != 0
        {
            modifiers.append(BattleModifier(name: "Місцевість", percent: value))
        }
        if RiverRules.crossesRiver(from: attacker.hexID, to: destination, in: world) {
            modifiers.append(BattleModifier(name: "Річка", percent: 20))
        }
        if let city = world.cities.first(where: { $0.hexID == destination && $0.ownerID == defender.ownerID }) {
            let buildingByID = Dictionary(uniqueKeysWithValues: buildings.map { ($0.id, $0) })
            let wallBonus = world.buildings.filter { $0.cityID == city.id && $0.typeID == "walls" }
                .compactMap { buildingByID[$0.typeID]?.defenseModifier }.reduce(0, +)
            if wallBonus > 0 { modifiers.append(BattleModifier(name: "Стіни", percent: wallBonus)) }
            if world.units.contains(where: { $0.ownerID == defender.ownerID && $0.location == .garrison(city.id) }) {
                modifiers.append(BattleModifier(name: "Гарнізон", percent: 10))
            }
        }
        return BattleContext(attackerRollBonus: attackerRollBonus, defenderRollBonus: defenderRollBonus, defenderModifiers: modifiers)
    }
}
