import Foundation
import AVFoundation
import UIKit

/// Handles safe recording with proper cleanup and interruption handling
class SafeRecordingHandler: NSObject {
    
    static let shared = SafeRecordingHandler()
    
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var activeRecordingURL: URL?
    
    private override init() {
        super.init()
        setupNotifications()
    }
    
    // MARK: - Setup Notifications
    private func setupNotifications() {
        // Monitor app lifecycle events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    // MARK: - Recording Session Management
    @MainActor
    func startRecordingSession(url: URL) {
        activeRecordingURL = url
        startBackgroundTask()
    }
    
    @MainActor
    func endRecordingSession() {
        activeRecordingURL = nil
        endBackgroundTask()
    }
    
    // MARK: - Background Task
    @MainActor
    private func startBackgroundTask() {
        endBackgroundTask()

        // The expiration handler is called synchronously on the main thread by iOS,
        // always after beginBackgroundTask returns, so self.backgroundTaskID is valid.
        backgroundTaskID = UIApplication.shared.beginBackgroundTask {
            print("⚠️ Background task expiring - emergency save")
            NotificationCenter.default.post(name: NSNotification.Name("EmergencyStopRecording"), object: nil)
            UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
            self.backgroundTaskID = .invalid
        }

        if backgroundTaskID != .invalid {
            let remaining = UIApplication.shared.backgroundTimeRemaining
            if remaining.isFinite && remaining != .greatestFiniteMagnitude {
                print("🕐 Background task started. Remaining time: \(Int(remaining))s")
            } else {
                print("🕐 Background task started.")
            }
        }
    }

    @MainActor
    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        print("✅ Ending background task")
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
    
    // MARK: - App Lifecycle Handlers
    @objc private func handleAppWillResignActive() {
        // App losing focus (power button, incoming call, etc.)
        print("📱 App will resign active - ensuring video file safety")
        
        // Post notification for RecordingManager to gracefully stop
        NotificationCenter.default.post(
            name: NSNotification.Name("SafeStopRecording"),
            object: nil
        )
    }
    
    @objc private func handleAppWillTerminate() {
        // App being force-closed by user or system
        print("🛑 App will terminate - emergency video save")
        
        // Last chance to save anything
        NotificationCenter.default.post(
            name: NSNotification.Name("EmergencyStopRecording"),
            object: nil
        )
    }
    
    @MainActor @objc private func handleAppDidEnterBackground() {
        // Only request background time when we're actually recording.
        guard activeRecordingURL != nil else { return }
        print("🌙 App entered background - maintaining background task")
        if backgroundTaskID == .invalid {
            startBackgroundTask()
        }
    }
    
    // MARK: - Disk Space Monitoring
    func checkDiskSpace() -> (available: Int64, isLow: Bool) {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
        
        if let values = try? fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            
            let minimumRequired: Int64 = 500 * 1024 * 1024 // 500MB minimum
            return (capacity, capacity < minimumRequired)
        }
        
        return (0, true)
    }
    
    // MARK: - Safe File Operations
    func verifyFileIntegrity(at url: URL) -> Bool {
        // Check if file exists and is readable
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        
        // Try to load the file as an asset to verify it's not corrupted
        let asset = AVAsset(url: url)
        
        // Check if asset is playable
        if #available(iOS 16.0, *) {
            // Use async load for iOS 16+
            let semaphore = DispatchSemaphore(value: 0)
            var isPlayable = false
            
            Task {
                isPlayable = (try? await asset.load(.isPlayable)) ?? false
                semaphore.signal()
            }
            
            semaphore.wait()
            return isPlayable
        } else {
            return asset.duration.seconds > 0
        }
    }
    
    func cleanupCorruptedFiles(in directory: URL) async {
        let fileManager = FileManager.default
        
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        for file in files where file.pathExtension.lowercased() == "mov" {
            // Check file size - if it's very small, it's likely corrupted
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size < 1024 { // Less than 1KB is definitely corrupted
                print("🗑️ Removing corrupted file: \(file.lastPathComponent)")
                try? fileManager.removeItem(at: file)
                continue
            }
            
            // Verify file integrity
            if !verifyFileIntegrity(at: file) {
                print("🗑️ Removing unplayable file: \(file.lastPathComponent)")
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        // End background task if still active
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
    }
}
