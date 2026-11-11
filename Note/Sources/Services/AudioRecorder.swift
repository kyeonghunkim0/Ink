import AVFoundation
import Observation

/// 녹음과 재생을 담당한다. 오디오 세션 설정은 이 클래스에서만 한다.
@MainActor
@Observable
final class AudioRecorder: NSObject, AVAudioPlayerDelegate {
    private(set) var isRecording = false
    private(set) var isPlaying = false
    private(set) var recordingStartedAt: Date?
    private(set) var recordingElapsed: TimeInterval = 0
    private(set) var playbackTime: TimeInterval = 0
    private(set) var playbackDuration: TimeInterval = 0
    private(set) var playingRecordingID: UUID?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var recordingURL: URL?

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startRecording() throws -> Date {
        stopPlayback()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.prepareToRecord()
        rec.record()
        recorder = rec
        recordingURL = url
        let start = Date()
        recordingStartedAt = start
        recordingElapsed = 0
        isRecording = true
        startTimer()
        return start
    }

    /// 녹음을 끝내고 (임시 URL, 시작 시각, 길이)를 돌려준다.
    func stopRecording() -> (url: URL, startedAt: Date, duration: TimeInterval)? {
        guard let recorder, let url = recordingURL, let start = recordingStartedAt else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        recordingURL = nil
        recordingStartedAt = nil
        isRecording = false
        stopTimer()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (url, start, duration)
    }

    func play(url: URL, recordingID: UUID) throws {
        stopPlayback()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        let p = try AVAudioPlayer(contentsOf: url)
        p.delegate = self
        p.prepareToPlay()
        p.play()
        player = p
        playingRecordingID = recordingID
        playbackDuration = p.duration
        playbackTime = 0
        isPlaying = true
        startTimer()
    }

    func pausePlayback() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func resumePlayback() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startTimer()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = max(0, min(time, playbackDuration))
        playbackTime = player?.currentTime ?? 0
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        playingRecordingID = nil
        playbackTime = 0
        playbackDuration = 0
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if let recorder { recordingElapsed = recorder.currentTime }
        if let player { playbackTime = player.currentTime }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playbackTime = self.playbackDuration
            self.isPlaying = false
            self.stopTimer()
        }
    }
}
