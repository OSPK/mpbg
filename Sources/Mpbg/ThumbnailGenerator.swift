import AVFoundation
import AppKit
import Foundation

enum ThumbnailGenerator {
    static func thumbnailData(path: String) -> Data? {
        avFoundationThumbnailData(path: path) ?? ffmpegThumbnailData(path: path)
    }

    private static func avFoundationThumbnailData(path: String) -> Data? {
        let asset = AVAsset(url: URL(fileURLWithPath: path))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        for seconds in [1.0, 0.1, 0.0] {
            do {
                let cgImage = try generator.copyCGImage(
                    at: CMTime(seconds: seconds, preferredTimescale: 600),
                    actualTime: nil
                )
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                if let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) {
                    return data
                }
            } catch {
                continue
            }
        }

        return nil
    }

    private static func ffmpegThumbnailData(path: String) -> Data? {
        guard let ffmpegURL = ffmpegURL() else { return nil }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mpbg-thumbnail-\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-ss", "1",
            "-i", path,
            "-frames:v", "1",
            "-vf", "scale=640:-1",
            "-q:v", "3",
            outputURL.path
        ]

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return try Data(contentsOf: outputURL)
        } catch {
            return nil
        }
    }

    private static func ffmpegURL() -> URL? {
        for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }
}
