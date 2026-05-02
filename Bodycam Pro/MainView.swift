import SwiftUI
import MapKit
import Photos
import CoreLocation
import AVFoundation

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

    @AppStorage("isPremium") private var isPremium = false

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

            // Icon or Map Thumbnail
            if let lat = rec.latitude, let lon = rec.longitude {
                MapSnapshotView(latitude: lat, longitude: lon)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        selectedMapRecording = rec
                        showMap = true
                    }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: "play.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(rec.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label("\(Int(rec.duration))s", systemImage: "clock")
                    Text("•")
                    Text(formatSize(rec.size))
                }
                .font(.caption)
                .foregroundColor(.secondary)

                // Location info if available
                if let address = rec.address {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2)
                        Text(address)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundColor(.green)
                } else if let lat = rec.latitude, let lon = rec.longitude {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                        Text("\(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))")
                            .font(.caption2)
                    }
                    .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .onTapGesture {
            if selectMode {
                toggleSelect(rec.id)
            }
        }
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
                    try await PHPhotoLibrary.shared().performChanges {
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
                    try await PHPhotoLibrary.shared().performChanges {
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

    var body: some View {
        NavigationStack {
            Group {
                if let lat = recording.latitude, let lon = recording.longitude {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))) {
                        Marker(
                            "Recording Location",
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        )
                        .tint(.red)

                        if let path = recording.locationPath, path.count > 1 {
                            MapPolyline(
                                coordinates: path.map {
                                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                                }
                            )
                            .stroke(.blue, lineWidth: 3)
                        }
                    }
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        mapInfoPanel(lat: lat, lon: lon)
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
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mapInfoPanel(lat: Double, lon: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recording.name)
                .font(.headline)

            if let address = recording.address {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.red)
                    Text(address)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                Text("\(String(format: "%.6f", lat)), \(String(format: "%.6f", lon))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let path = recording.locationPath {
                HStack(spacing: 8) {
                    Image(systemName: "point.bottomleft.forward.to.arrowtriangle.uturn.scurvepath")
                        .foregroundColor(.green)
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
