import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import UIKit
import WHOOPCore

private enum LiveMode: String, CaseIterable, Identifiable { case camera = "Camera", photo = "Photo"; var id: String { rawValue } }
private enum OverlayChoice: String, CaseIterable, Identifiable { case overview = "Overview", heartRate = "Heart rate", calories = "Calories", strain = "Strain", recovery = "Recovery", sleep = "Sleep"; var id: String { rawValue } }
struct LiveView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var recorder: WorkoutRecorder
    @EnvironmentObject private var device: DeviceModel
    @EnvironmentObject private var liveActivity: LiveActivityDriver
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = LiveCameraModel()
    @State private var mode = LiveMode.camera
    @State private var choice = OverlayChoice.overview
    @State private var microphone = true
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var renderedPhoto: UIImage?
    @State private var exportURL: URL?
    @State private var message: String?
    @State private var busy = false
    @State private var name = "Running"
    @State private var resting = 55.0
    @State private var maximum = 190.0
    @State private var task: Task<Void, Never>?
    @State private var confirmDiscard = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        NPage(title: "Live") {
            Picker("Media mode", selection: $mode) { ForEach(LiveMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(minHeight: 44).disabled(camera.recording)
            Picker("Stat overlay", selection: $choice) { ForEach(OverlayChoice.allCases) { Text($0.rawValue).tag($0) } }.frame(minHeight: 44).disabled(camera.recording)
            if mode == .camera { cameraContent } else { photoContent }
            if let message { NCard { Text(message).font(NFont.body(13)).foregroundStyle(NColor.cyan) } }
            NCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lock Screen & Dynamic Island").font(NFont.number(17))
                    Toggle("Live Activities", isOn: $liveActivity.enabled).font(NFont.body(14)).tint(NColor.cyan).frame(minHeight: 44)
                    Text(liveActivity.status).font(NFont.body(12)).foregroundStyle(NColor.muted)
                    Button("OPEN APP SETTINGS") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(NFont.label(10)).frame(minHeight: 44)
                    Text("Updates depend on app execution and sensor delivery. Readings become unavailable when stale; a running timer is not proof of a fresh heart-rate measurement.").font(NFont.body(11)).foregroundStyle(NColor.muted)
                }
            }
            Button("EXPORT TRANSPARENT STATS PNG") { exportTransparent() }.buttonStyle(NButton(secondary: true)).disabled(busy || camera.recording)
            if let exportURL { ShareLink(item: exportURL) { Label("SHARE OVERLAY", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44) }.font(NFont.label(12)) }
            Text("Camera clips include live received heart rate and a separately labeled local strain estimate. Workout calories and zones are not supplied by this recorder and stay unavailable. Photo overlays use the recorded day you select. Example scores remain labeled.").font(NFont.body(11)).foregroundStyle(NColor.muted)
        }
        .onReceive(clock) { _ in if mode == .camera { camera.engine.update(snapshot()) } }
        .onChange(of: choice) { _, _ in camera.engine.update(snapshot()); renderedPhoto = nil; exportURL = nil }
        .onChange(of: mode) { _, new in if new == .photo { camera.close() }; exportURL = nil }
        .onChange(of: photo) { _, item in
            guard let item else { return }; busy = true; message = nil
            task = Task { @MainActor in
                defer { busy = false }
                do { guard let data = try await item.loadTransferable(type: Data.self), data.count <= 30 * 1024 * 1024 else { throw LiveCameraError.photo }; try Task.checkCancellation(); photoData = data; renderedPhoto = nil; exportURL = nil }
                catch { if !Task.isCancelled { message = error.localizedDescription } }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active && camera.recording { camera.stop() } }
        .onDisappear { task?.cancel(); camera.close() }
        .confirmationDialog("Discard this workout recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive) { recorder.discard() }
        }
    }
    @ViewBuilder private var cameraContent: some View {
        if camera.ready {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                CameraPreview(session: camera.engine.session)
                    .overlay { Image(uiImage: LiveOverlayRenderer.image(snapshot: snapshot(), size: CGSize(width: 720, height: 1280), transparent: false)).resizable().scaledToFit() }
                    .aspectRatio(9/16, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 16))
            }
            HStack(spacing: 10) {
                Button(camera.recording ? "STOP VIDEO" : "RECORD VIDEO") {
                    if camera.recording { camera.stop() } else { camera.engine.update(snapshot()); camera.start() }
                }.buttonStyle(NButton()).disabled(!recorder.isRecording || recorder.isPaused || camera.starting)
                Button { camera.engine.flip() } label: { Image(systemName: "camera.rotate").frame(width: 48, height: 48) }.disabled(camera.recording).accessibilityLabel("Switch camera")
            }
        } else {
            NEmpty(title: "Record with your stats", detail: "Open the camera to preview your live heart rate and workout estimate.", symbol: "camera")
            Toggle("Include microphone audio", isOn: $microphone).font(NFont.body(13)).frame(minHeight: 44)
            Button("OPEN CAMERA") { task = Task { await camera.open(microphone: microphone); camera.engine.update(snapshot()) } }.buttonStyle(NButton())
        }
        Text(camera.status).font(NFont.body(12)).foregroundStyle(NColor.muted)
        if let movie = camera.movie {
            HStack(spacing: 10) {
                ShareLink(item: movie) { Label("SHARE VIDEO", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44) }.font(NFont.label(11))
                Button("SAVE VIDEO") { saveToPhotos(video: movie, image: nil) }.font(NFont.label(11)).frame(maxWidth: .infinity, minHeight: 44).disabled(busy)
            }
        }
        if recorder.isRecording {
            NCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(recorder.name).font(NFont.number(22))
                    Text("\(recorder.elapsedSeconds / 60) min · \(recorder.samples) samples").font(NFont.body(13)).foregroundStyle(NColor.muted)
                    Button(recorder.isPaused ? "RESUME WORKOUT" : "PAUSE WORKOUT") { recorder.togglePause() }.buttonStyle(NButton(secondary: true)).disabled(camera.recording)
                    Button("FINISH & SAVE WORKOUT") { do { try recorder.save(to: store); message = "Workout saved." } catch { message = error.localizedDescription } }.buttonStyle(NButton()).disabled(camera.recording)
                    Button("Discard workout", role: .destructive) { confirmDiscard = true }.font(NFont.body(12)).frame(minHeight: 44).disabled(camera.recording)
                }
            }
        } else {
            NCard {
                VStack(spacing: 10) {
                    TextField("Activity name", text: $name).font(NFont.label(15)).frame(minHeight: 44)
                    Stepper("Resting HR: \(Int(resting))", value: $resting, in: 30...110).font(NFont.body(13))
                    Stepper("Maximum HR: \(Int(maximum))", value: $maximum, in: 120...230).font(NFont.body(13))
                    Text("Use your known resting and maximum HR. Start the workout before recording a camera clip.").font(NFont.body(11)).foregroundStyle(NColor.muted)
                    Button("START LIVE WORKOUT") { do { try recorder.start(name: name, resting: resting, maximum: maximum) } catch { message = error.localizedDescription } }.buttonStyle(NButton()).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    private var photoContent: some View {
        VStack(spacing: 15) {
            DatePicker("Recorded day", selection: $store.selectedDate, in: ...Date(), displayedComponents: .date)
                .environment(\.calendar, DayCalendar.utc).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!).font(NFont.body(13)).frame(minHeight: 44)
                .onChange(of: store.selectedDate) { _, _ in renderedPhoto = nil; exportURL = nil }
            PhotosPicker(selection: $photo, matching: .images) { Label("CHOOSE SAVED PHOTO", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 46) }.font(NFont.label(12)).disabled(busy)
            if let renderedPhoto { Image(uiImage: renderedPhoto).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16)) }
            else if photoData != nil { Text("Photo selected. Choose your recorded date and overlay, then render.").font(NFont.body(13)).foregroundStyle(NColor.muted) }
            else { NEmpty(title: "Your photo, your recorded day", detail: "Choose a photo and apply the stats already saved for that UTC date.", symbol: "photo") }
            if busy { ProgressView("Preparing media…").tint(NColor.cyan) }
            Button("APPLY RECORDED STATS") { renderPhoto() }.buttonStyle(NButton()).disabled(photoData == nil || busy)
            if let exportURL, renderedPhoto != nil {
                ShareLink(item: exportURL) { Label("SHARE PHOTO", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44) }
                Button("SAVE PHOTO TO LIBRARY") { saveToPhotos(video: nil, image: renderedPhoto) }.buttonStyle(NButton(secondary: true)).disabled(busy)
            }
        }
    }
    private func snapshot() -> LiveOverlaySnapshot {
        let day = store.selectedDay, historical = mode == .photo
        let rates = day.heartRates, average = rates.isEmpty ? nil : rates.map(\.bpm).reduce(0, +) / Double(rates.count)
        let hr = historical ? average : recorder.latestHeartRate ?? device.heartRate
        let strain = historical ? day.strain : recorder.localStrain
        let calorieText = historical && day.energyKcal > 0 ? nText(day.energyKcal) : "—"
        let dayLabel = store.days.contains { DayCalendar.utc.isDate($0.date, inSameDayAs: day.date) } ? (day.source == .example ? "EXAMPLE DAY" : "RECORDED DAY") : "NO RECORDED DATA"
        let source = historical ? "\(NutritionDay.key(day.date)) · \(dayLabel)" : "LIVE HR · LOCAL STRAIN ESTIMATE · WORKOUT KCAL UNAVAILABLE"
        var values: [String], labels: [String], hrIndex: Int?
        switch choice {
        case .overview: values = [nText(hr), calorieText, nText(strain, digits: 1)]; labels = [historical ? "DAY AVG BPM" : "LIVE BPM", historical ? "DAY KCAL" : "WORKOUT KCAL", historical ? "DAY STRAIN" : "LOCAL STRAIN EST."]; hrIndex = 0
        case .heartRate: values = [nText(hr)]; labels = [historical ? "DAY AVG BPM" : "LIVE BPM"]; hrIndex = 0
        case .calories: values = [calorieText]; labels = [historical ? "DAY KCAL" : "WORKOUT KCAL"]
        case .strain: values = [nText(strain, digits: 1)]; labels = [historical ? "DAY STRAIN" : "LOCAL STRAIN EST."]
        case .recovery: values = [day.recovery.map { "\($0)%" } ?? "—"]; labels = ["DAY RECOVERY"]
        case .sleep: values = [day.sleepPerformance.map { "\($0)%" } ?? "—"]; labels = ["SLEEP PERFORMANCE"]
        }
        let dayScore = choice == .recovery || choice == .sleep
        return LiveOverlaySnapshot(title: historical || dayScore ? "Recorded day stats" : recorder.name,
            source: dayScore ? "\(NutritionDay.key(day.date)) · \(dayLabel)" : source,
            values: values, labels: labels, heartRateIndex: historical ? nil : hrIndex,
            sampleDate: historical || recorder.isPaused ? nil : recorder.latestSampleDate ?? device.heartRateReceivedAt)
    }
    private func renderPhoto() {
        guard let photoData else { return }
        do { let result = try LiveOverlayRenderer.photo(photoData, snapshot: snapshot()); renderedPhoto = result; exportURL = try writePNG(result); message = "Recorded-date overlay is ready. No new measurements were generated." }
        catch { message = error.localizedDescription }
    }
    private func exportTransparent() {
        do { let image = LiveOverlayRenderer.image(snapshot: snapshot(), size: CGSize(width: 1080, height: 600), transparent: true); exportURL = try writePNG(image); message = "Transparent PNG ready to share." }
        catch { message = error.localizedDescription }
    }
    private func writePNG(_ image: UIImage) throws -> URL {
        guard let data = image.pngData() else { throw LiveCameraError.photo }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stats-\(UUID().uuidString).png")
        try data.write(to: url, options: [.atomic, .completeFileProtection]); return url
    }
    private func saveToPhotos(video: URL?, image: UIImage?) {
        busy = true
        task = Task { @MainActor in
            defer { busy = false }
            guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else { message = "Photo-library saving is unavailable. You can still use Share."; return }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    if let video { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: video) }
                    else if let image { PHAssetChangeRequest.creationRequestForAsset(from: image) }
                }
                message = "Saved to your photo library."
            } catch { message = "The media could not be saved. Try sharing it to Files instead." }
        }
    }
}
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView { let view = PreviewView(); view.preview.session = session; view.preview.videoGravity = .resizeAspectFill; return view }
    func updateUIView(_ view: PreviewView, context: Context) { if let connection = view.preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 } }
}
