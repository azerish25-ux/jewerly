//
//  EngineEventTests.swift
//  JewelcraftKitTests
//
//  The observable side of the engine: what it publishes while it changes, and
//  the render requests it hands to the client.
//
//  The original's geometry service pushed state to the WPF client rather than
//  letting it pull. Keeping that shape is what makes the app's view model a
//  subscriber instead of a poller, so the events are part of the contract.
//

import XCTest
@testable import JewelcraftKit

final class EngineEventTests: XCTestCase {

    private let catalog = CatalogService(index: CatalogFixtures.makeIndex())

    private func makeEngine(_ designID: String = "JWL-1001") async throws -> InProcessCADEngine {
        let engine = InProcessCADEngine(sessionID: SessionID("test.events"), catalog: catalog)
        let design = try XCTUnwrap(catalog.design(id: DesignID(designID)))
        let configuration = try ConfigurationFactory.makeConfiguration(for: design, catalog: catalog)
        try await engine.open(design: design, configuration: configuration)
        return engine
    }

    func testOpeningPublishesSessionDesignConfigurationAndGemReport() async throws {
        let engine = InProcessCADEngine(sessionID: SessionID("test.events"), catalog: catalog)
        let stream = EngineEventStream()
        engine.addListener(stream)

        let design = try XCTUnwrap(catalog.design(id: DesignID("JWL-1003")))
        let configuration = try ConfigurationFactory.makeConfiguration(for: design, catalog: catalog)
        try await engine.open(design: design, configuration: configuration)

        let events = await stream.collect(maximum: 6, timeoutSeconds: 1)

        XCTAssertFalse(events.isEmpty, "opening a session published no events at all")
        XCTAssertTrue(events.contains { if case .sessionOpened = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .designLoaded = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .configurationChanged = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .gemReportUpdated = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .undoStateChanged = $0 { return true }; return false })
    }

    func testHighlightingAGemPublishesTheSelectedSlots() async throws {
        let engine = try await makeEngine("JWL-1005")
        let stream = EngineEventStream()
        engine.addListener(stream)

        await engine.highlightGem(slotIndex: 0)
        let events = await stream.collect(maximum: 4, timeoutSeconds: 1) { event in
            if case .selectionChanged = event { return true }
            return false
        }

        let slots = events.compactMap { event -> [Int]? in
            if case .selectionChanged(_, _, let slots) = event { return slots }
            return nil
        }.first
        XCTAssertEqual(slots, [0])
    }

    func testFreehandChangesArePublished() async throws {
        let engine = try await makeEngine()
        let stream = EngineEventStream()
        engine.addListener(stream)

        try await engine.setFreehand(.standard())
        let events = await stream.collect(maximum: 8, timeoutSeconds: 1) { event in
            if case .freehandChanged = event { return true }
            return false
        }

        XCTAssertTrue(events.contains { event in
            if case .freehandChanged(_, let state) = event { return state.isEnabled }
            return false
        })
    }

    func testRenderRequestsNameTheRecoveredTileSizesAndAdvanceWithTheModel() async throws {
        let engine = try await makeEngine()
        let first = try await engine.requestRender(target: .catalogTileWide)
        XCTAssertEqual(first.pixelSize.width, 1240)
        XCTAssertEqual(first.pixelSize.height, 600)

        let square = try await engine.requestRender(target: .catalogTileSquare)
        XCTAssertEqual(square.pixelSize.width, 1240)
        XCTAssertEqual(square.pixelSize.height, 1240)

        // A camera move invalidates rendered pixels without changing the model.
        var viewport = await engine.viewport()
        let revisionBefore = await engine.revision
        viewport.cameraLocation.x += 5
        await engine.setViewport(viewport)
        let revisionAfter = await engine.revision
        XCTAssertGreaterThan(revisionAfter, revisionBefore)
    }

    func testLoadingAnotherDesignRebuildsEverything() async throws {
        let engine = try await makeEngine()
        _ = try await engine.loadDesign(DesignID("JWL-1014"))
        let publishedSnapshot = await engine.snapshot()
        let snapshot = try XCTUnwrap(publishedSnapshot)

        XCTAssertEqual(snapshot.designID, DesignID("JWL-1014"))
        XCTAssertEqual(snapshot.accentPatternKind, .channel)
        XCTAssertGreaterThan(snapshot.gemCount, 1)
    }

    func testTheSameConfigurationBuildsTheSameModel() async throws {
        let first = try await makeEngine()
        let second = try await makeEngine()
        let a = try await first.build()
        let b = try await second.build()

        XCTAssertEqual(a.parts.count, b.parts.count)
        XCTAssertEqual(a.triangleCount, b.triangleCount)
        XCTAssertEqual(a.metalVolumeCubicMillimetres, b.metalVolumeCubicMillimetres, accuracy: 1e-9)
    }
}
