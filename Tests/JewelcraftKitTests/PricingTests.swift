//
//  PricingTests.swift
//  JewelcraftKitTests
//
//  Quoting: the arithmetic a customer is shown.
//
//  The load-bearing claim here is auditability. Every quote line must reconcile
//  quantity x rate = amount, the subtotal must be the sum of the lines, and the
//  total must be subtotal - discount + tax. A price that cannot be audited is a
//  price nobody can defend.
//

import XCTest
@testable import JewelcraftKit

final class PricingTests: XCTestCase {

    let catalog = CatalogService(index: CatalogFixtures.makeIndex())
    let pricing = PricingEngine(rateTable: RateTableFixtures.make())

    func configured(_ designID: String) throws -> (DesignDetail, Configuration, BuiltRing) {
        let design = try XCTUnwrap(catalog.design(id: DesignID(designID)))
        let configuration = try ConfigurationFactory.makeConfiguration(for: design, catalog: catalog)
        let built = RingBuilder.build(
            designID: design.id,
            parameters: InProcessCADEngine.parameters(for: design, configuration: configuration),
            plan: InProcessCADEngine.gemPlan(for: design, configuration: configuration),
            metal: configuration.metal1
        )
        return (design, configuration, built)
    }

    /// Rebuilds a model with a mutated configuration, which is what a quote for
    /// a changed ring must be based on.
    func rebuilt(
        _ design: DesignDetail,
        _ configuration: Configuration
    ) -> BuiltRing {
        RingBuilder.build(
            designID: design.id,
            parameters: InProcessCADEngine.parameters(for: design, configuration: configuration),
            plan: InProcessCADEngine.gemPlan(for: design, configuration: configuration),
            metal: configuration.metal1
        )
    }

    func testEveryDesignQuotesToASelfConsistentDocument() throws {
        for summary in catalog.allSummaries {
            let (design, configuration, built) = try configured(summary.id.rawValue)
            let quote = try pricing.quote(configuration: configuration, design: design, built: built)

            XCTAssertTrue(quote.isSelfConsistent, "\(summary.id.rawValue) quote does not reconcile")
            XCTAssertGreaterThan(quote.subtotal, 0)
            XCTAssertGreaterThan(quote.total, 0)
            XCTAssertEqual(quote.currency, "USD")
            XCTAssertFalse(quote.lines.isEmpty)
            for line in quote.lines {
                XCTAssertTrue(line.isSelfConsistent, "\(line.id) does not reconcile")
            }
        }
    }

    func testTheSameRingQuotesToTheSameTotal() throws {
        let (design, configuration, built) = try configured("JWL-1007")
        let first = try pricing.quote(configuration: configuration, design: design, built: built)
        let second = try pricing.quote(configuration: configuration, design: design, built: built)
        XCTAssertEqual(first.total, second.total, accuracy: 1e-9)
        XCTAssertEqual(first.lines.map(\.id), second.lines.map(\.id))
    }

    func testABiggerRingCostsMoreBecauseItWeighsMore() throws {
        let (design, configuration, built) = try configured("JWL-1001")
        let small = try pricing.quote(configuration: configuration, design: design, built: built)

        var larger = configuration
        larger.fingerSize = FingerSize(usSize: 12)
        let big = try pricing.quote(
            configuration: larger,
            design: design,
            built: rebuilt(design, larger)
        )

        XCTAssertGreaterThan(big.total, small.total)
        XCTAssertGreaterThan(
            big.metalGramsBreakdown.values.reduce(0, +),
            small.metalGramsBreakdown.values.reduce(0, +)
        )
    }

    func testALargerCentreStoneCostsMore() throws {
        let (design, configuration, built) = try configured("JWL-1001")
        let oneCarat = try pricing.quote(configuration: configuration, design: design, built: built)

        var twoCarat = configuration
        twoCarat.setCarat(2.0, forSlotIndex: 0)
        let bigger = try pricing.quote(
            configuration: twoCarat,
            design: design,
            built: rebuilt(design, twoCarat)
        )
        XCTAssertGreaterThan(bigger.total, oneCarat.total)
    }

    func testTwoToneRingsPriceBothMetalsSeparately() throws {
        let (design, configuration, _) = try configured("JWL-1001")
        var twoTone = configuration
        twoTone.metal2 = StandardMetals.catalog.metal(id: "platinum-950")
        let quote = try pricing.quote(
            configuration: twoTone,
            design: design,
            built: rebuilt(design, twoTone)
        )

        XCTAssertEqual(Set(quote.metalGramsBreakdown.keys), ["gold-14k-white", "platinum-950"])
        XCTAssertTrue(quote.isSelfConsistent)
    }

    func testAMissingMetalRateIsRefusedRatherThanPricedAtZero() throws {
        let (design, configuration, built) = try configured("JWL-1001")
        let empty = RateTable(
            schemaVersion: 1,
            metalRates: [],
            stoneRates: RateTableFixtures.stoneRates,
            labour: RateTableFixtures.labour,
            settingCharges: RateTableFixtures.settingCharges,
            policy: RateTableFixtures.policy
        )
        let engine = PricingEngine(rateTable: empty)
        XCTAssertThrowsError(try engine.quote(configuration: configuration, design: design, built: built)) { error in
            guard case PricingError.missingMetalRate = error as? PricingError else {
                return XCTFail("expected a missing metal rate, got \(error)")
            }
        }
    }

    func testADiscountReducesTheTotalAndIsStillAuditable() throws {
        let (design, configuration, built) = try configured("JWL-1009")
        let plain = try pricing.quote(configuration: configuration, design: design, built: built)
        let discounted = try pricing.quote(
            configuration: configuration, design: design, built: built, discountPercent: 10
        )

        XCTAssertLessThan(discounted.total, plain.total)
        XCTAssertEqual(discounted.discountPercent, 10, accuracy: 1e-9)
        XCTAssertGreaterThan(discounted.discount, 0)
        XCTAssertTrue(discounted.isSelfConsistent)
    }

    func testMeleeIsPricedPerStoneAndTheCentrePerCarat() throws {
        let (design, configuration, built) = try configured("JWL-1003")
        let quote = try pricing.quote(configuration: configuration, design: design, built: built)

        let stones = quote.lines.filter { $0.category == .stone }
        XCTAssertFalse(stones.isEmpty)
        XCTAssertTrue(stones.contains { $0.unit == "stone" }, "small stones are sold per stone")
        XCTAssertTrue(stones.contains { $0.unit == "carat" }, "the centre stone is sold per carat")
    }
}
