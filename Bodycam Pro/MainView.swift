import SwiftUI
import MapKit
import Photos
import CoreLocation
import AVFoundation
import UIKit

struct MainView: View {
    @StateObject private var manager = RecordingManager()
    @StateObject private var locationManager = LocationManager.shared
    
    // MARK: - UI States
    @State private var showRecorder = false
    
    // Selection & Deletion
    @State private var selectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteAllAlert = false
    @State private var showDeleteSelectedAlert = false
    
    // Export States
    @State private var showExportAllAlert = false
    @State private var showExportComplete = false
    @State private var exportedCount = 0

    // Ad tracking
    @State private var deleteActionCount = 0

    // Map State
    @State private var showMap = false
    @State private var selectedMapRecording: Recording?
    @State private var showPaywall = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    // Video player
    @State private var showVideoPlayer = false
    // Rename
    @State private var showRenameSheet = false
    @State private var renameText = ""
    // Tags
    @State private var showTagsSheet = false
    // Metadata detail
    @State private var showDetailSheet = false
    // Shared editing target
    @State private var editingRecording: Recording?

    @ObservedObject private var cloudManager = iCloudManager.shared
    @State private var showEvidenceInfo = false

    @AppStorage("isPremium") private var isPremium = false
    @AppStorage("autoStartRecording") private var autoStartRecording = false

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                // 1. Sleek Background
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {

                        // Header
                        headerView

                        // Premium entry point
                        premiumCta

                        // Main Settings Card
                        configurationSection

                        // Big Action Button
                        startRecordingButton

                        // Native Ad between settings and gallery
                        NativeAdBannerView()

                        Divider()
                            .padding(.vertical)

                        // Gallery Section
                        recordingsGallerySection
                    }
                    .padding()
                    .padding(.bottom, 50)
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .onAppear {
                locationManager.requestPermission()
                if autoStartRecording {
                    // Brief delay so the view is fully on screen before presenting
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showRecorder = true
                    }
                }
            }

            // Present Recording View
            .fullScreenCover(isPresented: $showRecorder, onDismiss: {
                // Show interstitial ad after recording ends if not premium
                if !isPremium {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        AdMobManager.shared.showInterstitialAd()
                    }
                }
            }) {
                RecordingView(manager: manager)
                    .interactiveDismissDisabled(true)
            }
            
            // MARK: - Alerts
            
            // 1. Export All Alert (With Ad Logic)
            .alert("Export All Videos?", isPresented: $showExportAllAlert) {
                Button(isPremium ? "Save All" : "Watch Ad to Save") {
                    attemptExportAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(isPremium ? "Save all \(manager.recordings.count) video(s) to your Photos library." : "Watch a short video to save all \(manager.recordings.count) video(s) to your Photos library.")
            }
            
            // 2. Export Success
            .alert("Export Complete", isPresented: $showExportComplete) {
                Button("OK") {
                    // Show interstitial after export completes if not premium
                    if !isPremium {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            AdMobManager.shared.showInterstitialAd()
                        }
                    }
                }
            } message: {
                Text("Successfully saved \(exportedCount) video(s).")
            }
            
            // 3. Delete All
            .alert("Delete ALL videos?", isPresented: $showDeleteAllAlert) {
                Button("Delete All", role: .destructive) {
                    manager.recordings.forEach { manager.deleteRecording($0) }
                    showInterstitialAfterAction()
                }
                Button("Cancel", role: .cancel) {}
            }

            // 4. Delete Selected
            .alert("Delete selected?", isPresented: $showDeleteSelectedAlert) {
                Button("Delete", role: .destructive) {
                    for rec in manager.recordings where selectedIDs.contains(rec.id) {
                        manager.deleteRecording(rec)
                    }
                    selectedIDs.removeAll()
                    selectMode = false
                    showInterstitialAfterAction()
                }
                Button("Cancel", role: .cancel) {}
            }

            // Full Map Sheet
            .sheet(isPresented: $showMap) {
                if let rec = selectedMapRecording {
                    FullMapView(recording: rec)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityView(items: shareItems)
            }
            .sheet(isPresented: $showVideoPlayer) {
                if let rec = editingRecording {
                    VideoPlayerView(recording: rec)
                }
            }
            .sheet(isPresented: $showRenameSheet) {
                if let rec = editingRecording {
                    RenameSheet(recording: rec, initialName: rec.customName ?? "") { newName in
                        manager.renameRecording(rec, customName: newName)
                    }
                }
            }
            .sheet(isPresented: $showTagsSheet) {
                if let rec = editingRecording {
                    TagsSheet(recording: rec) { tags in
                        manager.updateTags(rec, tags: tags)
                    }
                }
            }
            .sheet(isPresented: $showDetailSheet) {
                if let rec = editingRecording {
                    RecordingDetailSheet(recording: rec)
                }
            }
            // Widget deep link: open and auto-start recording
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WidgetQuickStartRecording"))) { _ in
                showRecorder = true
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("BodyCam")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Text("Pro")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            // GPS Status Indicator
            if locationManager.currentLocation != nil {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("GPS Ready")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.top, 10)
    }

    private var premiumCta: some View {
        if isPremium {
            return AnyView(
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Premium Active")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            )
        }

        return AnyView(
            Button {
                showPaywall = true
            } label: {
                HStack {
                    Image(systemName: "crown.fill")
                    Text("Go Premium")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
            }
        )
    }
    
    private var configurationSection: some View {
            VStack(spacing: 0) {
            // Row 1: Camera & Lens
            HStack {
                settingsMenu(title: "Camera", icon: "camera.fill") {
                    Picker("Camera", selection: $manager.cameraPosition) {
                        Text("Back").tag(AVCaptureDevice.Position.back)
                        Text("Front").tag(AVCaptureDevice.Position.front)
                    }
                }
                
                Spacer()
                
                if manager.cameraPosition == .back {
                    settingsMenu(title: "Lens", icon: "arrow.triangle.2.circlepath.camera") {
                        Picker("Lens", selection: $manager.cameraType) {
                            Text("Standard").tag(CameraType.wide)
                            Text("Ultra-Wide").tag(CameraType.ultraWide)
                        }
                    }
                    Spacer()
                }
                
                settingsMenu(title: "Quality", icon: "4k.tv") {
                    Picker("Resolution", selection: $manager.selectedResolution) {
                        ForEach(Resolution.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Row 2: Sliders & Toggles
            VStack(spacing: 16) {
                // Segment Length
                VStack(alignment: .leading) {
                    HStack {
                        Label("Segment Length", systemImage: "timer")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(manager.segmentLength/60)) min")
                            .font(.system(.body, design: .monospaced))
                            .bold()
                    }
                    Slider(
                        value: Binding(
                            get: { manager.segmentLength / 60 },
                            set: { manager.segmentLength = $0 * 60 }
                        ),
                        in: 1...10,
                        step: 1
                    )
                    .tint(.blue)
                }

                // Audio Toggle
                Toggle(isOn: $manager.audioOn) {
                    Label("Record Audio", systemImage: "mic.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .tint(.blue)

                // Stabilization Toggle
                Toggle(isOn: $manager.enableStabilization) {
                    Label("Stabilization", systemImage: "waveform.path")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .tint(.blue)

                // Auto-Start Toggle
                Toggle(isOn: $autoStartRecording) {
                    Label("Auto-Start on Launch", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .tint(.blue)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $manager.evidenceModeEnabled) {
                        HStack(spacing: 6) {
                            Label("Evidence Mode", systemImage: "checkmark.shield")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Button {
                                showEvidenceInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.subheadline)
                                    .foregroundColor(.blue.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .sheet(isPresented: $showEvidenceInfo) {
                                EvidenceModeInfoSheet()
                            }
                        }
                    }
                    .tint(.blue)

                    if manager.evidenceModeEnabled {
                        Toggle(isOn: $manager.includeTimestampWatermark) {
                            Label("Timestamp Watermark", systemImage: "clock.badge.checkmark")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .tint(.blue)

                        Toggle(isOn: $manager.includeGPSOverlay) {
                            Label("GPS Coordinates Overlay", systemImage: "location.viewfinder")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .tint(.blue)

                        Toggle(isOn: $manager.generateEvidenceSummary) {
                            Label("Export Evidence Summary", systemImage: "doc.text.magnifyingglass")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .tint(.blue)

                        Text("Evidence exports burn timestamp and GPS details into the saved video and generate a tamper-evident summary with SHA-256 hashes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $manager.iCloudBackupEnabled) {
                        Label("iCloud Backup", systemImage: "icloud.and.arrow.up")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .tint(.blue)

                    if manager.iCloudBackupEnabled {
                        if cloudManager.isAvailable {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.icloud").foregroundColor(.green).font(.caption2)
                                Text("Videos are automatically backed up to iCloud.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Button("Back Up All Now") {
                                cloudManager.uploadAll(manager.recordings)
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.icloud").foregroundColor(.orange).font(.caption2)
                                Text("Sign in to iCloud in Settings to enable backup.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // Custom Mini Menu Builder
    private func settingsMenu<Content: View>(title: String, icon: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        Menu {
            content()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
                    .textCase(.uppercase)
            }
            .foregroundColor(.primary)
            .frame(width: 70, height: 60)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
    }
    
    private var startRecordingButton: some View {
        Button {
            showRecorder = true
        } label: {
            HStack {
                Image(systemName: "record.circle")
                Text("Start Recording")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(Color.red)
            .cornerRadius(16)
            .shadow(color: .red.opacity(0.3), radius: 10, y: 5)
        }
    }
    
    private var recordingsGallerySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Text("Library")
                    .font(.title2.bold())
                
                Spacer()
                
                if !manager.recordings.isEmpty {
                    // Actions Menu
                    Menu {
                        Button {
                            withAnimation {
                                selectMode.toggle()
                                selectedIDs.removeAll()
                            }
                        } label: {
                            Label(selectMode ? "Done" : "Select", systemImage: "checkmark.circle")
                        }
                        
                        Divider()
                        
                        Button {
                            // Trigger the Ad/Save Flow
                            showExportAllAlert = true
                        } label: {
                            Label("Save All to Photos", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(role: .destructive) {
                            showDeleteAllAlert = true
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if selectMode {
                HStack {
                    Button("Delete Selected (\(selectedIDs.count))") { showDeleteSelectedAlert = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(selectedIDs.isEmpty)
                    
                    Spacer()
                    
                    Button("Save Selected") { exportSelectedWithConfirmation() }
                        .buttonStyle(.bordered)
                        .disabled(selectedIDs.isEmpty)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if manager.recordings.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.largeTitle)
                        .foregroundColor(.gray.opacity(0.3))
                    Text("No recordings yet")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(manager.recordings) { rec in
                        recordingRow(rec)
                    }
                }
            }
        }
    }
    
    private func recordingRow(_ rec: Recording) -> some View {
        HStack(spacing: 15) {
            if selectMode {
                Image(systemName: selectedIDs.contains(rec.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(selectedIDs.contains(rec.id) ? .blue : .gray.opacity(0.5))
            }

            // Map thumbnail taps open map; plain icon taps open player
            if let lat = rec.latitude, let lon = rec.longitude {
                MapSnapshotView(latitude: lat, longitude: lon)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        selectedMapRecording = rec
                        showMap = true
                    }
            } else {
                Button {
                    editingRecording = rec
                    showVideoPlayer = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: "play.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(rec.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label("\(Int(rec.duration))s", systemImage: "clock")
                    Text("•")
                    Text(formatSize(rec.size))
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if let address = rec.address {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse").font(.caption2)
                        Text(address).font(.caption2).lineLimit(1)
                    }
                    .foregroundColor(.green)
                } else if let lat = rec.latitude, let lon = rec.longitude {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill").font(.caption2)
                        Text("\(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))").font(.caption2)
                    }
                    .foregroundColor(.green)
                }

                // Tags row
                if !rec.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(rec.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            Spacer()

            // iCloud status badge
            if manager.iCloudBackupEnabled {
                iCloudStatusIcon(for: rec)
            }

            Menu {
                Button {
                    editingRecording = rec
                    showVideoPlayer = true
                } label: {
                    Label("Play Video", systemImage: "play.circle")
                }

                Button {
                    editingRecording = rec
                    showDetailSheet = true
                } label: {
                    Label("View Details", systemImage: "info.circle")
                }

                if rec.latitude != nil || rec.longitude != nil {
                    Button {
                        selectedMapRecording = rec
                        showMap = true
                    } label: {
                        Label("View Map", systemImage: "map")
                    }
                }

                Button {
                    editingRecording = rec
                    renameText = rec.customName ?? ""
                    showRenameSheet = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button {
                    editingRecording = rec
                    showTagsSheet = true
                } label: {
                    Label("Edit Tags", systemImage: "tag")
                }

                Button {
                    Task { await shareEvidenceSummary(for: rec) }
                } label: {
                    Label("Share Evidence Summary", systemImage: "doc.badge.arrow.up")
                }

                if manager.iCloudBackupEnabled {
                    Button {
                        cloudManager.upload(rec)
                    } label: {
                        Label("Back Up to iCloud", systemImage: "icloud.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.gray.opacity(0.7))
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectMode {
                toggleSelect(rec.id)
            } else {
                editingRecording = rec
                showVideoPlayer = true
            }
        }
    }

    @ViewBuilder
    private func iCloudStatusIcon(for rec: Recording) -> some View {
        let status = cloudManager.syncStatus(for: rec)
        Image(systemName: status.icon)
            .font(.caption)
            .foregroundColor(status == .uploaded ? .green : status == .uploading ? .blue : .gray.opacity(0.5))
    }
    
    // MARK: - Logic Helpers
    
    private func showInterstitialAfterAction() {
        if isPremium { return }
        deleteActionCount += 1
        // Show interstitial every 2 actions to balance revenue and UX
        if deleteActionCount % 2 == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AdMobManager.shared.showInterstitialAd()
            }
        }
    }

    private func toggleSelect(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
    
    func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes)/(1024*1024)
        return String(format: "%.1f MB", mb)
    }
    
    private func attemptExportAll() {
        // 1. Bypass for Premium
        if isPremium {
            exportAllWithConfirmation()
            return
        }
        
        // 2. Attempt to show Ad
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AdMobManager.shared.showRewardedAd { rewardEarned in
                // We trigger the export if they earned the reward
                // OR if you want to be nice: if the ad failed to load/show.
                if rewardEarned {
                    exportAllWithConfirmation()
                } else {
                    // FALLBACK: Ad failed or was dismissed.
                    // To ensure the user isn't stuck, you can either:
                    // A) Force the save anyway (Good UX if ad failed)
                    // B) Show an alert saying "Ad failed, please try again."
                    
                    print("Ad failed or skipped. Saving anyway to ensure no data loss.")
                    exportAllWithConfirmation()
                }
            }
        }
    }
    private func exportAllWithConfirmation() {
        _ = manager.recordings.count
        var successCount = 0

        Task {
            for rec in manager.recordings {
                do {
                    try await manager.exportRecordingToLibrary(rec)
                    successCount += 1
                } catch {
                    print("Failed to export \(rec.name): \(error)")
                }
            }

            await MainActor.run {
                exportedCount = successCount
                showExportComplete = true
            }
        }
    }
    
    private func exportSelectedWithConfirmation() {
        let selectedRecordings = manager.recordings.filter { selectedIDs.contains($0.id) }
        _ = selectedRecordings.count
        var successCount = 0

        Task {
            for rec in selectedRecordings {
                do {
                    try await manager.exportRecordingToLibrary(rec)
                    successCount += 1
                } catch {
                    print("Failed to export \(rec.name): \(error)")
                }
            }

            await MainActor.run {
                exportedCount = successCount
                showExportComplete = true
            }
        }
    }

    @MainActor
    private func shareEvidenceSummary(for rec: Recording) async {
        do {
            let items = try await manager.prepareEvidenceSummaryFiles(for: rec)
            shareItems = items
            showShareSheet = true
        } catch {
            print("Failed to prepare evidence summary for sharing: \(error)")
        }
    }
}

// MARK: - Map Views

struct MapSnapshotView: View {
    let latitude: Double
    let longitude: Double
    @State private var snapshotImage: UIImage?

    var body: some View {
        Group {
            if let image = snapshotImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.gray.opacity(0.2)
                    Image(systemName: "map")
                        .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            generateSnapshot()
        }
    }

    private func generateSnapshot() {
        let options = MKMapSnapshotter.Options()
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        options.size = CGSize(width: 88, height: 88) // 2x for retina
        options.scale = UIScreen.main.scale

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, error in
            guard let snapshot = snapshot, error == nil else { return }

            // Draw pin on snapshot
            let image = UIGraphicsImageRenderer(size: options.size).image { context in
                snapshot.image.draw(at: .zero)

                // Draw red pin
                let pinPoint = snapshot.point(for: coordinate)
                let pinSize: CGFloat = 20
                let pinRect = CGRect(
                    x: pinPoint.x - pinSize / 2,
                    y: pinPoint.y - pinSize,
                    width: pinSize,
                    height: pinSize
                )

                UIColor.systemRed.setFill()
                let pinPath = UIBezierPath(ovalIn: pinRect)
                pinPath.fill()
            }

            DispatchQueue.main.async {
                self.snapshotImage = image
            }
        }
    }
}

struct FullMapView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition
    @State private var scrubIndex: Double = 0

    init(recording: Recording) {
        self.recording = recording
        // Start camera at the first path point, or the stored location
        let coord: CLLocationCoordinate2D
        if let first = recording.locationPath?.first {
            coord = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
        } else if let lat = recording.latitude, let lon = recording.longitude {
            coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            coord = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
    }

    private var path: [LocationPoint] { recording.locationPath ?? [] }

    private var currentPoint: CLLocationCoordinate2D? {
        guard !path.isEmpty else {
            guard let lat = recording.latitude, let lon = recording.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        let idx = min(Int(scrubIndex), path.count - 1)
        return CLLocationCoordinate2D(latitude: path[idx].latitude, longitude: path[idx].longitude)
    }

    private var currentTimestamp: Date? {
        guard !path.isEmpty else { return nil }
        return path[min(Int(scrubIndex), path.count - 1)].timestamp
    }

    var body: some View {
        NavigationStack {
            Group {
                if recording.latitude != nil || recording.longitude != nil || !path.isEmpty {
                    ZStack(alignment: .bottom) {
                        Map(position: $cameraPosition) {
                            // Full route polyline
                            if path.count > 1 {
                                MapPolyline(
                                    coordinates: path.map {
                                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                                    }
                                )
                                .stroke(.blue.opacity(0.6), lineWidth: 3)
                            }
                            // Current scrub position marker
                            if let coord = currentPoint {
                                Marker("", coordinate: coord)
                                    .tint(.red)
                            }
                        }
                        .mapControls {
                            MapUserLocationButton()
                            MapCompass()
                            MapScaleView()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea(edges: .top)

                        // Bottom info + scrubber panel
                        VStack(spacing: 0) {
                            mapInfoPanel()

                            // Route scrubber — only shown when we have multiple points
                            if path.count > 1 {
                                VStack(spacing: 6) {
                                    HStack {
                                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                            .foregroundColor(.blue)
                                        Text("Route Playback")
                                            .font(.subheadline.bold())
                                        Spacer()
                                        if let ts = currentTimestamp {
                                            Text(ts, style: .time)
                                                .font(.caption.monospacedDigit())
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Slider(value: $scrubIndex, in: 0...Double(path.count - 1), step: 1)
                                        .tint(.red)
                                    HStack {
                                        Text(path.first?.timestamp ?? Date(), style: .time)
                                        Spacer()
                                        Text("\(path.count) pts")
                                        Spacer()
                                        Text(path.last?.timestamp ?? Date(), style: .time)
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(.ultraThinMaterial)
                            }
                        }
                    }
                    .onChange(of: scrubIndex) { _, _ in
                        if let coord = currentPoint {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                cameraPosition = .region(MKCoordinateRegion(
                                    center: coord,
                                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                                ))
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Location Unavailable",
                        systemImage: "map",
                        description: Text("This recording does not have GPS data.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Recording Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func mapInfoPanel() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recording.displayName)
                .font(.headline)

            if let address = recording.address {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse").foregroundColor(.red)
                    Text(address).font(.subheadline).foregroundColor(.secondary)
                }
            }

            if let coord = currentPoint {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill").foregroundColor(.blue)
                    Text(String(format: "%.6f, %.6f", coord.latitude, coord.longitude))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !path.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "point.bottomleft.forward.to.arrowtriangle.uturn.scurvepath").foregroundColor(.green)
                    Text("\(path.count) location points tracked")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Recording Detail Sheet

struct RecordingDetailSheet: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    @State private var evidenceSummary: EvidenceSummary?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                // MARK: File
                Section("File") {
                    detailRow("Name", value: recording.displayName)
                    detailRow("Filename", value: recording.name)
                    detailRow("Duration", value: formatDuration(recording.duration))
                    detailRow("Size", value: formatSize(recording.size))
                    if let date = recording.creation {
                        detailRow("Recorded", value: Self.dateFormatter.string(from: date))
                    }
                }

                // MARK: Location
                if recording.latitude != nil || recording.address != nil {
                    Section("Location") {
                        if let address = recording.address {
                            detailRow("Address", value: address)
                        }
                        if let lat = recording.latitude {
                            detailRow("Latitude", value: String(format: "%.6f°", lat))
                        }
                        if let lon = recording.longitude {
                            detailRow("Longitude", value: String(format: "%.6f°", lon))
                        }
                        if let path = recording.locationPath {
                            detailRow("GPS Points", value: "\(path.count) tracked")
                        }
                    }
                }

                // MARK: Tags
                if !recording.tags.isEmpty {
                    Section("Tags") {
                        Text(recording.tags.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: Evidence Summary (loaded from disk if present)
                if let summary = evidenceSummary {
                    Section("Evidence Summary") {
                        detailRow("Generated", value: Self.dateFormatter.string(from: summary.generatedAt))
                        detailRow("Timestamp Watermark", value: summary.timestampWatermarkIncluded ? "Included" : "Not included")
                        detailRow("GPS Overlay", value: summary.gpsOverlayIncluded ? "Included" : "Not included")
                        detailRow("GPS Points", value: "\(summary.locationPointCount)")
                    }

                    Section("Cryptographic Hashes") {
                        hashRow("Original SHA-256", hash: summary.originalSHA256)
                        hashRow("Exported SHA-256", hash: summary.exportedSHA256)
                    }

                    Section("File Sizes") {
                        detailRow("Original", value: formatSize(summary.originalFileSizeBytes))
                        detailRow("Exported", value: formatSize(summary.exportedFileSizeBytes))
                    }

                    Section("App") {
                        detailRow("Version", value: "\(summary.appVersion) (\(summary.buildNumber))")
                    }
                } else {
                    Section {
                        Label("No evidence summary on file. Export with Evidence Mode enabled to generate one.", systemImage: "checkmark.shield")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Recording Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { loadEvidenceSummary() }
    }

    // MARK: - Helpers

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func hashRow(_ label: String, hash: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(hash)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func loadEvidenceSummary() {
        let evidenceDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Evidence")
        let jsonURL = evidenceDir
            .appendingPathComponent("\(recording.url.deletingPathExtension().lastPathComponent)-evidence.json")

        guard let data = try? Data(contentsOf: jsonURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        evidenceSummary = try? decoder.decode(EvidenceSummary.self, from: data)
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60, s = Int(t) % 60
        return h > 0 ? String(format: "%dh %dm %ds", h, m, s) : String(format: "%dm %ds", m, s)
    }

    private func formatSize(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}

// MARK: - Evidence Mode Info Sheet

struct EvidenceModeInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Hero
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Evidence Mode")
                                .font(.title2.bold())
                            Text("Turn recordings into legally-defensible documents.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, 4)

                    infoCard(
                        icon: "clock.badge.checkmark",
                        iconColor: .orange,
                        title: "Timestamp Watermark",
                        body: "The recording date and time is permanently burned into the video frames — not as removable metadata, but as visible text baked into the pixels. Anyone watching the video can see exactly when it was recorded."
                    )

                    infoCard(
                        icon: "location.viewfinder",
                        iconColor: .green,
                        title: "GPS Coordinates Overlay",
                        body: "Your latitude, longitude, and street address are overlaid onto the video in the same way — permanently embedded into every frame, not attached as metadata that can be stripped."
                    )

                    infoCard(
                        icon: "doc.text.magnifyingglass",
                        iconColor: .blue,
                        title: "Tamper-Evident Summary",
                        body: "When you export, the app computes a SHA-256 cryptographic hash — a unique fingerprint — of both the original and exported file. If anyone modifies even a single frame after export, the hash will no longer match, proving tampering occurred. The summary report includes the hashes, timestamps, GPS data, and app version."
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("When to use it")
                            .font(.headline)
                        Text("Evidence Mode is for situations where you may need to prove **what** happened, **where**, **when**, and that the footage hasn't been edited — workplace incidents, encounters with law enforcement, property disputes, insurance claims, or anything that might involve HR, a lawyer, or a court.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Evidence Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func infoCard(icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text(body)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Rename Sheet

struct RenameSheet: View {
    let recording: Recording
    let initialName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(recording: Recording, initialName: String, onSave: @escaping (String) -> Void) {
        self.recording = recording
        self.initialName = initialName
        self.onSave = onSave
        _text = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Custom Name") {
                    TextField("e.g. Work Commute", text: $text)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("Filename: \(recording.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Rename Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Tags Sheet

private let presetTags = ["Work", "Commute", "Incident", "Travel", "Personal", "Evidence", "Training", "Other"]

struct TagsSheet: View {
    let recording: Recording
    let onSave: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTags: Set<String>
    @State private var customTag = ""

    init(recording: Recording, onSave: @escaping ([String]) -> Void) {
        self.recording = recording
        self.onSave = onSave
        _selectedTags = State(initialValue: Set(recording.tags))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Presets") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(presetTags, id: \.self) { tag in
                            Button {
                                if selectedTags.contains(tag) { selectedTags.remove(tag) }
                                else { selectedTags.insert(tag) }
                            } label: {
                                Text(tag)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(selectedTags.contains(tag) ? Color.blue : Color(uiColor: .secondarySystemBackground))
                                    .foregroundColor(selectedTags.contains(tag) ? .white : .primary)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Custom Tag") {
                    HStack {
                        TextField("Add custom tag…", text: $customTag)
                            .autocorrectionDisabled()
                        Button("Add") {
                            let t = customTag.trimmingCharacters(in: .whitespaces)
                            guard !t.isEmpty else { return }
                            selectedTags.insert(t)
                            customTag = ""
                        }
                        .disabled(customTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if !selectedTags.isEmpty {
                    Section("Selected") {
                        ForEach(Array(selectedTags).sorted(), id: \.self) { tag in
                            HStack {
                                Text(tag)
                                Spacer()
                                Button { selectedTags.remove(tag) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Array(selectedTags).sorted())
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Activity View

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
