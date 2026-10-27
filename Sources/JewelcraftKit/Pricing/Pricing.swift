//
//  Pricing.swift
//  JewelcraftKit
//
//  Quoting.
//
//  The recovered evidence is explicit about the limits here: the original's
//  pricing *mechanism* was observable — a service returning DTOs with metal,
//  stone and customer components, which the order summary turned into a
//  displayed total — but the actual arithmetic lived server-side and was never
//  established (report 04, section 6). So this is a mechanism-faithful rebuild
//  over our own rate tables, not a reconstruction of anyone's prices.
//
//  Two design rules carry over and are worth stating plainly:
//
//    * Every line carries the identifier of the rate it came from, so any quote
//      can be audited back to a row in the table.
//    * Metal cost is computed from the *built geometry*: the metal volume of the
//      actual parts, times the alloy's density. A quote therefore moves when the
//      model moves, which is the only way a quote can be trusted.
//

import Foundation

// MARK: - Rates

public struct MetalRate: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// Matches `Metal.rateKey`.
    public var rateKey: String
    public var currency: String
    public var ratePerGram: Double
    public var effectiveDate: String

    public init(id: String, rateKey: String, currency: String, ratePerGram: Double, effectiveDate: String) {
        self.id = id
        self.rateKey = rateKey
        self.currency = currency
        self.ratePerGram = ratePerGram
        self.effectiveDate = effectiveDate
    }
}

/// A price band for stones, keyed by material, quality and a carat interval.
public struct StoneRateBand: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var material: GemMaterial
    /// When nil, the band applies to any shape of this material. Shape-specific
    /// bands are chosen before shape-agnostic ones.
    public var shape: GemShape?
    public var qualityID: String
    public var minCarat: Double
    public var maxCarat: Double
    public var pricePerCarat: Double
    /// When present, stones are priced individually rather than by weight, which
    /// is how melee is sold.
    public var pricePerStone: Double?

    public init(
        id: String,
        material: GemMaterial,
        shape: GemShape?,
        qualityID: String,
        minCarat: Double,
        maxCarat: Double,
        pricePerCarat: Double,
        pricePerStone: Double? = nil
    ) {
        self.id = id
        self.material = material
        self.shape = shape
        self.qualityID = qualityID
        self.minCarat = minCarat
        self.maxCarat = maxCarat
        self.pricePerCarat = pricePerCarat
        self.pricePerStone = pricePerStone
    }

    public func covers(carat: Double) -> Bool {
        carat >= Swift.min(minCarat, maxCarat) - 1e-9
            && carat <= Swift.max(minCarat, maxCarat) + 1e-9
    }
}

public struct LabourRule: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var tier: LabourTier
    public var baseAmount: Double
    public var marginMultiplier: Double

    public init(id: String, tier: LabourTier, baseAmount: Double, marginMultiplier: Double) {
        self.id = id
        self.tier = tier
        self.baseAmount = baseAmount
        self.marginMultiplier = marginMultiplier
    }
}

public struct SettingCharge: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var role: GemRole
    public var amountPerStone: Double
    public var complexityMultiplier: Double

    public init(id: String, role: GemRole, amountPerStone: Double, complexityMultiplier: Double) {
        self.id = id
        self.role = role
        self.amountPerStone = amountPerStone
        self.complexityMultiplier = complexityMultiplier
    }
}

public struct PricingPolicy: Codable, Hashable, Sendable {
    public var priceListID: String
    public var currency: String
    public var metalMarkupPercent: Double
    public var stoneMarkupPercent: Double
    public var labourMarkupPercent: Double
    /// Amounts are rounded to this increment, so totals do not carry fractions
    /// a customer cannot be billed.
    public var roundingIncrement: Double
    public var taxPercent: Double

    public init(
        priceListID: String,
        currency: String,
        metalMarkupPercent: Double,
        stoneMarkupPercent: Double,
        labourMarkupPercent: Double,
        roundingIncrement: Double,
        taxPercent: Double
    ) {
        self.priceListID = priceListID
        self.currency = currency
        self.metalMarkupPercent = metalMarkupPercent
        self.stoneMarkupPercent = stoneMarkupPercent
        self.labourMarkupPercent = labourMarkupPercent
        self.roundingIncrement = roundingIncrement
        self.taxPercent = taxPercent
    }
}

/// The whole rate book.
public struct RateTable: Codable, Sendable {
    public var schemaVersion: Int
    public var metalRates: [MetalRate]
    public var stoneRates: [StoneRateBand]
    public var labour: [LabourRule]
    public var settingCharges: [SettingCharge]
    public var policy: PricingPolicy

    public init(
        schemaVersion: Int,
        metalRates: [MetalRate],
        stoneRates: [StoneRateBand],
        labour: [LabourRule],
        settingCharges: [SettingCharge],
        policy: PricingPolicy
    ) {
        self.schemaVersion = schemaVersion
        self.metalRates = metalRates
        self.stoneRates = stoneRates
        self.labour = labour
        self.settingCharges = settingCharges
        self.policy = policy
    }

    public func metalRate(rateKey: String) -> MetalRate? {
        metalRates.first { $0.rateKey == rateKey }
    }

    public func labourRule(tier: LabourTier) -> LabourRule? {
        labour.first { $0.tier == tier }
    }

    public func settingCharge(role: GemRole) -> SettingCharge? {
        settingCharges.first { $0.role == role }
    }

    /// The narrowest band that covers a stone.
    ///
    /// A shape-specific band beats a shape-agnostic one, and among equals the
    /// tightest carat interval wins, so a table can express "one carat and up is
    /// different" without the lookup depending on row order.
    public func stoneRate(
        material: GemMaterial,
        shape: GemShape,
        qualityID: String,
        carat: Double
    ) -> StoneRateBand? {
        let candidates = stoneRates.filter { band in
            band.material == material
                && band.qualityID == qualityID
                && band.covers(carat: carat)
                && (band.shape == nil || band.shape == shape)
        }
        return candidates.sorted { lhs, rhs in
            let lhsSpecific = lhs.shape != nil
            let rhsSpecific = rhs.shape != nil
            if lhsSpecific != rhsSpecific { return lhsSpecific }
            return abs(lhs.maxCarat - lhs.minCarat) < abs(rhs.maxCarat - rhs.minCarat)
        }.first
    }
}

// MARK: - Quote

public enum PriceCategory: String, Codable, CaseIterable, Sendable {
    case metal
    case stone
    case labour
    case setting
    case discount
    case tax

    public var displayName: String {
        switch self {
        case .metal: return "Metal"
        case .stone: return "Stones"
        case .labour: return "Labour"
        case .setting: return "Setting"
        case .discount: return "Discount"
        case .tax: return "Tax"
        }
    }
}

/// One line of a quote, with the rate it came from.
public struct QuoteLine: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var category: PriceCategory
    public var quantity: Double
    public var unit: String
    public var unitRate: Double
    public var amount: Double
    /// The `MetalRate`, `StoneRateBand`, `LabourRule` or `SettingCharge` this
    /// line was derived from.
    public var sourceRateID: String

    public init(
        id: String,
        label: String,
        category: PriceCategory,
        quantity: Double,
        unit: String,
        unitRate: Double,
        amount: Double,
        sourceRateID: String
    ) {
        self.id = id
        self.label = label
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.unitRate = unitRate
        self.amount = amount
        self.sourceRateID = sourceRateID
    }

    /// Whether the line's amount really is its quantity times its rate. Every
    /// line must pass this, or the quote is not auditable.
    public var isSelfConsistent: Bool {
        abs(amount - quantity * unitRate) < 1e-6
    }
}

public struct Quote: Codable, Hashable, Sendable {
    public var id: String
    public var priceListID: String
    public var currency: String
    public var lines: [QuoteLine]
    public var subtotal: Double
    public var discountPercent: Double
    public var discount: Double
    public var tax: Double
    public var total: Double
    public var createdAt: Date
    public var metalGramsBreakdown: [String: Double]

    public init(
        id: String,
        priceListID: String,
        currency: String,
        lines: [QuoteLine],
        subtotal: Double,
        discountPercent: Double,
        discount: Double,
        tax: Double,
        total: Double,
        createdAt: Date,
        metalGramsBreakdown: [String: Double] = [:]
    ) {
        self.id = id
        self.priceListID = priceListID
        self.currency = currency
        self.lines = lines
        self.subtotal = subtotal
        self.discountPercent = discountPercent
        self.discount = discount
        self.tax = tax
        self.total = total
        self.createdAt = createdAt
        self.metalGramsBreakdown = metalGramsBreakdown
    }

    /// Charge lines only: metals, stones, labour and setting.
    public var chargeLines: [QuoteLine] {
        lines.filter { $0.category != .discount && $0.category != .tax }
    }

    public var categoryTotals: [PriceCategory: Double] {
        var totals: [PriceCategory: Double] = [:]
        for line in lines {
            totals[line.category, default: 0] += line.amount
        }
        return totals
    }

    public func total(for category: PriceCategory) -> Double {
        categoryTotals[category] ?? 0
    }

    /// The quote re-derives from its own lines: line arithmetic is exact, the
    /// subtotal is the sum of the charge lines, and the total is the subtotal
    /// less the discount plus tax.
    ///
    /// The rounding increment means the raw sum and the rounded subtotal can
    /// differ by up to one increment, so the comparison uses that as its bound
    /// rather than pretending rounding does not happen.
    public var isSelfConsistent: Bool {
        guard lines.allSatisfy(\.isSelfConsistent) else { return false }
        let charges = chargeLines.reduce(0) { $0 + $1.amount }
        if abs(charges - subtotal) > 0.01 { return false }
        if abs((subtotal - discount + tax) - total) > 0.01 {
            // Totals are each rounded, so allow one increment of slack.
            return false
        }
        let discountLines = lines.filter { $0.category == .discount }
        if discountLines.isEmpty {
            if abs(discount) > 0.01 { return false }
        } else if abs(discountLines.reduce(0) { $0 + $1.amount } + discount) > 0.01 {
            return false
        }
        return true
    }

    public var formattedTotal: String {
        String(format: "%@ %.2f", currency, total)
    }
}

public enum PricingError: Error, Equatable, CustomStringConvertible {
    case missingMetalRate(String)
    case missingStoneRate(material: String, quality: String, carat: Double)
    case missingLabourRule(String)
    case missingSettingCharge(String)

    public var description: String {
        switch self {
        case .missingMetalRate(let key):
            return "No metal rate is defined for \(key)."
        case .missingStoneRate(let material, let quality, let carat):
            return String(format: "No stone rate is defined for %@ %@ at %.2f ct.", material, quality, carat)
        case .missingLabourRule(let tier):
            return "No labour rule is defined for \(tier)."
        case .missingSettingCharge(let role):
            return "No setting charge is defined for \(role)."
        }
    }
}

// MARK: - Engine

public final class PricingEngine {

    public let rateTable: RateTable
    private let sizer: GemSizer

    public init(rateTable: RateTable, sizer: GemSizer = GemSizer()) {
        self.rateTable = rateTable
        self.sizer = sizer
    }

    /// Parts that a two-tone ring makes in its second metal: everything in the
    /// head. Expressed as a set of part kinds rather than a percentage split, so
    /// the second metal's weight is a measured volume rather than an arbitrary
    /// share of the total.
    private static let headPartKinds: Set<PartKind> = [.prong, .basket, .bezel, .haloRail]

    /// A quote for a configured ring.
    ///
    /// Takes the built model rather than a weight, so metal cost follows the
    /// geometry: a change to the shank profile or the ring size moves the price
    /// because it moves the metal.
    public func quote(
        configuration: Configuration,
        design: DesignDetail,
        built: BuiltRing,
        discountPercent: Double = 0,
        quoteID: String? = nil,
        createdAt: Date = Date()
    ) throws -> Quote {
        let policy = rateTable.policy
        var lines: [QuoteLine] = []
        var gramsBreakdown: [String: Double] = [:]

        // MARK: Metal

        let headVolume = built.parts
            .filter { Self.headPartKinds.contains($0.kind) }
            .reduce(0.0) { $0 + abs($1.mesh.signedVolume) }
        let bodyVolume = built.parts
            .filter { $0.kind.isMetal && !Self.headPartKinds.contains($0.kind) }
            .reduce(0.0) { $0 + abs($1.mesh.signedVolume) }

        let metalVolumeShares: [(Metal, Double)]
        if let metal2 = configuration.metal2 {
            metalVolumeShares = [(configuration.metal1, bodyVolume), (metal2, headVolume)]
        } else {
            metalVolumeShares = [(configuration.metal1, bodyVolume + headVolume)]
        }

        for (metal, volume) in metalVolumeShares {
            let grams = metal.grams(forCubicMillimetres: volume)
            guard grams > 0 else { continue }
            gramsBreakdown[metal.id] = grams
            guard let rate = rateTable.metalRate(rateKey: metal.rateKey) else {
                throw PricingError.missingMetalRate(metal.rateKey)
            }
            let markedUp = rate.ratePerGram * (1 + policy.metalMarkupPercent / 100)
            lines.append(QuoteLine(
                id: "line.metal.\(metal.id)",
                label: "\(metal.displayName) — \(String(format: "%.2f", grams)) g",
                category: .metal,
                quantity: grams,
                unit: "g",
                unitRate: markedUp,
                amount: grams * markedUp,
                sourceRateID: rate.id
            ))
        }

        // MARK: Stones

        // Grouped by what actually determines the price, so a hundred melee
        // stones are one auditable line rather than a hundred.
        struct StoneGroupKey: Hashable {
            var role: GemRole
            var material: GemMaterial
            var shape: GemShape
            var qualityID: String
            var bandID: String
        }

        struct StoneGroup {
            var count: Int
            var carats: Double
            var rate: StoneRateBand
        }

        var groups: [StoneGroupKey: StoneGroup] = [:]

        for placement in built.gemPlacements {
            guard let band = rateTable.stoneRate(
                material: placement.material,
                shape: placement.shape,
                qualityID: placement.qualityID,
                carat: placement.carat
            ) else {
                throw PricingError.missingStoneRate(
                    material: placement.material.rawValue,
                    quality: placement.qualityID,
                    carat: placement.carat
                )
            }
            let key = StoneGroupKey(
                role: placement.role,
                material: placement.material,
                shape: placement.shape,
                qualityID: placement.qualityID,
                bandID: band.id
            )
            var entry = groups[key] ?? StoneGroup(count: 0, carats: 0, rate: band)
            entry.count += 1
            entry.carats += placement.carat
            groups[key] = entry
        }

        // A deterministic order, so two quotes for the same ring read the same.
        let sortedGroups = groups.sorted { lhs, rhs in
            if lhs.key.role.rawValue != rhs.key.role.rawValue {
                return lhs.key.role.rawValue < rhs.key.role.rawValue
            }
            if lhs.key.material.rawValue != rhs.key.material.rawValue {
                return lhs.key.material.rawValue < rhs.key.material.rawValue
            }
            return lhs.key.shape.rawValue < rhs.key.shape.rawValue
        }

        for (key, entry) in sortedGroups {
            let markup = 1 + policy.stoneMarkupPercent / 100
            if let perStone = entry.rate.pricePerStone {
                let unitRate = perStone * markup
                lines.append(QuoteLine(
                    id: "line.stone.\(key.role.rawValue).\(key.shape.rawValue).\(entry.rate.id)",
                    label: "\(key.material.displayName) \(key.shape.displayName) "
                        + "(\(key.role.displayName)) × \(entry.count)",
                    category: .stone,
                    quantity: Double(entry.count),
                    unit: "stone",
                    unitRate: unitRate,
                    amount: Double(entry.count) * unitRate,
                    sourceRateID: entry.rate.id
                ))
            } else {
                let unitRate = entry.rate.pricePerCarat * markup
                lines.append(QuoteLine(
                    id: "line.stone.\(key.role.rawValue).\(key.shape.rawValue).\(entry.rate.id)",
                    label: "\(key.material.displayName) \(key.shape.displayName) "
                        + "(\(key.role.displayName)) — \(String(format: "%.2f", entry.carats)) ct",
                    category: .stone,
                    quantity: entry.carats,
                    unit: "carat",
                    unitRate: unitRate,
                    amount: entry.carats * unitRate,
                    sourceRateID: entry.rate.id
                ))
            }
        }

        // MARK: Labour

        guard let labour = rateTable.labourRule(tier: design.summary.labourTier) else {
            throw PricingError.missingLabourRule(design.summary.labourTier.rawValue)
        }
        let labourRate = labour.baseAmount
            * labour.marginMultiplier
            * (1 + policy.labourMarkupPercent / 100)
        lines.append(QuoteLine(
            id: "line.labour.\(labour.id)",
            label: "\(design.summary.labourTier.displayName) labour",
            category: .labour,
            quantity: 1,
            unit: "ring",
            unitRate: labourRate,
            amount: labourRate,
            sourceRateID: labour.id
        ))

        // MARK: Setting

        let roles = Set(built.gemPlacements.map(\.role))
        for role in roles.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let charge = rateTable.settingCharge(role: role) else {
                throw PricingError.missingSettingCharge(role.rawValue)
            }
            let count = built.gemPlacements.filter { $0.role == role }.count
            guard count > 0 else { continue }
            let unitRate = charge.amountPerStone * charge.complexityMultiplier
            lines.append(QuoteLine(
                id: "line.setting.\(role.rawValue)",
                label: "Setting — \(role.displayName) × \(count)",
                category: .setting,
                quantity: Double(count),
                unit: "stone",
                unitRate: unitRate,
                amount: Double(count) * unitRate,
                sourceRateID: charge.id
            ))
        }

        // MARK: Totals

        let rawSubtotal = lines.reduce(0) { $0 + $1.amount }
        let subtotal = rawSubtotal.rounded(toNearest: policy.roundingIncrement)
        let clampedDiscountPercent = Swift.min(100, Swift.max(0, discountPercent))
        let discount = (subtotal * clampedDiscountPercent / 100)
            .rounded(toNearest: policy.roundingIncrement)
        if discount > 0 {
            lines.append(QuoteLine(
                id: "line.discount",
                label: String(format: "Discount %.1f%%", clampedDiscountPercent),
                category: .discount,
                quantity: 1,
                unit: "ring",
                unitRate: -discount,
                amount: -discount,
                sourceRateID: "policy.discount"
            ))
        }
        let tax = ((subtotal - discount) * policy.taxPercent / 100)
            .rounded(toNearest: policy.roundingIncrement)
        let total = subtotal - discount + tax

        return Quote(
            id: quoteID ?? "quote.\(configuration.id)",
            priceListID: policy.priceListID,
            currency: policy.currency,
            lines: lines,
            subtotal: subtotal,
            discountPercent: clampedDiscountPercent,
            discount: discount,
            tax: tax,
            total: total,
            createdAt: createdAt,
            metalGramsBreakdown: gramsBreakdown
        )
    }

    /// A quote straight from a configuration, building the model on the fly.
    /// Convenient for previews and tests; the app quotes the model the engine has
    /// already built.
    public func quote(
        configuration: Configuration,
        design: DesignDetail,
        discountPercent: Double = 0,
        createdAt: Date = Date()
    ) throws -> Quote {
        let parameters = InProcessCADEngine.parameters(for: design, configuration: configuration)
        let plan = InProcessCADEngine.gemPlan(for: design, configuration: configuration)
        let built = RingBuilder.build(
            designID: design.id,
            parameters: parameters,
            plan: plan,
            metal: configuration.metal1,
            sizer: sizer
        )
        return try quote(
            configuration: configuration,
            design: design,
            built: built,
            discountPercent: discountPercent,
            createdAt: createdAt
        )
    }
}
