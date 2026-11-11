import Foundation

public enum NutritionMeal: String, CaseIterable, Codable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}
public enum NutritionUnits: String, CaseIterable, Codable, Sendable { case metric, imperial }
public enum NutritionSex: String, CaseIterable, Codable, Sendable { case female, male }
public enum NutritionGoal: String, CaseIterable, Codable, Sendable { case lose, maintain, gain }
public enum NutritionActivity: String, CaseIterable, Codable, Sendable { case sedentary, light, moderate, active, veryActive }
public enum NutritionWeightUnit: String, Codable, Sendable { case kg, lb }
public struct NutritionFood: Codable, Equatable, Sendable {
    public var name: String
    public var grams: Double?
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var confidence: Double?
    public init(name: String = "", grams: Double? = nil, kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0, confidence: Double? = nil) {
        self.name = name; self.grams = grams; self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat; self.confidence = confidence
    }
}
public struct NutritionFoodEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var day: String
    public var meal: NutritionMeal
    public var food: NutritionFood
    public var createdAt: Date
    public init(id: UUID = UUID(), day: String, meal: NutritionMeal, food: NutritionFood, createdAt: Date = Date()) {
        self.id = id; self.day = day; self.meal = meal; self.food = food; self.createdAt = createdAt
    }
}
public struct NutritionExercise: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var day: String
    public var name: String
    public var kcal: Double
    public var minutes: Double?
    public var estimated: Bool
    public init(id: UUID = UUID(), day: String, name: String, kcal: Double, minutes: Double? = nil, estimated: Bool = false) {
        self.id = id; self.day = day; self.name = name; self.kcal = kcal; self.minutes = minutes; self.estimated = estimated
    }
}
public struct NutritionWeight: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var day: String
    public var value: Double
    public var unit: NutritionWeightUnit
    public init(id: UUID = UUID(), day: String, value: Double, unit: NutritionWeightUnit) { self.id = id; self.day = day; self.value = value; self.unit = unit }
}
public struct NutritionFavorite: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var food: NutritionFood
    public init(id: UUID = UUID(), food: NutritionFood) { self.id = id; self.food = food }
}
public struct NutritionSettings: Codable, Equatable, Sendable {
    public var age: Int?
    public var sex: NutritionSex
    public var height: Double?
    public var weight: Double?
    public var units: NutritionUnits
    public var activity: NutritionActivity
    public var goal: NutritionGoal
    public var maintenanceOverride: Double?
    public var calorieOverride: Double?
    public var proteinOverride: Double?
    public var carbsOverride: Double?
    public var fatOverride: Double?
    public init(age: Int? = nil, sex: NutritionSex = .female, height: Double? = nil, weight: Double? = nil, units: NutritionUnits = .metric, activity: NutritionActivity = .sedentary, goal: NutritionGoal = .maintain, maintenanceOverride: Double? = nil, calorieOverride: Double? = nil, proteinOverride: Double? = nil, carbsOverride: Double? = nil, fatOverride: Double? = nil) {
        self.age = age; self.sex = sex; self.height = height; self.weight = weight; self.units = units
        self.activity = activity; self.goal = goal; self.maintenanceOverride = maintenanceOverride; self.calorieOverride = calorieOverride
        self.proteinOverride = proteinOverride; self.carbsOverride = carbsOverride; self.fatOverride = fatOverride
    }
}
public struct NutritionData: Codable, Equatable, Sendable {
    public var foods: [NutritionFoodEntry]
    public var exercises: [NutritionExercise]
    public var weights: [NutritionWeight]
    public var favorites: [NutritionFavorite]
    public var completedDays: [String]
    public var settings: NutritionSettings
    public init(foods: [NutritionFoodEntry] = [], exercises: [NutritionExercise] = [], weights: [NutritionWeight] = [], favorites: [NutritionFavorite] = [], completedDays: [String] = [], settings: NutritionSettings = NutritionSettings()) {
        self.foods = foods; self.exercises = exercises; self.weights = weights; self.favorites = favorites; self.completedDays = completedDays; self.settings = settings
    }
}
public enum NutritionError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): return message } }
}
public enum NutritionDay {
    public static func key(_ date: Date) -> String { formatter().string(from: date) }
    public static func date(_ key: String) -> Date? {
        guard key.count == 10, key >= "1900-01-01", key <= "2100-12-31", let date = formatter().date(from: key), formatter().string(from: date) == key else { return nil }
        return date
    }
    private static func formatter() -> DateFormatter {
        let f = DateFormatter(); f.calendar = DayCalendar.utc; f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false; return f
    }
}
/// Storage integrity checks only. Energy formulas and aggregate arithmetic live in calc.ts.
public enum NutritionValidation {
    public static func validate(_ data: NutritionData) throws {
        let count = data.foods.count + data.exercises.count + data.weights.count + data.favorites.count + data.completedDays.count
        guard count <= 10_000 else { throw NutritionError.invalid("Export and archive older data before adding more than 10,000 nutrition records.") }
        func number(_ value: Double, _ range: ClosedRange<Double>) -> Bool { value.isFinite && range.contains(value) }
        func name(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= 120 && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
        func food(_ item: NutritionFood) -> Bool {
            name(item.name) && number(item.kcal, 0...20_000) && [item.protein, item.carbs, item.fat].allSatisfy { number($0, 0...2_000) } &&
            (item.grams.map { number($0, 0.1...10_000) } ?? true) && (item.confidence.map { number($0, 0...1) } ?? true)
        }
        guard Set(data.foods.map(\.id)).count == data.foods.count,
              Set(data.exercises.map(\.id)).count == data.exercises.count,
              Set(data.weights.map(\.id)).count == data.weights.count,
              Set(data.favorites.map(\.id)).count == data.favorites.count,
              Set(data.weights.map(\.day)).count == data.weights.count,
              Set(data.completedDays).count == data.completedDays.count else { throw NutritionError.invalid("Nutrition records have conflicting identifiers or duplicate weight dates.") }
        for item in data.foods {
            guard NutritionDay.date(item.day) != nil, food(item.food), item.createdAt.timeIntervalSince1970.isFinite, item.createdAt.timeIntervalSince1970 >= -62_135_596_800, item.createdAt.timeIntervalSince1970 < 253_402_300_800 else { throw NutritionError.invalid("A food record has an invalid date or measurement.") }
        }
        for item in data.favorites { guard food(item.food) else { throw NutritionError.invalid("A favorite food is invalid.") } }
        for item in data.exercises {
            guard NutritionDay.date(item.day) != nil, name(item.name), number(item.kcal, 0...20_000), item.minutes.map({ number($0, 1...1_440) }) ?? true else { throw NutritionError.invalid("Check the exercise name, date, duration and calories.") }
        }
        for item in data.weights { guard NutritionDay.date(item.day) != nil, number(item.value, item.unit == .kg ? 20...400 : 44.092452437...881.84904874) else { throw NutritionError.invalid("Check the weight date and value.") } }
        for day in data.completedDays { guard NutritionDay.date(day) != nil else { throw NutritionError.invalid("A completed date is invalid.") } }
        let s = data.settings
        guard s.age.map({ (18...100).contains($0) }) ?? true,
              s.height.map({ number($0, s.units == .metric ? 80...250 : 31.49606299...98.42519686) }) ?? true, s.weight.map({ number($0, s.units == .metric ? 20...400 : 44.092452437...881.84904874) }) ?? true,
              [s.maintenanceOverride, s.calorieOverride].allSatisfy({ $0.map { number($0, 1_000...10_000) } ?? true }),
              [s.proteinOverride, s.carbsOverride, s.fatOverride].allSatisfy({ $0.map { number($0, 0...2_000) } ?? true }) else { throw NutritionError.invalid("Nutrition settings contain an unsupported value.") }
    }
}

public struct NutritionCalculation: Decodable, Sendable {
    public struct Goals: Decodable, Sendable { public let maintenance: Double?; public let calories: Double?; public let protein: Double?; public let carbs: Double?; public let fat: Double?; public let weightKg: Double? }
    public struct Totals: Decodable, Sendable { public let eaten: Double; public let exercise: Double; public let protein: Double; public let carbs: Double; public let fat: Double; public let estimatedBurned: Double?; public let balance: Double?; public let fatChangeKg: Double? }
    public struct Meal: Decodable, Identifiable, Sendable { public let meal: NutritionMeal; public let kcal: Double; public let protein: Double; public let carbs: Double; public let fat: Double; public var id: String { meal.rawValue } }
    public struct DayPoint: Decodable, Identifiable, Sendable { public let day: String; public let eaten: Double?; public let protein: Double?; public let balance: Double?; public let goal: Double?; public let completed: Bool; public var id: String { day } }
    public struct WeightPoint: Decodable, Identifiable, Sendable { public let day: String; public let value: Double; public let trend: Double; public var id: String { day } }
    public struct Dial: Decodable, Sendable { public let value: Double?; public let target: Double?; public let fraction: Double; public let status: String }
    public let day: String
    public let goals: Goals
    public let totals: Totals
    public let meals: [Meal]
    public let series: [DayPoint]
    public struct Average: Decodable, Sendable { public let range: Int; public let eaten: Double?; public let protein: Double? }
    public let averageEaten: Double?
    public let averages: [Average]
    public let loggedDays: Int
    public let completeDays: Int
    public let weeklyBalance: Double?
    public let weeklyFatChangeKg: Double?
    public let loggingStreak: Int
    public let weightSeries: [WeightPoint]
    public let weightUnit: NutritionWeightUnit
    public let latestWeight: Double?
    public let caloriesDial: Dial
    public let proteinDial: Dial
    public let carbsDial: Dial
    public let fatDial: Dial
    public let netDial: Dial
    public let hasLog: Bool
    public let isComplete: Bool
}
