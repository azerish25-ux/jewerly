//
//  FixtureBundle.swift
//  JewelcraftKit
//
//  Fixture loading.
//
//  Two rules shape this file:
//
//   1. There is no code path that can leave the app with no catalogue, no price
//      list and no materials. Every fixture has a code-built equivalent, and a
//      missing or unreadable document falls back to it rather than failing. A
//      rebuilt studio that cannot show a ring because a JSON file did not ship
//      would be a worse product than the original.
//
//   2. The two forms are never allowed to disagree silently. `FixtureBundle`
//      reports which form was used, the manifest states the intended source,
//      and the test suite asserts the code-built fixture re-encodes to exactly
//      the bytes on disk.
//

import Foundation

// MARK: - Code fixtures

/// A fixture that can be built in code.
public protocol CodeFixture: Codable {
    /// Document name, without the `.json` extension.
    static var fixtureName: String { get }
    /// The fixture itself. Deterministic: same call, same bytes.
    static func make() -> Self
}

/// Where a loaded fixture actually came from.
public enum FixtureSource: String, Codable, Sendable {
    case json
    case code

    public var description: String {
        switch self {
        case .json: return "loaded from the bundled JSON document"
        case .code: return "built in code (no bundled document)"
        }
    }
}

/// The manifest that ships next to the fixtures.
public struct FixtureManifest: Codable, Sendable {
    public var schemaVersion: Int
    public var generatedBy: String
    public var generator: String
    public var note: String
    public var fixtures: [String: String]
    public var provenance: String

    public init(
        schemaVersion: Int,
        generatedBy: String,
        generator: String,
        note: String,
        fixtures: [String: String],
        provenance: String
    ) {
        self.schemaVersion = schemaVersion
        self.generatedBy = generatedBy
        self.generator = generator
        self.note = note
        self.fixtures = fixtures
        self.provenance = provenance
    }

    /// What the manifest says the intended source of a fixture is.
    public func declaredSource(of name: String) -> FixtureSource {
        FixtureSource(rawValue: fixtures[name] ?? "code") ?? .code
    }

    public static func make() -> FixtureManifest {
        FixtureManifest(
            schemaVersion: 1,
            generatedBy: "JewelcraftKit.FixtureBundle.writeAllFixtures(to:)",
            generator: "swift run generate-fixtures",
            note: "Fixture documents are published as JSON and checked against the code-built fixtures.",
            fixtures: [
                CatalogIndex.fixtureName: FixtureSource.code.rawValue,
                GemCatalog.fixtureName: FixtureSource.code.rawValue,
                RateTable.fixtureName: FixtureSource.code.rawValue,
                MaterialLibrary.fixtureName: FixtureSource.code.rawValue
            ],
            provenance: "Synthetic fixture data."
        )
    }
}

// MARK: - Errors

public enum FixtureError: Error, Equatable, CustomStringConvertible {
    case unavailable(String)
    case encodingFailed(String)

    public var description: String {
        switch self {
        case .unavailable(let name):
            return "No fixture named \(name) could be loaded or built."
        case .encodingFailed(let name):
            return "Fixture \(name) could not be encoded."
        }
    }
}

// MARK: - Loader

public enum FixtureBundle {

    /// Fixture load happens once per process, but the app and the tests may ask
    /// from different threads, so the record of what was loaded is guarded.
    private static let lock = NSLock()
    private static var loadedSources: [String: FixtureSource] = [:]

    /// The canonical JSON encoder for fixtures: sorted keys and stable
    /// formatting, so a regenerated document is byte-identical to the committed
    /// one. Without this, "the JSON matches the code" would be meaningless.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    public static func manifest(from bundle: Bundle = .module) -> FixtureManifest {
        guard
            let url = bundle.url(forResource: "fixtures-manifest", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let manifest = try? decoder().decode(FixtureManifest.self, from: data)
        else {
            return FixtureManifest.make()
        }
        return manifest
    }

    /// Loads a fixture: the bundled document when it is present and readable,
    /// the code-built equivalent otherwise.
    public static func decode<T: CodeFixture>(_ name: String, from bundle: Bundle = .module) throws -> T {
        guard name == T.fixtureName else {
            throw FixtureError.unavailable("\(name) (asked for \(name); the fixture type is \(T.fixtureName))")
        }
        if let url = bundle.url(forResource: name, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let value = try? decoder().decode(T.self, from: data) {
            record(source: .json, for: name)
            return value
        }
        record(source: .code, for: name)
        return T.make()
    }

    /// Which form the last load of a fixture used.
    public static func source(of name: String) -> FixtureSource {
        lock.lock()
        defer { lock.unlock() }
        return loadedSources[name] ?? .code
    }

    public static var sources: [String: FixtureSource] {
        lock.lock()
        defer { lock.unlock() }
        return loadedSources
    }

    private static func record(source: FixtureSource, for name: String) {
        lock.lock()
        loadedSources[name] = source
        lock.unlock()
    }

    /// The bundled JSON for a fixture, when the document shipped.
    public static func rawJSON(named name: String, from bundle: Bundle = .module) -> Data? {
        guard let url = bundle.url(forResource: name, withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Encodes a fixture in the canonical form: sorted keys, two-space indent,
    /// trailing newline.
    public static func data<T: Encodable>(for value: T, named name: String) throws -> Data {
        do {
            var data = try encoder().encode(value)
            data.append(0x0A)
            return data
        } catch {
            throw FixtureError.encodingFailed(name)
        }
    }

    /// SHA-256 of a fixture's canonical bytes, recorded in the fidelity ledger
    /// so a fixture change is visible rather than silent.
    public static func hash<T: Encodable>(of value: T, named name: String) throws -> String {
        SHA256.hexDigest(try data(for: value, named: name))
    }

    /// Every fixture's hash, keyed by document name.
    public static func allHashes() throws -> [String: String] {
        [
            CatalogIndex.fixtureName: try hash(of: CatalogFixtures.makeIndex(), named: CatalogIndex.fixtureName),
            GemCatalog.fixtureName: try hash(of: GemFixtures.catalog, named: GemCatalog.fixtureName),
            RateTable.fixtureName: try hash(of: RateTableFixtures.make(), named: RateTable.fixtureName),
            MaterialLibrary.fixtureName: try hash(of: MaterialFixtures.library, named: MaterialLibrary.fixtureName)
        ]
    }

    /// Writes every fixture to a directory, which is what the generator tool
    /// does. Returns the files written.
    @discardableResult
    public static func writeAllFixtures(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var written: [URL] = []
        func write<T: CodeFixture>(_ value: T) throws {
            let payload = try data(for: value, named: T.fixtureName)
            let url = directory.appendingPathComponent("\(T.fixtureName).json")
            try payload.write(to: url)
            written.append(url)
        }

        try write(CatalogFixtures.makeIndex())
        try write(GemFixtures.catalog)
        try write(RateTableFixtures.make())
        try write(MaterialFixtures.library)

        let manifestURL = directory.appendingPathComponent("fixtures-manifest.json")
        try data(for: FixtureManifest.make(), named: "fixtures-manifest").write(to: manifestURL)
        written.append(manifestURL)

        return written
    }
}
