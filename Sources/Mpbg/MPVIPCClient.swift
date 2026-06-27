import Foundation
import Darwin

enum MPVIPCClient {
    static func configureAndLoad(socketPath: String, video: VideoItem) -> Bool {
        var commands: [[String: Any]] = [
            ["command": ["loadfile", video.path, "replace"]]
        ]
        commands.append(contentsOf: propertyCommands(for: video))
        return send(socketPath: socketPath, commands: commands)
    }

    static func configureProperties(socketPath: String, video: VideoItem) -> Bool {
        send(socketPath: socketPath, commands: propertyCommands(for: video))
    }

    static func configureSpeed(socketPath: String, speed: Double) -> Bool {
        send(socketPath: socketPath, commands: [
            ["command": ["set_property", "speed", min(max(speed, 0.25), 3.0)]]
        ])
    }

    static func configureLoop(socketPath: String, loop: Bool) -> Bool {
        send(socketPath: socketPath, commands: [
            ["command": ["set_property", "loop-file", loop ? "inf" : "no"]]
        ])
    }

    static func configureFlip(socketPath: String, flipHorizontally: Bool) -> Bool {
        send(socketPath: socketPath, commands: [
            ["command": ["set_property", "vf", flipHorizontally ? "hflip" : ""]]
        ])
    }

    static func configureMaximize(socketPath: String, maximize: Bool) -> Bool {
        send(socketPath: socketPath, commands: [
            ["command": ["set_property", "window-maximized", maximize]]
        ])
    }

    static func configureVolume(socketPath: String, volume: Double) -> Bool {
        let clamped = min(max(volume, 0), 100)
        let commands: [[String: Any]] = [
            ["command": ["set_property", "volume", clamped]],
            ["command": ["set_property", "mute", clamped <= 0]]
        ]

        return send(socketPath: socketPath, commands: commands)
    }

    private static func propertyCommands(for video: VideoItem) -> [[String: Any]] {
        [
            ["command": ["set_property", "speed", video.speed]],
            ["command": ["set_property", "loop-file", video.loop ? "inf" : "no"]],
            ["command": ["set_property", "vf", video.flipHorizontally ? "hflip" : ""]],
            ["command": ["set_property", "volume", min(max(video.volume, 0), 100)]],
            ["command": ["set_property", "mute", video.volume <= 0]],
            ["command": ["set_property", "window-maximized", video.maximize]]
        ]
    }

    private static func send(socketPath: String, commands: [[String: Any]]) -> Bool {
        guard let payload = payload(for: commands) else { return false }

        for _ in 0..<5 {
            if sendOnce(socketPath: socketPath, payload: payload) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.08)
        }

        return false
    }

    private static func payload(for commands: [[String: Any]]) -> Data? {
        var lines: [Data] = []
        for command in commands {
            guard let data = try? JSONSerialization.data(withJSONObject: command) else { return nil }
            lines.append(data)
        }

        return lines.reduce(into: Data()) { result, line in
            result.append(line)
            result.append(0x0A)
        }
    }

    private static func sendOnce(socketPath: String, payload: Data) -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
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
        guard copiedPath else { return false }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return false }

        let wroteAllBytes = payload.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return true }
            var written = 0

            while written < rawBuffer.count {
                let result = write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written
                )

                guard result > 0 else { return false }
                written += result
            }

            return true
        }

        guard wroteAllBytes else {
            return false
        }

        shutdown(descriptor, SHUT_WR)
        return true
    }
}
