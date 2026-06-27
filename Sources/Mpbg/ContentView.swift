import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var library = VideoLibrary()
    @State private var isImporterPresented = false

    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            TabView {
                LibraryGridView(
                    videos: library.videos,
                    columns: columns,
                    screenIndexes: library.availableScreenIndexes,
                    runningIDs: library.runningIDs,
                    onAdd: { isImporterPresented = true },
                    onUpdate: library.update,
                    onSpeedChange: library.updateSpeed,
                    onLoopChange: library.updateLoop,
                    onFlipChange: library.updateFlip,
                    onMaximizeChange: library.updateMaximize,
                    onVolumeChange: library.updateVolume,
                    onPlay: library.play,
                    onStop: library.stop,
                    onEnqueue: library.enqueue,
                    onRemove: library.remove
                )
                .tabItem {
                    Label("Library", systemImage: "square.grid.2x2")
                }

                PlaylistView(
                    playlists: library.playlists,
                    selectedPlaylist: library.selectedPlaylist,
                    videos: library.selectedPlaylistVideos,
                    activeIndex: library.selectedPlaylistActiveIndex,
                    screenIndexes: library.availableScreenIndexes,
                    activeVideoIDByScreen: library.activeVideoIDByScreen,
                    onSelect: library.selectPlaylist,
                    onNew: library.createPlaylist,
                    onSaveDetails: library.updateSelectedPlaylist,
                    onDeletePlaylist: library.deleteSelectedPlaylist,
                    onPlay: library.playPlaylist,
                    onStopScreen: library.stopSelectedPlaylistScreen,
                    onClear: library.clearSelectedPlaylist,
                    onPlayItem: library.playPlaylistItem,
                    onStopItem: library.stopSelectedPlaylistItem,
                    onMove: library.moveSelectedPlaylistItems,
                    onDelete: library.removeFromSelectedPlaylist
                )
                .tabItem {
                    Label("Playlist", systemImage: "list.bullet")
                }

                DownloadView(onDownloaded: { url in
                    library.add(urls: [url])
                })
                .tabItem {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
            .navigationTitle("MPBG")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Add Videos", systemImage: "plus")
                    }

                    Button {
                        library.stopAll()
                    } label: {
                        Label("Stop All", systemImage: "stop.fill")
                    }
                    .disabled(library.runningIDs.isEmpty)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                library.add(urls: urls)
            case .failure(let error):
                library.lastError = error.localizedDescription
            }
        }
        .alert("MPBG", isPresented: Binding(
            get: { library.lastError != nil },
            set: { if !$0 { library.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
    }
}

private struct DownloadView: View {
    @StateObject private var manager = DownloadManager()
    let onDownloaded: (URL) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Download")
                    .font(.title2.weight(.semibold))

                urlSection
                folderSection

                if let info = manager.info {
                    formatSection(info)
                    trimSection
                    actionSection
                }

                statusSection
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("URL")
                .font(.headline)
            HStack {
                TextField("https://...", text: $manager.urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if manager.canInspect {
                            manager.inspect()
                        }
                    }

                Button {
                    manager.inspect()
                } label: {
                    Label("Inspect", systemImage: "magnifyingglass")
                }
                .disabled(!manager.canInspect)
            }
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save To")
                .font(.headline)
            HStack {
                Text(manager.outputFolder.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    chooseFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder")
                }
            }
            .padding(10)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func formatSection(_ info: DownloadInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(info.webpageURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Picker("Video", selection: $manager.selectedVideoFormatID) {
                ForEach(info.videoFormats) { format in
                    Text(format.label).tag(format.id)
                }
            }

            Picker("Audio", selection: $manager.selectedAudioFormatID) {
                ForEach(info.audioFormats) { format in
                    Text(format.label).tag(format.id)
                }
            }
        }
    }

    private var trimSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time Range")
                .font(.headline)

            HStack {
                TextField("Start, e.g. 00:01:20", text: $manager.startTime)
                    .textFieldStyle(.roundedBorder)
                TextField("End, e.g. 00:02:10", text: $manager.endTime)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var actionSection: some View {
        HStack {
            Button {
                manager.download(onFinished: onDownloaded)
            } label: {
                Label("Download", systemImage: "arrow.down")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!manager.canDownload)

            if manager.state == .downloading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch manager.state {
            case .idle:
                EmptyView()
            case .inspecting:
                Label("Inspecting formats", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            case .ready:
                Label("Ready to download", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case .downloading:
                Label("Downloading", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            case .finished(let path):
                Label("Added to library", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            if !manager.logText.isEmpty {
                ScrollView {
                    Text(manager.logText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 90, maxHeight: 180)
                .padding(10)
                .background(.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = manager.outputFolder

        if panel.runModal() == .OK, let url = panel.url {
            manager.outputFolder = url
        }
    }
}

private struct LibraryGridView: View {
    let videos: [VideoItem]
    let columns: [GridItem]
    let screenIndexes: [Int]
    let runningIDs: Set<UUID>
    let onAdd: () -> Void
    let onUpdate: (VideoItem) -> Void
    let onSpeedChange: (UUID, Double) -> Void
    let onLoopChange: (UUID, Bool) -> Void
    let onFlipChange: (UUID, Bool) -> Void
    let onMaximizeChange: (UUID, Bool) -> Void
    let onVolumeChange: (UUID, Double) -> Void
    let onPlay: (VideoItem) -> Void
    let onStop: (VideoItem) -> Void
    let onEnqueue: (VideoItem) -> Void
    let onRemove: (VideoItem) -> Void

    var body: some View {
        ScrollView {
            if videos.isEmpty {
                EmptyLibraryView(onAdd: onAdd)
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(videos) { video in
                        VideoCard(
                            video: video,
                            screenIndexes: screenIndexes,
                            isRunning: runningIDs.contains(video.id),
                            onUpdate: onUpdate,
                            onSpeedChange: onSpeedChange,
                            onLoopChange: onLoopChange,
                            onFlipChange: onFlipChange,
                            onMaximizeChange: onMaximizeChange,
                            onVolumeChange: onVolumeChange,
                            onPlay: onPlay,
                            onStop: onStop,
                            onEnqueue: onEnqueue,
                            onRemove: onRemove
                        )
                    }
                }
                .padding(20)
            }
        }
    }
}

private struct PlaylistView: View {
    let playlists: [VideoPlaylist]
    let selectedPlaylist: VideoPlaylist?
    let videos: [VideoItem]
    let activeIndex: Int?
    let screenIndexes: [Int]
    let activeVideoIDByScreen: [Int: UUID]
    let onSelect: (UUID) -> Void
    let onNew: (Int?) -> Void
    let onSaveDetails: (String, Int) -> Void
    let onDeletePlaylist: () -> Void
    let onPlay: () -> Void
    let onStopScreen: () -> Void
    let onClear: () -> Void
    let onPlayItem: (Int) -> Void
    let onStopItem: (Int) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onDelete: (IndexSet) -> Void

    @State private var draftName = ""
    @State private var draftScreen = 0

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)

            Divider()

            detail
        }
        .onAppear(perform: syncDraft)
        .onChange(of: selectedPlaylist) { _ in syncDraft() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Playlists")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    onNew(draftScreen)
                } label: {
                    Label("New Playlist", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("New playlist")
            }

            List(selection: Binding(
                get: { selectedPlaylist?.id },
                set: { if let id = $0 { onSelect(id) } }
            )) {
                ForEach(playlists) { playlist in
                    PlaylistSidebarRow(
                        playlist: playlist,
                        isRunning: activeVideoIDByScreen[playlist.screen] != nil
                    )
                    .tag(Optional(playlist.id))
                }
            }
            .listStyle(.sidebar)
        }
        .padding(16)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 16) {
            detailHeader

            if selectedPlaylist == nil || videos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text(emptyMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(videos.enumerated()), id: \.offset) { index, video in
                        let rowActive = activeIndex == index
                        PlaylistRow(
                            index: index,
                            video: video,
                            playlistScreen: selectedPlaylist?.screen,
                            isActive: rowActive,
                            onPlay: { onPlayItem(index) },
                            onStop: { onStopItem(index) }
                        )
                    }
                    .onMove(perform: onMove)
                    .onDelete(perform: onDelete)
                }
                .listStyle(.inset)
            }

            controls
        }
        .padding(20)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Playlist name", text: $draftName)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .disabled(selectedPlaylist == nil)

                Spacer()

                if let selectedPlaylist {
                    Label("Screen \(selectedPlaylist.screen)", systemImage: "display")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Picker("Screen", selection: $draftScreen) {
                    ForEach(screenIndexes, id: \.self) { index in
                        Text("Screen \(index)").tag(index)
                    }
                }
                .frame(width: 170)
                .disabled(selectedPlaylist == nil)

                Button {
                    onSaveDetails(draftName, draftScreen)
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(selectedPlaylist == nil)

                Button(role: .destructive) {
                    onDeletePlaylist()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedPlaylist == nil)
            }
        }
    }

    private var controls: some View {
        HStack {
            Button(action: onPlay) {
                Label("Play Playlist", systemImage: "play.fill")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .disabled(videos.isEmpty)

            Button(action: onStopScreen) {
                Label("Stop Screen", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!selectedScreenIsRunning)

            Button(action: onClear) {
                Label("Clear", systemImage: "xmark")
            }
            .disabled(videos.isEmpty)

            Spacer()

            if selectedScreenIsRunning, let selectedPlaylist {
                Text("Screen \(selectedPlaylist.screen) is playing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyMessage: String {
        selectedPlaylist == nil ? "Create a playlist or queue a video from the library." : "Queue videos from the grid."
    }

    private var selectedScreenIsRunning: Bool {
        guard let selectedPlaylist else { return false }
        return activeVideoIDByScreen[selectedPlaylist.screen] != nil
    }

    private func syncDraft() {
        draftName = selectedPlaylist?.name ?? ""
        draftScreen = selectedPlaylist?.screen ?? screenIndexes.first ?? 0
    }
}

private struct PlaylistSidebarRow: View {
    let playlist: VideoPlaylist
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isRunning ? "play.circle.fill" : "list.bullet")
                .foregroundStyle(isRunning ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .lineLimit(1)
                Text("Screen \(playlist.screen) - \(playlist.videoIDs.count) videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PlaylistRow: View {
    let index: Int
    let video: VideoItem
    let playlistScreen: Int?
    let isActive: Bool
    let onPlay: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)

            VideoThumbnailView(video: video, cornerRadius: 6)
                .frame(width: 96, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(video.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(video.loop ? "Loop" : "Once")
                    Text(video.flipHorizontally ? "Flip" : "Normal")
                    Text(speedText)
                    Text(volumeText)
                    Text("Screen \(playlistScreen ?? video.screen)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isActive ? onStop() : onPlay()
            } label: {
                Image(systemName: isActive ? "stop.circle.fill" : "play.circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .help(isActive ? "Stop this screen" : "Play this item")
        }
        .padding(.vertical, 6)
        .listRowBackground(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
    }

    private var speedText: String {
        video.speed == 1.0 ? "1x" : String(format: "%.2gx", video.speed)
    }

    private var volumeText: String {
        video.volume <= 0 ? "Muted" : String(format: "%.0f%%", video.volume)
    }
}

private struct VideoThumbnailView: View {
    let video: VideoItem
    var cornerRadius: CGFloat = 8

    @State private var image: NSImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: didFail || !video.exists ? "exclamationmark.triangle.fill" : "play.rectangle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(didFail || !video.exists ? .orange : .secondary)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: video.path) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        image = nil
        didFail = false

        guard video.exists else {
            didFail = true
            return
        }

        let path = video.path
        let generated = await Task.detached(priority: .utility) {
            ThumbnailGenerator.thumbnailData(path: path)
        }.value

        if let generated {
            image = NSImage(data: generated)
            didFail = image == nil
        } else {
            didFail = true
        }
    }
}

private struct EmptyLibraryView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "film.stack")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(.secondary)

            Text("No Videos")
                .font(.title2.weight(.semibold))

            Button(action: onAdd) {
                Label("Add Videos", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
}

private struct VideoCard: View {
    let video: VideoItem
    let screenIndexes: [Int]
    let isRunning: Bool
    let onUpdate: (VideoItem) -> Void
    let onSpeedChange: (UUID, Double) -> Void
    let onLoopChange: (UUID, Bool) -> Void
    let onFlipChange: (UUID, Bool) -> Void
    let onMaximizeChange: (UUID, Bool) -> Void
    let onVolumeChange: (UUID, Double) -> Void
    let onPlay: (VideoItem) -> Void
    let onStop: (VideoItem) -> Void
    let onEnqueue: (VideoItem) -> Void
    let onRemove: (VideoItem) -> Void

    @State private var draft: VideoItem

    init(
        video: VideoItem,
        screenIndexes: [Int],
        isRunning: Bool,
        onUpdate: @escaping (VideoItem) -> Void,
        onSpeedChange: @escaping (UUID, Double) -> Void,
        onLoopChange: @escaping (UUID, Bool) -> Void,
        onFlipChange: @escaping (UUID, Bool) -> Void,
        onMaximizeChange: @escaping (UUID, Bool) -> Void,
        onVolumeChange: @escaping (UUID, Double) -> Void,
        onPlay: @escaping (VideoItem) -> Void,
        onStop: @escaping (VideoItem) -> Void,
        onEnqueue: @escaping (VideoItem) -> Void,
        onRemove: @escaping (VideoItem) -> Void
    ) {
        self.video = video
        self.screenIndexes = screenIndexes
        self.isRunning = isRunning
        self.onUpdate = onUpdate
        self.onSpeedChange = onSpeedChange
        self.onLoopChange = onLoopChange
        self.onFlipChange = onFlipChange
        self.onMaximizeChange = onMaximizeChange
        self.onVolumeChange = onVolumeChange
        self.onPlay = onPlay
        self.onStop = onStop
        self.onEnqueue = onEnqueue
        self.onRemove = onRemove
        _draft = State(initialValue: video)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            thumbnail

            titleBlock

            controls

            actions
        }
        .padding(14)
        .background(.background)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isRunning ? Color.accentColor : Color.secondary.opacity(0.22), lineWidth: isRunning ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: video) { newValue in
            draft = newValue
        }
    }

    private var thumbnail: some View {
        VideoThumbnailView(video: video)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(video.displayName)
                .font(.headline)
                .lineLimit(1)
            Text(video.fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Screen", selection: $draft.screen) {
                ForEach(screenIndexes, id: \.self) { index in
                    Text("Screen \(index)").tag(index)
                }
            }
            .onChange(of: draft.screen) { _ in persistDraft() }

            HStack {
                Toggle("Loop", isOn: Binding(
                    get: { draft.loop },
                    set: {
                        draft.loop = $0
                        onLoopChange(draft.id, draft.loop)
                    }
                ))

                Toggle("Flip", isOn: Binding(
                    get: { draft.flipHorizontally },
                    set: {
                        draft.flipHorizontally = $0
                        onFlipChange(draft.id, draft.flipHorizontally)
                    }
                ))

                Toggle("Maximize", isOn: Binding(
                    get: { draft.maximize },
                    set: {
                        draft.maximize = $0
                        onMaximizeChange(draft.id, draft.maximize)
                    }
                ))
            }

            HStack(spacing: 10) {
                Text("Speed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { draft.speed },
                        set: { setSpeed($0) }
                    ),
                    in: 0.25...3.0,
                    step: 0.05
                )

                Button {
                    setSpeed(1.0)
                } label: {
                    Text(speedLabel)
                        .monospacedDigit()
                        .frame(width: 44)
                }
                .buttonStyle(.bordered)
                .help("Reset speed to 1x")
            }

            HStack(spacing: 10) {
                Text("Sound")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { draft.volume },
                        set: { setVolume($0) }
                    ),
                    in: 0...100,
                    step: 1
                )

                Button {
                    setVolume(draft.volume <= 0 ? 50 : 0)
                } label: {
                    Text(volumeLabel)
                        .monospacedDigit()
                        .frame(width: 44)
                }
                .buttonStyle(.bordered)
                .help(draft.volume <= 0 ? "Set volume to 50%" : "Mute")
            }
        }
    }

    private var actions: some View {
        HStack {
            Button {
                isRunning ? onStop(video) : onPlay(draft)
            } label: {
                Label(isRunning ? "Stop" : "Play", systemImage: isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!video.exists)

            Button {
                onEnqueue(draft)
            } label: {
                Label("Queue", systemImage: "text.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(!video.exists)

            Button(role: .destructive) {
                onRemove(video)
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
        }
    }

    private var speedLabel: String {
        draft.speed == 1.0 ? "1x" : String(format: "%.2gx", draft.speed)
    }

    private var volumeLabel: String {
        draft.volume <= 0 ? "Mute" : String(format: "%.0f%%", draft.volume)
    }

    private func setSpeed(_ value: Double) {
        let clamped = min(max(value, 0.25), 3.0)
        draft.speed = abs(clamped - 1.0) <= 0.04 ? 1.0 : clamped
        onSpeedChange(draft.id, draft.speed)
    }

    private func setVolume(_ value: Double) {
        draft.volume = min(max(value, 0), 100)
        onVolumeChange(draft.id, draft.volume)
    }

    private func persistDraft() {
        onUpdate(draft)
    }
}
