import SwiftUI
import AppKit

struct AccelerometerSetupView: View {
    @EnvironmentObject private var engine: KnockEngine
    @Environment(\.dismiss) private var dismiss
    private var starting: Bool { engine.detectorStatus == .starting }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(eyebrow: "MacBook mode", title: "Tune your taps",
                        subtitle: "Detects physical vibration with your built-in accelerometer. No microphone is used. Assigned actions are paused while this screen is open.")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    inputPanel
                    AccelerometerCalibrationPanel(readout: engine.diagnostics.calibration)
                    controls
                    checkPanel
                }.padding(4)
            }
            HStack {
                // Several dev builds are often open at once and are otherwise
                // indistinguishable; a stale window once produced a bad reading.
                Text("Closing stops detection. Experimental sensor activation may persist until your Mac restarts. Build \(Self.buildStamp)")
                    .font(KnockTheme.TypeStyle.caption).foregroundStyle(KnockTheme.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 620, height: 590)
        .background(KnockTheme.canvas)
        .foregroundStyle(KnockTheme.primary)
        .onAppear { engine.beginDetectionCheck() }
        .onDisappear { engine.endDetectionCheck() }
        .onExitCommand { dismiss() }
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Built-in accelerometer", systemImage: "waveform.path")
                    .font(KnockTheme.TypeStyle.heading)
                Spacer()
                Button(starting ? "Cancel" : (engine.isListening ? "Pause accelerometer" : "Start accelerometer")) {
                    engine.toggleListening()
                }.buttonStyle(.bordered)
            }
            if starting {
                Text("Waiting for sensor samples…").font(KnockTheme.TypeStyle.body)
            }
            AccelerometerLevelView(readout: engine.diagnostics.level)
            Text("Desk taps work only when vibration reaches the laptop. Keep the Mac on a stable surface.")
                .font(KnockTheme.TypeStyle.caption).foregroundStyle(KnockTheme.secondary)
            if let message = engine.permissionMessage {
                Text(message).font(KnockTheme.TypeStyle.body)
                    .foregroundStyle(KnockTheme.warning).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Input Monitoring settings") { openSettings("preference.security?Privacy_ListenEvent") }
                Spacer()
                Button("Use Trackpad") { engine.endDetectionCheck(); engine.mode = .trackpad; dismiss() }
            }.buttonStyle(.borderless).font(KnockTheme.TypeStyle.caption)
        }.padding(16).panelSurface()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("2. Adjust the feel").font(KnockTheme.TypeStyle.heading)
            HStack {
                Text("Sensitivity").frame(width: 85, alignment: .leading)
                Slider(value: $engine.sensitivity, in: 0...1)
                    .accessibilityLabel("Tap sensitivity")
                Text("\(Int(engine.sensitivity * 100))%").monospacedDigit().frame(width: 52)
            }
            HStack {
                Text("Cooldown").frame(width: 85, alignment: .leading)
                Slider(value: $engine.cooldown, in: 0.08...0.4, step: 0.01)
                    .accessibilityLabel("Minimum time between taps")
                Text("\(Int((engine.cooldown * 1000).rounded())) ms").monospacedDigit().frame(width: 52)
            }
            Text("Raise sensitivity for lighter taps. Increase cooldown to reject repeated vibration; it also limits how fast you can double-tap.")
                .foregroundStyle(KnockTheme.secondary)
            HStack {
                Text("Tap spacing").frame(width: 85, alignment: .leading)
                Slider(value: $engine.patternWindow, in: 0.3...1, step: 0.05)
                    .accessibilityLabel("Maximum time between taps in a pattern")
                Text("\(Int((engine.patternWindow * 1000).rounded())) ms").monospacedDigit().frame(width: 52)
            }
            Text("If doubles become two singles, increase tap spacing. Higher values also make single-tap actions wait longer.")
                .foregroundStyle(KnockTheme.secondary)
            Divider().padding(.vertical, 2)
            Toggle("Ignore taps while typing", isOn: $engine.ignoreWhileTyping)
            Toggle("Ignore taps while using the trackpad", isOn: $engine.ignoreWhileUsingTrackpad)
            Text("Keys and trackpad contact shake the chassis just like a tap, so Knock ignores taps for \(Int(AccelerometerKnockDetector.inputSettleWindow * 1000)) ms after you type, click, or move the pointer. With an external mouse, the trackpad option also pauses taps while the mouse moves.")
                .foregroundStyle(KnockTheme.secondary)
        }.font(KnockTheme.TypeStyle.body).padding(16).panelSurface()
    }

    private var checkPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("3. Try real taps").font(KnockTheme.TypeStyle.heading)
                Spacer()
                Button("Reset counts") { engine.resetCheckCounts() }.buttonStyle(.bordered)
            }
            Text("Tap gently on the palm rest. Leave 1.5 seconds between patterns. To check the typing filter, type a few lines and confirm the ignored count rises while the pattern counts stay put.")
                .font(KnockTheme.TypeStyle.body).foregroundStyle(KnockTheme.secondary)
            HStack(spacing: 22) {
                ForEach(KnockPattern.allCases) { pattern in
                    Text("\(pattern.shortTitle): \(engine.checkCounts[pattern, default: 0])")
                }
            }.font(KnockTheme.TypeStyle.heading).monospacedDigit()
            AccelerometerMetricsView(readout: engine.diagnostics.metrics)
        }.padding(16).panelSurface()
    }

    static let buildStamp: String = {
        guard let url = Bundle.main.executableURL,
              let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return "unknown" }
        return date.formatted(date: .abbreviated, time: .standard)
    }()

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct AccelerometerLevelView: View {
    @ObservedObject var readout: KnockReadout<Double>
    var body: some View {
        ProgressView(value: readout.value)
            .accessibilityLabel("Accelerometer input level")
    }
}

private struct AccelerometerMetricsView: View {
    @ObservedObject var readout: KnockReadout<AccelerometerMetrics>
    var body: some View {
        Text("\(readout.value.seconds) seconds of input · \(readout.value.impulses) impulses · \(readout.value.ignoredTyping) ignored while typing · \(readout.value.ignoredPointer) ignored while using the trackpad · Threshold \(String(format: "%.4f", readout.value.threshold)) g · \(readout.value.sampleRate) samples/s")
            .font(KnockTheme.TypeStyle.caption).foregroundStyle(KnockTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AccelerometerCalibrationPanel: View {
    @EnvironmentObject private var engine: KnockEngine
    @ObservedObject var readout: KnockReadout<AccelerometerCalibration>
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("1. Measure resting vibration").font(KnockTheme.TypeStyle.heading)
            switch readout.value {
            case .idle:
                Text("Keep the Mac and desk still for 3 seconds to measure background vibration.")
                    .font(KnockTheme.TypeStyle.body).foregroundStyle(KnockTheme.secondary)
                Button("Measure resting vibration") { engine.calibrateAccelerometer() }
                    .disabled(!engine.isListening).buttonStyle(.bordered)
            case .measuring(let progress):
                ProgressView(value: progress).accessibilityLabel("Resting vibration measurement")
                Text("Measuring… don’t tap yet.").font(KnockTheme.TypeStyle.body)
                Button("Cancel measurement") { engine.cancelAccelerometerCalibration() }.buttonStyle(.bordered)
            case .proposed(let result):
                Text("Suggested threshold: \(String(format: "%.4f", result)) g")
                    .font(KnockTheme.TypeStyle.body)
                HStack {
                    Button("Use suggested threshold") { engine.applyAccelerometerCalibration() }.buttonStyle(.borderedProminent)
                    Button("Measure again") { engine.calibrateAccelerometer() }.buttonStyle(.bordered)
                }
            case .failed(let message):
                Text(message).font(KnockTheme.TypeStyle.body).foregroundStyle(KnockTheme.warning)
                HStack {
                    Button("Try again") { engine.calibrateAccelerometer() }
                    Button("Keep current threshold") { engine.cancelAccelerometerCalibration() }
                }.buttonStyle(.bordered)
            }
        }.padding(16).panelSurface()
    }

}
