import XCTest
@testable import WHOOPCore

final class NutritionStorageTests: XCTestCase {
    func testCanonicalTypeScriptResultDecodesForNativeUI() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "NutritionCalculation", withExtension: "json", subdirectory: "Fixtures"))
        let result = try JSONDecoder().decode(NutritionCalculation.self, from: Data(contentsOf: url))
        XCTAssertEqual(result.day, "2026-11-09")
        XCTAssertEqual(result.totals.eaten, 500)
        XCTAssertEqual(result.goals.maintenance, 2136)
        XCTAssertEqual(result.averages.first?.protein, 25)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.caloriesDial.status, "progress")
    }
    private let day = "2026-11-09"
    private func data() -> NutritionData {
        let food = NutritionFood(name: "Oats", grams: 80, kcal: 300, protein: 12, carbs: 50, fat: 6, confidence: 0.7)
        return NutritionData(foods: [NutritionFoodEntry(day: day, meal: .breakfast, food: food, createdAt: NutritionDay.date(day)!)],
            exercises: [NutritionExercise(day: day, name: "Walk", kcal: 150, minutes: 30, estimated: true)],
            weights: [NutritionWeight(day: day, value: 80, unit: .kg)], favorites: [NutritionFavorite(food: food)],
            completedDays: [day], settings: NutritionSettings(age: 30, sex: .male, height: 180, weight: 80))
    }
    private func backup(_ nutrition: NutritionData?) -> LocalBackup {
        LocalBackup(exportedAt: NutritionDay.date(day)!, selectedDate: NutritionDay.date(day)!, days: [], journal: [], activities: [], nutrition: nutrition)
    }
    func testNutritionRoundtripsInTheExistingFullBackup() throws {
        let original = backup(data()), encoded = try LocalBackupCodec.encode(original)
        XCTAssertEqual(try LocalBackupCodec.decode(encoded), original)
        XCTAssertTrue(LocalBackupCodec.isBackup(encoded))
    }
    func testLegacyBackupWithoutNutritionStillDecodes() throws {
        let original = backup(nil), encoded = try LocalBackupCodec.encode(original)
        XCTAssertNil(try LocalBackupCodec.decode(encoded).nutrition)
    }
    func testInvalidFoodAndDuplicateWeightDaysAreRejectedAtomically() {
        var nutrition = data(); nutrition.foods[0].food.kcal = -1
        XCTAssertThrowsError(try LocalBackupCodec.encode(backup(nutrition)))
        nutrition = data(); nutrition.weights.append(NutritionWeight(day: day, value: 90, unit: .kg))
        XCTAssertThrowsError(try LocalBackupCodec.encode(backup(nutrition)))
    }
    func testImpossibleNutritionDatesAndNonfiniteNumbersAreRejected() {
        XCTAssertNil(NutritionDay.date("2026-02-30")); XCTAssertNil(NutritionDay.date("2026-1-9"))
        var nutrition = data(); nutrition.foods[0].food.protein = .infinity
        XCTAssertThrowsError(try NutritionValidation.validate(nutrition))
        nutrition = data(); nutrition.foods[0].day = "2026-02-30"
        XCTAssertThrowsError(try NutritionValidation.validate(nutrition))
    }
    func testCompletedDatesAndFavoritesAreValidatedWithoutInventingTargets() throws {
        XCTAssertNoThrow(try NutritionValidation.validate(NutritionData()))
        var nutrition = data(); nutrition.completedDays = [day, day]
        XCTAssertThrowsError(try NutritionValidation.validate(nutrition))
        nutrition = data(); nutrition.favorites[0].food.confidence = 2
        XCTAssertThrowsError(try NutritionValidation.validate(nutrition))
    }
}
