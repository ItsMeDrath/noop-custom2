import SwiftUI
import UniformTypeIdentifiers
import WHOOPCore

private enum AppSheet: String, Identifiable {
    case journal, activity, device, data, about, reference, healthImport, workout, activities, account, stress, live, tier, measurementExport
    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var device: DeviceModel
    @EnvironmentObject private var recorder: WorkoutRecorder
    @EnvironmentObject private var liveActivity: LiveActivityDriver
    @State private var sheet: AppSheet?
    @State private var metricRoute: ScoreMetric?
    @State private var showingQuickActions = false
    @State private var showingStartOptions = false
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument = JSONExportDocument()
    @State private var message: String?
    @State private var confirmClear = false
    @State private var restoringBackup = false
    @State private var pendingBackup: LocalBackup?
    @State private var exportName = "WHOOP-day-data"
    @State private var showingLive = false
    @State private var attemptedReconnect = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if store.tab != .nutrition { header }
            ScrollView {
                VStack(spacing: 22) {
                    switch store.tab {
                    case .home:
                        HomeView(openMetric: openMetric, openJournal: { sheet = .journal }, openActivity: { sheet = .activity }, openWorkout: { showingStartOptions = true }, openHealth: { store.tab = .health }, openStress: { sheet = .stress }, openActivities: { sheet = .activities }, openDevice: { sheet = .device }, openHealthImport: { sheet = .healthImport }, openAccount: { sheet = .account })
                    case .sleep: MetricDetailView(metric: .sleep, embedded: true)
                    case .recovery: MetricDetailView(metric: .recovery, embedded: true)
                    case .strain: MetricDetailView(metric: .strain, embedded: true)
                    case .nutrition: NutritionRootView()
                    case .health:
                        HealthView(openMetric: openMetric, importData: { restoringBackup = false; importing = true }, openHealthImport: { sheet = .healthImport })
                    case .community:
                        CommunityView(openActivity: { sheet = .activity }, importData: { restoringBackup = false; importing = true })
                    case .profile:
                        ProfileView(openJournal: { sheet = .journal }, openDevice: { sheet = .device }, exportData: exportData)
                    case .menu:
                        MenuView(openDevice: { sheet = .device }, importData: { restoringBackup = false; importing = true }, exportData: exportData,
                                 openDataHelp: { sheet = .data }, openAbout: { sheet = .about }, openReference: { sheet = .reference },
                                 showExamples: {
                                     if recorder.isRecording { message = "Finish or discard your recording before replacing local data." }
                                     else { store.restoreExamples() }
                                 }, clearData: { confirmClear = true },
                                 openHealthImport: { sheet = .healthImport }, openWorkout: { sheet = .workout },
                                 openActivities: { sheet = .activities }, exportBackup: exportBackup,
                                 restoreBackup: { restoringBackup = true; importing = true }, openLive: { showingLive = true }, openTier: { sheet = .tier }, openAccount: { sheet = .account }, openHealth: { store.tab = .health }, openCommunity: { store.tab = .community }, openProfile: { store.tab = .profile }, openJournal: { sheet = .journal })
                    }
                }.padding(.horizontal, 15).padding(.top, 8).padding(.bottom, 70)
                    .frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
                .id(store.tab)
                .overlay(alignment: .bottomTrailing) {
                    if store.tab != .nutrition {
                    Button { showingQuickActions = true } label: {
                        Image(systemName: "plus").font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.black).frame(width: 48, height: 48)
                            .background(Color.white, in: Circle()).shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                    }.padding(.trailing, 17).padding(.bottom, 15).accessibilityLabel("Add activity or journal")
                    }
                }
        }
        .background { if store.tab == .nutrition { NColor.background.ignoresSafeArea() } else { WhoopBackground() } }
        .safeAreaInset(edge: .bottom, spacing: 0) { floatingNavigation }
        .preferredColorScheme(.dark)
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .environment(\.calendar, DayCalendar.utc)
        .font(WFont.body())
        .tint(.white)
        .sheet(item: $sheet) { route in
            Group {
                switch route {
                case .journal: JournalEditorView()
                case .activity: ActivityEditorView()
                case .device: PulseTrackerView()
                case .data: DataHelpView()
                case .about: AboutView()
                case .reference: ReferenceStrainView()
                case .healthImport: HealthImportView()
                case .workout: WorkoutView()
                case .activities: ActivityLibraryView()
                case .account: AccountView()
                case .stress: StressMonitorView()
                case .live: LiveView()
                case .tier: ExperienceTierView()
                case .measurementExport: MeasurementExportView()
                }
            }.preferredColorScheme(.dark).presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $metricRoute) { metric in
            MetricDetailView(metric: metric).preferredColorScheme(.dark)
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                .environment(\.calendar, DayCalendar.utc)
        }
        .fullScreenCover(isPresented: $showingLive) { ReferenceLiveView(reference: nil) }
        .confirmationDialog("Start activity", isPresented: $showingStartOptions, titleVisibility: .visible) {
            Button("Record workout without camera") { sheet = .workout }
            Button("Record with Live camera") { showingLive = true }
        }
        .confirmationDialog("Add to your day", isPresented: $showingQuickActions, titleVisibility: .visible) {
            Button("Add activity") { sheet = .activity }
            Button("Start activity") { sheet = .workout }
            Button("Record with Live camera") { showingLive = true }
            Button("Fill out journal") { sheet = .journal }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .commaSeparatedText], allowsMultipleSelection: false) { result in
            Task { @MainActor in
                do {
                    guard let url = try result.get().first else { return }
                    if restoringBackup { pendingBackup = try await store.readBackupFile(url) }
                    else { try await store.importFile(url) }
                } catch { message = error.localizedDescription }
            }
        }
        .disabled(store.isImporting)
        .overlay {
            if store.isImporting {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    ProgressView("Importing your data…").tint(.white)
                        .padding(28).background(WColor.elevated, in: RoundedRectangle(cornerRadius: 18))
                }.accessibilityLabel("Importing data. Please wait.")
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: exportName) { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .alert("Something needs attention", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
        .confirmationDialog("Delete all day data, profile preferences, journal entries, activities and nutrition records from this iPhone?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete local data", role: .destructive) {
                if recorder.isRecording { message = "Finish or discard your recording before deleting local data." }
                else { do { try store.clearData() } catch { message = error.localizedDescription } }
            }
        }
        .confirmationDialog("Replace local data with this complete backup?", isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }), titleVisibility: .visible) {
            Button("Restore backup", role: .destructive) {
                if recorder.isRecording { message = "Finish or discard your recording before restoring a backup." }
                else if let pendingBackup {
                    do { try store.restoreBackup(pendingBackup) } catch { message = error.localizedDescription }
                }
                pendingBackup = nil
            }
        } message: { Text("This replaces saved day data, journal entries, activities and nutrition records. Save a full backup first if you want to keep the current data.") }
        .task { recorder.bind(device); liveActivity.bind(recorder) }
        .onAppear {
            if !attemptedReconnect { attemptedReconnect = true; device.reconnectSavedDevice() }
        }
        .alert("Your data needs attention", isPresented: Binding(get: { store.persistenceError != nil }, set: { if !$0 { store.persistenceError = nil } })) {
            Button("OK") { store.persistenceError = nil }
        } message: { Text(store.persistenceError ?? "") }
    }

    private var header: some View {
        HStack {
            Button { store.tab = .profile } label: {
                Image(systemName: "person.crop.circle").font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white).frame(width: 44, height: 44)
            }.accessibilityLabel("Your profile").frame(width: 54, alignment: .leading)
            Spacer()
            DaySelector(compact: true).frame(maxWidth: 174)
            Spacer()
            if recorder.isRecording {
                Button { sheet = .workout } label: { Image(systemName: "record.circle").foregroundStyle(.red).font(.system(size: 23)) }
                    .accessibilityLabel("Return to recording")
            }
            Button { sheet = .device } label: {
                HStack(spacing: 6) {
                    Image(systemName: device.connectedName == nil ? "sensor.tag.radiowaves.forward" : "sensor.tag.radiowaves.forward.fill")
                        .font(.system(size: 20, weight: .light))
                }.foregroundStyle(device.connectedName == nil ? WColor.muted : WColor.green)
                    .frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel(device.connectedName == nil ? "Connect a device" : "View connected device")
                .frame(width: 54, alignment: .trailing)
        }.padding(.horizontal, 15).padding(.top, 5).padding(.bottom, 6)
    }

    private var floatingNavigation: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.navigationTabs) { tab in
                let selected = store.tab == tab || ([AppTab.health, .community, .profile].contains(store.tab) && tab == .menu)
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { store.tab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab == .home ? "house" : tab == .health ? "heart" : tab.symbol)
                            .font(.system(size: 20, weight: selected ? .medium : .regular))
                        Text(tab.title).font(store.tab == .nutrition ? NFont.body(8) : WFont.body(9)).lineLimit(1)
                    }.foregroundStyle(selected ? Color.white : WColor.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }.accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.background(store.tab == .nutrition ? NColor.background : WColor.background)
            .overlay(alignment: .top) { Rectangle().fill(WColor.line).frame(height: 0.5) }
            .frame(maxWidth: .infinity).background(store.tab == .nutrition ? NColor.background : WColor.background)
    }

    private func openMetric(_ metric: ScoreMetric) {
        metricRoute = metric
    }
    private func exportBackup() {
        do {
            exportDocument = JSONExportDocument(data: try store.makeBackup())
            exportName = "WHOOP-full-backup"; exporting = true
        } catch { message = error.localizedDescription }
    }
    private func exportData() {
        sheet = .measurementExport
    }
}

struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SheetScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    private let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        NavigationStack {
            ScrollView { content.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity) }
                .scrollIndicators(.hidden).background(WColor.background)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.font(WFont.label(13)) } }
                .toolbarBackground(WColor.background, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }.tint(.white)
    }
}

struct DaySelector: View {
    @EnvironmentObject private var store: AppStore
    @State private var pickingDate = false
    var compact = false
    var body: some View {
        HStack {
            Button { store.moveDay(-1) } label: { Image(systemName: "chevron.left").font(.system(size: compact ? 11 : 16)).frame(width: 44, height: 44) }
                .accessibilityLabel("Previous day")
            Spacer()
            Button { pickingDate = true } label: {
                HStack(spacing: 8) {
                    Text(DayCalendar.utc.isDateInToday(store.selectedDate) ? "TODAY" : utcDateText(store.selectedDate, style: compact ? .dateTime.month(.abbreviated).day() : .dateTime.weekday(.wide)).uppercased())
                        .font(WFont.label(compact ? 10 : 12)).tracking(1.2)
                    if !compact {
                        Text(utcDateText(store.selectedDate, style: .dateTime.month(.abbreviated).day())).font(WFont.body(13)).foregroundStyle(WColor.muted)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(WColor.muted)
                    }
                }.frame(minHeight: 44)
            }.accessibilityLabel("Choose date, \(utcDateText(store.selectedDate, style: Date.FormatStyle(date: .complete, time: .omitted)))")
            Spacer()
            Button { store.moveDay(1) } label: { Image(systemName: "chevron.right").font(.system(size: compact ? 11 : 16)).frame(width: 44, height: 44) }
                .disabled(DayCalendar.utc.isDateInToday(store.selectedDate)).accessibilityLabel("Next day")
        }.foregroundStyle(.white)
            .background { if compact { Capsule().fill(WColor.elevated.opacity(0.55)) } }
            .sheet(isPresented: $pickingDate) {
                SheetScaffold(title: "Choose a day") {
                    DatePicker("Day", selection: $store.selectedDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical).tint(WColor.green)
                }.presentationDetents([.medium, .large])
            }
    }
}
