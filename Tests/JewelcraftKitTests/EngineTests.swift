//
//  EngineTests.swift
//  JewelcraftKitTests
//
//  The engine seam: one mutation path, one undo stack, one event stream.
//
//  These tests drive the engine the way the app does — through the protocol's
//  methods — so they check the behaviour a customer would see, not the internals
//  of the geometry kernel.
//

import XCTest
@testable import JewelcraftKit

final class EngineTests: XCTestCase {

    let catalog = CatalogService(index: CatalogFixtures.makeIndex())

    func makeEngine(_ designID: String = "JWL-1001") async throws -> InProcessCADEngine {
        let engine = InProcessCADEngine(sessionID: SessionID("test.session"), catalog: catalog)
        let design = try XCTUnwrap(catalog.design(id: DesignID(designID)))
        let configuration = try ConfigurationFactory.makeConfiguration(for: design, catalog: catalog)
        try await engine.open(design: design, configuration: configuration)
        return engine
    }

    func snapshot(_ engine: InProcessCADEngine) async throws -> ConfigurationSnapshot {
        let value = await engine.snapshot()
        return try XCTUnwrap(value)
    }

    func testOpeningASessionBuildsAWatertightRingAndPublishesASnapshot() async throws {
        let engine = try await makeEngine()
        // The session's own snapshot, named so it cannot shadow the helper that
        // fetched it.
        let state = try await snapshot(engine)

        XCTAssertEqual(state.designID, DesignID("JWL-1001"))
        XCTAssertGreaterThan(state.triangleCount, 1_000)
        XCTAssertGreaterThan(state.partCount, 3)
        XCTAssertGreaterThan(state.metalGrams, 0.5)
        XCTAssertTrue(state.issues.isEmpty)

        let built = try await engine.build()
        let openParts = built.parts
            .filter { !$0.mesh.isWatertight }
            .map { "\($0.name) [\($0.kind.rawValue)]: \($0.mesh.defectsDescription)" }
        XCTAssertTrue(openParts.isEmpty, "parts that are not closed: " + openParts.joined(separator: " | "))
        XCTAssertTrue(built.parts.contains { $0.kind == .shank })
        XCTAssertTrue(built.parts.contains { $0.kind == .centreStone })
        XCTAssertEqual(built.gemPlacements.filter { $0.role == .centre }.count, 1)

        let graph = await engine.sceneGraph()
        XCTAssertFalse(graph?.items.isEmpty ?? true)
        XCTAssertTrue(graph?.items.contains { $0.kind == .gem } ?? false)
    }

    func testTwoTonePairingSplitsTheMetalAndAddsWeight() async throws {
        let engine = try await makeEngine()
        let before = try await snapshot(engine)

        // One metal before the pairing, and the whole ring is weighed in it.
        XCTAssertEqual(before.metalBreakdown.count, 1)
        let baseline = try XCTUnwrap(before.metalBreakdown.first)
        XCTAssertEqual(baseline.metal.id, before.metal1ID)
        let singleMetal = try await engine.build()
        XCTAssertEqual(singleMetal.metalGrams, baseline.grams, accuracy: 1e-9)

        let white = try XCTUnwrap(StandardMetals.catalog.metal(id: "gold-14k-white"))
        let platinum = try XCTUnwrap(StandardMetals.catalog.metal(id: "platinum-950"))
        try await engine.setMetals(metal1: white, metal2: platinum)

        let after = try await snapshot(engine)
        XCTAssertEqual(after.metal1ID, "gold-14k-white")
        XCTAssertEqual(after.metal2ID, "platinum-950")

        // Platinum 950 is the denser metal and the head is cast in it, so the
        // ring gains weight. A pairing that changed nothing would mean the
        // second metal never reached the geometry at all.
        XCTAssertGreaterThan(after.metalGrams, before.metalGrams)

        // Two metals, weighed apart, and their sum is the ring.
        XCTAssertEqual(after.metalBreakdown.map(\.metal.id), ["gold-14k-white", "platinum-950"])
        let body = try XCTUnwrap(after.metalBreakdown.first)
        let head = try XCTUnwrap(after.metalBreakdown.last)
        XCTAssertEqual(body.grams + head.grams, after.metalGrams, accuracy: 1e-9)
        XCTAssertEqual(
            body.volumeCubicMillimetres + head.volumeCubicMillimetres,
            after.metalVolumeCubicMillimetres,
            accuracy: 1e-9
        )
        XCTAssertGreaterThan(body.volumeCubicMillimetres, head.volumeCubicMillimetres)
        XCTAssertEqual(
            head.grams,
            head.metal.grams(forCubicMillimetres: head.volumeCubicMillimetres),
            accuracy: 1e-9
        )

        // The head assembly is the second metal; the shank and the metalwork
        // that follows it stay the first.
        let built = try await engine.build()
        let headKinds = PartKind.headPartKinds
        let headParts = built.parts.filter { headKinds.contains($0.kind) }
        XCTAssertFalse(headParts.isEmpty)
        XCTAssertTrue(headParts.allSatisfy { $0.metalID == "platinum-950" })
        let bodyParts = built.parts.filter { $0.kind.isMetal && !headKinds.contains($0.kind) }
        XCTAssertFalse(bodyParts.isEmpty)
        XCTAssertTrue(bodyParts.allSatisfy { $0.metalID == "gold-14k-white" })
    }

    func testAnUnsolderableMetalPairIsRefused() async throws {
        let engine = try await makeEngine()
        let platinum = try XCTUnwrap(StandardMetals.catalog.metal(id: "platinum-950"))
        let titanium = try XCTUnwrap(StandardMetals.catalog.metal(id: "titanium-6al4v"))

        do {
            try await engine.setMetals(metal1: platinum, metal2: titanium)
            XCTFail("platinum and titanium cannot be soldered and must be refused")
        } catch let error as EngineError {
            guard case .metalPairUnsupported = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testCentreCaratIsRoundedToAQuarterWhenRoundingIsOn() async throws {
        let engine = try await makeEngine()
        let startsRounded = try await snapshot(engine).quarterCaratRounding
        XCTAssertTrue(startsRounded)

        try await engine.setCentreGem(carat: 1.13, shape: nil, colourID: nil, qualityID: nil)
        let roundedCarat = try await snapshot(engine).centreCarat ?? 0
        XCTAssertEqual(roundedCarat, 1.25, accuracy: 1e-9)

        _ = try await engine.toggleQuarterCaratRounding()
        try await engine.setCentreGem(carat: 1.13, shape: nil, colourID: nil, qualityID: nil)
        let exactCarat = try await snapshot(engine).centreCarat ?? 0
        XCTAssertEqual(exactCarat, 1.13, accuracy: 1e-9)
    }

    func testACentreWeightOutsideTheDesignsRangeIsRefused() async throws {
        let engine = try await makeEngine()
        do {
            try await engine.setCentreGem(carat: 9.0, shape: nil, colourID: nil, qualityID: nil)
            XCTFail("9 ct is outside this design's range")
        } catch let error as EngineError {
            guard case .caratOutOfRange = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testRingSizeChangesTheInsideDiameterAndTheMetalWeight() async throws {
        let engine = try await makeEngine()
        let before = try await snapshot(engine)

        try await engine.setFingerSize(FingerSize(usSize: 11))
        let after = try await snapshot(engine)

        XCTAssertEqual(after.fingerSizeUS, 11, accuracy: 1e-9)
        XCTAssertGreaterThan(after.innerDiameterMillimetres, before.innerDiameterMillimetres)
        XCTAssertGreaterThan(after.metalGrams, before.metalGrams, "a bigger ring is more metal")
    }

    func testManualSizingIsRecordedOnTheGemReport() async throws {
        let engine = try await makeEngine("JWL-1005")
        try await engine.setManualSize(slotIndex: 0, carat: 0.77)

        let manual = await engine.manualSizedStones()
        XCTAssertEqual(manual.count, 1)
        XCTAssertEqual(manual.first?.carat ?? 0, 0.77, accuracy: 1e-9)
        XCTAssertTrue(manual.first?.isManualSize ?? false)

        let report = await engine.gemReport()
        XCTAssertEqual(report.count, 3, "centre plus two accents")
        XCTAssertEqual(report.first?.index, 1)
    }

    func testUndoAndRedoRestoreThePreviousConfiguration() async throws {
        let engine = try await makeEngine()
        let yellow = try XCTUnwrap(StandardMetals.catalog.metal(id: "gold-14k-yellow"))

        try await engine.setMetals(metal1: yellow, metal2: nil)
        let initialMetal = try await snapshot(engine).metal1ID
        XCTAssertEqual(initialMetal, "gold-14k-yellow")

        try await engine.undo()
        let metalAfterUndo = try await snapshot(engine).metal1ID
        XCTAssertEqual(metalAfterUndo, "gold-14k-white")

        try await engine.redo()
        let metalAfterRedo = try await snapshot(engine).metal1ID
        XCTAssertEqual(metalAfterRedo, "gold-14k-yellow")
    }

    func testAClosedSessionRefusesChanges() async throws {
        let engine = try await makeEngine()
        await engine.close()
        do {
            try await engine.setCentreGem(carat: 1.0, shape: nil, colourID: nil, qualityID: nil)
            XCTFail("a closed session must refuse changes")
        } catch let error as EngineError {
            XCTAssertEqual(error, .sessionClosed)
        }
    }
}
