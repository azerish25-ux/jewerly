//
//  RateTableFixtures.swift
//  JewelcraftKit
//
//  The synthetic rate book.
//
//  Every number here is invented. That is not a limitation to apologise for: the
//  original's prices came from a supplier's server, and the rebuild is expressly
//  not allowed to carry them. What *is* reproduced is the structure of the
//  pricing domain, which the reverse engineering recovered:
//
//    * Metal is priced by weight, from a rate keyed by alloy, and the weight
//      comes from the modelled geometry rather than from a table.
//    * Stones are priced from carat bands, with a separately priced melee
//      channel, because small stones are sold per stone and large ones per
//      carat.
//    * Labour is priced by tier, and setting is charged per stone by role.
//    * A policy wraps markup, rounding and tax, so the arithmetic is auditable
//      and a quote line always reconciles with its own quantity and rate.
//
//  The bands cover every material, grade and weight the app can produce, so a
//  quote can never fail for want of a rate. `coverageIssues()` proves it, and
//  the pricing tests assert it is empty.
//

import Foundation

public enum RateTableFixtures {

    public static let fixtureName = "rates"

    // MARK: - Metal

    public static let metalRates: [MetalRate] = [
        MetalRate(id: "rate.metal.gold-10k", rateKey: "gold-10k", currency: "USD",
                  ratePerGram: 42.00, effectiveDate: "2026-01-01"),
        MetalRate(id: "rate.metal.gold-14k", rateKey: "gold-14k", currency: "USD",
                  ratePerGram: 58.00, effectiveDate: "2026-01-01"),
        MetalRate(id: "rate.metal.gold-18k", rateKey: "gold-18k", currency: "USD",
                  ratePerGram: 74.00, effectiveDate: "2026-01-01"),
        MetalRate(id: "rate.metal.gold-22k", rateKey: "gold-22k", currency: "USD",
                  ratePerGram: 91.00, effectiveDate: "2026-01-01"),
        MetalRate(id: "rate.metal.platinum-950", rateKey: "platinum-950", currency: "USD",
                  ratePerGram: 32.00, effectiveDate: "2026-01-01"),
        MetalRate(id: "rate.metal.palladium-950", rateKey: "palladium-950", currency: "USD",
                  ratePerGram: 30.00, effectiveDate: "2026-01-01"),
        MetalRate(id: "rate.metal.silver-925", rateKey: "silver-925", currency: "USD",
                  ratePerGram: 0.95, effectiveDate: "2026-01-01"),
        MetalRate(id: "rate.metal.titanium", rateKey: "titanium", currency: "USD",
                  ratePerGram: 0.12, effectiveDate: "2026-01-01"),
        MetalRate(id: "rate.metal.steel-316l", rateKey: "steel-316l", currency: "USD",
                  ratePerGram: 0.04, effectiveDate: "2026-01-01")
    ]

    // MARK: - Stones

    /// Base value per carat for a one-carat stone in the working grade.
    static let basePricePerCarat: [GemMaterial: Double] = [
        .diamond: 4200, .moissanite: 320, .cubicZirconia: 45, .imitation: 8,
        .ruby: 900, .sapphire: 800, .emerald: 1100, .morganite: 220,
        .aquamarine: 160, .tanzanite: 420, .amethyst: 60, .topaz: 45,
        .garnet: 70, .pearl: 25
    ]

    /// How a grade scales the base value.
    static let qualityMultipliers: [String: Double] = [
        "q.standard": 1.00,
        "q.diamond.signature": 1.90,
        "q.diamond.premier": 1.00,
        "q.diamond.classic": 0.60,
        "q.colour.fine": 1.50,
        "q.colour.commercial": 0.55
    ]

    /// Carat bands. Price per carat rises with size, which is the shape of a
    /// real stone price list; the melee bands are also priced per stone.
    static let sizeBuckets: [(min: Double, max: Double, multiplier: Double, melee: Bool)] = [
        (0.001, 0.10, 0.50, true),
        (0.10, 0.25, 0.70, true),
        (0.25, 0.50, 0.90, false),
        (0.50, 1.00, 1.00, false),
        (1.00, 2.00, 1.35, false),
        (2.00, 3.00, 1.90, false),
        (3.00, 10.00, 2.80, false),
        (10.00, 30.00, 4.00, false)
    ]

    public static var stoneRates: [StoneRateBand] {
        var bands: [StoneRateBand] = []
        let catalog = GemFixtures.catalog

        for material in GemMaterial.allCases {
            let base = basePricePerCarat[material] ?? 50
            for quality in catalog.qualities(for: material) {
                let multiplier = qualityMultipliers[quality.id] ?? 1
                for (index, bucket) in sizeBuckets.enumerated() {
                    let pricePerCarat = (base * multiplier * bucket.multiplier).rounded()
                    let midCarat = (bucket.min + bucket.max) / 2
                    bands.append(StoneRateBand(
                        id: "rate.stone.\(material.rawValue).\(quality.id).\(index)",
                        material: material,
                        shape: nil,
                        qualityID: quality.id,
                        minCarat: bucket.min,
                        maxCarat: bucket.max,
                        pricePerCarat: pricePerCarat,
                        pricePerStone: bucket.melee
                            ? (pricePerCarat * midCarat * 1.6).rounded()
                            : nil
                    ))
                }
            }
        }

        return bands
    }

    // MARK: - Labour, setting and policy

    public static let labour: [LabourRule] = [
        LabourRule(id: "rate.labour.standard", tier: .standard, baseAmount: 38, marginMultiplier: 1.00),
        LabourRule(id: "rate.labour.premium", tier: .premium, baseAmount: 85, marginMultiplier: 1.25),
        LabourRule(id: "rate.labour.master", tier: .master, baseAmount: 180, marginMultiplier: 1.60)
    ]

    public static let settingCharges: [SettingCharge] = [
        SettingCharge(id: "rate.setting.centre", role: .centre,
                      amountPerStone: 42, complexityMultiplier: 1.00),
        SettingCharge(id: "rate.setting.accent", role: .accent,
                      amountPerStone: 6.5, complexityMultiplier: 1.00),
        SettingCharge(id: "rate.setting.halo", role: .halo,
                      amountPerStone: 4.25, complexityMultiplier: 1.15)
    ]

    public static let policy = PricingPolicy(
        priceListID: "PL-2026-SYNTHETIC",
        currency: "USD",
        metalMarkupPercent: 18,
        stoneMarkupPercent: 22,
        labourMarkupPercent: 15,
        roundingIncrement: 0.01,
        taxPercent: 0
    )

    public static func make() -> RateTable {
        RateTable(
            schemaVersion: 1,
            metalRates: metalRates,
            stoneRates: stoneRates,
            labour: labour,
            settingCharges: settingCharges,
            policy: policy
        )
    }

    // MARK: - Coverage

    /// Combinations the table cannot price. The pricing tests require this to be
    /// empty across every material, grade and the weights the app can produce.
    public static func coverageIssues() -> [String] {
        let table = make()
        let catalog = GemFixtures.catalog
        var issues: [String] = []
        let sampleCarats: [Double] = [0.005, 0.02, 0.05, 0.1, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0, 5.0, 10.0]

        for metal in StandardMetals.all where table.metalRate(rateKey: metal.rateKey) == nil {
            issues.append("no metal rate for \(metal.id)")
        }

        for tier in LabourTier.allCases where table.labourRule(tier: tier) == nil {
            issues.append("no labour rule for tier \(tier.rawValue)")
        }

        for role in GemRole.allCases where table.settingCharge(role: role) == nil {
            issues.append("no setting charge for role \(role.rawValue)")
        }

        for material in GemMaterial.allCases {
            for quality in catalog.qualities(for: material) {
                for carat in sampleCarats where table.stoneRate(
                    material: material,
                    shape: .roundBrilliant,
                    qualityID: quality.id,
                    carat: carat
                ) == nil {
                    issues.append("no stone rate for \(material.rawValue) \(quality.id) at \(carat) ct")
                }
            }
        }

        // A diamond is the one material the catalogue cuts in every shape, so it
        // is the one that proves shape-specific lookups resolve.
        for shape in GemShape.allCases where table.stoneRate(
            material: .diamond,
            shape: shape,
            qualityID: "q.diamond.premier",
            carat: 1.0
        ) == nil {
            issues.append("no stone rate for diamond \(shape.rawValue) at 1.0 ct")
        }

        return issues
    }
}

// MARK: - Fixture conformance

extension RateTable: CodeFixture {
    public static var fixtureName: String { RateTableFixtures.fixtureName }
    public static func make() -> RateTable { RateTableFixtures.make() }
}
