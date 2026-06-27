import Foundation
import AVFoundation
import Photos
import UIKit
import os
import CoreLocation
import CryptoKit

@preconcurrency import AVFoundation   // Suppress non-Sendable warnings

private let logger = Logger(subsystem: "BodyCamPro", category: "RecordingManager")

// MARK: - Resolution
enum Resolution: String, CaseIterable, Identifiable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p4K = "4K"

    var id: String { rawValue }

    var preset: AVCaptureSession.Preset {
        switch self {
        case .p720: return .hd1280x720
        case .p1080: return .hd1920x1080
        case .p4K: return .hd4K3840x2160
        }
    }
}

// MARK: - CameraType
enum CameraType: String, CaseIterable, Identifiable {
    case wide = "Wide"
    case ultraWide = "Ultra-Wide"

    var id: String { rawValue }

    var avType: AVCaptureDevice.DeviceType {
        switch self {
        case .wide: return .builtInWideAngleCamera
        case .ultraWide: return .builtInUltraWideCamera
        }
    }
}

// MARK: - Location Data
struct LocationPoint: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}

// MARK: - Recording Model
struct Recording: Identifiable {
    let id = UUID()
    let name: String
    let duration: TimeInterval
    let size: Int64
    let url: URL
    let creation: Date?
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let locationPath: [LocationPoint]?
    var customName: String?
    var tags: [String]

    var displayName: String { customName ?? name }
}

// MARK: - Recording Metadata (for persistence)
struct RecordingMetadata: Codable {
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let locationPath: [LocationPoint]?
    var customName: String?
    var tags: [String]?
}

struct EvidenceSummary: Codable {
    let recordingName: String
    let generatedAt: Date
    let recordingStartedAt: Date?
    let durationSeconds: TimeInterval
    let originalFileSizeBytes: Int64
    let exportedFileSizeBytes: Int64
    let originalSHA256: String
    let exportedSHA256: String
    let latitude: Double?
    let longitude: Double?
    let address: String?
    let locationPointCount: Int
    let timestampWatermarkIncluded: Bool
    let gpsOverlayIncluded: Bool
    let appVersion: String
    let buildNumber: String
}

// MARK: - RecordingManager
@MainActor
class RecordingManager: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var recordings: [Recording] = []
    @Published var segmentLength: TimeInterval = 120
    @Published var selectedResolution: Resolution = .p1080
    @Published var audioOn = true
    @Published var enableStabilization = false
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var cameraType: CameraType = .wide
    @Published var isInterrupted = false
    @Published var isResuming = false
    @Published var interruptionMessage: String?
    @Published var evidenceModeEnabled = false
    @Published var includeTimestampWatermark = true
    @Published var includeGPSOverlay = true
    @Published var generateEvidenceSummary = true
    @Published var iCloudBackupEnabled: Bool = UserDefaults.standard.bool(forKey: "iCloudBackupEnabled") {
        didSet { UserDefaults.standard.set(iCloudBackupEnabled, forKey: "iCloudBackupEnabled") }
    }
    let freeRecordingLimit: TimeInterval = 30 * 60

    var isPremium: Bool {
        SubscriptionManager.shared.isPremium
    }

    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private var segmentTimer: Timer?
    private var isSegmenting = false
    private var activeSegmentURL: URL?
    private var recordingLocation: CLLocation?
    private var recordingPath: [LocationPoint] = []
    private var shouldResumeAfterInterruption = false
    private var shouldStopSessionAfterFinish = false

    override init() {
        super.init()
        createDirectory()
        Task { await loadRecordings() }
        setupSafetyNotifications()
        setupInterruptionNotifications()
    }
    
    // MARK: - Safety Notifications (NEW)
    private func setupSafetyNotifications() {
        // Listen for safe stop requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSafeStop),
            name: NSNotification.Name("SafeStopRecording"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEmergencyStop),
            name: NSNotification.Name("EmergencyStopRecording"),
            object: nil
        )
    }

    private func setupInterruptionNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureSessionInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureSessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: nil
        )
    }
    
    @objc private func handleSafeStop() {
        print("🛡️ Safe stop requested - gracefully stopping recording")
        if isRecording {
            // Stop recording immediately when app backgrounds
            stopRecording()
        }
    }
    
    @objc private func handleEmergencyStop() {
        print("🚨 Emergency stop - forcing immediate save")
        if isRecording {
            isRecording = false
            segmentTimer?.invalidate()
            
            // Force synchronous stop
            movieOutput?.stopRecording()
        }
    }

    // MARK: - Permissions
    private func requestVideo() async -> Bool {
        await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: cont.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { allowed in cont.resume(returning: allowed) }
            default: cont.resume(returning: false)
            }
        }
    }

    private func requestAudio() async -> Bool {
        await withCheckedContinuation { cont in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: cont.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { allowed in cont.resume(returning: allowed) }
            default: cont.resume(returning: false)
            }
        }
    }

    // MARK: - Session Setup
    func prepareSession() async -> Bool {
        let cam = await requestVideo()
        if !cam { return false }

        let mic = audioOn ? await requestAudio() : true

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = selectedResolution.preset

        // Video input
        guard let vdevice = bestDevice() else { return false }
        do {
            let vInput = try AVCaptureDeviceInput(device: vdevice)
            if session.canAddInput(vInput) { session.addInput(vInput); videoInput = vInput }
        } catch { return false }

        // Audio input
        if mic, let micDev = AVCaptureDevice.default(for: .audio) {
            do {
                let aInput = try AVCaptureDeviceInput(device: micDev)
                if session.canAddInput(aInput) { session.addInput(aInput); audioInput = aInput }
            } catch {}
        }

        // Output
        let movie = AVCaptureMovieFileOutput()
        if session.canAddOutput(movie) {
            session.addOutput(movie)
            movieOutput = movie

            // Enable stabilization if requested
            if enableStabilization, let connection = movie.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .standard
                }
            }
        }

        session.commitConfiguration()
        captureSession = session

        // Swift 6 safe – start session on background thread
        await Task.detached {
            session.startRunning()
        }.value

        return true
    }


    private func bestDevice() -> AVCaptureDevice? {
        if cameraPosition == .front {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }

        return AVCaptureDevice.default(cameraType.avType, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    // MARK: - Recording
    func startRecording() {
        guard let output = movieOutput else { return }

        isRecording = true
        let url = nextURL()
        activeSegmentURL = url

        // NEW: Notify safety handler
        SafeRecordingHandler.shared.startRecordingSession(url: url)

        // NEW: Check disk space before starting
        let diskSpace = SafeRecordingHandler.shared.checkDiskSpace()
        if diskSpace.isLow {
            print("⚠️ Low disk space: \(diskSpace.available / 1024 / 1024)MB available")
        }

        // Start location tracking
        LocationManager.shared.startTracking()
        recordingLocation = LocationManager.shared.currentLocation
        recordingPath = []

        // Track location updates during recording
        LocationManager.shared.onLocationUpdate = { [weak self] location in
            guard let self = self, self.isRecording else { return }
            let point = LocationPoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: Date()
            )
            self.recordingPath.append(point)
        }

        output.startRecording(to: url, recordingDelegate: self)
        startSegmentTimer()
    }

    func stopRecording() {
        stopRecordingInternal(endSession: true)
    }

    // MARK: - Segmentation
    private func startSegmentTimer() {
        segmentTimer?.invalidate()

        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentLength, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.rotateSegment() }
        }
    }

    private func rotateSegment() {
        guard isRecording, !isSegmenting else { return }
        isSegmenting = true
        movieOutput?.stopRecording()
    }

    private func stopRecordingInternal(endSession: Bool) {
        guard isRecording else { return }
        isRecording = false
        segmentTimer?.invalidate()
        movieOutput?.stopRecording()

        // Stop location tracking
        LocationManager.shared.stopTracking()
        LocationManager.shared.onLocationUpdate = nil

        // NEW: Notify safety handler
        SafeRecordingHandler.shared.endRecordingSession()

        shouldStopSessionAfterFinish = endSession
    }

    private func stopSession() {
        guard let session = captureSession else { return }
        session.stopRunning()
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
        movieOutput = nil
        videoInput = nil
        audioInput = nil
        captureSession = nil
    }

    // MARK: - File Helpers
    private func nextURL() -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let stamp = df.string(from: Date())
        let random = String(UUID().uuidString.prefix(6))
        return directory().appendingPathComponent("\(stamp)-\(random).mov")
    }

    private func directory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Videos")
    }

    private func evidenceDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Evidence")
    }

    private func createDirectory() {
        try? FileManager.default.createDirectory(at: directory(), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: evidenceDirectory(), withIntermediateDirectories: true)
    }

    // MARK: - Metadata Persistence
    private func metadataURL() -> URL {
        directory().appendingPathComponent("metadata.json")
    }

    private func loadMetadata() -> [String: RecordingMetadata] {
        guard let data = try? Data(contentsOf: metadataURL()),
              let metadata = try? JSONDecoder().decode([String: RecordingMetadata].self, from: data) else {
            return [:]
        }
        return metadata
    }

    private func saveMetadata(_ metadata: [String: RecordingMetadata]) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: metadataURL())
    }

    private func saveRecordingMetadata(filename: String, latitude: Double?, longitude: Double?, address: String?, locationPath: [LocationPoint]?) {
        var metadata = loadMetadata()
        metadata[filename] = RecordingMetadata(latitude: latitude, longitude: longitude, address: address, locationPath: locationPath)
        saveMetadata(metadata)
    }

    private func getRecordingMetadata(filename: String) -> RecordingMetadata? {
        let metadata = loadMetadata()
        return metadata[filename]
    }

    // MARK: - Load existing
    private func loadRecordings() async {
        let fm = FileManager.default
        let dir = directory()
        
        // NEW: Clean up any corrupted files first
        await SafeRecordingHandler.shared.cleanupCorruptedFiles(in: dir)

        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])
        else { return }

        var list: [Recording] = []

        for url in files where url.pathExtension.lowercased() == "mov" {
            // NEW: Verify file integrity before adding to list
            guard SafeRecordingHandler.shared.verifyFileIntegrity(at: url) else {
                print("⚠️ Skipping corrupted file: \(url.lastPathComponent)")
                continue
            }
            
            let attr = try? fm.attributesOfItem(atPath: url.path)
            let size = attr?[.size] as? Int64 ?? 0
            let creation = attr?[.creationDate] as? Date

            let asset = AVAsset(url: url)
            let duration: TimeInterval

            if #available(iOS 16, *) {
                duration = (try? await asset.load(.duration))?.seconds ?? 0
            } else {
                duration = asset.duration.seconds
            }

            // Load GPS metadata if available
            let metadata = getRecordingMetadata(filename: url.lastPathComponent)

            list.append(Recording(name: url.lastPathComponent,
                                  duration: duration,
                                  size: size,
                                  url: url,
                                  creation: creation,
                                  latitude: metadata?.latitude,
                                  longitude: metadata?.longitude,
                                  address: metadata?.address,
                                  locationPath: metadata?.locationPath,
                                  customName: metadata?.customName,
                                  tags: metadata?.tags ?? []))
        }

        recordings = list.sorted { ($0.creation ?? .distantPast) > ($1.creation ?? .distantPast) }
    }

    // MARK: - Export
    func exportAll() {
        for rec in recordings {
            exportRecording(rec)
        }
    }

    func exportRecording(_ rec: Recording) {
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: rec.url)

            // Embed GPS metadata if available
            if let lat = rec.latitude, let lon = rec.longitude {
                request?.location = CLLocation(latitude: lat, longitude: lon)
            }

            // Set creation date if available
            if let creation = rec.creation {
                request?.creationDate = creation
            }
        }
    }

    func exportRecordingToLibrary(_ rec: Recording) async throws {
        let assetURL: URL
        if evidenceModeEnabled {
            assetURL = try await createEvidenceExport(for: rec)
        } else {
            assetURL = rec.url
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: assetURL)

            if let lat = rec.latitude, let lon = rec.longitude {
                request?.location = CLLocation(latitude: lat, longitude: lon)
            }

            if let creation = rec.creation {
                request?.creationDate = creation
            }
        }

        if evidenceModeEnabled && generateEvidenceSummary {
            _ = try createEvidenceSummary(for: rec, exportedURL: assetURL)
        }
    }

    func prepareEvidenceSummaryFiles(for rec: Recording) async throws -> [URL] {
        let exportedURL: URL
        if evidenceModeEnabled {
            exportedURL = try await createEvidenceExport(for: rec)
        } else {
            exportedURL = rec.url
        }

        let jsonURL = try createEvidenceSummary(for: rec, exportedURL: exportedURL)
        let txtURL = evidenceDirectory()
            .appendingPathComponent("\(rec.url.deletingPathExtension().lastPathComponent)-evidence.txt")
        return [txtURL, jsonURL]
    }

    func deleteRecording(_ rec: Recording) {
        try? FileManager.default.removeItem(at: rec.url)
        recordings.removeAll { $0.id == rec.id }

        var metadata = loadMetadata()
        metadata.removeValue(forKey: rec.name)
        saveMetadata(metadata)
    }

    func renameRecording(_ rec: Recording, customName: String) {
        let trimmed = customName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        updateMetadataField(rec: rec) { m in
            RecordingMetadata(latitude: m.latitude, longitude: m.longitude,
                              address: m.address, locationPath: m.locationPath,
                              customName: trimmed, tags: m.tags)
        }
        if let idx = recordings.firstIndex(where: { $0.id == rec.id }) {
            recordings[idx].customName = trimmed
        }
    }

    func updateTags(_ rec: Recording, tags: [String]) {
        updateMetadataField(rec: rec) { m in
            RecordingMetadata(latitude: m.latitude, longitude: m.longitude,
                              address: m.address, locationPath: m.locationPath,
                              customName: m.customName, tags: tags)
        }
        if let idx = recordings.firstIndex(where: { $0.id == rec.id }) {
            recordings[idx].tags = tags
        }
    }

    private func updateMetadataField(rec: Recording, transform: (RecordingMetadata) -> RecordingMetadata) {
        var all = loadMetadata()
        let existing = all[rec.name] ?? RecordingMetadata(latitude: rec.latitude, longitude: rec.longitude,
                                                           address: rec.address, locationPath: rec.locationPath,
                                                           customName: rec.customName, tags: rec.tags)
        all[rec.name] = transform(existing)
        saveMetadata(all)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Evidence Exports
private extension RecordingManager {
    func createEvidenceExport(for rec: Recording) async throws -> URL {
        let asset = AVURLAsset(url: rec.url)
        let composition = AVMutableComposition()

        guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "BodycamPro.EvidenceMode", code: 1, userInfo: [NSLocalizedDescriptionKey: "Video track unavailable"])
        }

        let duration = try await asset.load(.duration)
        try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideoTrack, at: .zero)

        if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceAudioTrack, at: .zero)
        }

        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let transformedSize = naturalSize.applying(preferredTransform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        let overlayLayer = makeEvidenceOverlay(for: rec, renderSize: renderSize)
        parentLayer.addSublayer(overlayLayer)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        let exportURL = evidenceDirectory()
            .appendingPathComponent("\(rec.url.deletingPathExtension().lastPathComponent)-evidence.mov")

        try? FileManager.default.removeItem(at: exportURL)

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "BodycamPro.EvidenceMode", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create export session"])
        }

        exporter.outputURL = exportURL
        exporter.outputFileType = .mov
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = false

        try await export(exporter)
        return exportURL
    }

    func makeEvidenceOverlay(for rec: Recording, renderSize: CGSize) -> CALayer {
        let overlay = CALayer()
        overlay.frame = CGRect(origin: .zero, size: renderSize)
        overlay.masksToBounds = true

        let padding: CGFloat = 24
        let lineHeight: CGFloat = 24
        var lines: [String] = []

        if includeTimestampWatermark {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            let timestamp = formatter.string(from: rec.creation ?? Date())
            lines.append("RECORDED \(timestamp)")
        }

        if includeGPSOverlay, let lat = rec.latitude, let lon = rec.longitude {
            lines.append(String(format: "GPS %.6f, %.6f", lat, lon))
        }

        if let address = rec.address, includeGPSOverlay {
            lines.append(address)
        }

        guard !lines.isEmpty else { return overlay }

        let backdrop = CALayer()
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.58).cgColor
        backdrop.cornerRadius = 14
        backdrop.frame = CGRect(
            x: padding - 10,
            y: renderSize.height - padding - CGFloat(lines.count) * lineHeight - 18,
            width: min(renderSize.width - (padding * 2), renderSize.width * 0.82),
            height: CGFloat(lines.count) * lineHeight + 20
        )
        overlay.addSublayer(backdrop)

        for (index, line) in lines.enumerated() {
            let textLayer = CATextLayer()
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .semibold)
            textLayer.fontSize = 16
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.alignmentMode = .left
            textLayer.string = line
            textLayer.frame = CGRect(
                x: padding,
                y: renderSize.height - padding - CGFloat(lines.count - index) * lineHeight,
                width: backdrop.frame.width - 20,
                height: lineHeight
            )
            overlay.addSublayer(textLayer)
        }

        return overlay
    }

    func export(_ exporter: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            // Capture status/error before entering the Sendable closure to avoid
            // capturing the non-Sendable AVAssetExportSession across concurrency boundaries.
            exporter.exportAsynchronously { [status = exporter.status, exportError = exporter.error] in
                switch status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    let error = exportError ?? NSError(
                        domain: "BodycamPro.EvidenceMode",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Evidence export failed"]
                    )
                    continuation.resume(throwing: error)
                default:
                    let error = NSError(
                        domain: "BodycamPro.EvidenceMode",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Evidence export ended in unexpected state"]
                    )
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func createEvidenceSummary(for rec: Recording, exportedURL: URL) throws -> URL {
        let summary = EvidenceSummary(
            recordingName: rec.name,
            generatedAt: Date(),
            recordingStartedAt: rec.creation,
            durationSeconds: rec.duration,
            originalFileSizeBytes: rec.size,
            exportedFileSizeBytes: fileSize(for: exportedURL),
            originalSHA256: try sha256(for: rec.url),
            exportedSHA256: try sha256(for: exportedURL),
            latitude: rec.latitude,
            longitude: rec.longitude,
            address: rec.address,
            locationPointCount: rec.locationPath?.count ?? 0,
            timestampWatermarkIncluded: includeTimestampWatermark,
            gpsOverlayIncluded: includeGPSOverlay,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        )

        let jsonURL = evidenceDirectory()
            .appendingPathComponent("\(rec.url.deletingPathExtension().lastPathComponent)-evidence.json")
        let txtURL = evidenceDirectory()
            .appendingPathComponent("\(rec.url.deletingPathExtension().lastPathComponent)-evidence.txt")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(summary)
        try jsonData.write(to: jsonURL, options: .atomic)

        try renderEvidenceText(from: summary).write(to: txtURL, atomically: true, encoding: .utf8)
        return jsonURL
    }

    func renderEvidenceText(from summary: EvidenceSummary) -> String {
        [
            "Bodycam Pro Evidence Summary",
            "Recording: \(summary.recordingName)",
            "Generated: \(ISO8601DateFormatter().string(from: summary.generatedAt))",
            "Recorded At: \(summary.recordingStartedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "Unknown")",
            String(format: "Duration: %.2f seconds", summary.durationSeconds),
            "Original Size: \(summary.originalFileSizeBytes) bytes",
            "Exported Size: \(summary.exportedFileSizeBytes) bytes",
            "Original SHA256: \(summary.originalSHA256)",
            "Exported SHA256: \(summary.exportedSHA256)",
            summary.latitude.map { String(format: "Latitude: %.6f", $0) } ?? "Latitude: Unavailable",
            summary.longitude.map { String(format: "Longitude: %.6f", $0) } ?? "Longitude: Unavailable",
            "Address: \(summary.address ?? "Unavailable")",
            "Tracked Points: \(summary.locationPointCount)",
            "Timestamp Watermark: \(summary.timestampWatermarkIncluded ? "Included" : "Not included")",
            "GPS Overlay: \(summary.gpsOverlayIncluded ? "Included" : "Not included")",
            "App Version: \(summary.appVersion) (\(summary.buildNumber))"
        ]
        .joined(separator: "\n")
    }

    func sha256(for url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw NSError(domain: "BodycamPro.EvidenceMode", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unable to read file for hashing"])
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1024 * 1024)
            if data.isEmpty {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func fileSize(for url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int64 ?? 0
    }
}

// MARK: - Delegate
extension RecordingManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {

        Task { @MainActor in

            let asset = AVAsset(url: outputFileURL)
            let duration: TimeInterval

            if #available(iOS 16, *) {
                duration = (try? await asset.load(.duration))?.seconds ?? 0
            } else {
                duration = asset.duration.seconds
            }

            let attrs = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)
            let size = attrs?[.size] as? Int64 ?? 0
            let creation = attrs?[.creationDate] as? Date

            // Save location data
            let latitude = self.recordingLocation?.coordinate.latitude
            let longitude = self.recordingLocation?.coordinate.longitude
            let path = self.recordingPath.isEmpty ? nil : self.recordingPath

            // Get address via reverse geocoding
            var address: String?
            if let location = self.recordingLocation {
                address = await LocationManager.shared.getAddress(for: location)
            }

            // Persist GPS metadata to disk
            self.saveRecordingMetadata(filename: outputFileURL.lastPathComponent,
                                       latitude: latitude,
                                       longitude: longitude,
                                       address: address,
                                       locationPath: path)

            let newRecording = Recording(name: outputFileURL.lastPathComponent,
                          duration: duration,
                          size: size,
                          url: outputFileURL,
                          creation: creation,
                          latitude: latitude,
                          longitude: longitude,
                          address: address,
                          locationPath: path,
                          customName: nil,
                          tags: [])
            recordings.insert(newRecording, at: 0)

            if self.iCloudBackupEnabled {
                iCloudManager.shared.upload(newRecording)
            }

            if self.isRecording {
                let newURL = self.nextURL()
                output.startRecording(to: newURL, recordingDelegate: self)
                self.isSegmenting = false
                self.activeSegmentURL = newURL
            } else {
                // Recording stopped - end background task immediately
                SafeRecordingHandler.shared.endRecordingSession()
                if self.shouldStopSessionAfterFinish {
                    self.shouldStopSessionAfterFinish = false
                    self.stopSession()
                }
            }
        }
    }
}

// MARK: - Interruption Handling
private extension RecordingManager {
    @objc func handleAudioInterruption(_ notification: Notification) {
        Task { @MainActor in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }

            switch type {
            case .began:
                interruptionMessage = "Audio interruption"
                isInterrupted = true
                if isRecording {
                    shouldResumeAfterInterruption = true
                    stopRecordingInternal(endSession: true)
                }
            case .ended:
                if shouldResumeAfterInterruption {
                    shouldResumeAfterInterruption = false
                    isResuming = true
                    interruptionMessage = "Resuming..."
                    let ok = await prepareSession()
                    if ok {
                        startRecording()
                    }
                    isResuming = false
                    isInterrupted = false
                    interruptionMessage = nil
                } else {
                    isInterrupted = false
                    interruptionMessage = nil
                }
            @unknown default:
                isInterrupted = false
                interruptionMessage = nil
            }
        }
    }

    @objc func handleCaptureSessionInterrupted(_ notification: Notification) {
        Task { @MainActor in
            let reasonValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber
            let reason = reasonValue.flatMap { AVCaptureSession.InterruptionReason(rawValue: $0.intValue) }
            switch reason {
            case .audioDeviceInUseByAnotherClient:
                interruptionMessage = "Microphone in use"
            case .videoDeviceInUseByAnotherClient:
                interruptionMessage = "Camera in use"
            case .videoDeviceNotAvailableInBackground:
                interruptionMessage = "Camera unavailable in background"
            case .videoDeviceNotAvailableWithMultipleForegroundApps:
                interruptionMessage = "Camera unavailable with multiple apps"
            default:
                interruptionMessage = "Camera interrupted"
            }

            isInterrupted = true
            if isRecording {
                shouldResumeAfterInterruption = true
                stopRecordingInternal(endSession: true)
            }
        }
    }

    @objc func handleCaptureSessionInterruptionEnded(_ notification: Notification) {
        Task { @MainActor in
            if shouldResumeAfterInterruption {
                shouldResumeAfterInterruption = false
                isResuming = true
                interruptionMessage = "Resuming..."
                let ok = await prepareSession()
                if ok {
                    startRecording()
                }
                isResuming = false
                isInterrupted = false
                interruptionMessage = nil
            } else {
                isInterrupted = false
                interruptionMessage = nil
            }
        }
    }
}
