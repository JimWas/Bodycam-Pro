// BodycamWidget.swift
//
// SETUP INSTRUCTIONS:
// 1. In Xcode: File → New → Target → Widget Extension
// 2. Name it "BodycamWidget", uncheck "Include Configuration App Intent"
// 3. Delete the generated files and add this file to the new target instead
// 4. In your main app's Info.plist, add a URL type with scheme "bodycampro"
// 5. In Bodycam Pro's BodycamProApp.swift, the .onOpenURL handler is already wired up
//
// The widget appears on the Lock Screen (accessoryCircular) and Home Screen (systemSmall).
// Tapping it deep-links into the app and immediately starts recording.

import WidgetKit
import SwiftUI

struct BodycamEntry: TimelineEntry {
    let date: Date
}

struct BodycamProvider: TimelineProvider {
    func placeholder(in context: Context) -> BodycamEntry { BodycamEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (BodycamEntry) -> Void) {
        completion(BodycamEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BodycamEntry>) -> Void) {
        completion(Timeline(entries: [BodycamEntry(date: .now)], policy: .never))
    }
}

struct BodycamWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title2)
            }

        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                Text("Start Rec")
                    .font(.headline)
            }

        default: // systemSmall
            ZStack {
                Color.black
                VStack(spacing: 8) {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.red)
                        .font(.largeTitle)
                    Text("Start\nRecording")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .font(.caption.bold())
                }
            }
        }
    }
}

@main
struct BodycamWidget: Widget {
    let kind = "BodycamWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BodycamProvider()) { _ in
            BodycamWidgetView()
                .widgetURL(URL(string: "bodycampro://start-recording")!)
        }
        .configurationDisplayName("Bodycam Pro")
        .description("Tap to start recording immediately.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}
