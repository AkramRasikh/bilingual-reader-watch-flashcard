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
    @Published private(set) var isLooping = false
    let clock = AudioPlaybackClock()

    private static let slowRate: Float = 0.75

    private let player = AVPlayer()
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var loopStart: TimeInterval = 0
    private var loopEnd: TimeInterval?
    private var isSeekingLoop = false

    private init() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isLooping {
                    self.wrapToLoopStart()
                    return
                }
                self.isPlaying = false
                self.clock.publish(from: self.player.currentTime(), item: self.player.currentItem)
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
        play(url: url, cue: cue, key: key, seekEvenIfZero: true)
    }

    func pause() {
        player.pause()
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
        clearLoop()
        clock.reset()
    }

    /// Play the topic file from 0:00 (local if saved, otherwise stream).
    func startShadowing(fileName: String, language: String) {
        clearLoop()
        let key = "shadow:\(language)\u{1f}\(fileName)"
        guard let url = AudioFileStore.playbackURL(fileName: fileName, language: language) else { return }
        play(url: url, cue: 0, key: key, seekEvenIfZero: true)
    }

    func toggleLoop(start: TimeInterval, end: TimeInterval?) {
        if isLooping {
            clearLoop()
            applyLoopEndpoint()
            startObservingTime()
            return
        }
        isLooping = true
        loopStart = max(0, start)
        loopEnd = end
        print("[WordAudioPlayer] loop on \(loopStart) -> \(end.map { String($0) } ?? "nil")")
        startObservingTime()
        applyLoopEndpoint()
        if isPlaying, let end = resolvedLoopEnd() {
            let now = CMTimeGetSeconds(player.currentTime())
            if now.isFinite, now > loopStart + 0.25, now >= end {
                wrapToLoopStart()
            }
        }
    }

    func clearLoop() {
        isLooping = false
        loopStart = 0
        loopEnd = nil
        isSeekingLoop = false
        applyLoopEndpoint()
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
        if let currentURL = currentItemURL() {
            needsNewItem = currentURL.absoluteString != url.absoluteString
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

    private func currentItemURL() -> URL? {
        (player.currentItem?.asset as? AVURLAsset)?.url
    }

    private func seekAndPlay(cue: TimeInterval, key: String, seekEvenIfZero: Bool = false) {
        let targetSeconds = max(0, cue)
        if targetSeconds == 0, !seekEvenIfZero {
            activeKey = key
            applyLoopEndpoint()
            player.rate = playbackRate
            isPlaying = true
            return
        }

        player.pause()
        player.currentItem?.forwardPlaybackEndTime = .invalid
        let time = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                let landed = CMTimeGetSeconds(self.player.currentTime())
                let offTarget = landed.isFinite && abs(landed - targetSeconds) > 0.25
                if !finished || offTarget {
                    self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                        Task { @MainActor in
                            self?.finishSeekAndPlay(key: key)
                        }
                    }
                    return
                }
                self.finishSeekAndPlay(key: key)
            }
        }
    }

    private func finishSeekAndPlay(key: String) {
        activeKey = key
        applyLoopEndpoint()
        player.rate = playbackRate
        isPlaying = true
        clock.publish(from: player.currentTime(), item: player.currentItem)
    }

    private func startObservingTime() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        let seconds = isLooping ? 0.1 : 0.5
        let interval = CMTime(seconds: seconds, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.clock.publish(from: time, item: self.player.currentItem)
                self.wrapLoopIfNeeded(at: time)
            }
        }
    }

    private func resolvedLoopEnd() -> TimeInterval? {
        guard let loopEnd, loopEnd > loopStart else { return nil }
        return loopEnd
    }

    private func applyLoopEndpoint() {
        guard let item = player.currentItem else { return }
        if isLooping, let end = resolvedLoopEnd() {
            item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        } else {
            item.forwardPlaybackEndTime = .invalid
        }
    }

    private func wrapLoopIfNeeded(at time: CMTime) {
        guard isLooping, isPlaying, !isSeekingLoop else { return }
        let seconds = CMTimeGetSeconds(player.currentTime())
        guard seconds.isFinite, let end = resolvedLoopEnd() else { return }
        guard seconds > loopStart + 0.25 else { return }
        guard seconds >= end else { return }
        wrapToLoopStart()
    }

    private func wrapToLoopStart() {
        guard isLooping, !isSeekingLoop else { return }
        isSeekingLoop = true
        player.currentItem?.forwardPlaybackEndTime = .invalid
        let time = CMTime(seconds: loopStart, preferredTimescale: 600)
        print("[WordAudioPlayer] wrap to \(loopStart)")
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                self.isSeekingLoop = false
                guard finished, self.isLooping else { return }
                self.applyLoopEndpoint()
                self.player.rate = self.playbackRate
                self.isPlaying = true
                self.clock.publish(from: self.player.currentTime(), item: self.player.currentItem)
            }
        }
    }

    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[WordAudioPlayer] session error: \(error)")
        }
    }
}
