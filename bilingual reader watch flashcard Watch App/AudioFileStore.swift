//
//  AudioFileStore.swift
//  bilingual reader watch flashcard Watch App
//
//  Runtime MP3 downloads in Application Support — independent of the
//  JSON word cache and of the app bundle.
//

import Combine
import CryptoKit
import Foundation

enum AudioFileStoreError: Error {
    case missingRemoteURL
    case missingLocalURL
    case badStatus(Int)
}

enum AudioFileStore {
    private static let folderName = "audio-files"

    static func hasFile(language: String, fileName: String) -> Bool {
        guard let url = fileURL(language: language, fileName: fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func fileURL(language: String, fileName: String) -> URL? {
        guard let dir = directoryURL(language: language) else { return nil }
        return dir.appendingPathComponent(diskName(for: fileName), isDirectory: false)
    }

    /// Local file when saved, otherwise the Cloudflare stream URL.
    static func playbackURL(fileName: String, language: String) -> URL? {
        if hasFile(language: language, fileName: fileName) {
            return fileURL(language: language, fileName: fileName)
        }
        return WordAudioPlayer.audioURL(fileName: fileName, language: language)
    }

    static func download(
        language: String,
        fileName: String,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        if hasFile(language: language, fileName: fileName) {
            return
        }

        guard let remote = WordAudioPlayer.audioURL(fileName: fileName, language: language) else {
            throw AudioFileStoreError.missingRemoteURL
        }
        guard let dest = fileURL(language: language, fileName: fileName) else {
            throw AudioFileStoreError.missingLocalURL
        }

        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let (tempURL, response) = try await ProgressFileDownload.download(
            from: remote,
            onProgress: onProgress
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw AudioFileStoreError.badStatus(http.statusCode)
        }

        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        print("[AudioFileStore] saved \(language)/\(fileName)")
        await AudioLibrary.shared.bump()
    }

    private static func directoryURL(language: String) -> URL? {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return root
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(language, isDirectory: true)
    }

    /// Short, filesystem-safe name derived from the CDN basename (`topic.title`).
    private static func diskName(for fileName: String) -> String {
        let digest = SHA256.hash(data: Data(fileName.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).mp3"
    }
}

@MainActor
final class AudioLibrary: ObservableObject {
    static let shared = AudioLibrary()

    @Published private(set) var generation = 0

    func bump() {
        generation += 1
    }
}

/// URLSession download with optional fraction progress. Copies the temp
/// file before the delegate method returns (the system deletes it after).
private final class ProgressFileDownload: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (@Sendable (Double) -> Void)?
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var copiedURL: URL?
    private var urlResponse: URLResponse?
    private var session: URLSession?
    private var settled = false

    private init(onProgress: (@Sendable (Double) -> Void)?) {
        self.onProgress = onProgress
    }

    static func download(
        from remote: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> (URL, URLResponse) {
        let client = ProgressFileDownload(onProgress: onProgress)
        return try await client.start(url: remote)
    }

    private func start(url: URL) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(
                configuration: .default,
                delegate: self,
                delegateQueue: nil
            )
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    private func settle(_ result: Result<(URL, URLResponse), Error>) {
        guard !settled else { return }
        settled = true
        session?.finishTasksAndInvalidate()
        session = nil
        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("mp3")
        do {
            try FileManager.default.copyItem(at: location, to: tmp)
            copiedURL = tmp
            urlResponse = downloadTask.response
        } catch {
            settle(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            settle(.failure(error))
            return
        }
        guard let copiedURL, let urlResponse else {
            settle(.failure(URLError(.badServerResponse)))
            return
        }
        settle(.success((copiedURL, urlResponse)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0, let onProgress else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}
