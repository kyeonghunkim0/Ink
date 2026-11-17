import AVFoundation
import Observation

/// 녹음과 재생을 담당한다. 오디오 세션 설정은 이 클래스에서만 한다.
@MainActor
@Observable
public final class AudioRecorder: NSObject, AVAudioPlayerDelegate {
    public private(set) var isRecording = false
    public private(set) var isPlaying = false
    public private(set) var recordingStartedAt: Date?
    public private(set) var recordingElapsed: TimeInterval = 0
    public private(set) var playbackTime: TimeInterval = 0
    public private(set) var playbackDuration: TimeInterval = 0
    public private(set) var playingRecordingID: UUID?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var recordingURL: URL?

    public override init() { super.init() }

    public func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func startRecording() throws -> Date {
        stopPlayback()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
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
        guard rec.record() else { throw RecordingError.cannotStart }
        recorder = rec
        recordingURL = url
        let start = Date()
        recordingStartedAt = start
        recordingElapsed = 0
        isRecording = true
        startTimer()
        return start
    }

    /// 녹음을 끝내고 (임시 URL, 시작 시각, 길이)를 돌려준다. 오디오가 기록되지 않았으면 에러를 던진다.
    public func stopRecording() throws -> (url: URL, startedAt: Date, duration: TimeInterval) {
        guard let recorder, let url = recordingURL, let start = recordingStartedAt else { throw RecordingError.notRecording }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        recordingURL = nil
        recordingStartedAt = nil
        isRecording = false
        stopTimer()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard duration > 0.3, size > 1024 else {
            try? FileManager.default.removeItem(at: url)
            throw RecordingError.empty
        }
        return (url, start, duration)
    }

    public func play(url: URL, recordingID: UUID) throws {
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

    public func pausePlayback() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    public func resumePlayback() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startTimer()
    }

    public func seek(to time: TimeInterval) {
        player?.currentTime = max(0, min(time, playbackDuration))
        playbackTime = player?.currentTime ?? 0
    }

    public func stopPlayback() {
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

    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playbackTime = self.playbackDuration
            self.isPlaying = false
            self.stopTimer()
        }
    }
}

public enum RecordingError: LocalizedError {
    case cannotStart, notRecording, empty

    public var errorDescription: String? {
        switch self {
        case .cannotStart: "녹음을 시작할 수 없습니다. 마이크를 확인해 주세요."
        case .notRecording: "진행 중인 녹음이 없습니다."
        case .empty: "녹음된 오디오가 없습니다. 마이크 입력을 확인해 주세요."
        }
    }
}
