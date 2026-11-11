import SwiftUI
import UniformTypeIdentifiers
import WHOOPCore

/// Reuses the persisted AppStore. Home screenshot fixtures never enter this view.
struct MeasurementExportView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var account: AccountModel
    @Environment(\.dismiss) private var dismiss
    @State private var customRange = false
    @State private var start = DayCalendar.start(of: Date())
    @State private var end = DayCalendar.start(of: Date())
    @State private var showingAccount = false
    @State private var showingProfile = false
    @State private var importing = false
    @State private var exporting = false
    @State private var preparing = false
    @State private var format = MeasurementExportFormat.json
    @State private var document = MeasurementExportDocument(data: Data())
    @State private var filename = "WHOOP-saved-measurements"
    @State private var message: String?
    @State private var savedMessage: String?
    @State private var work: Task<Void, Never>?

    init(initialRange: ClosedRange<Date>? = nil) {
        _customRange = State(initialValue: initialRange != nil)
        _start = State(initialValue: initialRange?.lowerBound ?? DayCalendar.start(of: Date()))
        _end = State(initialValue: initialRange?.upperBound ?? DayCalendar.start(of: Date()))
    }
    private var highlights: ProfileHighlights { ProfileHighlightsCalculator.calculate(days: selected) }
    private var range: ClosedRange<Date>? { customRange ? start...max(start, end) : nil }
    private var selection: Result<[DailySnapshot], Error> { Result { try MeasurementExport.selectedDays(store.days, range: range) } }
    private var selected: [DailySnapshot] { (try? selection.get()) ?? [] }
    private var sampleCount: Int { selected.reduce(0) { $0 + $1.heartRates.count } }
    private var busy: Bool { preparing || store.isImporting }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    overview
                    profileSummary
                    dates
                    highlightsSummary
                    exportOptions
                    importOptions
                    if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill").foregroundStyle(PulseColor.mint)
                            .accessibilityIdentifier("exportSuccess")
                    }
                    Text("JSON contains your personalized profile, calculated highlights, daily measurements and saved heart-rate samples. Profile-only export works after you personalize. Activities, journal entries, nutrition and credentials are excluded; full backup remains separate.")
                        .font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(PulseColor.background).navigationTitle("Export Data").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                }
            }
            .toolbarBackground(PulseColor.background, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }
        .font(PulseFont.body(15)).foregroundStyle(PulseColor.text).tint(PulseColor.sleep).preferredColorScheme(.dark)
        .environment(\.calendar, DayCalendar.utc).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .sheet(isPresented: $showingAccount) { AccountView() }
        .sheet(isPresented: $showingProfile) { WHOOPProfileView() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .commaSeparatedText]) { result in
            switch result {
            case .success(let url):
                work = Task { @MainActor in
                    defer { work = nil }
                    do { try await store.importFile(url); savedMessage = "Import complete. Your available data is ready to export." }
                    catch { report(error) }
                }
            case .failure(let error): report(error)
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: format == .json ? .json : .commaSeparatedText,
                      defaultFilename: filename) { result in
            switch result {
            case .success: savedMessage = "Export saved to your chosen location."
            case .failure(let error): report(error)
            }
        }
        .alert("Export data", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
        .onDisappear { work?.cancel() }
    }

    private var overview: some View {
        PulseCard(padding: 18) {
            Image(systemName: "square.and.arrow.up").font(.system(size: 30, weight: .light)).foregroundStyle(PulseColor.sleep)
            Text("Your saved measurements").font(PulseFont.body(24).weight(.semibold))
            HStack(spacing: 24) {
                count(selected.count, label: "DAYS")
                count(sampleCount, label: "HEART-RATE SAMPLES")
            }
            Text("Home examples are excluded. Saved imports may combine WHOOP account data, Apple Health and tracker measurements; the archive does not identify every provider separately.")
                .font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
            if case .failure(let error) = selection {
                Text(error.localizedDescription).foregroundStyle(PulseColor.yellow)
            } else if selected.isEmpty {
                Label("No saved measurements in this range. Connect and sync your WHOOP account, import a data file, or choose another range.", systemImage: "tray")
                    .font(PulseFont.body(14)).foregroundStyle(PulseColor.muted).accessibilityIdentifier("exportEmptyState")
            }
        }
    }

    private var profileSummary: some View {
        PulseCard(padding: 18) {
            HStack {
                Text("PERSONALIZATION").font(PulseFont.label(11)).tracking(0.8)
                Spacer()
                Button("EDIT PROFILE") { showingProfile = true }.font(PulseFont.label(10)).frame(minWidth: 44, minHeight: 44).disabled(busy)
            }
            Text(store.profile.displayName.isEmpty ? "Choose your name, age and day streak" : store.profile.displayName).font(PulseFont.body(18).weight(.semibold))
            if !store.profile.age.isEmpty { Text("Age: " + store.profile.age).font(PulseFont.body(14)) }
            if !store.profile.whoopAge.isEmpty { Text("WHOOP Age display: " + store.profile.whoopAge).font(PulseFont.body(14)) }
            if let streak = store.profile.dayStreakOverride { Text("Chosen day streak: \(streak)").font(PulseFont.body(14)) }
            Text("Chosen profile values are tagged user-configured. Measured records and calculated streaks remain separate.").font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
        }
    }
    private var highlightsSummary: some View {
        let values = highlights
        return PulseCard(padding: 18) {
            Text("DATA HIGHLIGHTS").font(PulseFont.label(11)).tracking(0.8)
            HStack(alignment: .top) {
                highlight(values.bestSleepPerformance, title: "Best Sleep", suffix: "%")
                highlight(values.peakRecovery, title: "Peak Recovery", suffix: "%")
                highlight(values.peakStrain, title: "Max Strain", suffix: "", digits: 1)
            }
            Text("Includes HRV/RHR records, max heart rate, longest sleep and consecutive-day streaks from the selected saved dates. No example or future records are used for highlights.")
                .font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
        }
    }
    private func highlight(_ value: ProfileRecord?, title: String, suffix: String, digits: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value.map { $0.value.formatted(.number.precision(.fractionLength(digits))) + suffix } ?? "No data").font(PulseFont.number(value == nil ? 14 : 24))
            Text(title).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func canExport(_ format: MeasurementExportFormat) -> Bool {
        let profileOnly = store.profile.isPersonalized && (format == .json || format == .highlightsCSV)
        return !busy && (!selected.isEmpty || profileOnly) && (format != .heartRateCSV || sampleCount > 0)
    }

    private var dates: some View {
        PulseCard(padding: 18) {
            Text("DATE RANGE").font(PulseFont.label(11)).tracking(0.8)
            Toggle("Choose dates", isOn: $customRange).frame(minHeight: 44)
                .onChange(of: customRange) { _, enabled in
                    if enabled, let days = try? MeasurementExport.selectedDays(store.days), let first = days.first, let last = days.last {
                        start = first.date; end = last.date
                    }
                }
            if customRange {
                DatePicker("From", selection: $start, in: ...end, displayedComponents: .date).frame(minHeight: 44)
                DatePicker("Through", selection: $end, in: start..., displayedComponents: .date).frame(minHeight: 44)
            }
            Text(customRange ? "Includes both selected dates, grouped by UTC day." : "All saved dates · UTC")
                .font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
        }.disabled(busy)
    }

    private var exportOptions: some View {
        PulseCard(padding: 18) {
            Text("SAVE TO FILES").font(PulseFont.label(11)).tracking(0.8)
            exportButton("SAVE JSON", detail: "Profile, highlights, day archive and heart-rate samples. Can be imported back into this app.", format: .json)
            exportButton("SAVE PROFILE & HIGHLIGHTS CSV", detail: "Your chosen profile values and all calculated records/streaks, with units and dates.", format: .highlightsCSV)
            exportButton("SAVE DAILY CSV", detail: "One row per day for a spreadsheet. Heart-rate sample counts, not the individual samples.", format: .dailyCSV)
            exportButton("SAVE HEART-RATE CSV", detail: "Timestamp and BPM for each saved sample. No trace is reconstructed from daily averages.", format: .heartRateCSV)
            if preparing {
                HStack(spacing: 12) {
                    ProgressView().tint(PulseColor.sleep)
                    Text("Preparing export…")
                    Spacer()
                    Button("Cancel") { work?.cancel() }.frame(minWidth: 44, minHeight: 44)
                }.accessibilityIdentifier("exportPreparing")
            }
        }
    }

    private var importOptions: some View {
        PulseCard(padding: 18) {
            Text("ADD YOUR DATA").font(PulseFont.label(11)).tracking(0.8)
            Button { savedMessage = nil; showingAccount = true } label: {
                Label(account.isLinked ? "Sync WHOOP account" : "Connect WHOOP account", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }.accessibilityIdentifier("exportConnectAccount")
            Button { savedMessage = nil; importing = true } label: {
                Label("Import profile/day JSON or heart-rate CSV", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }.accessibilityIdentifier("exportImportData")
            if store.isImporting { ProgressView("Importing measurements…").tint(PulseColor.sleep) }
        }.buttonStyle(PulsePressStyle()).disabled(busy)
    }

    private func count(_ value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.formatted()).font(PulseFont.number(30)).accessibilityIdentifier(label == "DAYS" ? "exportDayCount" : "exportSampleCount")
            Text(label).font(PulseFont.label(9)).tracking(0.8).foregroundStyle(PulseColor.muted)
        }
    }

    private func exportButton(_ title: String, detail: String, format: MeasurementExportFormat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { prepare(format) } label: {
                Label(title, systemImage: "square.and.arrow.up").font(PulseFont.label(12)).tracking(0.8)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(PulseColor.elevated, in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(PulsePressStyle()).disabled(!canExport(format))
                .opacity(canExport(format) ? 1 : 0.45)
                .accessibilityIdentifier("export-\(format.rawValue)")
            Text(detail).font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
        }
    }

    private func prepare(_ requestedFormat: MeasurementExportFormat) {
        guard !busy else { return }
        preparing = true; savedMessage = nil
        let snapshot = store.days, selectedRange = range
        let personal = store.profile
        let exportDate = Date()
        work = Task { @MainActor in
            defer { preparing = false; work = nil }
            let worker = Task.detached(priority: .userInitiated) {
                try MeasurementExport.make(days: snapshot, format: requestedFormat, range: selectedRange, profile: personal, asOf: exportDate)
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                document = MeasurementExportDocument(data: result.data)
                filename = URL(fileURLWithPath: result.filename).deletingPathExtension().lastPathComponent
                format = requestedFormat; exporting = true
            } catch { report(error) }
        }
    }

    private func report(_ error: Error) {
        if error is CancellationError || (error as? CocoaError)?.code == .userCancelled { return }
        message = error.localizedDescription
    }
}

private struct MeasurementExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
