import Foundation
import Testing
@testable import Mpbg

@Test func buildsOriginalMpbgArguments() {
    let command = MPVCommandBuilder.command(
        screen: 1,
        speed: 0.75,
        loop: true,
        flipHorizontally: true,
        filePath: "/tmp/wallpaper video.mp4",
        executable: URL(fileURLWithPath: "/opt/homebrew/bin/mpv")
    )

    #expect(command.executable.path == "/opt/homebrew/bin/mpv")
    #expect(command.arguments == [
        "--border=no",
        "--vf=hflip",
        "--loop-file=inf",
        "--autofit-larger=100%x100%",
        "--audio=auto",
        "--volume=0",
        "--window-maximized=no",
        "--screen=1",
        "--speed=0.75",
        "/tmp/wallpaper video.mp4"
    ])
}

@Test func fallsBackThroughEnvWhenMpvPathIsUnknown() {
    let command = MPVCommandBuilder.command(
        screen: 0,
        speed: 1,
        loop: true,
        flipHorizontally: true,
        filePath: "/tmp/a.mov",
        executable: URL(fileURLWithPath: "/usr/bin/env")
    )

    #expect(command.arguments.first == "mpv")
    #expect(command.arguments.contains("--screen=0"))
    #expect(command.arguments.contains("--speed=1"))
    #expect(command.arguments.contains("--audio=auto"))
    #expect(command.arguments.contains("--volume=0"))
    #expect(command.arguments.contains("--window-maximized=no"))
}

@Test func canStartMaximized() {
    let command = MPVCommandBuilder.command(
        screen: 0,
        speed: 1,
        loop: true,
        flipHorizontally: true,
        volume: 0,
        maximize: true,
        filePath: "/tmp/a.mov",
        executable: URL(fileURLWithPath: "/opt/homebrew/bin/mpv")
    )

    #expect(command.arguments.contains("--window-maximized=yes"))
}

@Test func canDisableInfiniteLoopForPlaylistAdvance() {
    let command = MPVCommandBuilder.command(
        screen: 0,
        speed: 1,
        loop: false,
        flipHorizontally: true,
        filePath: "/tmp/a.mov",
        executable: URL(fileURLWithPath: "/opt/homebrew/bin/mpv")
    )

    #expect(command.arguments.contains("--loop-file=no"))
}

@Test func canDisableHorizontalFlip() {
    let command = MPVCommandBuilder.command(
        screen: 0,
        speed: 1,
        loop: true,
        flipHorizontally: false,
        filePath: "/tmp/a.mov",
        executable: URL(fileURLWithPath: "/opt/homebrew/bin/mpv")
    )

    #expect(!command.arguments.contains("--vf=hflip"))
}

@Test func canStartWithVolume() {
    let command = MPVCommandBuilder.command(
        screen: 0,
        speed: 1,
        loop: true,
        flipHorizontally: true,
        volume: 65,
        filePath: "/tmp/a.mov",
        executable: URL(fileURLWithPath: "/opt/homebrew/bin/mpv")
    )

    #expect(command.arguments.contains("--volume=65"))
    #expect(!command.arguments.contains("--no-audio"))
}
