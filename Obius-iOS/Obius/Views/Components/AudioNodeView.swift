import SwiftUI
import AVFoundation

// MARK: - Audio Player Model

@MainActor
final class AudioPlayerModel: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: CGFloat = 0
    @Published var currentTime: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    let duration: TimeInterval

    init(duration: TimeInterval) {
        self.duration = duration
    }

    func loadAndPlay(data: Data) {
        if isPlaying {
            pause()
            return
        }

        do {
            if player == nil {
                #if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                player = try AVAudioPlayer(data: data)
                player?.prepareToPlay()
            }

            player?.play()
            isPlaying = true

            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateProgress()
                }
            }
        } catch {
            print("Failed to play audio: \(error)")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        progress = 0
        currentTime = 0
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let player = player else { return }

        if !player.isPlaying {
            stop()
            return
        }

        currentTime = player.currentTime
        let totalDuration = player.duration > 0 ? player.duration : duration
        progress = CGFloat(player.currentTime / totalDuration)
    }

    deinit {
        progressTimer?.invalidate()
    }
}

// MARK: - Audio Node View

struct AudioNodeView: View {
    let audioHash: String
    let duration: TimeInterval
    let mediaRepository: MediaRepository

    @StateObject private var player: AudioPlayerModel
    @State private var audioData: Data?

    init(audioHash: String, duration: TimeInterval, mediaRepository: MediaRepository) {
        self.audioHash = audioHash
        self.duration = duration
        self.mediaRepository = mediaRepository
        _player = StateObject(wrappedValue: AudioPlayerModel(duration: duration))
    }

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button {
                if let data = audioData {
                    player.loadAndPlay(data: data)
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.orange))
            }
            .buttonStyle(.plain)

            // Waveform bars with progress
            WaveformBarsView(progress: player.progress)
                .frame(height: 32)

            // Duration label
            Text(formatDuration(player.isPlaying ? player.currentTime : duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: 48)
        .onAppear {
            loadAudio()
        }
        .onDisappear {
            player.stop()
        }
    }

    private func loadAudio() {
        if let data = try? mediaRepository.getMediaData(hash: audioHash) {
            audioData = data
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Waveform Bars View

struct WaveformBarsView: View {
    let progress: CGFloat
    private let barCount = 40

    /// Generate deterministic pseudo-random bar heights from a seed
    private var barHeights: [CGFloat] {
        var heights: [CGFloat] = []
        for i in 0..<barCount {
            let base = 0.3 + 0.7 * abs(sin(Double(i) * 0.4))
            let variation = abs(sin(Double(i) * 1.7 + 0.5)) * 0.4
            heights.append(CGFloat(min(1.0, base * (0.6 + variation))))
        }
        return heights
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let height = barHeights[index]
                    let barProgress = CGFloat(index) / CGFloat(barCount)
                    let isFilled = barProgress <= progress

                    RoundedRectangle(cornerRadius: 1)
                        .fill(isFilled ? Color.orange : Color.orange.opacity(0.3))
                        .frame(width: 3, height: max(3, height * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
