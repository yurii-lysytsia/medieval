import Foundation

public enum SaveKind: String, Codable, Equatable, Sendable {
    case manual
    case autosave
}

public struct SaveMetadata: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let kind: SaveKind
    public let updatedAt: Date
    public let turn: Int
    public let playerNames: [String]

    public init(id: UUID, name: String, kind: SaveKind, updatedAt: Date, turn: Int, playerNames: [String]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.updatedAt = updatedAt
        self.turn = turn
        self.playerNames = playerNames
    }
}

public struct GameSaveDocument: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let metadata: SaveMetadata
    public let game: GameState
    public let world: WorldState
    public let economy: EconomyState
    public let selectedHexID: HexID?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: SaveKind = .manual,
        updatedAt: Date = Date(),
        game: GameState,
        world: WorldState,
        economy: EconomyState,
        selectedHexID: HexID? = nil
    ) {
        formatVersion = Self.currentFormatVersion
        metadata = SaveMetadata(id: id, name: name, kind: kind, updatedAt: updatedAt, turn: game.turn, playerNames: game.players.map(\.displayName))
        self.game = game
        self.world = world
        self.economy = economy
        self.selectedHexID = selectedHexID
    }
}

public enum GameSaveError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case missingSave(UUID)
    case invalidName
    case unreadableSave

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version): "Версія збереження \(version) не підтримується."
        case .missingSave: "Файл збереження не знайдено."
        case .invalidName: "Вкажіть назву збереження."
        case .unreadableSave: "Збереження пошкоджене або має невідомий формат."
        }
    }
}

/// Where saved matches live.
///
/// Kept behind a protocol so the interface and the autosave can be exercised
/// against an in-memory catalog, without a test writing to the player's real
/// save folder.
public protocol GameSaveCatalog: Sendable {
    func list() -> [SaveMetadata]
    func save(_ document: GameSaveDocument) throws
    func load(_ id: UUID) throws -> GameSaveDocument
    func delete(_ id: UUID) throws
}

/// Saves matches as one JSON file each, under the user's Application Support.
///
/// The coders are built per call rather than held as properties: autosave runs
/// off the main actor, and a shared `JSONEncoder` is not safe to use from two
/// tasks at once. Building one costs far less than a save already does.
public final class FileGameSaveCatalog: GameSaveCatalog {
    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL = FileGameSaveCatalog.defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public static var defaultDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            // Sandboxed macOS apps always have one; falling back on the home
            // directory keeps a missing one from taking the app down with it.
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return root.appendingPathComponent("Medieval", isDirectory: true).appendingPathComponent("Saves", isDirectory: true)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Lists every save, including ones this build cannot open.
    ///
    /// Only the header is decoded, so a file written by a newer format still
    /// appears: a save that quietly vanished from the list because its version
    /// moved on looks to the player exactly like a save that was lost. Loading
    /// it is what reports the version.
    public func list() -> [SaveMetadata] {
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = decoder
        return urls.compactMap { url in
            guard url.pathExtension == Self.fileExtension,
                  let data = try? Data(contentsOf: url),
                  let header = try? decoder.decode(SaveHeader.self, from: data)
            else { return nil }
            return header.metadata
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Just enough of a save file to list it. Decoding the whole document would
    /// tie listing to every model the match state happens to contain today.
    private struct SaveHeader: Decodable {
        let formatVersion: Int
        let metadata: SaveMetadata
    }

    public static let fileExtension = "medievalsave"

    public func save(_ document: GameSaveDocument) throws {
        let name = document.metadata.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GameSaveError.invalidName }
        guard document.formatVersion == GameSaveDocument.currentFormatVersion else {
            throw GameSaveError.unsupportedVersion(document.formatVersion)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(document)
        try data.write(to: url(for: document.metadata.id), options: .atomic)
    }

    public func load(_ id: UUID) throws -> GameSaveDocument {
        let url = url(for: id)
        guard fileManager.fileExists(atPath: url.path) else { throw GameSaveError.missingSave(id) }
        guard let data = try? Data(contentsOf: url) else { throw GameSaveError.unreadableSave }
        let decoder = decoder
        // The version is checked before the body, not after. A save from another
        // format will not decode into today's models at all, so checking
        // afterwards could only ever report it as corrupted — which is the one
        // thing it is not.
        guard let header = try? decoder.decode(SaveHeader.self, from: data) else { throw GameSaveError.unreadableSave }
        guard header.formatVersion == GameSaveDocument.currentFormatVersion else {
            throw GameSaveError.unsupportedVersion(header.formatVersion)
        }
        guard let document = try? decoder.decode(GameSaveDocument.self, from: data) else {
            throw GameSaveError.unreadableSave
        }
        return document
    }

    public func delete(_ id: UUID) throws {
        let url = url(for: id)
        guard fileManager.fileExists(atPath: url.path) else { throw GameSaveError.missingSave(id) }
        try fileManager.removeItem(at: url)
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(Self.fileExtension)
    }
}
