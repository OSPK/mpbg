import Foundation

struct DownloadFormat: Identifiable, Hashable {
    let id: String
    let label: String
}

struct DownloadInfo {
    let title: String
    let webpageURL: String
    let videoFormats: [DownloadFormat]
    let audioFormats: [DownloadFormat]
}

@MainActor
final class DownloadManager: ObservableObject {
    enum State: Equatable {
        case idle
        case inspecting
        case ready
        case downloading
        case finished(String)
        case failed(String)
    }

    @Published var urlText = ""
    @Published var outputFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser
    @Published var startTime = ""
    @Published var endTime = ""
    @Published var info: DownloadInfo?
    @Published var selectedVideoFormatID = "bestvideo*"
    @Published var selectedAudioFormatID = "bestaudio"
    @Published var state: State = .idle
    @Published var logText = ""

    private var downloadProcess: Process?

    var canInspect: Bool {
        !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state != .inspecting && state != .downloading
    }

    var canDownload: Bool {
        info != nil && state != .inspecting && state != .downloading
    }

    func inspect() {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        state = .inspecting
        logText = "Inspecting formats..."

        Task {
            do {
                let fetched = try await YTDLPClient.fetchInfo(url: url)
                info = fetched
                selectedVideoFormatID = fetched.videoFormats.first?.id ?? "bestvideo*"
                selectedAudioFormatID = fetched.audioFormats.first?.id ?? "bestaudio"
                state = .ready
                logText = "Ready: \(fetched.title)"
            } catch {
                state = .failed(error.localizedDescription)
                logText = error.localizedDescription
            }
        }
    }

    func download(onFinished: @escaping (URL) -> Void) {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        state = .downloading
        logText = "Starting download..."

        Task {
            do {
                let result = try await YTDLPClient.download(
                    url: url,
                    outputFolder: outputFolder,
                    videoFormatID: selectedVideoFormatID,
                    audioFormatID: selectedAudioFormatID,
                    startTime: normalizedTimestamp(startTime),
                    endTime: normalizedTimestamp(endTime),
                    onOutput: { [weak self] line in
                        Task { @MainActor in
                            self?.appendLog(line)
                        }
                    }
                )

                state = .finished(result.path)
                appendLog("Saved: \(result.path)")
                onFinished(result)
            } catch {
                state = .failed(error.localizedDescription)
                appendLog(error.localizedDescription)
            }
        }
    }

    func cancelDownload() {
        downloadProcess?.terminate()
        downloadProcess = nil
        state = .idle
    }

    private func normalizedTimestamp(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func appendLog(_ line: String) {
        if logText.isEmpty {
            logText = line
        } else {
            logText += "\n\(line)"
        }
    }
}

enum YTDLPClient {
    static func fetchInfo(url: String) async throws -> DownloadInfo {
        let data = try await run(arguments: ["--dump-json", "--no-playlist", url]).stdout
        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            throw YTDLPError.message("yt-dlp returned unreadable metadata.")
        }

        let title = json["title"] as? String ?? "Untitled"
        let webpageURL = json["webpage_url"] as? String ?? url
        let formatsJSON = json["formats"] as? [[String: Any]] ?? []
        let formats = parseFormats(formatsJSON)

        return DownloadInfo(
            title: title,
            webpageURL: webpageURL,
            videoFormats: formats.video,
            audioFormats: formats.audio
        )
    }

    static func download(
        url: String,
        outputFolder: URL,
        videoFormatID: String,
        audioFormatID: String,
        startTime: String?,
        endTime: String?,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        var arguments = [
            "--no-playlist",
            "--newline",
            "--merge-output-format", "mkv",
            "--print", "after_move:filepath",
            "-P", outputFolder.path,
            "-o", "%(title).200B [%(id)s].%(ext)s",
            "-f", formatSelector(videoFormatID: videoFormatID, audioFormatID: audioFormatID)
        ]

        if let section = downloadSection(startTime: startTime, endTime: endTime) {
            arguments.append(contentsOf: ["--download-sections", section, "--force-keyframes-at-cuts"])
        }

        arguments.append(url)

        let result = try await run(arguments: arguments, onOutput: onOutput)
        let output = String(data: result.stdout, encoding: .utf8) ?? ""
        let candidates = output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }

        if let existing = candidates.last(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return existing
        }

        throw YTDLPError.message("Download finished, but MPBG could not find the output file.")
    }

    private static func parseFormats(_ formats: [[String: Any]]) -> (video: [DownloadFormat], audio: [DownloadFormat]) {
        var video = [DownloadFormat(id: "bestvideo*", label: "Best video")]
        var audio = [DownloadFormat(id: "bestaudio", label: "Best audio")]

        for format in formats {
            guard let id = format["format_id"] as? String else { continue }
            let vcodec = format["vcodec"] as? String ?? "none"
            let acodec = format["acodec"] as? String ?? "none"

            if vcodec != "none" {
                video.append(DownloadFormat(id: id, label: videoLabel(format)))
            } else if acodec != "none" {
                audio.append(DownloadFormat(id: id, label: audioLabel(format)))
            }
        }

        audio.append(DownloadFormat(id: "none", label: "No audio"))
        return (dedupe(video), dedupe(audio))
    }

    private static func videoLabel(_ format: [String: Any]) -> String {
        let id = format["format_id"] as? String ?? "?"
        let ext = format["ext"] as? String ?? ""
        let resolution = format["resolution"] as? String
            ?? ((format["height"] as? Int).map { "\($0)p" } ?? "video")
        let fps = (format["fps"] as? Double).map { String(format: "%.0ffps", $0) }
        let size = byteLabel(format)
        return [id, resolution, fps, ext, size].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - ")
    }

    private static func audioLabel(_ format: [String: Any]) -> String {
        let id = format["format_id"] as? String ?? "?"
        let ext = format["ext"] as? String ?? ""
        let abr = (format["abr"] as? Double).map { String(format: "%.0fkbps", $0) }
        let size = byteLabel(format)
        return [id, abr, ext, size].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - ")
    }

    private static func byteLabel(_ format: [String: Any]) -> String? {
        let bytes = format["filesize"] as? Int64 ?? format["filesize_approx"] as? Int64
        guard let bytes else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func dedupe(_ formats: [DownloadFormat]) -> [DownloadFormat] {
        var seen = Set<String>()
        return formats.filter { seen.insert($0.id).inserted }
    }

    private static func formatSelector(videoFormatID: String, audioFormatID: String) -> String {
        if audioFormatID == "none" {
            return "\(videoFormatID)/best"
        }
        return "\(videoFormatID)+\(audioFormatID)/\(videoFormatID)/best"
    }

    private static func downloadSection(startTime: String?, endTime: String?) -> String? {
        guard startTime != nil || endTime != nil else { return nil }
        return "*\(startTime ?? "0")-\(endTime ?? "inf")"
    }

    private static func run(
        arguments: [String],
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> (stdout: Data, stderr: Data) {
        try await Task.detached(priority: .userInitiated) {
            let stdoutURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("mpbg-ytdlp-stdout-\(UUID().uuidString).log")
            let stderrURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("mpbg-ytdlp-stderr-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            defer {
                try? FileManager.default.removeItem(at: stdoutURL)
                try? FileManager.default.removeItem(at: stderrURL)
            }

            guard let stdoutHandle = try? FileHandle(forWritingTo: stdoutURL),
                  let stderrHandle = try? FileHandle(forWritingTo: stderrURL) else {
                throw YTDLPError.message("Could not create temporary log files.")
            }
            defer {
                try? stdoutHandle.close()
                try? stderrHandle.close()
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")
            process.arguments = arguments

            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle

            try process.run()
            process.waitUntilExit()
            try? stdoutHandle.synchronize()
            try? stderrHandle.synchronize()

            let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
            let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()

            if let text = String(data: stdoutData + stderrData, encoding: .utf8) {
                text.split(separator: "\n").forEach { onOutput?(String($0)) }
            }

            guard process.terminationStatus == 0 else {
                let message = String(data: stderrData, encoding: .utf8) ?? "yt-dlp failed."
                throw YTDLPError.message(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            return (stdoutData, stderrData)
        }.value
    }
}

enum YTDLPError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}
