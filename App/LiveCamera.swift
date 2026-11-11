import Foundation
import Combine
@preconcurrency import AVFoundation
import CoreImage
import AudioToolbox
import UIKit
import ImageIO
import WHOOPCore

struct LiveOverlaySnapshot: Equatable, Sendable {
    var title: String
    var source: String
    var values: [String]
    var labels: [String]
    var heartRateIndex: Int?
    var sampleDate: Date?
    var referenceMode: CameraOverlayMode? = nil
    var referenceMetrics: [CameraOverlayMetric]? = nil
    func rendered(at now: Date) -> [String] {
        var result = values
        if let index = heartRateIndex, result.indices.contains(index), sampleDate.map({ !(0...10).contains(now.timeIntervalSince($0)) }) ?? true { result[index] = referenceMode == .live ? "Connect" : "—" }
        return result
    }
}
enum LiveOverlayRenderer {
    static func image(snapshot: LiveOverlaySnapshot, size: CGSize, transparent: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.opaque = false; format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if let mode = snapshot.referenceMode, let metrics = snapshot.referenceMetrics {
                drawReference(snapshot: snapshot, mode: mode, metrics: metrics, size: size, context: context.cgContext)
                return
            }
            let width = size.width, panelHeight = min(size.height * 0.80, size.width * 0.35)
            let panel = CGRect(x: width * 0.05, y: size.height - panelHeight - width * 0.03, width: width * 0.90, height: panelHeight)
            if !transparent { UIColor.black.withAlphaComponent(0.55).setFill(); UIBezierPath(roundedRect: panel, cornerRadius: width * 0.025).fill() }
            let heading = UIFont.systemFont(ofSize: width * 0.021, weight: .semibold)
            let title = snapshot.title.uppercased() as NSString
            title.draw(at: CGPoint(x: panel.minX + width * 0.03, y: panel.minY + width * 0.025), withAttributes: [.font: heading, .foregroundColor: UIColor.white])
            let values = snapshot.rendered(at: Date()), count = max(1, values.count), column = (panel.width - width * 0.06) / CGFloat(count)
            for (index, value) in values.enumerated() {
                let x = panel.minX + width * 0.03 + CGFloat(index) * column
                let font = UIFont.systemFont(ofSize: width * (count == 1 ? 0.10 : 0.064), weight: .bold)
                (value as NSString).draw(in: CGRect(x: x, y: panel.minY + panel.height * 0.29, width: column, height: panel.height * 0.42), withAttributes: [.font: font, .foregroundColor: UIColor.white])
                if snapshot.labels.indices.contains(index) {
                    (snapshot.labels[index] as NSString).draw(in: CGRect(x: x, y: panel.minY + panel.height * 0.70, width: column - 4, height: panel.height * 0.13), withAttributes: [.font: UIFont.systemFont(ofSize: width * 0.016, weight: .medium), .foregroundColor: UIColor(white: 0.85, alpha: 1)])
                }
            }
            (snapshot.source as NSString).draw(in: CGRect(x: panel.minX + width * 0.03, y: panel.maxY - width * 0.025, width: panel.width - width * 0.06, height: width * 0.02), withAttributes: [.font: UIFont.systemFont(ofSize: width * 0.013, weight: .medium), .foregroundColor: UIColor(white: 0.75, alpha: 1)])
            _ = context
        }
    }
    static func photo(_ data: Data, snapshot: LiveOverlaySnapshot) throws -> UIImage {
        guard data.count <= 30 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2_048] as CFDictionary) else { throw LiveCameraError.photo }
        let base = UIImage(cgImage: thumbnail)
        let originalSize = CGSize(width: CGFloat(thumbnail.width), height: CGFloat(thumbnail.height))
        let cropWidth = min(originalSize.width, originalSize.height * 9 / 16)
        let size = snapshot.referenceMode == nil ? originalSize : CGSize(width: cropWidth, height: cropWidth * 16 / 9)
        let scale = max(size.width / originalSize.width, size.height / originalSize.height)
        let drawRect = CGRect(x: (size.width - originalSize.width * scale) / 2,
                              y: (size.height - originalSize.height * scale) / 2,
                              width: originalSize.width * scale, height: originalSize.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in base.draw(in: drawRect); image(snapshot: snapshot, size: size, transparent: false).draw(in: CGRect(origin: .zero, size: size)) }
    }
}
enum LiveCameraError: LocalizedError, Sendable {
    case unavailable, photo, record
    var errorDescription: String? {
        switch self { case .unavailable: return "The camera could not start. Check camera access in iPhone Settings."; case .photo: return "Choose a supported photo below 30 MB."; case .record: return "The video could not be saved. Check free storage and try a shorter recording." }
    }
}

/// Session/writer mutations are confined to one queue. Telemetry crosses through a lock.
final class LiveCaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "live.capture.frames", qos: .userInitiated)
    private let lock = NSLock()
    private var snapshot = LiveOverlaySnapshot(title: "Live workout", source: "No connected measurements", values: ["—"], labels: ["LIVE BPM"], heartRateIndex: 0, sampleDate: nil)
    private var position: AVCaptureDevice.Position = .back
    private var input: AVCaptureDeviceInput?
    private let video = AVCaptureVideoDataOutput()
    private let audio = AVCaptureAudioDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var pendingPhoto: (id: UUID, requestID: Int64, state: LiveOverlaySnapshot, completion: @Sendable (Result<URL, LiveCameraError>) -> Void)?
    private var hasAudio = false
    private var configured = false
    private var requested = false
    private var finishing = false
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var started: CMTime?
    private var outputURL: URL?
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private var overlay: CIImage?
    private var overlayKey = ""
    var onFinish: (@Sendable (Result<URL, LiveCameraError>) -> Void)?
    func update(_ snapshot: LiveOverlaySnapshot) { lock.lock(); self.snapshot = snapshot; lock.unlock() }
    func prepare(audioAllowed: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            guard !self.requested, !self.finishing, self.pendingPhoto == nil else { completion(false); return }
            if !self.requested {
                self.session.beginConfiguration()
                for input in self.session.inputs { self.session.removeInput(input) }
                for output in self.session.outputs { self.session.removeOutput(output) }
                self.configured = false; self.hasAudio = false; self.input = nil
                self.session.sessionPreset = .hd1280x720
                do {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.position) else { throw LiveCameraError.unavailable }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input), self.session.canAddOutput(self.video) else { throw LiveCameraError.unavailable }
                    self.session.addInput(input); self.input = input
                    self.video.alwaysDiscardsLateVideoFrames = true
                    self.video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    self.video.setSampleBufferDelegate(self, queue: self.queue); self.session.addOutput(self.video)
                    if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
                    if let photoConnection = self.photoOutput.connection(with: .video), photoConnection.isVideoRotationAngleSupported(90) { photoConnection.videoRotationAngle = 90 }
                    if let connection = self.video.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    if audioAllowed, let microphone = AVCaptureDevice.default(for: .audio), let mic = try? AVCaptureDeviceInput(device: microphone), self.session.canAddInput(mic), self.session.canAddOutput(self.audio) {
                        self.session.addInput(mic); self.audio.setSampleBufferDelegate(self, queue: self.queue); self.session.addOutput(self.audio); self.hasAudio = true
                    }
                    self.configured = true
                } catch { self.session.commitConfiguration(); completion(false); return }
                self.session.commitConfiguration()
            }
            if !self.session.isRunning { self.session.startRunning() }
            completion(true)
        }
    }
    func flip() {
        queue.async {
            guard !self.requested, self.pendingPhoto == nil, let old = self.input else { return }
            self.turnTorchOff()
            let position: AVCaptureDevice.Position = self.position == .back ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position), let new = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration(); self.session.removeInput(old)
            if self.session.canAddInput(new) { self.session.addInput(new); self.input = new; self.position = position } else { self.session.addInput(old) }
            if let connection = self.video.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                if connection.isVideoMirroringSupported { connection.isVideoMirrored = self.position == .front }
            }
            if let connection = self.photoOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                if connection.isVideoMirroringSupported { connection.isVideoMirrored = self.position == .front }
            }
            self.session.commitConfiguration()
        }
    }
    func record(completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            guard self.configured, !self.finishing, !self.requested else { completion(false); return }
            if !self.session.isRunning { self.session.startRunning() }
            guard self.session.isRunning else { completion(false); return }
            self.requested = true; completion(true)
        }
    }
    func stop() { queue.async { self.finish() } }
    func shutdown() { queue.async {
        self.finish(); self.turnTorchOff()
        let pending = self.pendingPhoto; self.pendingPhoto = nil; pending?.completion(.failure(.unavailable))
        if self.session.isRunning { self.session.stopRunning() }
    } }
    func setTorch(_ enabled: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            guard let device = self.input?.device, device.hasTorch, device.isTorchAvailable else { completion(false); return }
            do {
                try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                if enabled { try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel) } else { device.torchMode = .off }
                completion(true)
            } catch { completion(false) }
        }
    }
    private func turnTorchOff() {
        guard let device = input?.device, device.hasTorch else { return }
        do { try device.lockForConfiguration(); device.torchMode = .off; device.unlockForConfiguration() } catch { }
    }
    func capturePhoto(state: LiveOverlaySnapshot, completion: @escaping @Sendable (Result<URL, LiveCameraError>) -> Void) {
        queue.async {
            guard self.configured, self.session.isRunning, !self.requested, !self.finishing,
                  self.pendingPhoto == nil, self.photoOutput.connection(with: .video) != nil else { completion(.failure(.unavailable)); return }
            let id = UUID()
            let settings = AVCapturePhotoSettings(); settings.flashMode = .off
            self.pendingPhoto = (id, settings.uniqueID, state, completion)
            self.photoOutput.capturePhoto(with: settings, delegate: self)
            self.queue.asyncAfter(deadline: .now() + 15) {
                guard self.pendingPhoto?.id == id else { return }
                self.pendingPhoto = nil; completion(.failure(.photo))
            }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation(), failed = error != nil, requestID = photo.resolvedSettings.uniqueID
        queue.async {
            guard let pending = self.pendingPhoto, pending.requestID == requestID else { return }; self.pendingPhoto = nil
            do {
                guard !failed, let data else { throw LiveCameraError.photo }
                let image = try LiveOverlayRenderer.photo(data, snapshot: pending.state)
                guard let png = image.pngData() else { throw LiveCameraError.photo }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-photo-\(UUID().uuidString).png")
                try png.write(to: url, options: [.atomic, .completeFileProtection]); pending.completion(.success(url))
            } catch { pending.completion(.failure(.photo)) }
        }
    }
    private func begin(_ buffer: CVPixelBuffer, time: CMTime) throws {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_500_000]])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw LiveCameraError.record }; writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        if hasAudio {
            let sound = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1, AVSampleRateKey: 44_100, AVEncoderBitRateKey: 64_000])
            sound.expectsMediaDataInRealTime = true
            if writer.canAdd(sound) { writer.add(sound); audioInput = sound }
        }
        guard writer.startWriting() else { throw LiveCameraError.record }
        writer.startSession(atSourceTime: time)
        self.writer = writer; self.videoInput = input; self.adaptor = adaptor; outputURL = url; started = time; overlayKey = ""; overlay = nil
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard requested, !finishing else { return }
        autoreleasepool {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if output === audio {
                if let started, CMTimeCompare(time, started) >= 0, let audioInput, audioInput.isReadyForMoreMediaData { _ = audioInput.append(sampleBuffer) }; return
            }
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            do { if writer == nil { try begin(buffer, time: time) } } catch { requested = false; onFinish?(.failure(.record)); return }
            if let started, CMTimeGetSeconds(CMTimeSubtract(time, started)) >= 300 { finish(); return }
            guard writer?.status == .writing, let videoInput, videoInput.isReadyForMoreMediaData, let adaptor, let pool = adaptor.pixelBufferPool else { return }
            lock.lock(); let state = snapshot; lock.unlock()
            let key = state.rendered(at: Date()).joined(separator: "|") + state.source + state.title
                + (state.referenceMode?.rawValue ?? "standard") + String(describing: state.referenceMetrics)
            if key != overlayKey {
                let image = LiveOverlayRenderer.image(snapshot: state, size: CGSize(width: CGFloat(CVPixelBufferGetWidth(buffer)), height: CGFloat(CVPixelBufferGetHeight(buffer))), transparent: false)
                if let cg = image.cgImage { overlay = CIImage(cgImage: cg) }; overlayKey = key
            }
            var target: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &target) == kCVReturnSuccess, let target else { return }
            let image = CIImage(cvPixelBuffer: buffer)
            ci.render(overlay?.composited(over: image) ?? image, to: target)
            if !adaptor.append(target, withPresentationTime: time) { finish() }
        }
    }
    private func finish() {
        let wasRequested = requested
        requested = false
        guard let writer, !finishing else { if wasRequested { onFinish?(.failure(.record)) }; return }
        guard writer.status == .writing else {
            self.writer = nil; self.videoInput = nil; self.audioInput = nil; self.adaptor = nil; self.started = nil
            if let outputURL { try? FileManager.default.removeItem(at: outputURL) }; self.outputURL = nil
            onFinish?(.failure(.record)); return
        }
        finishing = true; videoInput?.markAsFinished(); audioInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { return }
            self.queue.async {
                let result: Result<URL, LiveCameraError>
                if writer.status == .completed, let url = self.outputURL { result = .success(url) } else { result = .failure(.record) }
                self.writer = nil; self.videoInput = nil; self.audioInput = nil; self.adaptor = nil; self.started = nil; self.finishing = false; self.outputURL = nil
                self.onFinish?(result)
            }
        }
    }
}

@MainActor
final class LiveCameraModel: ObservableObject {
    let engine = LiveCaptureEngine()
    @Published private(set) var ready = false
    @Published private(set) var recording = false
    @Published private(set) var starting = false
    @Published private(set) var movie: URL?
    @Published private(set) var status = "Open the camera when you are ready."
    func open(microphone: Bool) async {
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard !Task.isCancelled else { return }
        guard allowed else { status = "Camera access is off. Allow it in iPhone Settings, or use the photo overlay instead."; return }
        let audio = microphone ? await AVCaptureDevice.requestAccess(for: .audio) : false
        guard !Task.isCancelled else { return }
        engine.onFinish = { [weak self] result in Task { @MainActor in
            guard let self else { return }; self.recording = false
            switch result { case .success(let url): self.movie = url; self.status = "Video ready to save or share."; case .failure(let error): self.status = error.localizedDescription }
        } }
        engine.prepare(audioAllowed: audio) { [weak self] ok in Task { @MainActor in self?.ready = ok; self?.status = ok ? (audio ? "Camera and microphone ready." : "Camera ready · video only.") : LiveCameraError.unavailable.localizedDescription } }
    }
    func start() {
        guard ready, !recording, !starting else { return }
        starting = true; movie = nil
        engine.record { [weak self] accepted in Task { @MainActor in
            self?.starting = false; self?.recording = accepted
            self?.status = accepted ? "Recording with your current stats · up to five minutes." : "The camera is not ready. Open it again and retry."
        } }
    }
    func stop() { guard recording else { return }; status = "Finishing video…"; engine.stop() }
    func close() { engine.shutdown(); ready = false }
}

extension LiveOverlayRenderer {
    /// One drawing implementation is used by preview, still photos and movie frames.
    private static func drawReference(snapshot: LiveOverlaySnapshot, mode: CameraOverlayMode,
                                      metrics: [CameraOverlayMetric], size: CGSize, context: CGContext) {
        let w = size.width, h = size.height
        func font(_ points: CGFloat) -> UIFont { UIFont(name: "DINPro-Bold", size: points) ?? .systemFont(ofSize: points, weight: .bold) }
        func text(_ value: String, center: CGPoint, size: CGFloat, color: UIColor = .white, tracking: CGFloat = 0) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font(size), .foregroundColor: color, .kern: tracking]
            let label = NSAttributedString(string: value, attributes: attributes), bounds = label.size()
            label.draw(at: CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
        }
        func label(_ value: String, rect: CGRect, size: CGFloat, color: UIColor = .white) {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineSpacing = w * 0.004
            (value as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                    attributes: [.font: font(size), .foregroundColor: color, .kern: w * 0.004,
                                                 .paragraphStyle: paragraph], context: nil)
        }
        func color(_ tone: CameraOverlayTone) -> UIColor {
            switch tone {
            case .cyan: return UIColor(red: 0, green: 0.623, blue: 0.906, alpha: 1)
            case .green: return UIColor(red: 0.07, green: 0.88, blue: 0.13, alpha: 1)
            case .yellow: return UIColor(red: 1, green: 0.89, blue: 0, alpha: 1)
            case .red: return UIColor(red: 1, green: 0, blue: 0.18, alpha: 1)
            case .neutral: return UIColor.white.withAlphaComponent(0.35)
            }
        }
        func brand(in rect: CGRect) {
            context.saveGState(); context.addPath(WhoopWordmark.drawingPath(in: rect).cgPath)
            context.setFillColor(UIColor.white.cgColor); context.fillPath(); context.restoreGState()
        }
        func number(_ value: String, center: CGPoint, size: CGFloat) {
            let parts = NSMutableAttributedString(string: value.hasSuffix("%") ? String(value.dropLast()) : value,
                                                 attributes: [.font: font(size), .foregroundColor: UIColor.white])
            if value.hasSuffix("%") { parts.append(NSAttributedString(string: "%", attributes: [.font: font(size * 0.48), .foregroundColor: UIColor.white])) }
            let bounds = parts.size()
            parts.draw(at: CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
        }
        func ring(_ metric: CameraOverlayMetric, center: CGPoint, diameter: CGFloat, stroke: CGFloat, big: Bool, compact: Bool = false) {
            let radius = (diameter - stroke) / 2
            context.saveGState(); context.setLineWidth(stroke); context.setLineCap(.butt)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.27).cgColor)
            context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false); context.strokePath()
            if let progress = metric.fraction, progress > 0, metric.available {
                context.setStrokeColor(color(metric.tone).cgColor)
                context.addArc(center: center, radius: radius, startAngle: -.pi / 2 + 0.006,
                               endAngle: -.pi / 2 + .pi * 2 * progress - 0.006, clockwise: false); context.strokePath()
            }
            context.restoreGState()
            if big {
                brand(in: CGRect(x: center.x - w * 0.12, y: center.y - w * 0.184, width: w * 0.24, height: w * 0.039))
                number(metric.value, center: CGPoint(x: center.x, y: center.y + w * 0.012), size: metric.available ? w * 0.22 : w * 0.11)
                label(metric.label.replacingOccurrences(of: "\n", with: " "), rect: CGRect(x: center.x - w * 0.32, y: center.y + w * 0.171, width: w * 0.64, height: w * 0.09), size: w * 0.035)
            } else {
                number(metric.value, center: center, size: compact ? w * 0.048 : metric.available ? w * 0.083 : w * 0.043)
                label(compact ? metric.label.replacingOccurrences(of: " ", with: "\n") : metric.label, rect: CGRect(x: center.x - w * 0.145, y: center.y + diameter / 2 + w * (compact ? 0.02 : 0.04),
                                                width: w * 0.29, height: w * 0.09), size: w * (compact ? 0.0225 : 0.025))
            }
        }
        if mode == .overview || mode == .live {
            brand(in: CGRect(x: w * 0.755, y: h * 0.035, width: w * 0.165, height: w * 0.027))
        }
        // Source/date stays in exported media too; illustrative values remain labeled.
        text(snapshot.source, center: CGPoint(x: w / 2, y: h * 0.095), size: w * 0.021,
             color: UIColor.white.withAlphaComponent(0.8), tracking: w * 0.001)
        switch mode {
        case .overview:
            for (index, metric) in metrics.prefix(3).enumerated() {
                ring(metric, center: CGPoint(x: w * (0.205 + CGFloat(index) * 0.295), y: h * 0.713),
                     diameter: w * 0.222, stroke: w * 0.011, big: false)
            }
        case .strain, .recovery, .sleep:
            if let metric = metrics.first { ring(metric, center: CGPoint(x: w / 2, y: h / 2), diameter: w * 0.75, stroke: w * 0.038, big: true) }
        case .live:
            guard metrics.count == 4 else { return }
            let cardX = w * 0.71, cardW = w * 0.255
            for index in 1...3 {
                let cardH = index == 3 ? h * 0.06 : h * 0.156
                let y = index == 1 ? h * 0.066 : index == 2 ? h * 0.236 : h * 0.406
                UIColor.black.withAlphaComponent(0.78).setFill()
                UIBezierPath(roundedRect: CGRect(x: cardX, y: y, width: cardW, height: cardH), cornerRadius: w * 0.014).fill()
                if index == 1 {
                    ring(metrics[index], center: CGPoint(x: cardX + cardW / 2, y: y + cardH * 0.40), diameter: w * 0.15, stroke: w * 0.008, big: false, compact: true)
                } else {
                    text(metrics[index].value, center: CGPoint(x: cardX + cardW / 2, y: y + cardH * 0.43), size: w * (index == 3 ? 0.037 : 0.058))
                    text(metrics[index].label, center: CGPoint(x: cardX + cardW / 2, y: y + cardH * 0.78), size: w * 0.023, tracking: w * 0.002)
                }
            }
            let center = CGPoint(x: w * 0.5, y: h * 0.718), radius = w * 0.142
            UIColor.black.withAlphaComponent(0.8).setFill(); UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
            text("♥", center: CGPoint(x: center.x, y: center.y - w * 0.075), size: w * 0.045)
            let rate = snapshot.rendered(at: Date()).first ?? "Connect"
            text(rate, center: center, size: Double(rate) == nil ? w * 0.042 : w * 0.115)
            text("BPM", center: CGPoint(x: center.x, y: center.y + w * 0.082), size: w * 0.025, tracking: w * 0.004)
        }
    }
}
