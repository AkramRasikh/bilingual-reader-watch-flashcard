//
//  ShadowingView.swift
//  bilingual reader watch flashcard Watch App
//
//  Start-to-finish topic playback with ±3s skip.
//

import SwiftUI

struct ShadowingView: View {
    let language: String
    let topic: ContentTopic

    @ObservedObject private var audioPlayer = WordAudioPlayer.shared

    private var fileName: String { topic.title }

    var body: some View {
        VStack(spacing: 8) {
            ShadowingProgressView(clock: audioPlayer.clock)

            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 4) {
                    skipButton("-3s", seconds: -3, label: "Rewind 3 seconds")
                    skipButton("-1m", seconds: -60, label: "Rewind 1 minute")
                }

                VStack(spacing: 4) {
                    Button {
                        audioPlayer.togglePlayback()
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 44, height: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
                    .animation(nil, value: audioPlayer.isPlaying)

                    Button {
                        audioPlayer.toggleSlowRate()
                    } label: {
                        Text("0.75×")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .frame(minWidth: 36, minHeight: 28)
                    }
                    .buttonStyle(.bordered)
                    .tint(audioPlayer.playbackRate < 1 ? .orange : .secondary)
                    .controlSize(.mini)
                    .accessibilityLabel(audioPlayer.playbackRate < 1 ? "Normal speed" : "Slow to 0.75")
                    .accessibilityAddTraits(audioPlayer.playbackRate < 1 ? .isSelected : [])
                }

                VStack(spacing: 4) {
                    skipButton("+3s", seconds: 3, label: "Forward 3 seconds")
                    skipButton("+1m", seconds: 60, label: "Forward 1 minute")
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(topic.title)
        .onAppear {
            audioPlayer.startShadowing(fileName: fileName, language: language)
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }

    private func skipButton(_ title: String, seconds: TimeInterval, label: String) -> some View {
        Button {
            audioPlayer.skip(by: seconds)
        } label: {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .frame(minWidth: 36, minHeight: 28)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .accessibilityLabel(label)
    }
}

private struct ShadowingProgressView: View {
    @ObservedObject var clock: AudioPlaybackClock

    var body: some View {
        VStack(spacing: 4) {
            ProgressView(value: clock.progress)
                .tint(.green)
                .transaction { $0.animation = nil }

            HStack {
                Text(formatTime(clock.currentTime))
                Spacer()
                Text(formatTime(clock.duration))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let minutes = total / 60
        let remainder = total % 60
        return "\(minutes):\(String(format: "%02d", remainder))"
    }
}
