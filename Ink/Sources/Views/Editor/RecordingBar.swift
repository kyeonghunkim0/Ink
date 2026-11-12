import SwiftUI

/// 녹음 중 / 재생 중 상태를 보여주는 플로팅 바.
struct RecordingBar: View {
    let model: EditorModel

    var body: some View {
        AdaptiveGlassContainer(spacing: 12) {
            HStack(spacing: 14) {
                if model.recorder.isRecording {
                    recordingContent
                } else if model.recorder.playingRecordingID != nil {
                    playbackContent
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .adaptiveGlassCapsule()
        }
        .padding(.horizontal, 24)
    }

    private var recordingContent: some View {
        HStack(spacing: 12) {
            Circle().fill(.red).frame(width: 10, height: 10)
                .opacity(Int(model.recorder.recordingElapsed * 2) % 2 == 0 ? 1 : 0.3)
            Text("녹음 중 \(formatDuration(model.recorder.recordingElapsed))")
                .font(.callout.monospacedDigit())
            Button {
                Task { await model.toggleRecording() }
            } label: {
                Label("정지", systemImage: "stop.fill")
            }
            .adaptiveProminentButtonStyle()
            .tint(.red)
        }
    }

    private var playbackContent: some View {
        let recorder = model.recorder
        return HStack(spacing: 12) {
            Button {
                recorder.isPlaying ? recorder.pausePlayback() : recorder.resumePlayback()
            } label: {
                Image(systemName: recorder.isPlaying ? "pause.fill" : "play.fill")
            }
            .adaptiveGlassButtonStyle()
            Text(formatDuration(recorder.playbackTime)).font(.caption.monospacedDigit())
            Slider(
                value: Binding(get: { recorder.playbackTime }, set: { recorder.seek(to: $0) }),
                in: 0...max(recorder.playbackDuration, 0.1))
            .frame(minWidth: 160, maxWidth: 320)
            Text(formatDuration(recorder.playbackDuration)).font(.caption.monospacedDigit())
            if let id = recorder.playingRecordingID,
               let rec = model.manifest.recordings.first(where: { $0.id == id }) {
                Menu {
                    Button(role: .destructive) { model.deleteRecording(rec) } label: { Label("녹음 삭제", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            Button { recorder.stopPlayback() } label: { Image(systemName: "xmark") }
                .adaptiveGlassButtonStyle()
        }
    }
}
