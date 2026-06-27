import Foundation
import Testing
@testable import Mpbg

@Test func sendsLivePlaybackCommandsToMpvSocket() async throws {
    let socketURL = URL(fileURLWithPath: "/tmp/mpbg-ipc-test-\(UUID().uuidString).sock")
    let logURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("mpbg-ipc-test-\(UUID().uuidString).log")
    defer {
        try? FileManager.default.removeItem(at: socketURL)
        try? FileManager.default.removeItem(at: logURL)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/mpv")
    process.arguments = [
        "--no-config",
        "--idle=yes",
        "--force-window=no",
        "--terminal=no",
        "--input-ipc-server=\(socketURL.path)"
    ]
    process.standardOutput = try FileHandle(forWritingTo: createFile(logURL))
    process.standardError = process.standardOutput
    try process.run()
    defer {
        process.terminate()
        process.waitUntilExit()
    }

    for _ in 0..<20 where !FileManager.default.fileExists(atPath: socketURL.path) {
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(FileManager.default.fileExists(atPath: socketURL.path))
    #expect(MPVIPCClient.configureSpeed(socketPath: socketURL.path, speed: 1.25))
    #expect(MPVIPCClient.configureLoop(socketPath: socketURL.path, loop: false))
    #expect(MPVIPCClient.configureFlip(socketPath: socketURL.path, flipHorizontally: true))
    #expect(MPVIPCClient.configureMaximize(socketPath: socketURL.path, maximize: true))
    #expect(MPVIPCClient.configureVolume(socketPath: socketURL.path, volume: 60))
}

private func createFile(_ url: URL) -> URL {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    return url
}
