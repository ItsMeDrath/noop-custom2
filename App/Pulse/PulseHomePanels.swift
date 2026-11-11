import SwiftUI

enum PulseHomePanel: String, Identifiable {
    case sleep, recovery, strain, membership, review, health, stress, alarm, journal, plan, weight, labs, shop, referral, profile, live, strength, activity, session
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sleep: return "Sleep"; case .recovery: return "Recovery"; case .strain: return "Strain"
        case .membership: return "Membership"; case .review: return "Day In Review"; case .health: return "Health Monitor"
        case .stress: return "Stress Monitor"; case .alarm: return "Set Alarm"; case .journal: return "My Journal"
        case .plan: return "My Plan"; case .weight: return "Weight"; case .labs: return "Advanced Labs"
        case .shop: return "Shop"; case .referral: return "Invite Friends"; case .profile: return "Profile"
        case .live: return "Create WHOOP Live"; case .strength: return "Strength Trainer"
        case .activity: return "Add Activity"; case .session: return "Start Activity"
        }
    }
}
/// Local Home context sheets, not final versions of the pending secondary-screen rebuilds.
struct PulseHomePanelView: View {
    let panel: PulseHomePanel
    let data: PulseHomeData
    let day: PulseHomeDay
    @EnvironmentObject private var store: AppStore
    private var greeting: String { data.coachGreeting.replacingOccurrences(of: data.firstName, with: store.profile.displayName.isEmpty ? data.firstName : store.profile.displayName) }
    @Environment(\.dismiss) private var dismiss
    @State private var caffeine = false
    @State private var alcohol = false
    @State private var lateMeal = false
    @State private var alarm = false
    @State private var time = Date()
    @State private var activity = "Walking"
    @State private var minutes = 30
    @State private var weight = ""
    @State private var saved = false
    var body: some View {
        if panel == .profile { WHOOPProfileView(fallbackName: data.firstName, fallbackInitials: data.initials) } else {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(panel.title).font(PulseFont.body(27).weight(.semibold))
                    context
                    Text("Illustrative data · local interface preview").font(PulseFont.body(10)).foregroundStyle(PulseColor.muted)
                }.padding(20)
            }.background(PulseColor.background).navigationTitle(panel.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.frame(minWidth: 44, minHeight: 44) } }
                .toolbarBackground(PulseColor.background, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }.font(PulseFont.body()).foregroundStyle(PulseColor.text).tint(PulseColor.sleep).preferredColorScheme(.dark)
        }
    }
    @ViewBuilder private var context: some View {
        switch panel {
        case .sleep, .recovery, .strain:
            PulseCard {
                HStack {
                    Text(panel == .sleep ? "\(day.sleep)%" : panel == .recovery ? "\(day.readiness)%" : day.load.formatted(.number.precision(.fractionLength(1))))
                        .font(PulseFont.number(64))
                    Spacer()
                    Image(systemName: panel == .sleep ? "moon.fill" : panel == .recovery ? "heart" : "waveform.path.ecg").font(.system(size: 34, weight: .light)).foregroundStyle(PulseColor.sleep)
                }
            }
            Text("This score belongs to the sample day shown on Home. It is separate from live Bluetooth measurements.").foregroundStyle(PulseColor.muted)
        case .membership:
            PulseCard { Text("WHOOP Peak · sample membership").font(PulseFont.body(16)) }
            Text("This is a membership layout preview. No subscription purchase or payment is made.").foregroundStyle(PulseColor.muted)
        case .review:
            PulseCard { Text(greeting).font(PulseFont.body(17)).lineSpacing(6) }
        case .health:
            ForEach(day.statistics.filter { ["hrv", "rhr"].contains($0.id) }) { PulseReferenceMetric(metric: $0) }
            PulseCard { Text("Skin temperature: +1.3°C from sample baseline").foregroundStyle(PulseColor.yellow) }
        case .stress:
            PulseCard {
                Text("\(day.stressValue.formatted(.number.precision(.fractionLength(1))))  \(day.tension)").font(PulseFont.number(28)).foregroundStyle(PulseColor.mint)
                PulseStressChart(values: day.stressValues)
            }
        case .alarm:
            PulseCard {
                DatePicker("Wake-up time", selection: $time, displayedComponents: .hourAndMinute).frame(minHeight: 44)
                Toggle("Alarm preview", isOn: $alarm).frame(minHeight: 44)
            }
            Text("This local preview does not set an iPhone or tracker alarm.").foregroundStyle(PulseColor.muted)
        case .journal:
            PulseCard {
                Toggle("Consumed caffeine", isOn: $caffeine).frame(minHeight: 48)
                Toggle("Consumed alcohol", isOn: $alcohol).frame(minHeight: 48)
                Toggle("Ate close to bedtime", isOn: $lateMeal).frame(minHeight: 48)
            }
            saveButton("SAVE JOURNAL")
        case .activity, .strength, .session:
            PulseCard {
                Picker("Activity", selection: $activity) {
                    ForEach(["Walking", "Soccer", "Running", "Cycling", "Strength Training"], id: \.self) { Text($0) }
                }.frame(minHeight: 48)
                Stepper("Duration: \(minutes) minutes", value: $minutes, in: 1...600).frame(minHeight: 48)
            }
            saveButton(panel == .session ? "SAVE SAMPLE SESSION" : "SAVE ACTIVITY")
        case .weight:
            PulseCard { TextField("Weight in kg", text: $weight).keyboardType(.decimalPad).font(PulseFont.number(30)).frame(minHeight: 55).accessibilityLabel("Sample weight in kilograms") }
            saveButton("SAVE WEIGHT")
        case .profile: EmptyView()
        case .plan:
            PulseCard {
                HStack { VStack(alignment: .leading, spacing: 10) { Text("Build Your Best Self").font(PulseFont.body(19).weight(.semibold)); Text("Set goals, track progress, and turn small actions into long-term wins.").foregroundStyle(PulseColor.muted) }; PulsePlanArtwork() }
            }
        case .live:
            PulseCard {
                Text("Live camera").font(PulseFont.body(20).weight(.semibold))
                Text("Camera capture is not opened in this Home-only visual review. Your camera and photo library remain untouched.").foregroundStyle(PulseColor.muted)
            }
        case .labs, .shop, .referral:
            PulseCard {
                Text(panel == .labs ? "Lab-result integration is not connected." : panel == .shop ? "This storefront is a visual sample. No order or payment is placed." : "Referral credits and memberships are not connected to a service.").font(PulseFont.body(16)).foregroundStyle(PulseColor.muted)
            }
        }
        if saved { Label("Saved in this temporary preview", systemImage: "checkmark.circle.fill").foregroundStyle(PulseColor.mint) }
    }
    private func saveButton(_ title: String) -> some View {
        Button { saved = true } label: {
            Text(title).font(PulseFont.label(11)).tracking(0.8).frame(maxWidth: .infinity, minHeight: 46).foregroundStyle(PulseColor.background).background(PulseColor.sleep, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(PulsePressStyle()).disabled(panel == .weight && (Double(weight) == nil || (Double(weight) ?? 0) <= 0))
    }
}
struct PulseCoachPreview: View {
    let data: PulseHomeData
    @EnvironmentObject private var store: AppStore
    private var greeting: String { data.coachGreeting.replacingOccurrences(of: data.firstName, with: store.profile.displayName.isEmpty ? data.firstName : store.profile.displayName) }
    @State private var question = ""
    @State private var answer: String?
    @State private var vote: Bool?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Label("v6.1", systemImage: "sparkles").font(PulseFont.body(12)).padding(8).background(.white.opacity(0.08), in: Capsule())
                Spacer()
                Text("Memory").font(PulseFont.label(12))
                Image(systemName: "lightbulb").font(.system(size: 20, weight: .light))
            }
            Text("Sample conversation").font(PulseFont.body(10)).foregroundStyle(PulseColor.muted)
            Text(greeting).font(PulseFont.body(17)).lineSpacing(10)
            HStack(spacing: 18) {
                ShareLink(item: greeting) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share sample message")
                Button { vote = true } label: { Image(systemName: vote == true ? "hand.thumbsup.fill" : "hand.thumbsup") }.accessibilityLabel("Helpful sample")
                Button { vote = false } label: { Image(systemName: vote == false ? "hand.thumbsdown.fill" : "hand.thumbsdown") }.accessibilityLabel("Not helpful sample")
            }.font(.system(size: 16)).buttonStyle(PulsePressStyle())
            if let answer { Text(answer).font(PulseFont.body(15)).foregroundStyle(PulseColor.muted).lineSpacing(5) }
            Spacer(minLength: 10)
            HStack(spacing: 12) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14)) }.accessibilityLabel("Close sample conversation")
                TextField("Ask WHOOP anything", text: $question).font(PulseFont.body(16)).submitLabel(.send)
                    .onSubmit { if !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { answer = data.coachReply; question = "" } }
                    .frame(minHeight: 44).padding(.horizontal, 14).background(PulseColor.top.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(LinearGradient(colors: [.purple, PulseColor.load], startPoint: .leading, endPoint: .trailing), lineWidth: 0.8))
            }
        }.padding(22).padding(.top, 10).foregroundStyle(PulseColor.text)
            .background(LinearGradient(colors: [Color(red: 0.08, green: 0.13, blue: 0.20), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
            .presentationDetents([.large, .medium]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
    }
}

/// Personalization and saved-data highlights in the supplied Profile layout.
struct WHOOPProfileView: View {
    var fallbackName = "Your Profile"
    var fallbackInitials = "AA"
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var exporting = false
    @State private var period = "ALL TIME"
    @State private var draft = ProfilePersonalization()
    @State private var customStreak = false
    @State private var streakText = ""
    @State private var error: String?
    private var range: ClosedRange<Date>? {
        guard period != "ALL TIME" else { return nil }
        let end = DayCalendar.start(of: Date())
        let start = DayCalendar.utc.date(byAdding: .month, value: period == "1M" ? -1 : -3, to: end) ?? end
        return start...end
    }
    private var name: String { store.profile.displayName.isEmpty ? fallbackName : store.profile.displayName }
    var body: some View {
        NavigationStack {
            ScrollView { content.padding(.horizontal, 15).padding(.top, 22).padding(.bottom, 40) }
                .background(LinearGradient(colors: [Color(red: 0.35, green: 0.27, blue: 0.24), PulseColor.top, PulseColor.background], startPoint: .top, endPoint: .bottom))
                .navigationTitle("PROFILE").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Close profile") }
                    ToolbarItem(placement: .topBarTrailing) { Button(action: edit) { Image(systemName: "gearshape").font(.system(size: 23, weight: .light)).frame(width: 44, height: 44) }.accessibilityLabel("Personalize profile") }
                }
        }.font(PulseFont.body(15)).foregroundStyle(PulseColor.text).tint(.white).preferredColorScheme(.dark)
            .sheet(isPresented: $editing) { editor }
            .sheet(isPresented: $exporting) { MeasurementExportView(initialRange: range) }
    }
    private var content: some View {
        let now = Date()
        let all = ProfileHighlightsCalculator.calculate(days: store.days, asOf: now)
        let selected = (try? MeasurementExport.selectedDays(store.days, range: range)) ?? []
        let highlights = ProfileHighlightsCalculator.calculate(days: selected, asOf: now)
        let streak = store.profile.dayStreakOverride ?? all.currentLoggedDayStreak
        return VStack(alignment: .leading, spacing: 26) {
            Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.7, blue: 0.43), Color(red: 1, green: 0.53, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 92, height: 92).overlay(Text(store.profile.initials(fallback: fallbackInitials)).font(PulseFont.body(36)).foregroundStyle(.black))
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(name).font(PulseFont.body(24).weight(.semibold)).accessibilityIdentifier("profileName")
                    HStack(spacing: 6) {
                        if !store.profile.username.isEmpty { Text("@" + store.profile.username) }
                        if !store.profile.age.isEmpty { Text(store.profile.age + " years").lineLimit(1).minimumScaleFactor(0.5) }
                    }.font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                }
                Spacer(minLength: 4)
                Button(action: edit) { Label("EDIT", systemImage: "pencil").font(PulseFont.label(10)).tracking(1).padding(.horizontal, 14).frame(minHeight: 44).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)) }
                    .accessibilityIdentifier("profileEdit")
            }
            HStack(spacing: 8) {
                WhoopMonogram().frame(width: 15, height: 13)
                Text("PERSONAL PROFILE").font(PulseFont.label(10)).tracking(1)
                Spacer(); Text("ON THIS IPHONE").font(PulseFont.label(8)).foregroundStyle(PulseColor.muted)
            }.padding(12).background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 11) {
                PulseCard {
                    VStack(spacing: 12) {
                        ZStack { Circle().stroke(PulseColor.yellow.opacity(0.5), lineWidth: 1).frame(width: 65, height: 65); Text(all.savedDays.formatted()).font(PulseFont.number(28)) }
                        Text("SAVED DAYS").font(PulseFont.label(11)).tracking(1)
                        Text("From measurements").font(PulseFont.body(11)).foregroundStyle(PulseColor.muted)
                    }.frame(maxWidth: .infinity, minHeight: 112)
                }
                PulseCard {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(RadialGradient(colors: [.black, Color(red: 0.35, green: 0.24, blue: 0.04), PulseColor.yellow.opacity(0.65)], center: .center, startRadius: 16, endRadius: 35))
                            Canvas { context, size in
                                for index in 0..<45 {
                                    let angle = Double(index) * 2.39996, radius = CGFloat(13 + (index * 17) % 21)
                                    let x = size.width / 2 + CGFloat(cos(angle)) * radius, y = size.height / 2 + CGFloat(sin(angle)) * radius
                                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: index % 4 == 0 ? 1.4 : 0.7, height: index % 4 == 0 ? 1.4 : 0.7)), with: .color(.yellow.opacity(0.75)))
                                }
                            }
                            Text(store.profile.whoopAge.isEmpty ? "Set age" : store.profile.whoopAge)
                                .font(PulseFont.number(store.profile.whoopAge.isEmpty ? 17 : 24)).lineLimit(1).minimumScaleFactor(0.2).padding(7)
                        }.frame(width: 67, height: 67)
                        Text("WHOOP AGE").font(PulseFont.label(11)).tracking(1)
                        Text("Personalized display").font(PulseFont.body(11)).foregroundStyle(PulseColor.muted)
                    }.frame(maxWidth: .infinity, minHeight: 112)
                }
            }
            PulseCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DAY STREAK").font(PulseFont.label(11)).tracking(1)
                        Text(store.profile.dayStreakOverride == nil ? "Saved UTC days" : "Personalized")
                            .font(PulseFont.body(9)).foregroundStyle(PulseColor.muted)
                    }
                    Spacer(); Image(systemName: "flame.fill").foregroundStyle(.orange)
                    Text("\(streak.formatted()) Days").font(PulseFont.number(17)).lineLimit(1).minimumScaleFactor(0.6)
                }.frame(minHeight: 23)
            }
            Text("Data Highlights").font(PulseFont.body(24).weight(.semibold))
            PulseCard(padding: 15) {
                Picker("Highlight period", selection: $period) {
                    ForEach(["1M", "3M", "ALL TIME"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).frame(minHeight: 44)
                HStack(alignment: .top, spacing: 6) {
                    ProfileHighlightDial(record: highlights.bestSleepPerformance, title: "Best Sleep", suffix: "%", maximum: 100, tint: PulseColor.sleep)
                    ProfileHighlightDial(record: highlights.peakRecovery, title: "Peak Recovery", suffix: "%", maximum: 100, tint: PulseColor.recoveryScore(highlights.peakRecovery?.value))
                    ProfileHighlightDial(record: highlights.peakStrain, title: "Max Strain", suffix: "", maximum: 21, tint: PulseColor.load)
                }.padding(.vertical, 10)
                Text("STREAKS").font(PulseFont.label(10)).tracking(1).foregroundStyle(PulseColor.muted).padding(.top, 10)
                HStack(alignment: .top) {
                    streakBadge(highlights.longestSleep70Streak, title: "70%+ Sleep", symbol: "moon", tint: PulseColor.sleep)
                    streakBadge(highlights.longestGreenRecoveryStreak, title: "Green Recovery", symbol: "heart", tint: PulseColor.readiness)
                    streakBadge(highlights.longestStrain10Streak, title: "10+ Strain", symbol: "dumbbell", tint: PulseColor.load)
                }.padding(.vertical, 12)
                if highlights.savedDays == 0 {
                    Label("Sync or import measurements to see records. You can still personalize and export your profile now.", systemImage: "tray").font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                }
                Text("NOTABLE STATS").font(PulseFont.label(10)).tracking(1).foregroundStyle(PulseColor.muted).padding(.top, 12)
                recordRow("Lowest RHR", record: highlights.lowestRestingHeartRate, unit: "bpm", symbol: "heart")
                recordRow("Highest RHR", record: highlights.highestRestingHeartRate, unit: "bpm", symbol: "heart")
                recordRow("Lowest HRV", record: highlights.lowestHRV, unit: "ms", symbol: "waveform.path.ecg")
                recordRow("Highest HRV", record: highlights.highestHRV, unit: "ms", symbol: "waveform.path.ecg")
                recordRow("Max Heart Rate", record: highlights.maxHeartRate, unit: "bpm", symbol: "heart.fill")
                recordRow("Longest Sleep", record: highlights.longestSleepMinutes, unit: "hours", symbol: "moon", duration: true)
                recordRow("Lowest Recovery", record: highlights.lowestRecovery, unit: "%", symbol: "arrow.triangle.2.circlepath")
            }
            Button { exporting = true } label: {
                Label("EXPORT PROFILE & HIGHLIGHTS", systemImage: "square.and.arrow.up").font(PulseFont.label(12)).tracking(0.7)
                    .frame(maxWidth: .infinity, minHeight: 52).background(PulseColor.elevated, in: RoundedRectangle(cornerRadius: 11))
            }.accessibilityIdentifier("profileExport")
        }
    }
    private func edit() {
        error = nil
        draft = store.profile; customStreak = draft.dayStreakOverride != nil
        streakText = draft.dayStreakOverride.map(String.init) ?? String(ProfileHighlightsCalculator.calculate(days: store.days).currentLoggedDayStreak)
        editing = true
    }
    private var editor: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PulseCard {
                        profileField("Display name", text: $draft.displayName)
                        profileField("Username", text: $draft.username)
                    }
                    PulseCard {
                        profileField("Age", text: $draft.age, decimal: true)
                        profileField("WHOOP Age · custom display", text: $draft.whoopAge, decimal: true)
                        Text("Any non-negative age is allowed, including decimals. There is no upper age limit. These are your chosen display values.").font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                    }
                    PulseCard {
                        Toggle("Choose my displayed day streak", isOn: $customStreak).frame(minHeight: 44)
                        if customStreak { TextField("Number of days", text: $streakText).keyboardType(.numberPad).frame(minHeight: 48).accessibilityLabel("Chosen day streak") }
                        Text("Turn off to show the streak calculated from saved days. This setting does not replace measured records.").font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                    }
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(PulseFont.body(13)).foregroundStyle(PulseColor.yellow) }
                    Button("SAVE PROFILE") {
                        do {
                            if customStreak {
                                guard let value = Int(streakText.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 0 else {
                                    throw ProfilePersonalizationError.invalid("Enter a whole-number streak of zero or greater.")
                                }
                                draft.dayStreakOverride = value
                            } else { draft.dayStreakOverride = nil }
                            try store.updateProfile(draft); error = nil; editing = false
                        } catch { self.error = error.localizedDescription }
                    }.font(PulseFont.label(12)).frame(maxWidth: .infinity, minHeight: 52).background(PulseColor.elevated, in: RoundedRectangle(cornerRadius: 11)).disabled(store.isImporting)
                }.padding(20)
            }.background(PulseColor.background).navigationTitle("Personalize Profile").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { editing = false }.frame(minWidth: 44, minHeight: 44) } }
        }.font(PulseFont.body(15)).foregroundStyle(PulseColor.text).tint(PulseColor.sleep).preferredColorScheme(.dark)
    }
    private func profileField(_ label: String, text: Binding<String>, decimal: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(PulseFont.label(11)).foregroundStyle(PulseColor.muted)
            TextField(label, text: text).keyboardType(decimal ? .decimalPad : .default).textInputAutocapitalization(.never)
                .autocorrectionDisabled().frame(minHeight: 48).accessibilityLabel(label)
        }
    }
    private func streakBadge(_ count: Int, title: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(tint).frame(height: 28)
            Text("\(count) Days").font(PulseFont.number(16))
            Text(title).font(PulseFont.body(11)).foregroundStyle(PulseColor.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
    private func recordRow(_ title: String, record: ProfileRecord?, unit: String, symbol: String, duration: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(PulseColor.yellow.opacity(0.7)).frame(width: 26)
            Text(title).font(PulseFont.body(14)); Spacer(minLength: 4)
            if let record {
                Text(duration ? "\(Int(record.value) / 60):\(String(format: "%02d", Int(record.value) % 60))" : record.value.formatted(.number.precision(.fractionLength(0...1))))
                    .font(PulseFont.number(20))
                if !duration { Text(unit).font(PulseFont.body(11)).foregroundStyle(PulseColor.muted) }
            } else { Text("No saved data").font(PulseFont.body(12)).foregroundStyle(PulseColor.muted) }
        }.frame(minHeight: 44).padding(.vertical, 6).overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5) }
    }
}

private struct ProfileHighlightDial: View {
    let record: ProfileRecord?
    let title: String
    let suffix: String
    let maximum: Double
    let tint: Color
    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 3.4)
                if let record { Circle().trim(from: 0, to: min(1, max(0, record.value / maximum))).stroke(tint, style: StrokeStyle(lineWidth: 3.4, lineCap: .round)).rotationEffect(.degrees(-90)) }
                Text(record.map { $0.value.formatted(.number.precision(.fractionLength(maximum == 21 ? 1 : 0))) + suffix } ?? "Sync")
                    .font(PulseFont.number(record == nil ? 16 : 20)).lineLimit(1).minimumScaleFactor(0.7)
            }.frame(width: 65, height: 65)
            Text(title).font(PulseFont.body(12)).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
            .accessibilityLabel(title + ", " + (record.map { $0.value.formatted() + suffix } ?? "No saved data"))
    }
}
