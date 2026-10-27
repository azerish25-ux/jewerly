//
//  Metals.swift
//  JewelcraftKit
//
//  Metal alloys as data.
//
//  Density is the interesting field: the pricing engine multiplies a measured
//  metal volume by it to get a gram weight, and a quote is only as good as that
//  number. Published alloy densities are reference values, so they are recorded
//  here with their source shape (karat plus family plus colour) rather than
//  being guessed from karat alone — 18k white gold is meaningfully denser than
//  14k white gold, and the difference shows up in the price.
//

import Foundation

public enum MetalFamily: String, Codable, CaseIterable, Sendable {
    case gold
    case platinum
    case palladium
    case silver
    case steel
    case titanium

    public var displayName: String {
        switch self {
        case .gold: return "Gold"
        case .platinum: return "Platinum"
        case .palladium: return "Palladium"
        case .silver: return "Silver"
        case .steel: return "Steel"
        case .titanium: return "Titanium"
        }
    }
}

/// A metal alloy option.
public struct Metal: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var family: MetalFamily
    /// Karat for gold, 0 for metals not sold by karat.
    public var karat: Int
    /// Colour family, which drives the filter facet this metal appears under.
    public var colourID: String
    /// Published density in g/cm³.
    public var densityGramsPerCubicCentimetre: Double
    /// Key into the pricing rate table. Never a supplier's own identifier.
    public var rateKey: String
    /// Display swatch.
    public var swatchHex: String

    public init(
        id: String,
        name: String,
        family: MetalFamily,
        karat: Int,
        colourID: String,
        densityGramsPerCubicCentimetre: Double,
        rateKey: String,
        swatchHex: String
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.karat = karat
        self.colourID = colourID
        self.densityGramsPerCubicCentimetre = densityGramsPerCubicCentimetre
        self.rateKey = rateKey
        self.swatchHex = swatchHex
    }

    /// g/cm³ and mg/mm³ are the same number, so converting to a per-millimetre
    /// density is a division by a thousand, not a unit guess.
    public var densityGramsPerCubicMillimetre: Double {
        densityGramsPerCubicCentimetre / 1000
    }

    public var displayName: String {
        if karat > 0 {
            return "\(karat)k \(name)"
        }
        return name
    }

    public var swatch: RGBColour {
        RGBColour(hex: swatchHex) ?? RGBColour(red: 0.8, green: 0.8, blue: 0.8)
    }

    /// Mass of a measured volume of this alloy, in grams.
    public func grams(forCubicMillimetres volume: Double) -> Double {
        Swift.max(0, volume) * densityGramsPerCubicMillimetre
    }

    /// Whether this metal may be paired with another as a two-tone ring. Golds
    /// pair freely; a platinum and a titanium shank do not, because they cannot
    /// be soldered in the ordinary way.
    public func canPair(with other: Metal) -> Bool {
        if id == other.id { return true }
        switch (family, other.family) {
        case (.gold, .gold), (.gold, .platinum), (.platinum, .gold),
             (.gold, .palladium), (.palladium, .gold),
             (.platinum, .palladium), (.palladium, .platinum):
            return true
        default:
            return false
        }
    }
}

/// The loaded metal list.
public struct MetalCatalog: Codable, Sendable {
    public var schemaVersion: Int
    public var metals: [Metal]

    public init(schemaVersion: Int, metals: [Metal]) {
        self.schemaVersion = schemaVersion
        self.metals = metals
    }

    public var all: [Metal] { metals }

    public func metal(id: String) -> Metal? {
        metals.first { $0.id == id }
    }

    public func metals(inFamily family: MetalFamily) -> [Metal] {
        metals.filter { $0.family == family }
    }

    public func metals(colourID: String) -> [Metal] {
        metals.filter { $0.colourID == colourID }
    }

    /// Distinct colour ids in a stable order, for the metal facet group.
    public var colourIDs: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for metal in metals where !seen.contains(metal.colourID) {
            seen.insert(metal.colourID)
            ordered.append(metal.colourID)
        }
        return ordered
    }

    /// Pairs that may be offered for a two-tone configuration with `metal`.
    public func pairingOptions(for metal: Metal) -> [Metal] {
        metals.filter { metal.canPair(with: $0) }
    }
}

/// The metals the studio offers, as fixture data.
///
/// Written in code rather than loaded from JSON because the list is small,
/// stable, and needs to exist even when a resource bundle is unavailable (unit
/// tests of the builder, for instance). The pricing rates that go with these
/// keys live in the rate table as data.
public enum StandardMetals {

    public static let all: [Metal] = [
        Metal(id: "gold-10k-yellow", name: "yellow gold", family: .gold, karat: 10,
              colourID: "yellow", densityGramsPerCubicCentimetre: 11.60,
              rateKey: "gold-10k", swatchHex: "#D8B25E"),
        Metal(id: "gold-14k-yellow", name: "yellow gold", family: .gold, karat: 14,
              colourID: "yellow", densityGramsPerCubicCentimetre: 13.40,
              rateKey: "gold-14k", swatchHex: "#D4AF37"),
        Metal(id: "gold-14k-white", name: "white gold", family: .gold, karat: 14,
              colourID: "white", densityGramsPerCubicCentimetre: 13.40,
              rateKey: "gold-14k", swatchHex: "#E6E6E6"),
        Metal(id: "gold-14k-rose", name: "rose gold", family: .gold, karat: 14,
              colourID: "rose", densityGramsPerCubicCentimetre: 13.30,
              rateKey: "gold-14k", swatchHex: "#E0A899"),
        Metal(id: "gold-18k-yellow", name: "yellow gold", family: .gold, karat: 18,
              colourID: "yellow", densityGramsPerCubicCentimetre: 15.50,
              rateKey: "gold-18k", swatchHex: "#E0BE5A"),
        Metal(id: "gold-18k-white", name: "white gold", family: .gold, karat: 18,
              colourID: "white", densityGramsPerCubicCentimetre: 15.20,
              rateKey: "gold-18k", swatchHex: "#EDEDED"),
        Metal(id: "gold-18k-rose", name: "rose gold", family: .gold, karat: 18,
              colourID: "rose", densityGramsPerCubicCentimetre: 15.30,
              rateKey: "gold-18k", swatchHex: "#D99C8E"),
        Metal(id: "gold-22k-yellow", name: "yellow gold", family: .gold, karat: 22,
              colourID: "yellow", densityGramsPerCubicCentimetre: 17.70,
              rateKey: "gold-22k", swatchHex: "#E8C766"),
        Metal(id: "platinum-950", name: "platinum", family: .platinum, karat: 0,
              colourID: "white", densityGramsPerCubicCentimetre: 20.70,
              rateKey: "platinum-950", swatchHex: "#E5E4E2"),
        Metal(id: "palladium-950", name: "palladium", family: .palladium, karat: 0,
              colourID: "white", densityGramsPerCubicCentimetre: 12.00,
              rateKey: "palladium-950", swatchHex: "#DCDCDC"),
        Metal(id: "silver-sterling", name: "sterling silver", family: .silver, karat: 0,
              colourID: "white", densityGramsPerCubicCentimetre: 10.36,
              rateKey: "silver-925", swatchHex: "#C9C9C9"),
        Metal(id: "titanium-6al4v", name: "titanium", family: .titanium, karat: 0,
              colourID: "grey", densityGramsPerCubicCentimetre: 4.43,
              rateKey: "titanium", swatchHex: "#B4B8BC"),
        Metal(id: "steel-316l", name: "stainless steel", family: .steel, karat: 0,
              colourID: "grey", densityGramsPerCubicCentimetre: 7.99,
              rateKey: "steel-316l", swatchHex: "#A5AAAF")
    ]

    public static var catalog: MetalCatalog {
        MetalCatalog(schemaVersion: 1, metals: all)
    }

    /// The metals a design may offer for its first tone by default.
    public static var defaultOffer: [Metal] {
        all.filter { $0.id == "gold-14k-yellow" || $0.id == "gold-14k-white" || $0.id == "gold-14k-rose" }
    }
}
