import Foundation

struct VideoItem: Identifiable, Codable, Equatable {
    var id: UUID
    var path: String
    var screen: Int
    var speed: Double
    var loop: Bool
    var flipHorizontally: Bool
    var volume: Double
    var maximize: Bool
    var dateAdded: Date

    init(id: UUID = UUID(), path: String, screen: Int = 0, speed: Double = 1.0, loop: Bool = true, flipHorizontally: Bool = true, volume: Double = 0, maximize: Bool = false, dateAdded: Date = Date()) {
        self.id = id
        self.path = path
        self.screen = screen
        self.speed = speed
        self.loop = loop
        self.flipHorizontally = flipHorizontally
        self.volume = volume
        self.maximize = maximize
        self.dateAdded = dateAdded
    }

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case screen
        case speed
        case loop
        case flipHorizontally
        case volume
        case maximize
        case dateAdded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        screen = try container.decode(Int.self, forKey: .screen)
        speed = try container.decode(Double.self, forKey: .speed)
        loop = try container.decodeIfPresent(Bool.self, forKey: .loop) ?? true
        flipHorizontally = try container.decodeIfPresent(Bool.self, forKey: .flipHorizontally) ?? true
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0
        maximize = try container.decodeIfPresent(Bool.self, forKey: .maximize) ?? false
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }

    var fileName: String {
        url.lastPathComponent
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
