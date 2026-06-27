import Foundation
import Combine

@MainActor
class iCloudManager: ObservableObject {
    static let shared = iCloudManager()

    enum UploadStatus: Equatable {
        case notStarted, uploading, uploaded, failed(String)

        var icon: String {
            switch self {
            case .notStarted: return "icloud"
            case .uploading:  return "icloud.and.arrow.up"
            case .uploaded:   return "checkmark.icloud.fill"
            case .failed:     return "exclamationmark.icloud"
            }
        }

        var color: String {
            switch self {
            case .uploaded: return "green"
            case .failed:   return "red"
            default:        return "gray"
            }
        }
    }

    @Published var statuses: [String: UploadStatus] = [:]

    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var containerURL: URL? {
        // Must be called off-main-thread; caller is responsible.
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents/Videos")
    }

    // Check if a file already exists in iCloud.
    func syncStatus(for recording: Recording) -> UploadStatus {
        if let status = statuses[recording.name] { return status }
        // Synchronously check file presence (container lookup cached by OS).
        if let url = containerURL {
            let dest = url.appendingPathComponent(recording.name)
            return FileManager.default.fileExists(atPath: dest.path) ? .uploaded : .notStarted
        }
        return .notStarted
    }

    func upload(_ recording: Recording) {
        guard isAvailable else { return }
        statuses[recording.name] = .uploading

        Task.detached(priority: .background) { [weak self, url = recording.url, name = recording.name] in
            guard let self else { return }
            do {
                guard let containerURL = await MainActor.run(body: { self.containerURL }) else {
                    await MainActor.run { self.statuses[name] = .failed("iCloud unavailable") }
                    return
                }
                try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
                let dest = containerURL.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.copyItem(at: url, to: dest)
                }
                await MainActor.run { self.statuses[name] = .uploaded }
            } catch {
                await MainActor.run { self.statuses[name] = .failed(error.localizedDescription) }
            }
        }
    }

    func uploadAll(_ recordings: [Recording]) {
        for rec in recordings where syncStatus(for: rec) != .uploaded {
            upload(rec)
        }
    }
}
