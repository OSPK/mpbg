import Foundation

struct MPVCommand: Equatable {
    let executable: URL
    let arguments: [String]
}

enum MPVCommandBuilder {
    static func executableURL(fileManager: FileManager = .default) -> URL {
        let candidates = [
            "/opt/homebrew/bin/mpv",
            "/usr/local/bin/mpv",
            "/usr/bin/mpv"
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        return URL(fileURLWithPath: "/usr/bin/env")
    }

    static func command(screen: Int, speed: Double, loop: Bool, flipHorizontally: Bool = true, volume: Double = 0, maximize: Bool = false, filePath: String, ipcServerPath: String? = nil, executable: URL? = nil) -> MPVCommand {
        let resolvedExecutable = executable ?? executableURL()
        let speedString = String(format: "%.3g", speed)
        let volumeString = String(format: "%.0f", min(max(volume, 0), 100))
        var arguments = [
            "--border=no",
            "--loop-file=\(loop ? "inf" : "no")",
            "--autofit-larger=100%x100%",
            "--audio=auto",
            "--volume=\(volumeString)",
            "--window-maximized=\(maximize ? "yes" : "no")",
            "--screen=\(screen)",
            "--speed=\(speedString)",
            filePath
        ]

        if flipHorizontally {
            arguments.insert("--vf=hflip", at: 1)
        }

        if let ipcServerPath {
            arguments.insert("--input-ipc-server=\(ipcServerPath)", at: 0)
        }

        if resolvedExecutable.path == "/usr/bin/env" {
            arguments.insert("mpv", at: 0)
        }

        return MPVCommand(executable: resolvedExecutable, arguments: arguments)
    }
}
