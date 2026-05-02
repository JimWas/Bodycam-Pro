# Bodycam Pro

Bodycam Pro is an iOS body camera app for recording video with GPS location tracking, map playback, exports, and an optional premium upgrade for unlimited recording.

## Features

- Video recording with camera, audio, and live recording status
- GPS capture with location metadata attached to recordings
- Map playback for recorded videos, including route display when location history is available
- Batch export to Photos
- Recording library with file size, duration, date, and map access
- Automatic safe-stop handling for interruptions and app lifecycle changes
- Free tier with a 30-minute recording limit per session
- Premium subscription support for unlimited recording
- AdMob integration for free users

## Premium

- Product ID: `com.jimwas.bodycampro.premium.monthly`
- Price: $3.99/month
- Unlocks unlimited recording time

## Tech Stack

- SwiftUI
- AVFoundation
- MapKit
- CoreLocation
- StoreKit 2
- Google Mobile Ads SDK

## Requirements

- iOS 17.6+
- Xcode 16+
- Camera permission
- Microphone permission
- Location permission for GPS tagging
- Photo Library permission for exports

## Project Structure

- `Bodycam Pro/RecordingManager.swift`  
  Recording session setup, capture lifecycle, interruption handling, and file management
- `Bodycam Pro/MainView.swift`  
  Main app UI, recording library, map sheet, export flow, and premium entry points
- `Bodycam Pro/RecordingView.swift`  
  Active recording screen and free-tier limit handling
- `Bodycam Pro/SubscriptionManager.swift`  
  StoreKit 2 product loading, purchase, restore, and entitlement state
- `Bodycam Pro/AdMobManager.swift`  
  Interstitial, rewarded, and native ad loading

## Setup

1. Clone the repository.
2. Open `Bodycam Pro.xcworkspace` in Xcode.
3. Configure your signing team and bundle settings.
4. Add your own AdMob unit IDs if needed.
5. Configure the subscription product in App Store Connect:
   `com.jimwas.bodycampro.premium.monthly`
6. Build and run on a device.

## Notes

- The app uses CocoaPods for Google Mobile Ads.
- The app currently includes a StoreKit configuration file for local subscription testing.
- App icon assets were regenerated from the current logo and are included in the asset catalog.

## Disclaimer

Users are responsible for complying with local laws regarding recording, privacy, and consent.
