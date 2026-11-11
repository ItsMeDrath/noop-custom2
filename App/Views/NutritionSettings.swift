import SwiftUI
import Charts
import UniformTypeIdentifiers
import WHOOPCore

struct NutritionSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: NutritionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = NutritionSettings()
    @State private var age = ""
    @State private var height = ""
    @State private var weight = ""
    @State private var maintenance = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var error: String?
    @State private var preview: NutritionCalculation.Goals?
    @State private var busy = false
    @State private var confirmingReset = false
    @State private var exporting = false
    @State private var exportDocument = JSONExportDocument()
    @State private var task: Task<Void, Never>?
    var body: some View {
        NPage(title: "Nutrition settings") {
            NHeading(title: "Build your targets", subtitle: "Mifflin–St Jeor maintenance, with manual overrides")
            NCard {
                VStack(spacing: 9) {
                    Picker("Units", selection: $settings.units) { Text("Metric").tag(NutritionUnits.metric); Text("Imperial").tag(NutritionUnits.imperial) }.pickerStyle(.segmented).frame(minHeight: 44)
                    field("Age (18–100)", text: $age, whole: true)
                    Picker("Sex used by formula", selection: $settings.sex) { Text("Female").tag(NutritionSex.female); Text("Male").tag(NutritionSex.male) }.frame(minHeight: 44)
                    field(settings.units == .metric ? "Height (cm)" : "Height (inches)", text: $height)
                    field(settings.units == .metric ? "Weight (kg)" : "Weight (lb)", text: $weight)
                    Picker("Activity level", selection: $settings.activity) {
                        ForEach(NutritionActivity.allCases, id: \.self) { Text(activityTitle($0)).tag($0) }
                    }.frame(minHeight: 44)
                    Picker("Goal", selection: $settings.goal) { Text("Lose").tag(NutritionGoal.lose); Text("Maintain").tag(NutritionGoal.maintain); Text("Gain").tag(NutritionGoal.gain) }.pickerStyle(.segmented).frame(minHeight: 44)
                }
            }
            Text("Enter profile values in the units selected above. The latest weight log on or before the selected day takes precedence over profile weight. Calculated goals use a 500 kcal loss offset or 300 kcal gain offset, with a default 30% protein / 40% carbs / 30% fat split. These are configurable estimates.").font(NFont.body(11)).foregroundStyle(NColor.muted)
            NCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Manual overrides").font(NFont.number(17))
                    Text("Leave blank to calculate automatically. A manual calorie goal can be used without a complete profile.").font(NFont.body(12)).foregroundStyle(NColor.muted)
                    field("Maintenance (kcal)", text: $maintenance)
                    field("Calorie goal (kcal)", text: $calories)
                    field("Protein target (g)", text: $protein)
                    field("Carb target (g)", text: $carbs)
                    field("Fat target (g)", text: $fat)
                }
            }
            if let preview {
                NCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Calculated targets").font(NFont.number(18))
                        Text("Maintenance \(nText(preview.maintenance)) kcal · Goal \(nText(preview.calories)) kcal").font(NFont.body(13))
                        Text("Protein \(nText(preview.protein)) g · Carbs \(nText(preview.carbs)) g · Fat \(nText(preview.fat)) g").font(NFont.body(12)).foregroundStyle(NColor.muted)
                    }
                }
            }
            if busy { NLoadingCard(); ProgressView("Calculating…").tint(NColor.cyan).frame(maxWidth: .infinity, minHeight: 44) }
            if let error { NError(message: error) }
            Button("CALCULATE TARGETS") { calculate(save: false) }.buttonStyle(NButton(secondary: true)).disabled(busy)
            Button("SAVE SETTINGS") { calculate(save: true) }.buttonStyle(NButton()).disabled(busy || model.isSaving)
            NCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI connection").font(NFont.number(17))
                    Text("AI uses your existing secure account connection. Configure AI_API_KEY and AI_API_URL only in the server environment, then restart that service. No key is entered or stored on this iPhone.").font(NFont.body(12)).foregroundStyle(NColor.muted)
                }
            }
            Button("EXPORT NUTRITION JSON") { export() }.buttonStyle(NButton(secondary: true))
            Button("RESET NUTRITION DATA", role: .destructive) { confirmingReset = true }.font(NFont.label(12)).frame(maxWidth: .infinity, minHeight: 44)
        }.onAppear(perform: load)
            .onDisappear { task?.cancel() }
            .confirmationDialog("Delete all nutrition entries, weights, favorites and settings?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset nutrition only", role: .destructive) {
                    task = Task { do { try await model.commit(store) { $0 = NutritionData() }; load() } catch { self.error = error.localizedDescription } }
                }
            } message: { Text("Your other app records stay unchanged. Export your nutrition JSON first if you want a copy.") }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "nutrition-export") { result in if case .failure(let error) = result { self.error = error.localizedDescription } }
    }
    private func field(_ title: String, text: Binding<String>, whole: Bool = false) -> some View {
        HStack {
            Text(title).font(NFont.body(13))
            Spacer()
            TextField(title, text: text).keyboardType(whole ? .numberPad : .decimalPad).multilineTextAlignment(.trailing)
                .frame(maxWidth: 125, minHeight: 44).font(NFont.body(15)).accessibilityLabel(title)
        }
    }
    private func activityTitle(_ activity: NutritionActivity) -> String {
        switch activity { case .sedentary: return "Sedentary"; case .light: return "Light"; case .moderate: return "Moderate"; case .active: return "Active"; case .veryActive: return "Very active" }
    }
    private func parse(_ text: String, label: String) throws -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        guard let parsed = Double(value.replacingOccurrences(of: ",", with: ".")), parsed.isFinite else { throw NutritionError.invalid("Enter a valid number for \(label).") }
        return parsed
    }
    private func draft() throws -> NutritionSettings {
        var s = settings
        if age.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { s.age = nil }
        else { guard let value = Int(age), (18...100).contains(value) else { throw NutritionError.invalid("Enter an age from 18 to 100.") }; s.age = value }
        s.height = try parse(height, label: "height"); s.weight = try parse(weight, label: "weight")
        s.maintenanceOverride = try parse(maintenance, label: "maintenance"); s.calorieOverride = try parse(calories, label: "calorie goal")
        s.proteinOverride = try parse(protein, label: "protein"); s.carbsOverride = try parse(carbs, label: "carbs"); s.fatOverride = try parse(fat, label: "fat")
        return s
    }
    private func calculate(save: Bool) {
        error = nil; busy = true
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let value = try draft()
                if save { try await model.commit(store) { $0.settings = value }; dismiss() }
                else {
                    var data = store.nutrition; data.settings = value; let snapshot = data, day = NutritionDay.key(store.selectedDate)
                    let calculated = try await Task.detached { try NutritionEngine.calculate(snapshot, day: day) }.value
                    try Task.checkCancellation(); preview = calculated.goals
                }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func load() {
        settings = store.nutrition.settings
        age = settings.age.map(String.init) ?? ""; height = settings.height.map { String($0) } ?? ""; weight = settings.weight.map { String($0) } ?? ""
        maintenance = settings.maintenanceOverride.map { String($0) } ?? ""; calories = settings.calorieOverride.map { String($0) } ?? ""
        protein = settings.proteinOverride.map { String($0) } ?? ""; carbs = settings.carbsOverride.map { String($0) } ?? ""; fat = settings.fatOverride.map { String($0) } ?? ""
        preview = model.calculation?.goals
    }
    private func export() {
        struct Export: Encodable { let format = "NUTRITION_EXPORT"; let version = 1; let exportedAt = Date(); let nutrition: NutritionData }
        do { exportDocument = JSONExportDocument(data: try ImportReader.jsonEncoder().encode(Export(nutrition: store.nutrition))); exporting = true }
        catch { self.error = error.localizedDescription }
    }
}

struct NutritionWeightView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: NutritionViewModel
    @State private var date = Date()
    @State private var value = ""
    @State private var unit = NutritionWeightUnit.kg
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NPage(title: "Weight") {
            NHeading(title: "Your weight log", subtitle: "Recorded values and a seven-day rolling average")
            if model.isLoading && model.calculation == nil { NSkeleton() }
            else if let c = model.calculation {
                if c.weightSeries.isEmpty { NEmpty(title: "No weight trend yet", detail: "Log a weight to start your chart. Only real entries contribute.", symbol: "scalemass") }
                else {
                    NStat(label: "Latest recorded weight", value: c.latestWeight, unit: c.weightUnit.rawValue, digits: 1)
                    NCard {
                        Chart {
                            ForEach(c.weightSeries) { point in
                                if let date = NutritionDay.date(point.day) {
                                    LineMark(x: .value("Day", date), y: .value("Weight", point.value)).foregroundStyle(by: .value("Series", "Recorded"))
                                    PointMark(x: .value("Day", date), y: .value("Weight", point.value)).foregroundStyle(by: .value("Series", "Recorded"))
                                    LineMark(x: .value("Day", date), y: .value("Weight", point.trend)).foregroundStyle(by: .value("Series", "7-day average"))
                                }
                            }
                        }.chartForegroundStyleScale(["Recorded": NColor.cyan, "7-day average": NColor.yellow]).frame(height: 200)
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: utcDateFormat(.dateTime.month(.abbreviated).day())).foregroundStyle(NColor.muted) } }
                            .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine().foregroundStyle(Color.white.opacity(0.06)); AxisValueLabel().foregroundStyle(NColor.muted) } }
                            .accessibilityElement(children: .ignore).accessibilityLabel("Recorded weight and seven-day rolling average, in \(c.weightUnit.rawValue). Last 30 calendar days.")
                    }
                }
            }
            NCard {
                VStack(spacing: 9) {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date).font(NFont.body(13)).frame(minHeight: 44).environment(\.calendar, DayCalendar.utc).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    Picker("Weight unit", selection: $unit) { Text("kg").tag(NutritionWeightUnit.kg); Text("lb").tag(NutritionWeightUnit.lb) }.pickerStyle(.segmented).frame(minHeight: 44)
                    TextField("Weight", text: $value).keyboardType(.decimalPad).font(NFont.body(18)).frame(minHeight: 44).accessibilityLabel("Weight value")
                    Button("SAVE WEIGHT") { save() }.buttonStyle(NButton()).disabled(model.isSaving || value.isEmpty)
                }
            }
            Text("Saving again on the same UTC date replaces that day's weight. Unit conversions and the rolling average are calculated by the shared nutrition engine.").font(NFont.body(11)).foregroundStyle(NColor.muted)
            if let error { NError(message: error) }
            if store.nutrition.weights.isEmpty { NEmpty(title: "Your entries will appear here", detail: "Add your first weight above.", symbol: "calendar") }
            ForEach(store.nutrition.weights.sorted { $0.day > $1.day }) { entry in
                NCard {
                    HStack {
                        Text(entry.day).font(NFont.body(13)); Spacer()
                        Text("\(nText(entry.value, digits: 1)) \(entry.unit.rawValue)").font(NFont.label(14))
                        Button(role: .destructive) {
                            task = Task { do { try await model.commit(store) { $0.weights.removeAll { $0.id == entry.id } } } catch { self.error = error.localizedDescription } }
                        } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.disabled(model.isSaving).accessibilityLabel("Delete weight for \(entry.day)")
                    }
                }
            }
        }.onAppear { date = store.selectedDate; unit = store.nutrition.settings.units == .metric ? .kg : .lb }.onDisappear { task?.cancel() }
    }
    private func save() {
        guard let number = Double(value.replacingOccurrences(of: ",", with: ".")), number.isFinite else { error = "Enter a valid weight."; return }
        let entry = NutritionWeight(day: NutritionDay.key(date), value: number, unit: unit)
        task = Task { @MainActor in
            do { try await model.commit(store) { data in data.weights.removeAll { $0.day == entry.day }; data.weights.append(entry) }; value = ""; error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
}
