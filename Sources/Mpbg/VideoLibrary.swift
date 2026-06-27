import AppKit
import Foundation

@MainActor
final class VideoLibrary: ObservableObject {
    @Published var videos: [VideoItem] = [] {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

    @Published private(set) var runningIDs: Set<UUID> = []
    @Published var playlists: [VideoPlaylist] = [] {
        didSet {
            guard !isLoading else { return }
            savePlaylists()
        }
    }
    @Published var selectedPlaylistID: UUID?
    @Published private(set) var activePlaylistIndexByScreen: [Int: Int] = [:]
    @Published private(set) var activePlaylistIDByScreen: [Int: UUID] = [:]
    @Published private(set) var activeVideoIDByScreen: [Int: UUID] = [:]
    @Published var lastError: String?

    private struct Player {
        let screen: Int
        let process: Process
        let ipcSocketPath: String
        var activeVideo: VideoItem
    }

    private var playersByScreen: [Int: Player] = [:]
    private let storeURL: URL
    private let playlistsURL: URL
    private var isLoading = false

    init(storeURL: URL = VideoLibrary.defaultStoreURL(), playlistsURL: URL = VideoLibrary.defaultPlaylistsURL()) {
        self.storeURL = storeURL
        self.playlistsURL = playlistsURL
        load()
    }

    static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Mpbg/videos.json")
    }

    static func defaultPlaylistsURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Mpbg/playlists.json")
    }

    var availableScreenIndexes: [Int] {
        let count = max(NSScreen.screens.count, 1)
        return Array(0..<count)
    }

    var selectedPlaylist: VideoPlaylist? {
        guard let selectedPlaylistID else { return nil }
        return playlists.first { $0.id == selectedPlaylistID }
    }

    var selectedPlaylistVideos: [VideoItem] {
        selectedPlaylist?.videoIDs.compactMap(video) ?? []
    }

    var selectedPlaylistActiveIndex: Int? {
        guard let playlist = selectedPlaylist,
              activePlaylistIDByScreen[playlist.screen] == playlist.id else {
            return nil
        }
        return activePlaylistIndexByScreen[playlist.screen]
    }

    func add(urls: [URL]) {
        let existingPaths = Set(videos.map(\.path))
        let newItems = urls
            .filter { !existingPaths.contains($0.path) }
            .map { VideoItem(path: $0.path) }

        videos.append(contentsOf: newItems)
    }

    func update(_ video: VideoItem) {
        guard let index = videos.firstIndex(where: { $0.id == video.id }) else { return }
        videos[index] = video
        updateActivePlayers(for: video)
    }

    func updateSpeed(for id: UUID, speed: Double) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(speed, 0.25), 3.0)
        videos[index].speed = clamped
        updateActivePlayers(for: id) { player in
            MPVIPCClient.configureSpeed(socketPath: player.ipcSocketPath, speed: clamped)
        } mutate: {
            $0.speed = clamped
        }
    }

    func updateLoop(for id: UUID, loop: Bool) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[index].loop = loop
        updateActivePlayers(for: id) { player in
            MPVIPCClient.configureLoop(socketPath: player.ipcSocketPath, loop: loop)
        } mutate: {
            $0.loop = loop
        }
    }

    func updateFlip(for id: UUID, flipHorizontally: Bool) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[index].flipHorizontally = flipHorizontally
        updateActivePlayers(for: id) { player in
            MPVIPCClient.configureFlip(socketPath: player.ipcSocketPath, flipHorizontally: flipHorizontally)
        } mutate: {
            $0.flipHorizontally = flipHorizontally
        }
    }

    func updateMaximize(for id: UUID, maximize: Bool) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[index].maximize = maximize
        updateActivePlayers(for: id) { player in
            MPVIPCClient.configureMaximize(socketPath: player.ipcSocketPath, maximize: maximize)
        } mutate: {
            $0.maximize = maximize
        }
    }

    func updateVolume(for id: UUID, volume: Double) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(volume, 0), 100)
        videos[index].volume = clamped
        updateActivePlayers(for: id) { player in
            MPVIPCClient.configureVolume(socketPath: player.ipcSocketPath, volume: clamped)
        } mutate: {
            $0.volume = clamped
        }
    }

    func remove(_ video: VideoItem) {
        stop(video)
        videos.removeAll { $0.id == video.id }
        for index in playlists.indices {
            playlists[index].videoIDs.removeAll { $0 == video.id }
            playlists[index].dateUpdated = Date()
        }
    }

    func play(_ video: VideoItem) {
        guard FileManager.default.fileExists(atPath: video.path) else {
            lastError = "File not found: \(video.fileName)"
            return
        }

        activePlaylistIndexByScreen[video.screen] = nil
        activePlaylistIDByScreen[video.screen] = nil
        start(video)
    }

    func enqueue(_ video: VideoItem) {
        let playlistID = playlistIDForQueue(screen: video.screen)
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].videoIDs.append(video.id)
        playlists[index].dateUpdated = Date()
        selectedPlaylistID = playlistID
    }

    func createPlaylist(screen: Int? = nil) {
        let resolvedScreen = screen ?? availableScreenIndexes.first ?? 0
        let playlist = VideoPlaylist(
            name: defaultPlaylistName(screen: resolvedScreen),
            screen: resolvedScreen
        )
        playlists.append(playlist)
        selectedPlaylistID = playlist.id
    }

    func selectPlaylist(_ id: UUID) {
        selectedPlaylistID = id
    }

    func updateSelectedPlaylist(name: String, screen: Int) {
        guard let index = selectedPlaylistIndex else { return }
        let oldScreen = playlists[index].screen
        let playlistID = playlists[index].id
        playlists[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultPlaylistName(screen: screen)
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        playlists[index].screen = screen
        playlists[index].dateUpdated = Date()

        if oldScreen != screen, activePlaylistIDByScreen[oldScreen] == playlistID {
            activePlaylistIDByScreen[oldScreen] = nil
            activePlaylistIndexByScreen[oldScreen] = nil
        }
    }

    func deleteSelectedPlaylist() {
        guard let selectedPlaylistID else { return }
        playlists.removeAll { $0.id == selectedPlaylistID }
        for (screen, playlistID) in activePlaylistIDByScreen where playlistID == selectedPlaylistID {
            activePlaylistIDByScreen[screen] = nil
            activePlaylistIndexByScreen[screen] = nil
        }
        self.selectedPlaylistID = playlists.first?.id
    }

    func clearSelectedPlaylist() {
        guard let index = selectedPlaylistIndex else { return }
        let screen = playlists[index].screen
        playlists[index].videoIDs.removeAll()
        playlists[index].dateUpdated = Date()
        if activePlaylistIDByScreen[screen] == playlists[index].id {
            activePlaylistIDByScreen[screen] = nil
            activePlaylistIndexByScreen[screen] = nil
        }
    }

    func removeFromSelectedPlaylist(at offsets: IndexSet) {
        guard let index = selectedPlaylistIndex else { return }
        playlists[index].videoIDs.remove(atOffsets: offsets)
        playlists[index].dateUpdated = Date()
        activePlaylistIndexByScreen[playlists[index].screen] = nil
    }

    func moveSelectedPlaylistItems(from source: IndexSet, to destination: Int) {
        guard let index = selectedPlaylistIndex else { return }
        playlists[index].videoIDs.move(fromOffsets: source, toOffset: destination)
        playlists[index].dateUpdated = Date()
        activePlaylistIndexByScreen[playlists[index].screen] = nil
    }

    func playPlaylist() {
        guard let playlist = selectedPlaylist else {
            lastError = "Playlist is empty."
            return
        }
        guard !playlist.videoIDs.isEmpty else {
            lastError = "\(playlist.name) is empty."
            return
        }

        playPlaylistItem(playlistID: playlist.id, startingAt: 0)
    }

    func playPlaylistItem(at index: Int) {
        guard let playlist = selectedPlaylist else { return }
        playPlaylistItem(playlistID: playlist.id, startingAt: index)
    }

    func stopSelectedPlaylistScreen() {
        guard let playlist = selectedPlaylist else { return }
        stop(screen: playlist.screen, clearPlaylistState: true)
    }

    func stopSelectedPlaylistItem(at index: Int) {
        guard let playlist = selectedPlaylist,
              activePlaylistIDByScreen[playlist.screen] == playlist.id,
              activePlaylistIndexByScreen[playlist.screen] == index else {
            return
        }
        stop(screen: playlist.screen, clearPlaylistState: true)
    }

    private func playPlaylistItem(playlistID: UUID, startingAt index: Int) {
        guard let playlist = playlists.first(where: { $0.id == playlistID }) else { return }
        guard index < playlist.videoIDs.count else {
            activePlaylistIndexByScreen[playlist.screen] = nil
            activePlaylistIDByScreen[playlist.screen] = nil
            return
        }

        for candidateIndex in index..<playlist.videoIDs.count {
            guard let video = video(for: playlist.videoIDs[candidateIndex]) else { continue }
            guard FileManager.default.fileExists(atPath: video.path) else { continue }
            var playbackVideo = video
            playbackVideo.screen = playlist.screen
            activePlaylistIndexByScreen[playlist.screen] = candidateIndex
            activePlaylistIDByScreen[playlist.screen] = playlist.id
            start(playbackVideo)
            return
        }

        activePlaylistIndexByScreen[playlist.screen] = nil
        activePlaylistIDByScreen[playlist.screen] = nil
    }

    @discardableResult
    private func start(_ video: VideoItem) -> Bool {
        if let player = playersByScreen[video.screen], player.process.isRunning {
            if MPVIPCClient.configureAndLoad(socketPath: player.ipcSocketPath, video: video) {
                var updatedPlayer = player
                updatedPlayer.activeVideo = video
                playersByScreen[video.screen] = updatedPlayer
                refreshRunningIDs()
                return true
            }
        }

        stop(screen: video.screen, clearPlaylistState: false)

        let ipcSocketPath = "/tmp/mpbg-\(UUID().uuidString)-s\(video.screen).sock"
        try? FileManager.default.removeItem(atPath: ipcSocketPath)

        let command = MPVCommandBuilder.command(
            screen: video.screen,
            speed: video.speed,
            loop: video.loop,
            flipHorizontally: video.flipHorizontally,
            volume: video.volume,
            maximize: video.maximize,
            filePath: video.path,
            ipcServerPath: ipcSocketPath
        )
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playersByScreen[video.screen]?.process === process else { return }
                let finishedVideo = self.playersByScreen[video.screen]?.activeVideo
                self.playersByScreen[video.screen] = nil
                self.refreshRunningIDs()

                if let finishedVideo, !finishedVideo.loop {
                    self.advancePlaylist(after: finishedVideo.id)
                }
            }
        }

        do {
            try process.run()
            playersByScreen[video.screen] = Player(
                screen: video.screen,
                process: process,
                ipcSocketPath: ipcSocketPath,
                activeVideo: video
            )
            refreshRunningIDs()
            return true
        } catch {
            activePlaylistIndexByScreen[video.screen] = nil
            activePlaylistIDByScreen[video.screen] = nil
            lastError = "Could not start mpv: \(error.localizedDescription)"
            return false
        }
    }

    private func advancePlaylist(after id: UUID) {
        for (screen, playlistID) in activePlaylistIDByScreen {
            guard let currentIndex = activePlaylistIndexByScreen[screen],
                  let playlist = playlists.first(where: { $0.id == playlistID }),
                  currentIndex < playlist.videoIDs.count,
                  playlist.videoIDs[currentIndex] == id else {
                continue
            }
            playPlaylistItem(playlistID: playlistID, startingAt: currentIndex + 1)
            return
        }
    }

    private func video(for id: UUID) -> VideoItem? {
        videos.first { $0.id == id }
    }

    func stop(_ video: VideoItem) {
        let screens = playersByScreen
            .filter { $0.value.activeVideo.id == video.id }
            .map(\.key)

        for screen in screens {
            stop(screen: screen, clearPlaylistState: true)
        }
    }

    func stopAll() {
        for screen in Array(playersByScreen.keys) {
            stop(screen: screen, clearPlaylistState: true)
        }
        runningIDs.removeAll()
        activePlaylistIndexByScreen.removeAll()
        activePlaylistIDByScreen.removeAll()
    }

    private func stop(screen: Int, clearPlaylistState: Bool) {
        guard let player = playersByScreen[screen] else { return }
        player.process.terminate()
        playersByScreen[screen] = nil
        try? FileManager.default.removeItem(atPath: player.ipcSocketPath)

        if clearPlaylistState {
            activePlaylistIndexByScreen[screen] = nil
            activePlaylistIDByScreen[screen] = nil
        }

        refreshRunningIDs()
    }

    private func refreshRunningIDs() {
        activeVideoIDByScreen = playersByScreen.mapValues(\.activeVideo.id)
        runningIDs = Set(activeVideoIDByScreen.values)
    }

    private func updateActivePlayers(for video: VideoItem) {
        for (screen, player) in playersByScreen where player.activeVideo.id == video.id {
            var playbackVideo = video
            playbackVideo.screen = player.activeVideo.screen
            guard MPVIPCClient.configureProperties(socketPath: player.ipcSocketPath, video: playbackVideo) else {
                continue
            }

            var updatedPlayer = player
            updatedPlayer.activeVideo = playbackVideo
            playersByScreen[screen] = updatedPlayer
        }
        refreshRunningIDs()
    }

    private func updateActivePlayers(
        for id: UUID,
        send: (Player) -> Bool,
        mutate: (inout VideoItem) -> Void
    ) {
        for (screen, player) in playersByScreen where player.activeVideo.id == id {
            guard send(player) else {
                continue
            }

            var updatedPlayer = player
            mutate(&updatedPlayer.activeVideo)
            playersByScreen[screen] = updatedPlayer
        }
        refreshRunningIDs()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        if let data = try? Data(contentsOf: storeURL) {
            do {
            videos = try JSONDecoder().decode([VideoItem].self, from: data)
            } catch {
                lastError = "Could not read saved video library."
            }
        }

        if let data = try? Data(contentsOf: playlistsURL) {
            do {
                playlists = try JSONDecoder().decode([VideoPlaylist].self, from: data)
                selectedPlaylistID = playlists.first?.id
            } catch {
                lastError = "Could not read saved playlists."
            }
        }

        if playlists.isEmpty {
            let screen = availableScreenIndexes.first ?? 0
            let playlist = VideoPlaylist(name: defaultPlaylistName(screen: screen), screen: screen)
            playlists = [playlist]
            selectedPlaylistID = playlist.id
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(videos)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            lastError = "Could not save video library."
        }
    }

    private var selectedPlaylistIndex: Int? {
        guard let selectedPlaylistID else { return nil }
        return playlists.firstIndex { $0.id == selectedPlaylistID }
    }

    private func playlistIDForQueue(screen: Int) -> UUID {
        if let selected = selectedPlaylist, selected.screen == screen {
            return selected.id
        }

        if let existing = playlists.first(where: { $0.screen == screen }) {
            return existing.id
        }

        let playlist = VideoPlaylist(name: defaultPlaylistName(screen: screen), screen: screen)
        playlists.append(playlist)
        return playlist.id
    }

    private func defaultPlaylistName(screen: Int) -> String {
        "Screen \(screen) Playlist"
    }

    private func savePlaylists() {
        do {
            try FileManager.default.createDirectory(
                at: playlistsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(playlists)
            try data.write(to: playlistsURL, options: .atomic)
        } catch {
            lastError = "Could not save playlists."
        }
    }
}
