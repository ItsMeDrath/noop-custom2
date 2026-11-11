import SwiftUI
import UniformTypeIdentifiers
import WHOOPCore

@main
@MainActor
struct WHOOPApp: App {
    @StateObject private var tracker = DeviceModel()
    @StateObject private var store = AppStore()
    @StateObject private var account = AccountModel()
    @StateObject private var recorder = WorkoutRecorder()
    @StateObject private var liveActivity = LiveActivityDriver()
    @StateObject private var health = HealthDataModel()
    @StateObject private var nutrition = NutritionViewModel()
    var body: some Scene {
        WindowGroup {
            AppLaunchView().environmentObject(tracker).environmentObject(store).environmentObject(account)
                .environmentObject(recorder).environmentObject(liveActivity)
                .environmentObject(health).environmentObject(nutrition)
                .task { recorder.bind(tracker); liveActivity.bind(recorder) }
                .preferredColorScheme(.dark)
        }
    }
}

/// Setup is remembered on this iPhone; reference screenshots are never the launch route.
struct AppLaunchView: View {
    @AppStorage("whoop.setup.completed.v1") private var completed = false
    var body: some View {
        if completed { RootView() }
        else { FirstRunView { completed = true } }
    }
}

private enum SetupStep: Int, CaseIterable {
    case welcome, profile, tracker, data
    var title: String {
        switch self {
        case .welcome: return "Your day.\nYour potential."
        case .profile: return "Make it yours."
        case .tracker: return "Meet your tracker."
        case .data: return "Bring your day to life."
        }
    }
}

private enum SetupSheet: String, Identifiable {
    case health, account
    var id: String { rawValue }
}

private struct FirstRunView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var tracker: DeviceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = SetupStep.welcome
    @State private var draft = ProfilePersonalization()
    @State private var initialized = false
    @State private var sheet: SetupSheet?
    @State private var importing = false
    @State private var error: String?
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(step.title).font(PulseFont.number(42)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    stepContent.id(step).transition(.opacity)
                    if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(PulseFont.body(14)).accessibilityIdentifier("setupError") }
                }.padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
            bottomBar
        }.foregroundStyle(PulseColor.text).font(PulseFont.body(16))
            .background(LinearGradient(colors: [PulseColor.top, PulseColor.background], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .preferredColorScheme(.dark)
            .onAppear { if !initialized { draft = store.profile; initialized = true } }
            .sheet(item: $sheet) { route in
                switch route { case .health: HealthImportView(); case .account: AccountView() }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .commaSeparatedText]) { result in
                Task { @MainActor in
                    do { try await store.importFile(result.get()); draft = store.profile; error = nil }
                    catch { self.error = error.localizedDescription }
                }
            }
            .onChange(of: tracker.connectedName) { _, name in if name != nil { tracker.stop() } }
            .onDisappear { tracker.stop() }
    }

    private var topBar: some View {
        HStack {
            if step != .welcome {
                Button { changeStep(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous setup step")
            }
            Spacer()
            WhoopWordmark().frame(width: 94, height: 19).accessibilityLabel("WHOOP")
            Spacer()
            if step != .welcome { Color.clear.frame(width: 44, height: 44) }
        }.padding(.horizontal, 16).frame(height: 70)
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome:
            ZStack {
                Circle().stroke(PulseColor.sleep.opacity(0.25), lineWidth: 12).frame(width: 218, height: 218)
                Circle().trim(from: 0, to: 0.74).stroke(PulseColor.load, style: StrokeStyle(lineWidth: 12, lineCap: .round)).frame(width: 218, height: 218).rotationEffect(.degrees(-90))
                Circle().trim(from: 0, to: 0.61).stroke(PulseColor.mint, style: StrokeStyle(lineWidth: 10, lineCap: .round)).frame(width: 170, height: 170).rotationEffect(.degrees(-90))
                Circle().trim(from: 0, to: 0.83).stroke(PulseColor.sleep, style: StrokeStyle(lineWidth: 8, lineCap: .round)).frame(width: 127, height: 127).rotationEffect(.degrees(-90))
                Image(systemName: "waveform.path.ecg").font(.system(size: 38, weight: .light))
            }.frame(maxWidth: .infinity).padding(.vertical, 24).accessibilityHidden(true)
            Text("Understand your sleep, recovery and daily effort. Connect a tracker, bring in your measurements, and build your routine.").foregroundStyle(PulseColor.muted)
            feature("Connect your wearable", symbol: "sensor.tag.radiowaves.forward", detail: "Find nearby heart-rate sensors over Bluetooth.")
            feature("Build your personal record", symbol: "chart.xyaxis.line", detail: "Your dashboard grows with the data you save.")
        case .profile:
            Text("Choose how you appear in the app. You can change this later in Profile.").foregroundStyle(PulseColor.muted)
            PulseCard {
                Text("YOUR NAME").font(PulseFont.label(11)).foregroundStyle(PulseColor.muted)
                TextField("What should we call you?", text: $draft.displayName).textContentType(.givenName).textInputAutocapitalization(.words).frame(minHeight: 48).accessibilityLabel("Your name")
                Divider()
                Text("AGE · OPTIONAL").font(PulseFont.label(11)).foregroundStyle(PulseColor.muted)
                TextField("Your age", text: $draft.age).keyboardType(.decimalPad).frame(minHeight: 48).accessibilityLabel("Your age, optional")
            }
            Text("Your name and age are stored on this iPhone. Recovery and sleep scores come from measurements you import; setup does not create scores.").font(PulseFont.body(14)).foregroundStyle(PulseColor.muted)
        case .tracker:
            Text("Wear your sensor and keep it close to your iPhone. If it has a heart-rate broadcast setting, turn that on.").foregroundStyle(PulseColor.muted)
            PulseCard {
                Label(tracker.connectedName ?? "Ready to connect", systemImage: tracker.connectedName == nil ? "sensor.tag.radiowaves.forward" : "checkmark.circle.fill")
                    .font(PulseFont.body(21).weight(.semibold)).foregroundStyle(tracker.connectedName == nil ? PulseColor.text : PulseColor.mint)
                Text(tracker.status).font(PulseFont.body(14)).foregroundStyle(PulseColor.muted).accessibilityIdentifier("setupTrackerStatus")
                if tracker.isScanning || tracker.isConnecting { ProgressView().tint(PulseColor.load).frame(minHeight: 44).accessibilityLabel(tracker.isScanning ? "Searching for trackers" : "Connecting to tracker") }
                if tracker.connectedName == nil {
                    Button(tracker.isScanning ? "STOP SEARCHING" : "SEARCH FOR MY TRACKER") {
                        if tracker.isScanning { tracker.stop() } else { tracker.scan() }
                    }.buttonStyle(WButton(filled: false)).disabled(tracker.isConnecting).accessibilityIdentifier("setupSearchTracker")
                }
                if tracker.canStartCustomStream || tracker.startingCustomStream {
                    Button(tracker.startingCustomStream ? "STARTING HEART RATE…" : "ENABLE LIVE HEART RATE") { tracker.startCustomStream() }
                        .buttonStyle(WButton(filled: false)).disabled(tracker.startingCustomStream)
                }
            }
            if tracker.connectedName == nil {
                ForEach(tracker.devices) { device in
                    Button { tracker.connect(device) } label: {
                        PulseCard {
                            HStack(spacing: 12) {
                                Image(systemName: "sensor.tag.radiowaves.forward").foregroundStyle(PulseColor.load)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name).font(PulseFont.body(17).weight(.semibold))
                                    Text("Signal \(device.rssi) dBm").font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.frame(minHeight: 44)
                        }
                    }.buttonStyle(.plain).disabled(tracker.isConnecting).accessibilityLabel("Connect to \(device.name)")
                }
            }
            Text("You can connect later from Home. Bluetooth heart rate does not provide a full sleep or Recovery history; those can be imported in the next step.").font(PulseFont.body(14)).foregroundStyle(PulseColor.muted)
        case .data:
            Text("Choose where your measurements come from, or start fresh and add them later.").foregroundStyle(PulseColor.muted)
            dataSource("Apple Health", symbol: "heart.fill", detail: "Choose which measurements to import.") { sheet = .health }
            dataSource("WHOOP account", symbol: "person.crop.circle", detail: "Connect through your configured secure bridge.") { sheet = .account }
            dataSource("Import a data file", symbol: "square.and.arrow.down", detail: "Bring in an app JSON export or heart-rate CSV.") { importing = true }
            let count = store.days.filter { $0.source != .example }.count
            if count > 0 {
                Label("\(count) saved days ready for your dashboard", systemImage: "checkmark.circle.fill").foregroundStyle(PulseColor.mint)
            } else {
                Text("No measurements yet. Home will help you connect and start recording; no sample scores will be shown as yours.").font(PulseFont.body(14)).foregroundStyle(PulseColor.muted)
            }
            if store.isImporting { ProgressView("Saving your measurements…").tint(PulseColor.load).frame(minHeight: 44) }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 7) {
                ForEach(SetupStep.allCases, id: \.rawValue) { item in
                    Capsule().fill(item == step ? PulseColor.text : PulseColor.muted.opacity(0.25)).frame(width: item == step ? 24 : 7, height: 6)
                }
            }.accessibilityElement(children: .ignore).accessibilityLabel("Setup step \(step.rawValue + 1) of 4")
            Button(buttonTitle, action: advance).buttonStyle(WButton()).disabled(store.isImporting || tracker.isConnecting)
                .accessibilityIdentifier("setupContinue")
        }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity).background(PulseColor.background.opacity(0.9))
    }

    private var buttonTitle: String {
        switch step {
        case .welcome: return "GET STARTED"
        case .profile: return "CONTINUE"
        case .tracker: return tracker.connectedName == nil ? "CONNECT LATER" : "CONTINUE"
        case .data: return "OPEN MY HOME"
        }
    }
    private func advance() {
        error = nil
        do {
            if step == .profile { try store.updateProfile(draft) }
            if step == .data {
                try store.completeSetup()
                tracker.stop()
                finish()
            } else { changeStep(1) }
        } catch { self.error = error.localizedDescription }
    }
    private func changeStep(_ offset: Int) {
        guard let next = SetupStep(rawValue: step.rawValue + offset) else { return }
        tracker.stop(); error = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = next }
    }
    private func feature(_ title: String, symbol: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).foregroundStyle(PulseColor.load).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(PulseFont.body(18).weight(.semibold)); Text(detail).font(PulseFont.body(14)).foregroundStyle(PulseColor.muted) }
        }.padding(.vertical, 4)
    }
    private func dataSource(_ title: String, symbol: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PulseCard {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(PulseColor.load).frame(width: 32)
                    VStack(alignment: .leading, spacing: 5) { Text(title).font(PulseFont.body(18).weight(.semibold)); Text(detail).font(PulseFont.body(13)).foregroundStyle(PulseColor.muted) }
                    Spacer(); Image(systemName: "chevron.right")
                }.frame(minHeight: 54)
            }
        }.buttonStyle(.plain).disabled(store.isImporting)
    }
}
