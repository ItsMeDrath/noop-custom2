import Foundation
import Combine
import JavaScriptCore
import ImageIO
import UIKit
import WHOOPCore

/// Executes the generated TypeScript calculator locally, without networking or keys.
enum NutritionEngine {
    private struct Input: Encodable { let day: String; let data: NutritionData }
    static func calculate(_ data: NutritionData, day: String) throws -> NutritionCalculation {
        try NutritionValidation.validate(data)
        guard let url = Bundle.main.url(forResource: "nutrition-calc", withExtension: "js"),
              let context = JSContext() else { throw NutritionError.invalid("The nutrition calculator could not be loaded.") }
        let source = try String(contentsOf: url, encoding: .utf8)
        context.evaluateScript(source)
        guard context.exception == nil else { throw NutritionError.invalid("The nutrition calculator could not start.") }
        let input = try ImportReader.jsonEncoder().encode(Input(day: day, data: data))
        guard let text = String(data: input, encoding: .utf8),
              let function = context.objectForKeyedSubscript("NutritionCalc")?.forProperty("calculate"),
              let json = function.call(withArguments: [text])?.toString(), context.exception == nil,
              let output = json.data(using: .utf8) else {
            let message = context.exception?.toString()?.replacingOccurrences(of: "Error: ", with: "") ?? "Check your nutrition settings and entries."
            throw NutritionError.invalid(String(message.prefix(400)))
        }
        return try JSONDecoder().decode(NutritionCalculation.self, from: output)
    }
}

@MainActor
final class NutritionViewModel: ObservableObject {
    @Published private(set) var calculation: NutritionCalculation?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var error: String?
    @Published private(set) var review: String?
    @Published private(set) var reviewing = false
    private var revision = UUID()
    func refresh(_ data: NutritionData, date: Date) async {
        let token = UUID(); revision = token; isLoading = true; error = nil; review = nil
        let day = NutritionDay.key(date)
        if calculation?.day != day { calculation = nil }
        do {
            let result = try await Task.detached(priority: .userInitiated) { try NutritionEngine.calculate(data, day: day) }.value
            guard revision == token, !Task.isCancelled else { return }
            calculation = result; isLoading = false
        } catch {
            guard revision == token else { return }
            calculation = nil; self.error = error.localizedDescription; isLoading = false
        }
    }
    func commit(_ store: AppStore, edit: (inout NutritionData) -> Void) async throws {
        guard !isSaving else { throw NutritionError.invalid("A nutrition save is already in progress.") }
        isSaving = true; defer { isSaving = false }
        let previous = store.nutrition; var next = previous; edit(&next)
        let day = NutritionDay.key(store.selectedDate)
        let snapshot = next
        let result = try await Task.detached(priority: .userInitiated) { try NutritionEngine.calculate(snapshot, day: day) }.value
        try Task.checkCancellation()
        guard store.nutrition == previous else { throw NutritionError.invalid("Your data changed while saving. Review your entry and save again.") }
        try store.updateNutrition(next)
        calculation = result; error = nil; review = nil; revision = UUID()
    }
    func generateReview(account: AccountModel) async {
        guard !reviewing, let current = calculation else { return }
        reviewing = true; error = nil; let token = revision
        defer { reviewing = false }
        struct Request: Encodable {
            let day: String; let eaten: Double; let protein: Double; let carbs: Double; let fat: Double; let exercise: Double
            let goal: Double?; let estimatedBurned: Double?; let balance: Double?; let complete: Bool
            enum CodingKeys: String, CodingKey { case day, eaten, protein, carbs, fat, exercise, goal, estimatedBurned, balance, complete }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(day, forKey: .day); try c.encode(eaten, forKey: .eaten); try c.encode(protein, forKey: .protein)
                try c.encode(carbs, forKey: .carbs); try c.encode(fat, forKey: .fat); try c.encode(exercise, forKey: .exercise)
                try c.encode(goal, forKey: .goal); try c.encode(estimatedBurned, forKey: .estimatedBurned); try c.encode(balance, forKey: .balance); try c.encode(complete, forKey: .complete)
            }
        }
        struct Response: Decodable { let summary: String }
        do {
            let result: Response = try await account.nutritionPost(path: "day-review", input: Request(day: current.day, eaten: current.totals.eaten, protein: current.totals.protein, carbs: current.totals.carbs, fat: current.totals.fat, exercise: current.totals.exercise, goal: current.goals.calories, estimatedBurned: current.totals.estimatedBurned, balance: current.totals.balance, complete: current.isComplete))
            try Task.checkCancellation()
            guard revision == token else { return }
            review = result.summary
        } catch { if revision == token && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

enum NutritionPhoto {
    /// Decode a bounded thumbnail, apply orientation, and strip metadata by JPEG re-encoding.
    static func compress(_ data: Data) throws -> String {
        guard data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1_280] as CFDictionary) else {
            throw NutritionError.invalid("Choose a supported meal photo below 20 MB.")
        }
        let image = UIImage(cgImage: thumb)
        for quality in [0.7, 0.5, 0.3] {
            if let encoded = image.jpegData(compressionQuality: quality), encoded.count <= 1_000_000 {
                return "data:image/jpeg;base64," + encoded.base64EncodedString()
            }
        }
        throw NutritionError.invalid("The photo is still too large. Crop the meal and try again.")
    }
}
