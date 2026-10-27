//
//  FixtureRenderTests.swift
//  JewelcraftKitTests
//
//  Fixtures as documents, and the render assets as data.
//
//  The fixture tests exist to stop the published JSON and the checked Swift from
//  drifting: a fixture is encoded in the canonical form, decoded again, and the
//  two hashes must agree. The render tests pin the two sizes that were actually
//  recovered from the original, and say out loud which sizes were derived.
//

import XCTest
@testable import JewelcraftKit

final class FixtureRenderTests: XCTestCase {

    func testEveryFixtureSurvivesACanonicalRoundTrip() throws {
        func roundTrip<T: CodeFixture>(_ value: T) throws -> String {
            let data = try FixtureBundle.data(for: value, named: T.fixtureName)
            let decoded = try FixtureBundle.decoder().decode(T.self, from: data)
            let again = try FixtureBundle.data(for: decoded, named: T.fixtureName)
            return SHA256.hexDigest(again)
        }

        XCTAssertEqual(
            try FixtureBundle.hash(of: CatalogFixtures.makeIndex(), named: "catalog"),
            try roundTrip(CatalogFixtures.makeIndex())
        )
        XCTAssertEqual(
            try FixtureBundle.hash(of: GemFixtures.catalog, named: "gem-catalog"),
            try roundTrip(GemFixtures.catalog)
        )
        XCTAssertEqual(
            try FixtureBundle.hash(of: RateTableFixtures.make(), named: "rates"),
            try roundTrip(RateTableFixtures.make())
        )
        XCTAssertEqual(
            try FixtureBundle.hash(of: MaterialFixtures.library, named: "materials"),
            try roundTrip(MaterialFixtures.library)
        )
    }

    func testFixtureHashesAreStableAndDistinct() throws {
        let first = try FixtureBundle.allHashes()
        let second = try FixtureBundle.allHashes()
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.keys).count, 4)
        XCTAssertEqual(Set(first.values).count, 4, "every fixture has its own content")
        for value in first.values {
            XCTAssertEqual(value.count, 64, "sha256 hex")
        }
    }

    func testTheManifestNamesEveryFixtureAndItsProvenance() {
        let manifest = FixtureBundle.manifest()
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(Set(manifest.fixtures.keys), ["catalog", "gem-catalog", "rates", "materials"])
        XCTAssertFalse(manifest.provenance.isEmpty)
        XCTAssertEqual(manifest.fixtures["catalog"], "code")
        XCTAssertEqual(manifest.declaredSource(of: "catalog"), .code)
        XCTAssertEqual(FixtureBundle.source(of: "catalog"), .code)
    }

    func testFixturesLoadThroughTheBundleOrFallBackToCode() throws {
        // Either the document shipped (then the manifest says so) or the
        // code-built fixture is used. Both are valid; what is not valid is an
        // empty catalogue.
        let loaded: CatalogIndex = try FixtureBundle.decode("catalog")
        XCTAssertEqual(loaded.designs.count, CatalogFixtures.makeIndex().designs.count)
        XCTAssertEqual(FixtureBundle.source(of: "catalog"), .code)

        let gems: GemCatalog = try FixtureBundle.decode("gem-catalog")
        XCTAssertFalse(gems.definitions.isEmpty)
        let wronglyTyped: RateTable? = try? FixtureBundle.decode("gem-catalog", from: .main)
        XCTAssertNil(wronglyTyped, "a document must not decode as the wrong fixture type")
    }

    func testTheRecoveredCatalogueTileSizesAreExactlyReproduced() {
        XCTAssertEqual(RenderTarget.catalogTileWide.pixelSize, PixelSize(width: 1240, height: 600))
        XCTAssertEqual(RenderTarget.catalogTileSquare.pixelSize, PixelSize(width: 1240, height: 1240))
        XCTAssertTrue(RenderTarget.catalogTileWide.isRecoveredSize)
        XCTAssertTrue(RenderTarget.catalogTileSquare.isRecoveredSize)
    }

    func testDerivedSizesFollowTheirStatedRules() {
        let wide = RenderTarget.catalogTileWide.pixelSize
        let thumbnail = RenderTarget.thumbnail.pixelSize
        XCTAssertFalse(RenderTarget.thumbnail.isRecoveredSize)
        XCTAssertEqual(thumbnail.width * 2, wide.width)
        XCTAssertEqual(thumbnail.height * 2, wide.height)

        let order = RenderTarget.orderImage.pixelSize
        XCTAssertEqual(order.width, wide.width * 2)
        XCTAssertEqual(order.height, wide.height * 2)
        XCTAssertFalse(RenderTarget.orderImage.derivationNote.isEmpty)
    }

    func testTileKeysAddressADesignAtASize() {
        let designID = DesignID("JWL-1001")
        let key = RenderTarget.catalogTileWide.key(for: designID)
        XCTAssertTrue(key.contains("JWL-1001"))
        XCTAssertTrue(key.contains("1240x600"))
        XCTAssertNotEqual(key, RenderTarget.catalogTileSquare.key(for: designID))
    }

    func testEveryMetalAndStoneHasATintableMaterial() {
        let library = MaterialFixtures.library
        XCTAssertEqual(library.missingMetalMaterials(in: StandardMetals.catalog), [])
        XCTAssertEqual(library.missingGemMaterials(), [])

        for metal in StandardMetals.all {
            let material = library.material(for: metal)
            XCTAssertEqual(material.kind, .metal)
            XCTAssertEqual(material.metallic, 1.0, accuracy: 1e-9)
        }

        for gem in GemMaterial.allCases {
            let material = library.material(forGemMaterial: gem, colour: RGBColour(red: 0.2, green: 0.4, blue: 0.8))
            XCTAssertEqual(material.kind, .gem)
            XCTAssertLessThan(material.opacity, 1.0)
            XCTAssertGreaterThan(material.indexOfRefraction, 1.0)
        }
    }

    func testTintingMovesTheColourTowardsTheStone() {
        let library = MaterialFixtures.library
        let white = library.material(forGemMaterial: .diamond, colour: .white)
        let blue = library.material(forGemMaterial: .diamond, colour: RGBColour(red: 0.2, green: 0.4, blue: 0.9))

        // The gem base colour is a cool white, so "bluer than the white stone"
        // is not the property that matters — the tint has to make the stone
        // read as blue, and leave a colourless stone neutral.
        let blueDominance = blue.baseColour.blue - blue.baseColour.red
        let whiteDominance = white.baseColour.blue - white.baseColour.red
        XCTAssertGreaterThan(blueDominance, whiteDominance)
        XCTAssertGreaterThan(blueDominance, 0.15)
        XCTAssertLessThan(abs(whiteDominance), 0.05)
        XCTAssertNotEqual(white.baseColourHex, blue.baseColourHex)
    }

    func testTheFallbackMaterialIsUsableWhenAnIDIsUnknown() {
        let library = MaterialFixtures.library
        XCTAssertEqual(library.material(id: "metal.does-not-exist"), nil)
        XCTAssertEqual(library.fallback.id, "neutral.white-metal")
        XCTAssertNotNil(RGBColour(hex: library.renderOptions.backgroundHex))
        XCTAssertGreaterThan(library.renderOptions.environmentIntensity, 0)
    }
}
