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

public protocol GameSaveCatalog: Sendable {
    func list() -> [SaveMetadata]
    func save(_ document: GameSaveDocument) throws
    func load(_ id: UUID) throws -> GameSaveDocument
    func delete(_ id: UUID) throws
}

public final class FileGameSaveCatalog: GameSaveCatalog, @unchecked Sendable {
    public let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL = FileGameSaveCatalog.defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public static var defaultDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("Medieval", isDirectory: true).appendingPathComponent("Saves", isDirectory: true)
    }

    public func list() -> [SaveMetadata] {
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "medievalsave",
                  let data = try? Data(contentsOf: url),
                  let document = try? decoder.decode(GameSaveDocument.self, from: data),
                  document.formatVersion == GameSaveDocument.currentFormatVersion
            else { return nil }
            return document.metadata
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

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
        let document: GameSaveDocument
        do {
            document = try decoder.decode(GameSaveDocument.self, from: Data(contentsOf: url))
        } catch {
            throw GameSaveError.unreadableSave
        }
        guard document.formatVersion == GameSaveDocument.currentFormatVersion else {
            throw GameSaveError.unsupportedVersion(document.formatVersion)
        }
        return document
    }

    public func delete(_ id: UUID) throws {
        let url = url(for: id)
        guard fileManager.fileExists(atPath: url.path) else { throw GameSaveError.missingSave(id) }
        try fileManager.removeItem(at: url)
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("medievalsave")
    }
}
