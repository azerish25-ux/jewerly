//
//  ConfigurationTests.swift
//  JewelcraftKitTests
//
//  The configuration rules the original enforced, restated as tests: ring sizes
//  quantise to quarter steps, quarter-carat rounding snaps only the centre stone,
//  and a configuration that cannot be made is rejected before the geometry
//  kernel sees it.
//

import XCTest
@testable import JewelcraftKit

final class ConfigurationTests: XCTestCase {

    private let catalog = CatalogService(index: CatalogFixtures.makeIndex())

    // MARK: - Ring size

    func testRingSizesQuantiseToQuarterSteps() {
        XCTAssertEqual(FingerSize(usSize: 7.31).usSize, 7.25, accuracy: 1e-9)
        XCTAssertEqual(FingerSize(usSize: 7.13).usSize, 7.25, accuracy: 1e-9)
        XCTAssertEqual(FingerSize(usSize: 2.0).usSize, 3.0, accuracy: 1e-9, "clamped to the offered range")
        XCTAssertEqual(FingerSize(usSize: 21.0).usSize, 16.0, accuracy: 1e-9)
    }

    func testRingSizeDiametersFollowTheSizingTable() {
        // US 6 is 16.51 mm inside; US 10 is 19.76 mm.
        XCTAssertEqual(FingerSize(usSize: 6).innerDiameterMillimetres, 16.51, accuracy: 0.06)
        XCTAssertEqual(FingerSize(usSize: 10).innerDiameterMillimetres, 19.76, accuracy: 0.06)
        XCTAssertEqual(FingerSize(usSize: 7).displayText, "US 7")
        XCTAssertEqual(FingerSize(usSize: 7.5).displayText, "US 7 1/2")
    }

    func testEveryOfferedSizeIsAQuarterStepInsideTheRange() {
        for size in FingerSize.allOfferedSizes {
            XCTAssertTrue(size.isWithinOfferedRange, size.displayText)
            XCTAssertTrue(FingerSize.isQuarterStep(size.usSize))
            XCTAssertGreaterThan(size.innerDiameterMillimetres, 10)
        }
        XCTAssertEqual(FingerSize.allOfferedSizes.count, 53) // US 3 to 16 by quarters
    }

    // MARK: - Quarter-carat rounding

    func testCaratRoundingSnapsToTheNearestQuarter() {
        XCTAssertEqual(CaratRounding.rounded(1.13, enabled: true), 1.25, accuracy: 1e-9)
        XCTAssertEqual(CaratRounding.rounded(1.10, enabled: true), 1.00, accuracy: 1e-9)
        XCTAssertEqual(CaratRounding.rounded(1.13, enabled: false), 1.13, accuracy: 1e-9)
        XCTAssertTrue(CaratRounding.isQuarterCarat(2.25))
        XCTAssertFalse(CaratRounding.isQuarterCarat(2.30))
    }

    func testApplyingRoundingMovesOnlyTheCentreStone() throws {
        let design = try XCTUnwrap(catalog.design(id: DesignID("JWL-1003")))
        var configuration = try ConfigurationFactory.makeConfiguration(for: design, catalog: catalog)
        let accentBefore = configuration.gems.filter { $0.role == .accent }.map(\.carat)

        let centreIndex = try XCTUnwrap(configuration.gems.firstIndex { $0.role == .centre })
        configuration.gems[centreIndex].carat = 1.13
        configuration.quarterCaratRounding = true
        configuration.applyCaratRounding()

        XCTAssertEqual(configuration.gems[centreIndex].carat, 1.25, accuracy: 1e-9)
        XCTAssertEqual(configuration.gems.filter { $0.role == .accent }.map(\.carat), accentBefore)
    }

    // MARK: - Factory

    func testFactoryOpensInTheDesignsFirstMetalWithItsSuggestedCentre() throws {
        for summary in catalog.allSummaries {
            let design = try XCTUnwrap(catalog.design(id: summary.id))
            let configuration = try ConfigurationFactory.makeConfiguration(for: design, catalog: catalog)

            XCTAssertEqual(configuration.metal1.id, summary.metalIDs.first)
            XCTAssertEqual(configuration.centreGem?.slotIndex, 0)
            XCTAssertEqual(configuration.centreCarat ?? 0, design.suggestedCentreCarat, accuracy: 1e-9)
            XCTAssertEqual(configuration.centreGem?.material, design.centreSlot?.defaultMaterial)
            XCTAssertTrue(configuration.validationIssues.isEmpty, "\(summary.id.rawValue): \(configuration.validationIssues)")
        }
    }

    // MARK: - Validation

    func testInvalidConfigurationsAreRejected() throws {
        let design = try XCTUnwrap(catalog.design(id: DesignID("JWL-1001")))
        let valid = try ConfigurationFactory.makeConfiguration(for: design, catalog: catalog)

        var noCentre = valid
        noCentre.gems = valid.gems.filter { $0.role != .centre }
        XCTAssertTrue(noCentre.validationIssues.contains { $0.contains("no centre stone") })

        var twoCentres = valid
        twoCentres.gems.append(valid.gems[0])
        XCTAssertTrue(twoCentres.validationIssues.contains { $0.contains("Two stones share the same slot") })

        var negative = valid
        negative.gems[0].carat = -1
        XCTAssertTrue(negative.validationIssues.contains { $0.contains("non-positive weight") })

        var badSize = valid
        badSize.fingerSize = FingerSize(usSize: 7, innerDiameterMillimetres: 0)
        XCTAssertTrue(badSize.validationIssues.contains { $0.contains("non-positive inside diameter") })

        XCTAssertTrue(valid.isValid)
    }

    func testMetalsThatCannotBeJoinedAreRejected() throws {
        let design = try XCTUnwrap(catalog.design(id: DesignID("JWL-1001")))
        let valid = try ConfigurationFactory.makeConfiguration(for: design, catalog: catalog)
        let silver = try XCTUnwrap(StandardMetals.catalog.metal(id: "silver-sterling"))
        let platinum = try XCTUnwrap(StandardMetals.catalog.metal(id: "platinum-950"))

        var configuration = valid
        configuration.metal1 = platinum
        configuration.metal2 = silver
        if platinum.canPair(with: silver) {
            XCTAssertTrue(configuration.isValid)
        } else {
            XCTAssertTrue(configuration.validationIssues.contains { $0.contains("cannot be paired") })
        }
    }

    // MARK: - Freehand

    func testFreehandVisibilityAndCommonCentreToggles() {
        var state = FreehandState.standard()
        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.parts.count, 2)

        state.setVisibility(false, ofPartNamed: "Shank top curve")
        XCTAssertEqual(state.visibleParts.count, 1)

        (state.parts.indices).forEach { state.parts[$0].isVisible = true }
        state.commonCentreMode = true
        XCTAssertTrue(state.commonCentreMode)
        XCTAssertTrue(state.hasCurves)
    }
}
