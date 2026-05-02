import SwiftUI

@MainActor
struct RecordingView: View {

    @ObservedObject var manager: RecordingManager
    @Environment(\.dismiss) private var dismiss

    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isPulsing = false
    @State private var showFreeLimitAlert = false
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            // Dark background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Recording indicator with pulse animation
                ZStack {
                    // Outer pulse ring
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .frame(width: 120, height: 120)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .opacity(isPulsing ? 0 : 0.6)

                    // Inner recording dot
                    Circle()
                        .fill(Color.red)
                        .frame(width: 80, height: 80)
                        .shadow(color: .red.opacity(0.5), radius: 20)

                    // REC text
                    Text("REC")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }

                // Timer display
                Text(formatTime(elapsedTime))
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .foregroundColor(.white)

                // Status text
                Text(statusText)
                    .font(.title2)
                    .foregroundColor(manager.isInterrupted ? .yellow.opacity(0.9) : .white.opacity(0.7))

                // GPS indicator
                if LocationManager.shared.currentLocation != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.green)
                        Text("GPS Active")
                            .foregroundColor(.green)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(20)
                }

                Spacer()

                // Stop Recording Button
                Button(action: stopAndDismiss) {
                    HStack(spacing: 12) {
                        Image(systemName: "stop.fill")
                            .font(.title2)
                        Text("STOP RECORDING")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.red)
                    .cornerRadius(16)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            startRecording()
        }
        .onDisappear {
            timer?.invalidate()
            if manager.isRecording {
                manager.stopRecording()
            }
        }
        .alert("Free Limit Reached", isPresented: $showFreeLimitAlert) {
            Button("Go Premium") {
                showPaywall = true
            }
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Free recording is limited to 30 minutes. Upgrade to premium for unlimited recording.")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Recording Logic

    private func startRecording() {
        Task {
            let ok = await manager.prepareSession()
            if ok {
                manager.startRecording()
                startTimer()
                startPulseAnimation()
            }
        }
    }

    private func startTimer() {
        elapsedTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                elapsedTime += 1
                if !manager.isPremium && elapsedTime >= manager.freeRecordingLimit {
                    timer?.invalidate()
                    manager.stopRecording()
                    showFreeLimitAlert = true
                }
            }
        }
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
            isPulsing = true
        }
    }

    private func stopAndDismiss() {
        timer?.invalidate()
        manager.stopRecording()
        dismiss()
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private var statusText: String {
        if manager.isResuming {
            return "Resuming..."
        }
        if manager.isInterrupted {
            return manager.interruptionMessage ?? "Paused"
        }
        return "Recording..."
    }
}
