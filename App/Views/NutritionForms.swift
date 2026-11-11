import SwiftUI
import PhotosUI
import WHOOPCore

private struct FoodDraft: Identifiable { let id = UUID(); var food: NutritionFood }
private enum FoodInputMode: String, CaseIterable, Identifiable { case manual = "Manual", text = "AI text", photo = "AI photo"; var id: String { rawValue } }
struct NutritionFoodForm: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: NutritionViewModel
    @EnvironmentObject private var account: AccountModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode = FoodInputMode.manual
    @State private var meal = NutritionMeal.breakfast
    @State private var drafts = [FoodDraft(food: NutritionFood())]
    @State private var description = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageDataURL: String?
    @State private var busy = false
    @State private var error: String?
    @State private var favoritesOnly = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        NPage(title: "Add food") {
            Picker("Meal type", selection: $meal) { ForEach(NutritionMeal.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).frame(minHeight: 44).disabled(busy)
            Picker("Entry method", selection: $mode) { ForEach(FoodInputMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(minHeight: 44).disabled(busy)
            if mode == .text { textEntry }
            if mode == .photo { photoEntry }
            if busy { NLoadingCard(); ProgressView("Preparing editable estimates…").tint(NColor.cyan).frame(maxWidth: .infinity, minHeight: 44); Button("CANCEL") { task?.cancel() }.buttonStyle(NButton(secondary: true)) }
            if let error { NError(message: error) }
            NHeading(title: mode == .manual ? "Your food" : "Review before saving", subtitle: "Check each portion, calorie value and macro. Nothing saves automatically.")
            ForEach($drafts) { $draft in
                NCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Food name", text: $draft.food.name).font(NFont.label(15)).frame(minHeight: 44).accessibilityLabel("Food name")
                            Button(role: .destructive) { drafts.removeAll { $0.id == draft.id } } label: { Image(systemName: "xmark.circle").frame(width: 44, height: 44) }.accessibilityLabel("Remove food draft")
                        }
                        optionalNumber("Portion (grams)", value: $draft.food.grams)
                        NNumberField(title: "Calories (kcal)", value: $draft.food.kcal)
                        NNumberField(title: "Protein (g)", value: $draft.food.protein)
                        NNumberField(title: "Carbs (g)", value: $draft.food.carbs)
                        NNumberField(title: "Fat (g)", value: $draft.food.fat)
                        if let confidence = draft.food.confidence { Text("AI confidence: \(confidence.formatted(.percent.precision(.fractionLength(0)))) · editable estimate").font(NFont.body(10)).foregroundStyle(NColor.muted).padding(.top, 7) }
                    }
                }.disabled(busy || model.isSaving)
            }
            Button("+ ANOTHER FOOD") { drafts.append(FoodDraft(food: NutritionFood())) }.buttonStyle(NButton(secondary: true)).disabled(busy || drafts.count >= 30)
            Button(model.isSaving ? "SAVING…" : "SAVE FOOD") { save() }.buttonStyle(NButton()).disabled(busy || model.isSaving || drafts.isEmpty || drafts.contains { $0.food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            library
        }.onDisappear { task?.cancel() }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                busy = true; error = nil
                task = Task { @MainActor in
                    defer { busy = false }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw NutritionError.invalid("The selected photo could not be opened.") }
                        try Task.checkCancellation()
                        imageDataURL = try NutritionPhoto.compress(data)
                    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                }
            }
    }
    private var textEntry: some View {
        NCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Describe what you ate").font(NFont.label(14))
                TextField("2 eggs and a slice of toast", text: $description, axis: .vertical).lineLimit(3...6).font(NFont.body(15)).accessibilityLabel("Meal description")
                    .onChange(of: description) { _, value in if value.count > 2_000 { description = String(value.prefix(2_000)) } }
                Text("Only this description is sent to the AI provider configured on your server.").font(NFont.body(11)).foregroundStyle(NColor.muted)
                Button("ESTIMATE FOODS") { analyze() }.buttonStyle(NButton()).disabled(busy || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    private var photoEntry: some View {
        NCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Scan a meal photo").font(NFont.label(14))
                PhotosPicker(selection: $photoItem, matching: .images) { Label(imageDataURL == nil ? "CHOOSE PHOTO" : "CHANGE PHOTO", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 44) }.disabled(busy)
                if imageDataURL != nil { Label("Photo compressed and ready", systemImage: "checkmark.circle").font(NFont.body(13)).foregroundStyle(NColor.green) }
                Text("Photos are resized and re-encoded on this iPhone before upload. Tap Analyze to send the meal photo to your configured provider. Photos are not saved in your nutrition log.").font(NFont.body(11)).foregroundStyle(NColor.muted)
                Button("ANALYZE PHOTO") { analyze() }.buttonStyle(NButton()).disabled(busy || imageDataURL == nil)
            }
        }
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            NHeading(title: "Your foods")
            Picker("Food library", selection: $favoritesOnly) { Text("Recent").tag(false); Text("Favorites").tag(true) }.pickerStyle(.segmented).frame(minHeight: 44)
            if favoritesOnly {
                if store.nutrition.favorites.isEmpty { NEmpty(title: "No favorites yet", detail: "Tap the star beside a saved meal to keep it here.", symbol: "star") }
                ForEach(store.nutrition.favorites) { favorite in
                    foodLibraryRow(favorite.food) {
                        task = Task { do { try await model.commit(store) { $0.favorites.removeAll { $0.id == favorite.id } } } catch { self.error = error.localizedDescription } }
                    }
                }
            } else {
                if recent.isEmpty { NEmpty(title: "No recent foods", detail: "Saved foods will appear here for quick reuse.", symbol: "clock") }
                ForEach(Array(recent.enumerated()), id: \.offset) { row in foodLibraryRow(row.element, remove: nil) }
            }
        }
    }
    private var recent: [NutritionFood] {
        var seen = Set<String>()
        return store.nutrition.foods.sorted { $0.createdAt > $1.createdAt }.compactMap { entry in
            seen.insert(entry.food.name.lowercased()).inserted ? entry.food : nil
        }.prefix(12).map { $0 }
    }
    private func foodLibraryRow(_ food: NutritionFood, remove: (() -> Void)?) -> some View {
        NCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text(food.name).font(NFont.label(13)); Text("\(nText(food.kcal)) kcal").font(NFont.body(11)).foregroundStyle(NColor.muted) }
                Spacer()
                Button {
                    if drafts.count == 1 && drafts[0].food.name.isEmpty { drafts = [FoodDraft(food: food)] }
                    else if drafts.count < 30 { drafts.append(FoodDraft(food: food)) }
                } label: { Image(systemName: "plus.circle").frame(width: 44, height: 44) }.disabled(busy || drafts.count >= 30).accessibilityLabel("Add \(food.name) to review")
                if let remove { Button(role: .destructive, action: remove) { Image(systemName: "trash").frame(width: 44, height: 44) }.disabled(model.isSaving).accessibilityLabel("Remove favorite \(food.name)") }
            }
        }
    }
    private func optionalNumber(_ title: String, value: Binding<Double?>) -> some View {
        HStack { Text(title).font(NFont.body(13)); Spacer(); TextField(title, value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 110, minHeight: 44).font(NFont.body(15)).accessibilityLabel(title) }
    }
    private func analyze() {
        busy = true; error = nil
        task = Task { @MainActor in
            defer { busy = false }
            struct TextRequest: Encodable { let text: String }
            struct ImageRequest: Encodable { let image: String }
            struct Response: Decodable { let items: [NutritionFood] }
            do {
                let result: Response
                if mode == .photo {
                    guard let imageDataURL else { throw NutritionError.invalid("Choose a meal photo first.") }
                    result = try await account.nutritionPost(path: "analyze-meal", input: ImageRequest(image: imageDataURL))
                } else { result = try await account.nutritionPost(path: "parse-food", input: TextRequest(text: description)) }
                try Task.checkCancellation()
                guard !result.items.isEmpty, result.items.count <= 30 else { throw NutritionError.invalid("No usable food estimates were returned.") }
                drafts = result.items.map { FoodDraft(food: $0) }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func save() {
        error = nil
        let foods = drafts.map(\.food), selectedMeal = meal, day = NutritionDay.key(store.selectedDate)
        task = Task { @MainActor in
            do { try await model.commit(store) { data in data.foods.append(contentsOf: foods.map { NutritionFoodEntry(day: day, meal: selectedMeal, food: $0) }) }; dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct NutritionExerciseForm: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: NutritionViewModel
    @EnvironmentObject private var account: AccountModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var minutes = 30.0
    @State private var kcal = 0.0
    @State private var description = ""
    @State private var estimated = false
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NPage(title: "Activity") {
            NHeading(title: "Log exercise", subtitle: "Manual values or an editable AI estimate")
            NCard {
                VStack(spacing: 5) {
                    TextField("Activity name", text: $name).frame(minHeight: 44).accessibilityLabel("Activity name")
                    NNumberField(title: "Duration (minutes)", value: $minutes)
                    NNumberField(title: "Calories burned (kcal)", value: $kcal)
                }
            }
            NCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Estimate from a description").font(NFont.label(14))
                    TextField("30 min jogging", text: $description, axis: .vertical).lineLimit(2...4).frame(minHeight: 44).accessibilityLabel("Exercise description")
                    Text("Uses your latest recorded/profile weight: \(nText(model.calculation?.goals.weightKg, digits: 1)) kg. Set weight in Nutrition Settings first. The description and weight are sent only when you tap Estimate.").font(NFont.body(11)).foregroundStyle(NColor.muted)
                    if busy { NLoadingCard(); ProgressView("Estimating…").tint(NColor.cyan) }
                    Button("ESTIMATE CALORIES") { estimate() }.buttonStyle(NButton(secondary: true)).disabled(busy || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if estimated { Text("AI estimate. Review and edit the calorie value before saving.").font(NFont.body(12)).foregroundStyle(NColor.yellow) }
            if let error { NError(message: error) }
            Button("SAVE EXERCISE") { save() }.buttonStyle(NButton()).disabled(busy || model.isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.onDisappear { task?.cancel() }
    }
    private func estimate() {
        guard let weightKg = model.calculation?.goals.weightKg else { error = "Add your weight in Nutrition Settings before estimating exercise."; return }
        error = nil; busy = true
        task = Task { @MainActor in
            defer { busy = false }
            struct Request: Encodable { let text: String; let weightKg: Double }
            struct Response: Decodable { let kcal: Double }
            do {
                let response: Response = try await account.nutritionPost(path: "estimate-exercise", input: Request(text: description, weightKg: weightKg))
                try Task.checkCancellation(); kcal = response.kcal; estimated = true
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = String(description.prefix(120)) }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func save() {
        let entry = NutritionExercise(day: NutritionDay.key(store.selectedDate), name: name, kcal: kcal, minutes: minutes, estimated: estimated)
        task = Task { @MainActor in
            do { try await model.commit(store) { $0.exercises.append(entry) }; dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}
