import SwiftUI
import AVFoundation

#if os(iOS)

// MARK: - Audio Recorder Model

@MainActor
final class AudioRecorderModel: ObservableObject {
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0
    @Published var meterLevels: [CGFloat] = []

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var startTime: Date?
    private var tempURL: URL?

    /// Request microphone permission then start recording
    func startRecording() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard granted else {
                    print("Microphone permission denied")
                    return
                }
                self?.beginRecording()
            }
        }
    }

    /// Actually start recording to a temporary M4A file (called after permission is granted)
    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio_\(UUID().uuidString).m4a")
        tempURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.record()
            isRecording = true
            startTime = Date()
            meterLevels = []

            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateMetering()
                }
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    /// Stop recording and return the audio data and duration
    func stopRecording() -> (Data, TimeInterval)? {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        isRecording = false

        guard let url = tempURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        let finalDuration = duration

        // Clean up temp file
        try? FileManager.default.removeItem(at: url)
        tempURL = nil

        return (data, finalDuration)
    }

    /// Cancel recording without saving
    func cancelRecording() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        isRecording = false
        duration = 0
        meterLevels = []

        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
            tempURL = nil
        }
    }

    private func updateMetering() {
        guard let recorder = recorder, isRecording else { return }
        recorder.updateMeters()

        if let start = startTime {
            duration = Date().timeIntervalSince(start)
        }

        // Normalize dB level (-160..0) to 0..1
        let avgPower = recorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, (avgPower + 50) / 50))
        meterLevels.append(CGFloat(normalized))

        // Keep a sliding window of levels
        if meterLevels.count > 80 {
            meterLevels.removeFirst()
        }
    }
}

// MARK: - Audio Recorder View

struct AudioRecorderView: View {
    let onSave: (Data, TimeInterval) -> Void
    let onDismiss: () -> Void
    @StateObject private var recorder = AudioRecorderModel()

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Button("Cancel") {
                    recorder.cancelRecording()
                    onDismiss()
                }
                .foregroundStyle(.secondary)

                Spacer()

                Text("Record Audio")
                    .font(.headline)

                Spacer()

                Button("Save") {
                    if let (data, duration) = recorder.stopRecording() {
                        onSave(data, duration)
                    }
                    onDismiss()
                }
                .fontWeight(.semibold)
                .disabled(!recorder.isRecording && recorder.duration == 0)
            }
            .padding(.horizontal)
            .padding(.top, 28)

            Spacer()

            // Live waveform bars
            RecordingWaveformView(levels: recorder.meterLevels)
                .frame(height: 60)
                .padding(.horizontal, 24)

            // Duration counter
            Text(formatDuration(recorder.duration))
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(recorder.isRecording ? .orange : .secondary)

            Spacer()

            // Record / Stop button
            Button {
                if recorder.isRecording {
                    if let (data, duration) = recorder.stopRecording() {
                        onSave(data, duration)
                    }
                    onDismiss()
                } else {
                    recorder.startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 72, height: 72)

                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 28, height: 28)
                    }
                }
            }

            Spacer()
        }
        .presentationDetents([.height(320)])
        .onDisappear {
            if recorder.isRecording {
                recorder.cancelRecording()
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Recording Waveform View

struct RecordingWaveformView: View {
    let levels: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let barCount = displayLevels(width: geo.size.width)
            let offset = max(0, levels.count - barCount)
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let arrayIndex = offset + index
                    let level: CGFloat = arrayIndex < levels.count ? levels[arrayIndex] : 0
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange)
                        .frame(width: 3, height: max(3, level * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func displayLevels(width: CGFloat) -> Int {
        max(1, Int(width / 5))
    }
}

#endif
