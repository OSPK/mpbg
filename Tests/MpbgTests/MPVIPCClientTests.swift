import Foundation
import Darwin
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

    if let sampleURL = sampleVideoURL() {
        let item = VideoItem(path: sampleURL.path, screen: 0, speed: 1, loop: true, flipHorizontally: false, volume: 0, maximize: false)
        #expect(MPVIPCClient.configureAndLoad(socketPath: socketURL.path, video: item))
        var loadedPath: String?
        for _ in 0..<20 {
            loadedPath = readPath(socketPath: socketURL.path)
            if loadedPath == sampleURL.path { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(loadedPath == sampleURL.path)
    }
}

private func createFile(_ url: URL) -> URL {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    return url
}

private func sampleVideoURL() -> URL? {
    let candidates = [
        "/Users/waqas/web/Percy Jackson： Sea Of Monsters ｜ Official Trailer #2 HD ｜ 2013 [xg3znoE9m7I].mkv",
        "/Users/waqas/web/Tremors Official Trailer #1 - (1990) HD [liJfZvXdiTE].webm"
    ]

    return candidates
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.fileExists(atPath: $0.path) }
}

private func readPath(socketPath: String) -> String? {
    let payload = Data(#"{"request_id":1,"command":["get_property","path"]}"#.utf8) + Data([0x0A])
    guard let response = sendAndRead(socketPath: socketPath, payload: payload),
          let object = try? JSONSerialization.jsonObject(with: response),
          let json = object as? [String: Any] else {
        return nil
    }

    return json["data"] as? String
}

private func sendAndRead(socketPath: String, payload: Data) -> Data? {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return nil }
    defer { close(descriptor) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    #if os(macOS)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    #endif

    let copiedPath = socketPath.withCString { pathPointer in
        withUnsafeMutableBytes(of: &address.sun_path) { pathBytes in
            guard socketPath.utf8.count < pathBytes.count,
                  let baseAddress = pathBytes.baseAddress else {
                return false
            }

            let destination = baseAddress.assumingMemoryBound(to: CChar.self)
            destination.initialize(repeating: 0, count: pathBytes.count)
            strncpy(destination, pathPointer, pathBytes.count - 1)
            return true
        }
    }
    guard copiedPath else { return nil }

    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { return nil }

    let wrote = payload.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return true }
        return write(descriptor, baseAddress, rawBuffer.count) == rawBuffer.count
    }
    guard wrote else { return nil }
    shutdown(descriptor, SHUT_WR)

    var buffer = [UInt8](repeating: 0, count: 4096)
    let count = read(descriptor, &buffer, buffer.count)
    guard count > 0 else { return nil }
    return Data(buffer.prefix(count))
}
