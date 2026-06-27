import Foundation

struct VideoPlaylist: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var screen: Int
    var videoIDs: [UUID]
    var dateCreated: Date
    var dateUpdated: Date

    init(
        id: UUID = UUID(),
        name: String,
        screen: Int,
        videoIDs: [UUID] = [],
        dateCreated: Date = Date(),
        dateUpdated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.screen = screen
        self.videoIDs = videoIDs
        self.dateCreated = dateCreated
        self.dateUpdated = dateUpdated
    }
}
