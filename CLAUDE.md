# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BodyCam Pro is a personal bodycamera iOS app for capturing video with GPS location tracking. It features a simple recording interface with real-time status display, automatic video segmentation, and comprehensive location metadata embedded in recordings.

## Build & Run

**Important**: Open `Bodycam Pro.xcworkspace` (NOT .xcodeproj) due to Cocoapods integration.

```bash
# Install dependencies
pod install

# Build via Xcode
open "Bodycam Pro.xcworkspace"
# Configure signing in project settings, then build/run on physical device

# Build from command line (for CI)
xcodebuild build-for-testing -scheme "Bodycam Pro" -workspace "Bodycam Pro.xcworkspace" -destination "platform=iOS Simulator,name=iPhone 16"

# Run tests
xcodebuild test-without-building -scheme "Bodycam Pro" -workspace "Bodycam Pro.xcworkspace" -destination "platform=iOS Simulator,name=iPhone 16"
```

### Requirements
- iOS 15.0+
- Xcode with SwiftUI support
- Physical device for testing (camera/recording features don't work in simulator)

### Required Capabilities
- Background Modes → "Audio, AirPlay, and Picture in Picture"
- Camera, Microphone, Photo Library, Location permissions

## Architecture

### Core Singleton Managers
All managers use `@MainActor` for thread safety and are accessed as singletons:

- **RecordingManager** - Video recording lifecycle, segmentation, metadata persistence
- **LocationManager** - GPS tracking with reverse geocoding
- **AdMobManager** - Google AdMob interstitial/rewarded ads
- **SafeRecordingHandler** - Background task management, crash protection

### Key Enums (in RecordingManager.swift)
- `Resolution` - 720p, 1080p, 4K
- `CameraType` - Wide, Ultra-Wide

### Recording Flow
1. User configures settings in MainView (camera, resolution, audio, etc.)
2. User taps "Start Recording" → RecordingView displays
3. RecordingView shows recording status (timer, GPS indicator, stop button)
4. RecordingManager handles AVFoundation recording in background
5. SafeRecordingHandler manages background tasks and crash protection
6. Videos stored in `Documents/Videos/` with JSON metadata

### File Storage
- Recordings: `Documents/Videos/`
- Metadata: `Documents/Videos/metadata.json`

## Key Files

| File | Purpose |
|------|---------|
| `RecordingManager.swift` | Core recording logic, segmentation, file management |
| `MainView.swift` | Main UI hub, settings, video gallery |
| `RecordingView.swift` | Recording status UI with timer and stop button |
| `SafeRecordingHandler.swift` | Background task extension, crash protection |
| `LocationManager.swift` | GPS tracking, reverse geocoding |
| `AdMobManager.swift` | Ad monetization |

## Important Patterns

### Background Task Management
```swift
backgroundTaskID = UIApplication.shared.beginBackgroundTask { ... }
// 25-30 second extension window for emergency saves
UIApplication.shared.endBackgroundTask(backgroundTaskID)
```

### Async Asset Loading (iOS 16+)
```swift
let duration = (try? await asset.load(.duration))?.seconds ?? 0
```

### Cross-Component Communication
Uses `NotificationCenter` for recording control:
```swift
// Graceful stop with save
NotificationCenter.default.post(name: NSNotification.Name("SafeStopRecording"), object: nil)

// Emergency immediate save (app termination)
NotificationCenter.default.post(name: NSNotification.Name("EmergencyStopRecording"), object: nil)
```

### Recording Segmentation
Long recordings are split into configurable chunks (1-10 minutes) stored in `segmentFiles` array.

## Configuration Defaults

- Default resolution: 1080p
- Default segment length: 120 seconds
- Minimum disk space: 500MB

## Dependencies

- **Google-Mobile-Ads-SDK** (Cocoapods) - AdMob functionality
- **AVFoundation** - Video recording
- **CoreLocation** - GPS tracking
- **MapKit** - Map display

## Concurrency

Uses Swift 6 concurrency with `@MainActor` on all managers. Background operations use:
```swift
await Task.detached { session.startRunning() }.value  // AVCaptureSession on background thread
```
