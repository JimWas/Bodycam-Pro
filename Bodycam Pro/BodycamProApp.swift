import SwiftUI
import AVFoundation
import AppTrackingTransparency

@main
struct BodycamProApp: App {

    @Environment(\.scenePhase) private var scenePhase
    @State private var hasRequestedTracking = false

    // Create an init to set up global things on launch
    init() {
        // Configure Audio Session (Important for video recording)
        // Note: AdMob initialization moved to after ATT request
        setupAudioSession()
        _ = SubscriptionManager.shared
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.light) // Optional: Keep app in light mode
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && !hasRequestedTracking {
                hasRequestedTracking = true
                Task {
                    // Small delay to ensure the UI is fully rendered
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await requestTrackingPermission()
                }
            }
        }
    }

    private func requestTrackingPermission() async {
        var trackingStatus = ATTrackingManager.trackingAuthorizationStatus

        if trackingStatus == .notDetermined {
            // Request permission - this will show the popup
            trackingStatus = await ATTrackingManager.requestTrackingAuthorization()
        }

        // Initialize AdMob after ATT with the user's tracking preference
        // AdMob will serve non-personalized ads if tracking was denied
        await MainActor.run {
            AdMobManager.shared.initializeAdMob(trackingStatus: trackingStatus)
        }
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Allow mixing (so music doesn't stop) and default to speaker
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
}
