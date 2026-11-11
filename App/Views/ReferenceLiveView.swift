import SwiftUI
import AVFoundation
import PhotosUI
import Photos
import ImageIO
import WHOOPCore

/// Full-screen camera composition measured from the supplied Live reference.
struct ReferenceLiveView: View {
    let reference: PulseHomeDay?
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var device: DeviceModel
    @EnvironmentObject private var recorder: WorkoutRecorder
    @EnvironmentObject private var liveActivity: LiveActivityDriver
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var camera = LiveCameraModel()
    @State private var mode = CameraOverlayMode.overview
    @State private var now = Date()
    @State private var drawer = false
    @State private var microphone = false
    @State private var torch = false
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoImage: UIImage?
    @State private var mediaURL: URL?
    @State private var busy = false
    @State private var message: String?
    @State private var showTracker = false
    @State private var useHomeExample = true
    @State private var task: Task<Void, Never>?
    @State private var clipStarted: Date?
    @State private var activityName = "Running"
    @State private var resting = 55.0
    @State private var maximum = 190.0
    @State private var confirmDiscard = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = min(width * 16 / 9, geometry.size.height - 100)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                canvas(width: width, height: height)
                footer(width: width).frame(height: 100)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
        }.ignoresSafeArea().statusBarHidden(true).preferredColorScheme(.dark)
            .task { if photoData == nil { await openCamera() } }
            .onReceive(clock) { date in now = date; camera.engine.update(snapshot()) }
            .onChange(of: mode) { _, _ in camera.engine.update(snapshot()) }
            .onChange(of: photo) { _, item in loadPhoto(item) }
            .onChange(of: camera.movie) { _, url in if let url { mediaURL = url; drawer = true } }
            .onChange(of: camera.recording) { _, recording in clipStarted = recording ? Date() : nil }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { camera.close(); torch = false }
                else if photoData == nil { task = Task { await openCamera() } }
            }
            .onDisappear { task?.cancel(); camera.close() }
            .sheet(isPresented: $drawer) { controls }
            .alert("Live", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
    }

    private func canvas(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if let photoImage {
                Image(uiImage: photoImage).resizable().scaledToFill().frame(width: width, height: height).clipped()
            } else if camera.ready {
                ReferenceCameraPreview(session: camera.engine.session).frame(width: width, height: height)
            } else {
                Color(white: 0.08)
                VStack(spacing: 16) {
                    Image(systemName: "camera").font(.system(size: 36, weight: .light))
                    Text(camera.status).font(PulseFont.body(14)).multilineTextAlignment(.center)
                    Button("OPEN CAMERA") { task = Task { await openCamera() } }
                        .font(PulseFont.label(12)).frame(minHeight: 48)
                    Button("IPHONE CAMERA SETTINGS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.font(PulseFont.label(10)).frame(minHeight: 44)
                }.foregroundStyle(.white).padding(32).offset(y: -height * 0.1)
            }
            Image(uiImage: LiveOverlayRenderer.image(snapshot: snapshot(), size: CGSize(width: width * 2, height: height * 2), transparent: true))
                .resizable().frame(width: width, height: height).allowsHitTesting(false)
                .accessibilityLabel(snapshot().referenceMetrics?.map { "\($0.label.replacingOccurrences(of: "\n", with: " ")), \($0.value)" }.joined(separator: ". ") ?? "Saved day stats")
            VStack {
                HStack {
                    Button {
                        if camera.recording { camera.stop(); drawer = true } else { dismiss() }
                    } label: { Image(systemName: "xmark").font(.system(size: 21, weight: .semibold)).frame(width: 44, height: 44) }
                        .accessibilityLabel(camera.recording ? "Stop video and review" : "Close Live")
                    Spacer()
                }.padding(.horizontal, width * 0.018).padding(.top, height * 0.017)
                Spacer()
                if camera.recording {
                    Label("RECORDING", systemImage: "record.circle.fill").font(PulseFont.label(10))
                        .foregroundStyle(.red).padding(8).background(.black.opacity(0.6), in: Capsule())
                }
                captureControls(width: width).padding(.bottom, height * 0.013)
            }.foregroundStyle(.white)
            if busy { ProgressView("Preparing media…").padding(20).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12)).tint(.white) }
        }.frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 8))
            .simultaneousGesture(DragGesture(minimumDistance: 50).onEnded { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5, let index = CameraOverlayMode.allCases.firstIndex(of: mode) else { return }
                let next = min(CameraOverlayMode.allCases.count - 1, max(0, index + (drag.translation.width < 0 ? 1 : -1)))
                select(CameraOverlayMode.allCases[next])
            })
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Live camera, \(mode.rawValue). \(snapshot().source)")
    }

    private func captureControls(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            PhotosPicker(selection: $photo, matching: .images) {
                Group {
                    if let photoImage { Image(uiImage: photoImage).resizable().scaledToFill() }
                    else { Image(systemName: "photo").font(.system(size: 24, weight: .light)) }
                }.frame(width: 38, height: 38).clipped().background(.black.opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.5), lineWidth: 3))
                    .clipShape(RoundedRectangle(cornerRadius: 4)).frame(maxWidth: .infinity, minHeight: 48)
            }.accessibilityLabel("Choose a saved photo").disabled(camera.recording || busy)
            Button { drawer = true } label: { Image(systemName: "rectangle.split.3x1.fill").font(.system(size: 23)).frame(maxWidth: .infinity, minHeight: 48) }
                .accessibilityLabel("Overlay and capture settings").disabled(camera.recording || camera.starting || busy)
            Button(action: shutter) {
                ZStack {
                    Circle().fill(mode == .live ? Color.red : .white.opacity(0.4)).frame(width: 69, height: 69)
                    Circle().fill(.white).frame(width: 56, height: 56)
                    if camera.recording { RoundedRectangle(cornerRadius: 4).fill(.red).frame(width: 22, height: 22) }
                    else { WhoopMonogram().fill(mode == .live ? .red : Color(white: 0.23)).frame(width: 25, height: 22) }
                }.frame(width: width / 5, height: 76)
            }.accessibilityLabel(camera.recording ? "Stop video" : mode == .live && photoData == nil ? "Record video" : "Capture photo with stats")
                .disabled(busy || camera.starting || (photoData == nil && !camera.ready))
            Button {
                let requested = !torch
                camera.engine.setTorch(requested) { accepted in Task { @MainActor in
                    if accepted { torch = requested } else { message = "The light is unavailable for this camera." }
                } }
            } label: { Image(systemName: torch ? "bolt.fill" : "bolt.slash.fill").font(.system(size: 23)).frame(maxWidth: .infinity, minHeight: 48) }
                .accessibilityLabel(torch ? "Turn camera light off" : "Turn camera light on").disabled(photoData != nil || busy || !camera.ready)
            Button { torch = false; camera.engine.flip() } label: {
                Image(systemName: "camera.rotate").font(.system(size: 29, weight: .light)).frame(maxWidth: .infinity, minHeight: 48)
            }.accessibilityLabel("Switch front and back cameras").disabled(camera.recording || camera.starting || busy || photoData != nil)
        }.buttonStyle(PulsePressStyle())
    }

    private func footer(width: CGFloat) -> some View {
        ZStack {
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(CameraOverlayMode.allCases, id: \.rawValue) { item in
                            Button { select(item) } label: {
                                Text(item.rawValue.uppercased()).font(PulseFont.label(10)).tracking(2)
                                    .foregroundStyle(mode == item ? .white : .white.opacity(0.45)).frame(width: 108, height: 44)
                            }.id(item.rawValue).disabled(camera.recording || camera.starting || busy)
                        }
                    }.padding(.horizontal, max(0, (width - 108) / 2))
                }.scrollIndicators(.hidden)
                    .onAppear { reader.scrollTo(mode.rawValue, anchor: .center) }
                    .onChange(of: mode) { _, value in withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { reader.scrollTo(value.rawValue, anchor: .center) } }
            }.frame(height: 48).position(x: width / 2, y: 30)
            Button { drawer = true } label: { Image(systemName: "arrowtriangle.up.fill").font(.system(size: 12)).frame(width: 60, height: 44) }
                .foregroundStyle(.white).accessibilityLabel("Open Live controls").position(x: width / 2, y: 68)
        }.background(.black)
    }
    private func select(_ selection: CameraOverlayMode) {
        guard !camera.recording, !camera.starting, !busy else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { mode = selection }
    }

    private var day: DailySnapshot {
        guard useHomeExample, store.isExampleMode, let reference, let date = NutritionDay.date(reference.id) else { return store.selectedDay }
        var day = DailySnapshot.empty(on: date, source: .example)
        day.strain = reference.load; day.recovery = reference.readiness; day.sleepPerformance = reference.sleep
        let components = reference.sleepDuration.split(separator: ":").compactMap { Int($0) }
        day.sleepMinutes = components.count == 2 ? components[0] * 60 + components[1] : 0
        if let energy = reference.statistics.first(where: { $0.id == "energy" }) {
            day.energyKcal = Double(energy.value.replacingOccurrences(of: ",", with: "")) ?? 0
        }
        // Home fixtures remain illustrative and are never written into AppStore.
        return day
    }
    private func snapshot() -> LiveOverlaySnapshot {
        let day = day
        let useRecorder = !recorder.isPaused && (recorder.latestSampleDate ?? .distantPast) > (device.heartRateReceivedAt ?? .distantPast)
        let hr = photoData == nil ? (useRecorder ? recorder.latestHeartRate : device.heartRate) : nil
        let received = photoData == nil ? (useRecorder ? recorder.latestSampleDate : device.heartRateReceivedAt) : nil
        let elapsed = clipStarted.map { max(0, Int(Date().timeIntervalSince($0))) } ?? recorder.elapsedSeconds
        let metrics = CameraOverlayData.metrics(mode: mode, day: day, liveHeartRate: hr, sampleDate: received, now: now, elapsedSeconds: elapsed)
        let exists = store.days.contains { DayCalendar.utc.isDate($0.date, inSameDayAs: day.date) }
        let label = day.source == .example ? "EXAMPLE" : exists ? "RECORDED DAY" : "NO SAVED DATA"
        return LiveOverlaySnapshot(title: "WHOOP Live", source: "\(label) · \(NutritionDay.key(day.date))",
                                   values: metrics.map(\.value), labels: metrics.map(\.label), heartRateIndex: mode == .live ? 0 : nil,
                                   sampleDate: received, referenceMode: mode, referenceMetrics: metrics)
    }
    private func openCamera() async {
        guard scenePhase == .active, !camera.recording, !camera.starting, !Task.isCancelled else { return }
        await camera.open(microphone: microphone)
        if !Task.isCancelled { camera.engine.update(snapshot()) }
    }
    private func shutter() {
        guard !busy else { return }
        camera.engine.update(snapshot())
        if photoData != nil { renderSelectedPhoto(); return }
        if mode == .live {
            if camera.recording { camera.stop() } else { mediaURL = nil; camera.start() }
        } else {
            busy = true; mediaURL = nil
            camera.engine.capturePhoto(state: snapshot()) { result in Task { @MainActor in
                busy = false
                switch result { case .success(let url): mediaURL = url; drawer = true
                case .failure(let error): message = error.localizedDescription }
            } }
        }
    }
    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item, !camera.recording else { return }
        camera.close(); torch = false; busy = true
        task?.cancel()
        task = Task { @MainActor in
            defer { busy = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self), data.count <= 30 * 1024 * 1024,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary) else { throw LiveCameraError.photo }
                try Task.checkCancellation(); photoData = data; photoImage = UIImage(cgImage: image); mediaURL = nil
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }
    private func renderSelectedPhoto() {
        guard let photoData else { return }
        busy = true
        let state = snapshot()
        task = Task { @MainActor in
            defer { busy = false }
            let worker = Task.detached(priority: .userInitiated) { () throws -> URL in
                let image = try LiveOverlayRenderer.photo(photoData, snapshot: state)
                guard let data = image.pngData() else { throw LiveCameraError.photo }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-photo-\(UUID().uuidString).png")
                try data.write(to: url, options: [.atomic, .completeFileProtection]); return url
            }
            do {
                let url = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation(); mediaURL = url; drawer = true
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }

    private var controls: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PulseCard {
                        Text("\(day.source == .example ? "Example" : "Saved") day stats").font(PulseFont.body(20).weight(.semibold))
                        DatePicker("Recorded day · UTC", selection: $store.selectedDate, displayedComponents: .date)
                            .frame(minHeight: 44).onChange(of: store.selectedDate) { _, _ in useHomeExample = false }
                        Text("Overview shows day Strain, Recovery and hours asleep. Live shows received heart rate and day totals; calories are not a workout estimate.")
                            .font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                        if store.isExampleMode, reference != nil {
                            Toggle("Use Home reference example", isOn: $useHomeExample).frame(minHeight: 44)
                        }
                        Button("CONNECT TRACKER") { showTracker = true }.font(PulseFont.label(12)).frame(minHeight: 44)
                    }
                    PulseCard {
                        Text("CAPTURE").font(PulseFont.label(11)).tracking(1)
                        Text(camera.status).font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                        Text("Use Live for video, or the other modes for a photo. Video clips stop after five minutes or when the app leaves the foreground.")
                            .font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                        Toggle("Microphone audio", isOn: $microphone).frame(minHeight: 44)
                            .onChange(of: microphone) { _, _ in if photoData == nil { task = Task { await openCamera() } } }
                        if photoData != nil {
                            Button("RETURN TO CAMERA") {
                                photoData = nil; photoImage = nil; photo = nil; drawer = false
                                task = Task { await openCamera() }
                            }.font(PulseFont.label(12)).frame(minHeight: 44)
                        }
                    }.disabled(camera.recording || busy)
                    if let mediaURL {
                        PulseCard {
                            Text("Media ready").font(PulseFont.body(20).weight(.semibold))
                            ShareLink(item: mediaURL) {
                                Label("SHARE OR SAVE TO FILES", systemImage: "square.and.arrow.up").frame(minHeight: 48)
                            }.font(PulseFont.label(12))
                            Button("SAVE TO PHOTOS") { saveToPhotos(mediaURL) }.font(PulseFont.label(12)).frame(minHeight: 48).disabled(busy)
                        }
                    }
                    PulseCard {
                        Button("EXPORT TRANSPARENT STATS PNG") { exportTransparent() }.font(PulseFont.label(12)).frame(minHeight: 48).disabled(busy || camera.recording)
                        Toggle("Lock Screen Live Activities", isOn: $liveActivity.enabled).frame(minHeight: 44)
                        Text(liveActivity.status).font(PulseFont.body(12)).foregroundStyle(PulseColor.muted)
                    }
                    workoutControls
                }.padding(20)
            }.background(PulseColor.background).navigationTitle("Live Controls").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { drawer = false }.frame(minWidth: 44, minHeight: 44) } }
        }.font(PulseFont.body(15)).foregroundStyle(PulseColor.text).tint(PulseColor.sleep).preferredColorScheme(.dark)
            .environment(\.calendar, DayCalendar.utc).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .sheet(isPresented: $showTracker) { PulseTrackerView().environmentObject(device) }
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) { recorder.discard() }
            }
    }
    private var workoutControls: some View {
        PulseCard {
            Text("WORKOUT").font(PulseFont.label(11)).tracking(1)
            if recorder.isRecording {
                Text("\(recorder.name) · \(recorder.elapsedSeconds / 60) min · \(recorder.samples) samples").font(PulseFont.body(16))
                Text(recorder.status).font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                Button(recorder.isPaused ? "RESUME WORKOUT" : "PAUSE WORKOUT") { recorder.togglePause() }
                    .font(PulseFont.label(12)).frame(minHeight: 44).disabled(camera.recording)
                Button("FINISH AND SAVE WORKOUT") {
                    do { try recorder.save(to: store) } catch { message = error.localizedDescription }
                }.font(PulseFont.label(12)).frame(minHeight: 44).disabled(camera.recording)
                Button("Discard workout", role: .destructive) { confirmDiscard = true }.frame(minHeight: 44).disabled(camera.recording)
            } else {
                TextField("Activity name", text: $activityName).frame(minHeight: 44)
                Stepper("Resting HR: \(Int(resting))", value: $resting, in: 30...110).frame(minHeight: 44)
                Stepper("Maximum HR: \(Int(maximum))", value: $maximum, in: 120...230).frame(minHeight: 44)
                Text("Use your known heart-rate limits. Starting a workout saves received samples when you finish; the local Strain estimate is separate from the saved day Strain shown in the overlay.")
                    .font(PulseFont.body(13)).foregroundStyle(PulseColor.muted)
                Button("START WORKOUT") {
                    do { try recorder.start(name: activityName, resting: resting, maximum: maximum) }
                    catch { message = error.localizedDescription }
                }.font(PulseFont.label(12)).frame(minHeight: 44).disabled(activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.disabled(busy || camera.starting)
    }
    private func exportTransparent() {
        do {
            let image = LiveOverlayRenderer.image(snapshot: snapshot(), size: CGSize(width: 1080, height: 1920), transparent: true)
            guard let data = image.pngData() else { throw LiveCameraError.photo }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-overlay-\(UUID().uuidString).png")
            try data.write(to: url, options: [.atomic, .completeFileProtection]); mediaURL = url
        } catch { message = error.localizedDescription }
    }
    private func saveToPhotos(_ url: URL) {
        busy = true
        task = Task { @MainActor in
            defer { busy = false }
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else { message = "Allow Photos access in iPhone Settings, or use Share to save to Files."; return }
            do {
                let video = url.pathExtension.lowercased() == "mp4"
                let image = video ? nil : UIImage(contentsOfFile: url.path)
                guard video || image != nil else { throw LiveCameraError.photo }
                try await PHPhotoLibrary.shared().performChanges {
                    if video { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
                    else if let image { PHAssetChangeRequest.creationRequestForAsset(from: image) }
                }
                message = "Saved to Photos."
            } catch { message = error.localizedDescription }
        }
    }
}

private struct ReferenceCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(); view.preview.session = session; view.preview.videoGravity = .resizeAspectFill; return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {
        if let connection = view.preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
}
