import Foundation
@testable import Medieval
import Testing

/// Guard rails for the shipped balance.
///
/// These pin the pacing the numbers are meant to produce, not the numbers
/// themselves: any table that keeps a match moving passes. They exist because
/// the previous table did not — a single capital earned about six coins a turn
/// against six hundred coins of development, so the first soldier arrived on
/// turn 19 and the economy never recovered from him.
struct EconomyBalanceTests {
    private let content = try! GameContentLoader.loadMVP()

    private func level(_ id: CityLevelID) throws -> CityLevelDefinition {
        try #require(content.cityLevels.first { $0.id == id })
    }

    private func building(_ id: BuildingTypeID) throws -> BuildingDefinition {
        try #require(content.buildings.first { $0.id == id })
    }

    private func unit(_ id: UnitTypeID) throws -> UnitDefinition {
        try #require(content.units.first { $0.id == id })
    }

    private func plainsIncome() throws -> Int {
        try #require(content.terrain.first { $0.id == "plains" }).incomeModifier
    }

    /// The opening turn should buy the barracks, the town hall and a first
    /// soldier. A game whose first turn can only save is a game with no turn.
    @Test func theOpeningTurnAffordsBarracksATownHallAndASoldier() throws {
        let opening = try building("barracks").constructionCost
            + building("town-hall").constructionCost
            + unit("infantry").recruitmentCost

        #expect(opening <= content.scenario.startingGold)
    }

    @Test func aVillageSavesUpItsUpgradeWithinTenTurns() throws {
        let income = try level("village").baseIncome + plainsIncome()

        #expect(try level("town").upgradeCost <= income * 10)
    }

    /// A town that has invested in its economy carries a full army with room to
    /// spare. Upkeep that eats the whole income leaves nothing to develop with,
    /// which is exactly how the old table stalled.
    @Test func aDevelopedTownOutEarnsAFullArmyTwiceOver() throws {
        let townHall = try building("town-hall")
        let market = try building("market")
        let barracks = try building("barracks")
        let income = try level("town").baseIncome + plainsIncome()
            + townHall.incomeModifier - townHall.upkeep
            + market.incomeModifier - market.upkeep
            - barracks.upkeep
        let army = try ArmyOperations.maximumLandUnits * unit("infantry").upkeep

        #expect(income >= army * 2)
    }

    /// Every building has to be worth its slot: one that costs upkeep without
    /// paying it back in income has to earn its keep in defence instead.
    @Test func everyBuildingEarnsItsUpkeepInCoinsOrInDefence() throws {
        for definition in content.buildings {
            #expect(definition.incomeModifier - definition.upkeep >= 0 || definition.defenseModifier > 0)
        }
    }

    /// The ladder should be climbable in a campaign, not in a lifetime. It is
    /// measured in two steps, because the income paying for it changes on the
    /// way up: the starting purse buys the first upgrade, and the town it
    /// becomes pays for the rest.
    @Test func theDevelopmentLadderFitsInACampaign() throws {
        let firstStep = try building("town-hall").constructionCost + level("town").upgradeCost
        #expect(firstStep <= content.scenario.startingGold)

        let townHall = try building("town-hall")
        let market = try building("market")
        let townIncome = try level("town").baseIncome + plainsIncome()
            + townHall.incomeModifier - townHall.upkeep
            + market.incomeModifier - market.upkeep
        let rest = try building("market").constructionCost
            + building("barracks").constructionCost
            + building("walls").constructionCost
            + level("city").upgradeCost

        #expect(rest <= townIncome * 20)
    }
}
