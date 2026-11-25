import Foundation

public struct ProviderPlaylist: Identifiable, Sendable, Equatable {
    public let id: String
    public let platform: MusicPlatform
    public let name: String
    public let coverURL: URL?
    public let trackCount: Int?

    public init(id: String, platform: MusicPlatform, name: String, coverURL: URL? = nil, trackCount: Int? = nil) {
        self.id = id
        self.platform = platform
        self.name = name
        self.coverURL = coverURL
        self.trackCount = trackCount
    }
}

public struct ProviderTrack: Identifiable, Sendable, Equatable {
    public let id: String
    public let platform: MusicPlatform
    public let name: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let duration: TimeInterval?
    public let mediaID: String?
    public let hash: String?
    public let albumID: String?
    public let albumAudioID: String?

    public init(id: String, platform: MusicPlatform, name: String, artist: String, album: String? = nil, artworkURL: URL? = nil,
                duration: TimeInterval? = nil, mediaID: String? = nil, hash: String? = nil,
                albumID: String? = nil, albumAudioID: String? = nil) {
        self.id = id
        self.platform = platform
        self.name = name
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
        self.mediaID = mediaID
        self.hash = hash
        self.albumID = albumID
        self.albumAudioID = albumAudioID
    }
}

public protocol PlatformMusicProviderClient: PlatformAccountVerifying {
    var platform: MusicPlatform { get }
    func userPlaylists(cookieHeader: String) async throws -> [ProviderPlaylist]
    func playlistTracks(_ playlist: ProviderPlaylist, cookieHeader: String, limit: Int, offset: Int) async throws -> [ProviderTrack]
    func searchTracks(keyword: String, cookieHeader: String, limit: Int) async throws -> [ProviderTrack]
    func playbackURL(for track: ProviderTrack, cookieHeader: String) async throws -> URL
}

public enum PlatformMusicError: LocalizedError {
    case missingCredential
    case unsupported(String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential: return "请先登录对应音乐平台并验证账号状态。"
        case .unsupported(let message), .unavailable(let message): return message
        }
    }
}
