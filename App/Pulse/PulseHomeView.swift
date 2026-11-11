import SwiftUI

private struct PulseHomeOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
/// Matches the latest supplied Home reference states using explicitly illustrative fixtures.
struct PulseHomeView: View {
    @EnvironmentObject private var tracker: DeviceModel
    @EnvironmentObject private var store: AppStore
    private let data: PulseHomeData?
    @State private var index: Int
    @State private var compactHeader = false
    @State private var showingTracker = false
    @State private var showingCoach = false
    @State private var showingDataExport = false
    @State private var showingLive = false
    @State private var showingProfile = false
    @State private var quickMenu = false
    @State private var customizing = false
    @State private var hiddenMetrics = Set<String>()
    @State private var panel: PulseHomePanel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init() {
        let loaded = try? PulseHomeData.load()
        self.data = loaded; _index = State(initialValue: max(0, (loaded?.days.count ?? 1) - 1))
    }
    var body: some View {
        Group {
            if let data {
                home(data, day: data.days[index])
                    .sheet(isPresented: $showingCoach) { PulseCoachPreview(data: data) }
                    .sheet(item: $panel) { PulseHomePanelView(panel: $0, data: data, day: data.days[index]) }
            } else {
                ContentUnavailableView("Sample data could not load", systemImage: "exclamationmark.circle", description: Text("The WHOOP reference resource must be included in the app build."))
            }
        }.font(PulseFont.body()).foregroundStyle(PulseColor.text)
            .background(LinearGradient(colors: [PulseColor.top, PulseColor.background], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showingTracker) { PulseTrackerView().environmentObject(tracker) }
            .sheet(isPresented: $showingDataExport) { MeasurementExportView() }
            .fullScreenCover(isPresented: $showingLive) { ReferenceLiveView(reference: data?.days[index]) }
            .fullScreenCover(isPresented: $showingProfile) { WHOOPProfileView(fallbackName: data?.firstName ?? "Your Profile", fallbackInitials: data?.initials ?? "AA") }
    }
    private func home(_ data: PulseHomeData, day: PulseHomeDay) -> some View {
        VStack(spacing: 0) {
            header(data)
            if compactHeader { miniatureMetrics(day).padding(.horizontal, 30).frame(height: 39).transition(.opacity) }
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero(day).padding(.bottom, 7)
                    insight(day)
                    HStack(spacing: 11) {
                        PulseReferenceMonitor(title: "HEALTH MONITOR", badge: "!", value: day.healthStatus, detail: day.healthDetail, tint: PulseColor.yellow) { panel = .health }
                        PulseReferenceMonitor(title: "STRESS MONITOR", badge: day.stressValue.formatted(.number.precision(.fractionLength(1))), value: day.tension, detail: day.stressUpdated, tint: PulseColor.mint) { panel = .stress }
                    }
                    myDay(data, day: day).zIndex(3)
                    plan
                    dashboard(data, day: day)
                    discover
                    HStack(spacing: 8) {
                        WhoopWordmark().frame(width: 65, height: 12).accessibilityLabel("WHOOP")
                        Text("PEAK").font(PulseFont.body(10)).tracking(3).foregroundStyle(PulseColor.sleep)
                    }.frame(maxWidth: .infinity).padding(.top, 11)
                    Text("Illustrative reference data · Bluetooth readings are separate").font(PulseFont.body(9)).foregroundStyle(PulseColor.muted).frame(maxWidth: .infinity).padding(.bottom, 20)
                }.padding(.horizontal, 14.5).padding(.top, 22).padding(.bottom, 100)
                    .frame(maxWidth: 600).frame(maxWidth: .infinity)
                    .background(GeometryReader { proxy in Color.clear.preference(key: PulseHomeOffset.self, value: proxy.frame(in: .named("pulseHomeScroll")).minY) })
            }.coordinateSpace(name: "pulseHomeScroll").scrollIndicators(.hidden)
                .onPreferenceChange(PulseHomeOffset.self) { value in
                    let next = value < -155
                    if next != compactHeader { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { compactHeader = next } }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 55).onEnded { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
                    index = min(data.days.count - 1, max(0, index + (drag.translation.width < 0 ? 1 : -1)))
                })
        }.overlay(alignment: .bottom) {
            PulseTabBar(coachAction: { showingCoach = true }, moreAction: { showingDataExport = true })
                .padding(.horizontal, 11).offset(y: 8)
        }.onChange(of: index) { _, _ in quickMenu = false }
    }
    private func header(_ data: PulseHomeData) -> some View {
        let streak = store.profile.dayStreakOverride ?? (store.isExampleMode ? data.streak : ProfileHighlightsCalculator.calculate(days: store.days).currentLoggedDayStreak)
        return ZStack {
            HStack(spacing: 0) {
            Button { showingProfile = true } label: {
                HStack(spacing: -5) {
                    Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.71, blue: 0.44), Color(red: 1, green: 0.52, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 29, height: 29).overlay(Text(store.profile.initials(fallback: data.initials)).font(PulseFont.body(10).weight(.medium)).foregroundStyle(.black))
                    HStack(spacing: 7) { Text("🔥").font(.system(size: 15)); Text(streak.formatted()).font(PulseFont.number(11)).lineLimit(1).minimumScaleFactor(0.3) }
                        .frame(width: 57, height: 29).background(PulseColor.card, in: RoundedRectangle(cornerRadius: 11))
                }.frame(minHeight: 44)
            }.buttonStyle(PulsePressStyle()).accessibilityLabel("Profile, \(streak)-day displayed streak")
            Spacer(minLength: 3)
            Button { showingTracker = true } label: {
                HStack(spacing: 4) {
                    if tracker.connectedName == nil { Text("\(data.battery)%").font(PulseFont.compact(12)).foregroundStyle(PulseColor.muted) }
                    Image(systemName: "applewatch").font(.system(size: 24, weight: .light))
                        .overlay(alignment: .topTrailing) { Circle().fill(tracker.connectedName == nil ? PulseColor.muted : PulseColor.mint).frame(width: 5, height: 5) }
                }.frame(minWidth: 61, minHeight: 44)
            }.buttonStyle(PulsePressStyle()).accessibilityLabel(tracker.connectedName == nil ? "Connect tracker. Reference battery is sample data." : "Connected tracker. Open real device status.")
            }
            PulseDayStrip(index: $index, days: data.days)
        }.padding(.horizontal, 18).frame(height: 43)
    }
    private func hero(_ day: PulseHomeDay) -> some View {
        VStack(spacing: 20) {
            WhoopWordmark().frame(width: 65, height: 12).accessibilityLabel("WHOOP")
            HStack(spacing: 32) {
                PulseRing(value: "\(day.sleep)%", fraction: Double(day.sleep) / 100, previous: nil, tint: PulseColor.sleep, label: "SLEEP") { panel = .sleep }
                PulseRing(value: "\(day.readiness)%", fraction: Double(day.readiness) / 100, previous: nil, tint: recoveryColor(day.readiness), label: "RECOVERY") { panel = .recovery }
                PulseRing(value: day.load.formatted(.number.precision(.fractionLength(1))), fraction: day.load / 21, previous: 0.5, tint: PulseColor.load, label: "STRAIN") { panel = .strain }
            }.padding(.horizontal, 15)
        }.frame(maxWidth: .infinity)
    }
    private func miniatureMetrics(_ day: PulseHomeDay) -> some View {
        HStack {
            miniMetric("SLEEP", Double(day.sleep) / 100, PulseColor.sleep, .sleep)
            Spacer()
            miniMetric("RECOVERY", Double(day.readiness) / 100, recoveryColor(day.readiness), .recovery)
            Spacer()
            miniMetric("STRAIN", day.load / 21, PulseColor.load, .strain)
        }
    }
    private func miniMetric(_ title: String, _ value: Double, _ color: Color, _ destination: PulseHomePanel) -> some View {
        Button { panel = destination } label: {
            HStack(spacing: 7) {
                ZStack { Circle().stroke(.white.opacity(0.10), lineWidth: 2); Circle().trim(from: 0, to: value).stroke(color, lineWidth: 2).rotationEffect(.degrees(-90)) }.frame(width: 20, height: 20)
                Text(title).font(PulseFont.label(10)).tracking(0.8)
            }.frame(minHeight: 39)
        }.buttonStyle(PulsePressStyle())
    }
    private func insight(_ day: PulseHomeDay) -> some View {
        PulseCard(padding: 18) {
            HStack(alignment: .top, spacing: 13) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(day.insightTitle).font(PulseFont.body(13.5).weight(.semibold))
                    Text(day.insightBody).font(PulseFont.body(13)).foregroundStyle(PulseColor.text.opacity(0.75)).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 5) { Image(systemName: "checkmark").font(.system(size: 15)); Text("1").font(PulseFont.body(12)).foregroundStyle(PulseColor.muted) }.padding(5).background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            }.frame(minHeight: 75, alignment: .top)
        }
    }
    private func myDay(_ data: PulseHomeData, day: PulseHomeDay) -> some View {
        VStack(spacing: 15) {
            VStack(spacing: 5) {
                HStack {
                    Text("My Day").font(PulseFont.section)
                    Spacer()
                    Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { quickMenu.toggle() } } label: {
                        Image(systemName: quickMenu ? "xmark" : "plus").font(.system(size: 23, weight: .regular))
                            .foregroundStyle(quickMenu ? PulseColor.text : PulseColor.background).frame(width: 34, height: 34)
                            .background(quickMenu ? PulseColor.card : .white, in: RoundedRectangle(cornerRadius: 12)).frame(width: 44, height: 44)
                    }.buttonStyle(PulsePressStyle()).accessibilityLabel(quickMenu ? "Close daily actions" : "Open daily actions")
                }.frame(height: 44).overlay(alignment: .bottomTrailing) {
                    if quickMenu { PulseQuickMenu { destination in
                        quickMenu = false
                        if destination == .live { showingLive = true } else { panel = destination }
                    }
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.94, anchor: .bottomTrailing).combined(with: .opacity))
                        .offset(y: -52).zIndex(20) }
                }
                Button { panel = .review } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "moon").font(.system(size: 20, weight: .light)).foregroundStyle(Color(red: 0.67, green: 0.61, blue: 0.88))
                        Text("\(store.profile.displayName.isEmpty ? data.firstName : store.profile.displayName)'s Day In Review").font(PulseFont.body(13.5))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .light)).foregroundStyle(PulseColor.sleep)
                    }.padding(.horizontal, 14).frame(minHeight: 44)
                        .background(LinearGradient(colors: [Color(red: 0.21, green: 0.18, blue: 0.36), Color(red: 0.10, green: 0.27, blue: 0.32)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(PulsePressStyle())
            }.zIndex(5)
            tonight(day)
            activities(day)
            journal(data)
        }
    }
    private func tonight(_ day: PulseHomeDay) -> some View {
        PulseCard {
            VStack(spacing: 14) {
                HStack { Text("TONIGHT’S SLEEP").font(PulseFont.label(10.5)).tracking(0.8); Spacer(); Image(systemName: "chevron.right").font(.system(size: 13, weight: .light)).foregroundStyle(PulseColor.muted) }
                HStack(alignment: .top) {
                    VStack(spacing: 7) {
                        Label(day.bedtime, systemImage: "sun.horizon").font(PulseFont.number(22))
                        Text("RECOMMENDED\nBEDTIME").font(PulseFont.label(9)).tracking(0.7).foregroundStyle(PulseColor.muted).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity)
                    Text("---------").font(PulseFont.body(11)).foregroundStyle(PulseColor.muted.opacity(0.5)).padding(.top, 7).accessibilityHidden(true)
                    VStack(spacing: 7) {
                        Label(day.plannedWake, systemImage: "sun.horizon").font(PulseFont.number(22))
                        Text("ALARM OFF").font(PulseFont.label(9)).tracking(0.8).foregroundStyle(PulseColor.yellow)
                    }.frame(maxWidth: .infinity)
                }.padding(.vertical, 7)
                Button { panel = .alarm } label: {
                    Label("SET ALARM", systemImage: "sensor.tag.radiowaves.forward").font(PulseFont.label(10)).tracking(0.9).frame(maxWidth: .infinity, minHeight: 36).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(PulsePressStyle()).frame(minHeight: 44)
            }
        }
    }
    private func activities(_ day: PulseHomeDay) -> some View {
        PulseCard(padding: 11) {
            VStack(spacing: 11) {
                HStack { Text("TODAY’S ACTIVITIES").font(PulseFont.label(10.5)).tracking(0.8); Spacer(); Image(systemName: "arrow.up.right.and.arrow.down.left").font(.system(size: 14)).foregroundStyle(PulseColor.muted) }.padding(.horizontal, 3).padding(.top, 4).padding(.bottom, 3)
                ForEach(day.activities) { activity in
                    Button { panel = activity.isSleep ? .sleep : .activity } label: { PulseReferenceActivityRow(activity: activity) }.buttonStyle(PulsePressStyle())
                }
                HStack(spacing: 11) {
                    smallAction("ADD ACTIVITY", "plus", .activity)
                    smallAction("START ACTIVITY", "stopwatch", .session)
                }.padding(.top, 4)
            }
        }
    }
    private func smallAction(_ title: String, _ icon: String, _ destination: PulseHomePanel) -> some View {
        Button { panel = destination } label: {
            Label(title, systemImage: icon).font(PulseFont.label(9)).tracking(0.8).frame(maxWidth: .infinity, minHeight: 36).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(PulsePressStyle()).frame(minHeight: 44)
    }
    private func journal(_ data: PulseHomeData) -> some View {
        PulseCard {
            VStack(spacing: 19) {
                Button { panel = .journal } label: { HStack { Text("MY JOURNAL").font(PulseFont.label(10.5)).tracking(0.8); Spacer(); Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(PulseColor.muted) } }.buttonStyle(PulsePressStyle())
                HStack {
                    ForEach(Array(data.days.enumerated()), id: \.element.id) { item in
                        Button { index = item.offset } label: {
                            VStack(spacing: 9) {
                                Text(item.element.weekday.uppercased()).font(PulseFont.label(9)).tracking(0.7)
                                Circle().fill(item.offset == index ? .white.opacity(0.22) : .clear).overlay(Circle().stroke(item.offset == index ? .white.opacity(0.7) : .white.opacity(0.20), lineWidth: 0.8)).frame(width: 19, height: 19)
                            }.frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(item.offset == index ? PulseColor.text : PulseColor.muted)
                        }.buttonStyle(PulsePressStyle()).accessibilityLabel("Journal for \(item.element.weekday), November \(item.element.dayNumber)")
                    }
                }.padding(.vertical, 7)
                Button { panel = .journal } label: { Label("BEHAVIOR INSIGHTS", systemImage: "lightbulb").font(PulseFont.label(10)).tracking(0.9).frame(maxWidth: .infinity, minHeight: 36).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(PulsePressStyle()).frame(minHeight: 44)
            }.padding(.vertical, 4)
        }
    }
    private var plan: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("My Plan").font(PulseFont.section)
            Button { panel = .plan } label: {
                PulseCard(padding: 18) {
                    HStack(spacing: 5) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Build Your Best Self").font(PulseFont.body(13.5).weight(.semibold))
                            Text("Set goals, track progress, and turn small actions into long-term wins.").font(PulseFont.body(12)).foregroundStyle(PulseColor.muted).lineSpacing(3)
                            HStack(spacing: 9) { Text("EXPLORE PLANS").font(PulseFont.label(10)).tracking(0.9); Image(systemName: "arrow.right").font(.system(size: 18, weight: .light)) }.foregroundStyle(PulseColor.sleep)
                        }
                        PulsePlanArtwork()
                    }.frame(minHeight: 94)
                }
            }.buttonStyle(PulsePressStyle())
        }
    }
    private func dashboard(_ data: PulseHomeData, day: PulseHomeDay) -> some View {
        VStack(spacing: 11) {
            HStack {
                Text("My Dashboard").font(PulseFont.section)
                Spacer()
                Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { customizing.toggle() } } label: { Label("CUSTOMIZE", systemImage: "pencil").font(PulseFont.label(9)).tracking(0.8).frame(minHeight: 44) }.buttonStyle(PulsePressStyle())
            }.frame(height: 34).padding(.bottom, 1)
            if customizing {
                PulseCard {
                    ForEach(day.statistics) { stat in
                        Toggle(stat.title, isOn: Binding(get: { !hiddenMetrics.contains(stat.id) }, set: { visible in if visible { hiddenMetrics.remove(stat.id) } else { hiddenMetrics.insert(stat.id) } })).font(PulseFont.body(12)).frame(minHeight: 44)
                    }
                }.tint(PulseColor.mint)
            }
            ForEach(day.statistics.prefix(3).filter { !hiddenMetrics.contains($0.id) }) { PulseReferenceMetric(metric: $0) }
            PulseCard {
                HStack { Text("STRAIN & RECOVERY").font(PulseFont.label(10.5)).tracking(0.8); Spacer(); Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(PulseColor.muted) }
                PulseWeekChart(days: data.days, selected: index)
            }
            Button { panel = .stress } label: {
                PulseCard {
                    VStack(spacing: 17) {
                        HStack { Text("STRESS MONITOR").font(PulseFont.label(10.5)).tracking(0.8); Spacer(); Image(systemName: "chevron.right").font(.system(size: 15, weight: .light)).foregroundStyle(PulseColor.muted) }
                        HStack { Text("Last updated \(day.stressUpdated)").font(PulseFont.body(10.5)).foregroundStyle(PulseColor.muted); Spacer(); Text(day.tension).font(PulseFont.label(11)).tracking(0.6).foregroundStyle(PulseColor.mint); Text(day.stressValue.formatted(.number.precision(.fractionLength(1)))).font(PulseFont.number(16)) }
                        PulseStressChart(values: day.stressValues)
                    }
                }
            }.buttonStyle(PulsePressStyle())
            ForEach(day.statistics.dropFirst(3).filter { !hiddenMetrics.contains($0.id) }) { PulseReferenceMetric(metric: $0) }
            Button { panel = .weight } label: { PulseCard { HStack { Label("WEIGHT", systemImage: "scalemass").font(PulseFont.label(10.5)).tracking(0.8); Spacer(); Image(systemName: "chevron.right").foregroundStyle(PulseColor.muted) }.frame(minHeight: 27) } }.buttonStyle(PulsePressStyle())
        }
    }
    private var discover: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Discover More").font(PulseFont.section).padding(.bottom, 2)
            PulseDiscoverCard(title: "Test with Advanced Labs", detail: "Clinician-reviewed lab results of up to 122+ biomarkers. HSA/FSA eligible.", cta: "GO TO ADVANCED LABS", symbol: "testtube.2", tone: PulseColor.mint) { panel = .labs }
            PulseDiscoverCard(title: "Explore the WHOOP shop", detail: "New bands, smart apparel, batteries and accessories", cta: "GO TO SHOP", symbol: "bag", tone: PulseColor.sleep) { panel = .shop }
            PulseDiscoverCard(title: "Get your friend on WHOOP", detail: "Get a 1 month credit for each friend you refer", cta: "REFER A FRIEND", symbol: "person.2", tone: .orange) { panel = .referral }
            PulseDiscoverCard(title: "Extend your WHOOP membership", detail: "No one on WHOOP is quite like you.", cta: "EXTEND YOUR MEMBERSHIP", symbol: "sensor.tag.radiowaves.forward", tone: Color(red: 0.75, green: 0.62, blue: 0.43)) { panel = .membership }
        }
    }
    private func recoveryColor(_ value: Int) -> Color { value <= 33 ? .red : value <= 66 ? PulseColor.recoveryYellow : PulseColor.readiness }
}
