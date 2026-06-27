# Bodycam Pro

> **Your phone. Your witness.**

Bodycam Pro turns your iPhone into a professional-grade body camera — always ready, always recording, always protecting you. Whether you're a rideshare driver, delivery worker, journalist, legal professional, or anyone who needs documented proof of what happened, Bodycam Pro gives you the tools to record with confidence and export with credibility.

---

## Why Bodycam Pro?

Most camera apps are built for memories. Bodycam Pro is built for **accountability**.

- **One tap to record** — or set it to start the moment you open the app
- **GPS-tagged footage** with live route tracking and map playback
- **Evidence Mode** bakes timestamps, coordinates, and SHA-256 cryptographic hashes into your exports — so the footage holds up when it matters
- **Lock screen widget** means you never have to unlock your phone to start recording
- **iCloud backup** keeps your recordings safe even if your device is seized or damaged

---

## Features

### Recording
- 720p / 1080p / 4K resolution selection
- Front and back camera support, including Ultra-Wide lens
- Configurable segment length (1–10 minutes) for automatic file chunking
- Audio toggle with Bluetooth HFP support
- Video stabilization
- Auto-start recording on app launch
- Interruption handling — automatically resumes after phone calls, audio session conflicts, and camera preemption

### GPS & Mapping
- Live GPS tracking with location points logged throughout each recording
- Reverse geocoding to a human-readable street address
- Map thumbnail previews in the recording library
- Full-screen map with recorded route polyline
- **GPS route scrubber** — drag the timeline slider to move the pin along your exact path, with timestamps at every point

### Evidence Mode
Turn any recording into a legally-defensible document.

| Feature | What it does |
|---|---|
| Timestamp Watermark | Burns the recording date and time permanently into the video frames — not as strippable metadata, but as visible text baked into the pixels |
| GPS Coordinates Overlay | Permanently overlays latitude, longitude, and street address onto every frame |
| SHA-256 Hash Report | Generates a cryptographic fingerprint of both the original and exported file. If anyone modifies a single frame after export, the hash won't match — proving tampering |
| Evidence Summary | Exports a `.json` + `.txt` report with hashes, timestamps, GPS data, app version, and build number |

### Library & Management
- Recording library with duration, file size, creation date, and GPS thumbnail
- In-app video playback (no need to export to Photos to watch)
- Custom name per recording
- Tags — preset chips (Work, Commute, Incident, Travel, Personal, Evidence, Training) plus free-text custom tags
- Recording Details sheet — view all metadata including evidence hashes in-app
- Batch export to Photos library
- Select mode for multi-recording export and delete
- Share evidence summary package directly from the app

### iCloud Backup
- Toggle automatic iCloud backup after each recording finishes
- "Back Up All Now" to sync existing recordings
- Per-recording iCloud status indicator (uploading / uploaded / failed)
- Graceful fallback when iCloud is unavailable

### Lock Screen Widget
- Add a widget to your Lock Screen or Home Screen for one-tap recording start
- Supports `.accessoryCircular` (Lock Screen), `.accessoryRectangular`, and `systemSmall`
- Deep-links via `bodycampro://start-recording` — app opens and recording begins immediately

### Monetization
| Tier | Features |
|---|---|
| Free | 30-minute recording limit per session, AdMob ads (interstitial, rewarded, native) |
| Premium ($3.99/mo or lifetime) | Unlimited recording, no ads |

---

## Technical Architecture

### Core Managers

| Class | Role |
|---|---|
| `RecordingManager` | AVFoundation session setup, recording lifecycle, segment rotation, metadata persistence, evidence exports |
| `LocationManager` | CoreLocation GPS tracking, reverse geocoding, location path accumulation |
| `SafeRecordingHandler` | Background task management, crash protection, disk space monitoring, file integrity verification |
| `AdMobManager` | Interstitial, rewarded, and native ad loading and presentation |
| `SubscriptionManager` | StoreKit 2 product loading, purchase, restore, and entitlement observation |
| `iCloudManager` | iCloud Drive upload, per-recording sync status tracking |

### Key Patterns

**Recording Segmentation**
Long recordings are split into configurable chunks stored as individual `.mov` files. This prevents data loss on crash and keeps file sizes manageable.

**Metadata Persistence**
GPS coordinates, address, location path, custom name, and tags are stored in a sidecar `metadata.json` alongside the video files. Evidence summaries are stored in a separate `Evidence/` directory.

**Background Safety**
```
App backgrounds → beginBackgroundTask → SafeRecordingHandler expiration handler
    → synchronous endBackgroundTask + EmergencyStopRecording notification
    → AVCaptureMovieFileOutput.stopRecording() → file saved
```
The expiration handler calls `endBackgroundTask` synchronously (not via `Task`) to avoid the "still not ended" system warning.

**Evidence Export Pipeline**
```
AVURLAsset → AVMutableComposition → CALayer overlay (timestamp + GPS text)
    → AVVideoCompositionCoreAnimationTool → AVAssetExportSession
    → SHA-256 hash of original + exported → EvidenceSummary JSON + TXT
```

**Widget Deep Link**
```
BodycamWidget (WidgetKit) → widgetURL("bodycampro://start-recording")
    → BodycamProApp.onOpenURL → NotificationCenter post
    → MainView.onReceive → showRecorder = true
```

### Concurrency
All managers use `@MainActor`. Background operations use `Task.detached` for AVCaptureSession and `Task.detached(priority: .background)` for iCloud file copies.

### File Storage
```
Documents/
├── Videos/
│   ├── 2026-01-15-14-32-01-abc123.mov
│   ├── 2026-01-15-14-32-01-abc123.mov  ← segments
│   └── metadata.json                   ← GPS + tags + custom names
└── Evidence/
    ├── 2026-01-15-14-32-01-abc123-evidence.mov
    ├── 2026-01-15-14-32-01-abc123-evidence.json
    └── 2026-01-15-14-32-01-abc123-evidence.txt
```

---

## Project Structure

```
Bodycam Pro/
├── BodycamProApp.swift          # App entry, audio session, ATT, URL scheme handler
├── MainView.swift               # Main UI, library, settings, all sheet views
├── RecordingView.swift          # Active recording screen, free-tier limit
├── RecordingManager.swift       # Core recording logic, evidence exports
├── LocationManager.swift        # GPS tracking, reverse geocoding
├── SafeRecordingHandler.swift   # Background tasks, crash protection
├── AdMobManager.swift           # Ad loading and presentation
├── NativeAdView.swift           # Native ad UIKit component with MediaView
├── SubscriptionManager.swift    # StoreKit 2 purchases
├── PaywallView.swift            # Paywall UI
├── VideoPlayerView.swift        # In-app AVKit video player
├── iCloudManager.swift          # iCloud Drive backup
└── BodycamPro.entitlements

BodycamWidget/
└── BodycamWidget.swift          # Lock screen / home screen WidgetKit extension
```

---

## Setup

### Prerequisites
- Xcode 16+
- iOS 17.6+ device (camera and recording features require a physical device)
- Apple Developer account

### Steps

1. Clone the repository
2. Install CocoaPods dependencies:
   ```bash
   pod install
   ```
3. Open `Bodycam Pro.xcworkspace` (**not** `.xcodeproj`)
4. Configure signing in target settings
5. Update AdMob App ID in `Info.plist` if using your own account
6. Configure StoreKit products in App Store Connect:
   - `com.jimwas.bodycampro.premium.monthly` — $3.99/month subscription
   - `com.jimwas.bodycampro.premium.lifetime` — one-time lifetime purchase
7. Build and run on a physical device

### Widget Setup (optional)
1. In Xcode: **File → New Target → Widget Extension**, name it `BodycamWidget`
2. Uncheck "Include Configuration App Intent"
3. Replace generated files with `BodycamWidget/BodycamWidget.swift`
4. Add URL Type in `Info.plist` with scheme `bodycampro`

### iCloud Backup Setup (optional)
1. In Apple Developer Portal, enable iCloud Documents for App ID `JimWas.Bodycam-Pro`
2. Add container `iCloud.JimWas.Bodycam-Pro`
3. In Xcode: target → **Signing & Capabilities → iCloud → iCloud Documents**
4. Xcode will add the required entitlement keys automatically

---

## Requirements

| Requirement | Detail |
|---|---|
| iOS | 17.6+ |
| Xcode | 16+ |
| Camera | Required |
| Microphone | Required |
| Location | Required for GPS tagging |
| Photo Library | Required for export to Photos |
| iCloud | Optional — for backup feature |

---

## Dependencies

| Dependency | Purpose | Source |
|---|---|---|
| Google Mobile Ads SDK | AdMob ads | CocoaPods |
| AVFoundation | Video recording | System |
| CoreLocation | GPS tracking | System |
| MapKit | Map display and snapshots | System |
| StoreKit 2 | In-app purchases | System |
| WidgetKit | Lock screen widget | System |
| CryptoKit | SHA-256 evidence hashes | System |

---

## Changelog

### Latest
- In-app video player — tap any recording to watch without exporting
- GPS route scrubber — interactive timeline slider in the map view
- Custom recording names and tags (Work, Commute, Incident, Travel, and more)
- iCloud automatic backup after each recording
- Lock screen and home screen widget for instant recording start
- Auto-start recording on app launch toggle
- Evidence Mode info popup with full feature explanation
- Recording Details sheet — view all metadata and SHA-256 hashes in-app
- Fixed white screen bug on map view (Map frame collapse in ZStack)
- Fixed background task "still not ended" warning (synchronous expiration handler)
- Fixed background task firing on every app backgrounding when not recording
- Added MediaView to native ads so video-format ads render correctly
- Fixed rewarded ad unit ID format mismatch
- Fixed `AVAssetExportSession` Sendable concurrency warning

---

## Legal

Users are responsible for complying with local laws regarding video recording, audio recording, privacy, and consent. Laws vary by jurisdiction. When in doubt, inform the people you are recording.

App Store privacy policy: [jimwashkau.com/privacy](https://www.jimwashkau.com/privacy)  
Terms of use: [jimwashkau.com/terms](https://jimwashkau.com/terms)
