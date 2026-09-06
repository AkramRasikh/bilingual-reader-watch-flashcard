//
//  WordAudioPlayer.swift
//  bilingual reader watch flashcard Watch App
//
//  Plays topic MP3s from local storage when saved, otherwise streams
//  from Cloudflare (web getAudioURL).
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPlaybackClock: ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    func reset() {
        currentTime = 0
        duration = 0
    }

    func publish(from time: CMTime, item: AVPlayerItem?) {
        let seconds = CMTimeGetSeconds(time)
        let nextTime = seconds.isFinite ? max(0, seconds) : 0
        if abs(nextTime - currentTime) >= 0.2 {
            currentTime = nextTime
        }
        guard let item else { return }
        let itemDuration = CMTimeGetSeconds(item.duration)
        if itemDuration.isFinite, itemDuration > 0, itemDuration != duration {
            duration = itemDuration
        }
    }
}

@MainActor
final class WordAudioPlayer: ObservableObject {
    static let shared = WordAudioPlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var activeKey: String?
    @Published private(set) var playbackRate: Float = 1
    let clock = AudioPlaybackClock()

    private static let slowRate: Float = 0.75

    private let player = AVPlayer()
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?

    private init() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.clock.publish(from: self?.player.currentTime() ?? .zero, item: self?.player.currentItem)
            }
        }
    }

    deinit {
        statusObserver?.invalidate()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    /// Same shape as web `getAudioURL(title, language)`.
    nonisolated static func audioURL(fileName: String, language: String) -> URL? {
        let base = GeneratedEnv.cloudflareAssetsURL.absoluteString
        let trimmedBase = base.hasSuffix("/") ? base : base + "/"
        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        return URL(string: "\(trimmedBase)\(language)-audio/\(encodedName).mp3")
    }

    nonisolated static func itemKey(fileName: String, language: String, cue: TimeInterval) -> String {
        "\(language)\u{1f}\(fileName)#\(cue)"
    }

    func toggle(fileName: String, language: String, cue: TimeInterval) {
        let key = Self.itemKey(fileName: fileName, language: language, cue: cue)

        if isPlaying, activeKey == key {
            pause()
            return
        }

        guard let url = AudioFileStore.playbackURL(fileName: fileName, language: language) else { return }
        play(url: url, cue: cue, key: key)
    }

    func pause() {
        player.rate = 0
        isPlaying = false
    }

    func stop() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        activeKey = nil
        playbackRate = 1
        clock.reset()
    }

    /// Play the topic file from 0:00 (local if saved, otherwise stream).
    func startShadowing(fileName: String, language: String) {
        let key = "shadow:\(language)\u{1f}\(fileName)"
        guard let url = AudioFileStore.playbackURL(fileName: fileName, language: language) else { return }
        play(url: url, cue: 0, key: key, seekEvenIfZero: true)
    }

    func togglePlayback() {
        if isPlaying {
            pause()
            return
        }
        guard let item = player.currentItem else { return }
        let current = CMTimeGetSeconds(player.currentTime())
        let duration = CMTimeGetSeconds(item.duration)
        if current.isFinite, duration.isFinite, duration > 0, current >= duration - 0.25 {
            seekAndPlay(cue: 0, key: activeKey ?? "", seekEvenIfZero: true)
            return
        }
        player.rate = playbackRate
        isPlaying = true
    }

    func toggleSlowRate() {
        let next = playbackRate == Self.slowRate ? Float(1) : Self.slowRate
        if isPlaying {
            player.rate = next
        }
        playbackRate = next
    }

    func skip(by seconds: TimeInterval) {
        guard let item = player.currentItem else { return }
        let current = CMTimeGetSeconds(player.currentTime())
        guard current.isFinite else { return }

        var duration = CMTimeGetSeconds(item.duration)
        if !duration.isFinite || duration < 0 {
            duration = .greatestFiniteMagnitude
        }
        let target = min(max(0, current + seconds), duration)
        let time = CMTime(seconds: target, preferredTimescale: 600)
        let shouldResume = isPlaying
        let slack = CMTime(seconds: 0.15, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: slack, toleranceAfter: slack) { [weak self] finished in
            Task { @MainActor in
                guard let self, finished else { return }
                self.clock.publish(from: self.player.currentTime(), item: self.player.currentItem)
                if shouldResume {
                    self.player.rate = self.playbackRate
                    self.isPlaying = true
                }
            }
        }
    }

    private func play(url: URL, cue: TimeInterval, key: String, seekEvenIfZero: Bool = false) {
        activateSession()

        let needsNewItem: Bool
        if let currentURL = (player.currentItem?.asset as? AVURLAsset)?.url {
            needsNewItem = currentURL != url
        } else {
            needsNewItem = true
        }

        if needsNewItem {
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            player.automaticallyWaitsToMinimizeStalling = !url.isFileURL
            startObservingTime()
            statusObserver?.invalidate()
            statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if item.status == .readyToPlay {
                        self.seekAndPlay(cue: cue, key: key, seekEvenIfZero: seekEvenIfZero)
                    } else if item.status == .failed {
                        print("[WordAudioPlayer] failed: \(item.error?.localizedDescription ?? "?")")
                        self.isPlaying = false
                        self.activeKey = nil
                    }
                }
            }
            activeKey = key
            // Seek once ready; also try immediately in case already ready.
            if item.status == .readyToPlay {
                seekAndPlay(cue: cue, key: key, seekEvenIfZero: seekEvenIfZero)
            }
        } else {
            if timeObserver == nil {
                startObservingTime()
            }
            seekAndPlay(cue: cue, key: key, seekEvenIfZero: seekEvenIfZero)
        }
    }

    private func seekAndPlay(cue: TimeInterval, key: String, seekEvenIfZero: Bool = false) {
        if cue <= 0, !seekEvenIfZero {
            activeKey = key
            player.rate = playbackRate
            isPlaying = true
            return
        }

        let time = CMTime(seconds: max(0, cue), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, finished else { return }
                self.activeKey = key
                self.player.rate = self.playbackRate
                self.isPlaying = true
                self.clock.publish(from: self.player.currentTime(), item: self.player.currentItem)
            }
        }
    }

    private func startObservingTime() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.clock.publish(from: time, item: self?.player.currentItem)
            }
        }
    }

    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("[WordAudioPlayer] session error: \(error)")
        }
    }
}
