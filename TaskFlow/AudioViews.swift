import SwiftUI
import AVFoundation

func mmss(_ t: TimeInterval) -> String {
    String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
}

// MARK: - 录音器

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentURL: URL?

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)
        session.requestRecordPermission { [weak self] granted in
            guard granted else { return }
            Task { @MainActor in self?.begin() }
        }
    }

    private func begin() {
        let name = UUID().uuidString + ".m4a"
        let url = TaskStore.attachmentsDir.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return }
        currentURL = url
        recorder = r
        r.record()
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 0.1 }
        }
    }

    /// 停止并返回录音文件名；太短的录音自动丢弃
    func stop() -> String? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        guard let url = currentURL else { return nil }
        currentURL = nil
        if elapsed < 0.5 {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url.lastPathComponent
    }
}

// MARK: - 录音按钮行（放在编辑器里）

struct RecordRow: View {
    @ObservedObject var recorder: AudioRecorder
    var onSaved: (String) -> Void

    var body: some View {
        HStack {
            Button {
                if recorder.isRecording {
                    if let name = recorder.stop() { onSaved(name) }
                } else {
                    recorder.start()
                }
            } label: {
                Label(recorder.isRecording ? "停止" : "录制语音",
                      systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
            }
            .foregroundStyle(recorder.isRecording ? .red : .blue)

            if recorder.isRecording {
                Circle().fill(.red).frame(width: 8, height: 8)
                    .opacity(recorder.elapsed.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.2)
                Text(mmss(recorder.elapsed))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.red)
                Spacer()
                Text("录音中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 录音播放行

struct AudioPlayerRow: View {
    let fileName: String

    @StateObject private var player = PlayerViewModel()

    var body: some View {
        HStack(spacing: 10) {
            Button {
                player.toggle(TaskStore.url(for: fileName))
            } label: {
                Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            Text(player.durationText)
                .font(.body.monospacedDigit())

            ProgressView(value: player.progress)
                .tint(.blue)
        }
    }
}

@MainActor
final class PlayerViewModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    @Published var progress: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    var durationText: String {
        let d = player?.duration ?? 0
        return mmss(progress > 0 ? d * progress : d)
    }

    func toggle(_ url: URL) {
        if playing {
            player?.pause()
            playing = false
            timer?.invalidate()
            return
        }
        if player == nil {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
        }
        guard let player, player.duration > 0 else { return }
        player.play()
        playing = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player else { return }
                self.progress = p.currentTime / max(p.duration, 0.001)
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playing = false
            self.progress = 0
            self.player?.currentTime = 0
            self.timer?.invalidate()
        }
    }
}
