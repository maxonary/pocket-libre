import SwiftUI
import AVFoundation
import Combine

// Ownership transfers once from the preparation task to the main actor.
private final class PreparedAudio: @unchecked Sendable {
    let player: AVAudioPlayer
    init(url: URL) throws { player = try AVAudioPlayer(contentsOf: url); player.prepareToPlay() }
}

@MainActor
final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var recordingID: String?
    @Published private(set) var playing = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var loading = false
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var ticker: AnyCancellable?
    private var interruption: AnyCancellable?
    private var route: AnyCancellable?
    private var requestID = UUID()
    override init() {
        super.init()
        ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.position = player.currentTime; self.playing = player.isPlaying
            }
        }
        interruption = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification).sink { [weak self] _ in
            Task { @MainActor in self?.pause() }
        }
        route = NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).sink { [weak self] note in
            guard let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.pause() }
        }
    }
    func load(_ recording: Recording, url: URL) async {
        guard recordingID != recording.id else { return }
        let token = UUID(); requestID = token
        player?.stop(); player = nil; playing = false
        recordingID = recording.id; duration = recording.duration; position = 0; loading = true; error = nil
        do {
            // Reading a large file must not freeze the playback controls.
            let prepared = try await Task.detached { try PreparedAudio(url: url) }.value.player
            guard requestID == token else { return }
            prepared.delegate = self
            player = prepared; duration = prepared.duration; loading = false
        } catch {
            guard requestID == token else { return }
            self.error = "Audio konnte nicht geöffnet werden."; loading = false
        }
    }
    func toggle() {
        guard let player else { return }
        if player.isPlaying { pause(); return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            if position >= duration - 0.05 { player.currentTime = 0 }
            playing = player.play(); position = player.currentTime
            if !playing { error = "Wiedergabe konnte nicht gestartet werden." }
        } catch { self.error = "Audioausgabe ist momentan nicht verfügbar." }
    }
    func pause() { player?.pause(); playing = false }
    static func clamped(_ value: Double, duration: Double) -> Double {
        guard value.isFinite, duration.isFinite else { return 0 }
        return min(max(value, 0), max(duration, 0))
    }
    func seek(_ value: Double) {
        position = Self.clamped(value, duration: duration); player?.currentTime = position
    }
    func skip(_ seconds: Double) { seek(position + seconds) }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playing = false; position = duration
    }
    static func time(_ value: Double) -> String {
        let seconds = Int(value.isFinite ? max(0, value) : 0)
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct AudioPlayerView: View {
    @ObservedObject var playback: AudioPlayback
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0
    @State private var resumeAfterScrub = false
    var body: some View {
        VStack(spacing: 14) {
            Slider(value: Binding(get: { scrubbing ? scrubPosition : playback.position }, set: { scrubPosition = $0; if !scrubbing { playback.seek($0) } }),
                   in: 0...max(playback.duration, 0.01), onEditingChanged: { editing in
                if editing {
                    scrubPosition = playback.position; resumeAfterScrub = playback.playing
                    scrubbing = true; playback.pause()
                } else {
                    playback.seek(scrubPosition); scrubbing = false
                    if resumeAfterScrub { playback.toggle() }
                }
            }).disabled(playback.loading || playback.error != nil)
                .accessibilityLabel("Wiedergabeposition")
                .accessibilityValue(AudioPlayback.time(scrubbing ? scrubPosition : playback.position))
            HStack {
                Text(AudioPlayback.time(scrubbing ? scrubPosition : playback.position))
                    .accessibilityIdentifier("playback.elapsed")
                Spacer()
                Text("−" + AudioPlayback.time(playback.duration - (scrubbing ? scrubPosition : playback.position)))
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 36) {
                Button { playback.skip(-15) } label: { Image(systemName: "gobackward.15").font(.title2).frame(width: 48, height: 48) }
                    .accessibilityLabel("15 Sekunden zurück")
                Button { playback.toggle() } label: {
                    Group {
                        if playback.loading { ProgressView() }
                        else { Image(systemName: playback.playing ? "pause.fill" : "play.fill").font(.largeTitle) }
                    }.frame(width: 64, height: 64)
                }.accessibilityLabel(playback.playing ? "Pause" : "Abspielen")
                Button { playback.skip(15) } label: { Image(systemName: "goforward.15").font(.title2).frame(width: 48, height: 48) }
                    .accessibilityLabel("15 Sekunden vor")
            }.buttonStyle(.plain).disabled(playback.loading || playback.error != nil)
            if let error = playback.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
        }.tint(OntoraStyle.blue)
    }
}
