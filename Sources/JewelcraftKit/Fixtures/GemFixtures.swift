//
//  GemFixtures.swift
//  JewelcraftKit
//
//  The gemstone vocabulary: grades, colours and the per-shape definition
//  records.
//
//  Two properties of the original are reproduced here, and one is deliberately
//  not.
//
//  Reproduced:
//    * Grades are the studio's own vocabulary, and the mapping from a grade to
//      whatever a supplier calls it lives in exactly one place
//      (`QualityVocabulary`) rather than in a view or an order document.
//    * A definition record is per material *and* shape, because what the CAD
//      side needs to know differs by shape as much as by material.
//
//  Not reproduced: any supplier's grade names, codes or prices. These grades
//  are invented and the rate table that prices them is synthetic.
//

import Foundation

public enum GemFixtures {

    /// The document name this fixture is published under.
    public static let fixtureName = "gem-catalog"

    public static let defaultColourID = "c.white"

    // MARK: - Grades

    /// A material with no graduated grades still needs one selectable state, or
    /// the configurator has a choice it cannot express. That is `q.standard`.
    public static let standardGrade = GemQuality(
        id: "q.standard", name: "Standard", rank: 0, appliesToMaterials: []
    )

    private static let diamondFamily: [GemMaterial] = [
        .diamond, .moissanite, .cubicZirconia, .imitation
    ]

    private static let colouredFamily: [GemMaterial] = [
        .ruby, .sapphire, .emerald, .morganite, .aquamarine,
        .tanzanite, .amethyst, .topaz, .garnet
    ]

    /// The graduated grades offered for the diamond-family materials, best
    /// first by rank. `q.standard` ranks 0 and therefore leads every list.
    public static let diamondGrades: [GemQuality] = [
        GemQuality(id: "q.diamond.signature", name: "Signature", rank: 1,
                   appliesToMaterials: diamondFamily),
        GemQuality(id: "q.diamond.premier", name: "Premier", rank: 2,
                   appliesToMaterials: diamondFamily),
        GemQuality(id: "q.diamond.classic", name: "Classic", rank: 3,
                   appliesToMaterials: diamondFamily)
    ]

    /// The grades offered for the coloured materials.
    public static let colouredGrades: [GemQuality] = [
        GemQuality(id: "q.colour.fine", name: "Fine", rank: 1,
                   appliesToMaterials: colouredFamily),
        GemQuality(id: "q.colour.commercial", name: "Commercial", rank: 2,
                   appliesToMaterials: colouredFamily)
    ]

    public static let qualities: [GemQuality] = [standardGrade] + diamondGrades + colouredGrades

    // MARK: - Colours

    public static let colours: [GemColour] = [
        GemColour(id: "c.white", name: "White", swatchHex: "#F4F6F8", appliesToMaterials: []),
        GemColour(id: "c.champagne", name: "Champagne", swatchHex: "#E7D3A9",
                  appliesToMaterials: [.diamond, .moissanite, .cubicZirconia]),
        GemColour(id: "c.fancyYellow", name: "Fancy yellow", swatchHex: "#F2C14E",
                  appliesToMaterials: [.diamond, .sapphire, .topaz, .cubicZirconia]),
        GemColour(id: "c.pink", name: "Pink", swatchHex: "#F0B4C4",
                  appliesToMaterials: [.diamond, .sapphire, .morganite, .topaz, .cubicZirconia]),
        GemColour(id: "c.blue", name: "Blue", swatchHex: "#6FA8DC",
                  appliesToMaterials: [.sapphire, .topaz, .aquamarine, .tanzanite]),
        GemColour(id: "c.red", name: "Red", swatchHex: "#C0392B",
                  appliesToMaterials: [.ruby, .garnet]),
        GemColour(id: "c.green", name: "Green", swatchHex: "#4E9A6B",
                  appliesToMaterials: [.emerald, .tanzanite]),
        GemColour(id: "c.purple", name: "Purple", swatchHex: "#8E7CC3",
                  appliesToMaterials: [.amethyst, .sapphire]),
        GemColour(id: "c.cream", name: "Cream", swatchHex: "#F5EFE6",
                  appliesToMaterials: [.pearl]),
        GemColour(id: "c.grey", name: "Grey", swatchHex: "#B4B8BC",
                  appliesToMaterials: [.diamond, .pearl, .imitation, .cubicZirconia])
    ]

    // MARK: - Definitions

    /// One row per material: the shapes it is cut in, its default grade and its
    /// default colour. Kept as a table because it is data, and because a table
    /// is what a future catalogue import would produce.
    public static let definitionTable: [(material: GemMaterial, shapes: [GemShape], qualityID: String, colourID: String)] = [
        (.diamond, GemShape.allCases, "q.diamond.premier", "c.white"),
        (.moissanite, [.roundBrilliant, .oval, .cushion, .princess], "q.diamond.premier", "c.white"),
        (.cubicZirconia, [.roundBrilliant, .oval, .princess], "q.diamond.classic", "c.white"),
        (.imitation, [.roundBrilliant, .oval], "q.diamond.classic", "c.white"),
        (.ruby, [.roundBrilliant, .oval, .cushion], "q.colour.fine", "c.red"),
        (.sapphire, [.roundBrilliant, .oval, .cushion, .emerald], "q.colour.fine", "c.blue"),
        (.emerald, [.emerald, .oval, .roundBrilliant], "q.colour.fine", "c.green"),
        (.morganite, [.oval, .cushion], "q.colour.fine", "c.pink"),
        (.aquamarine, [.oval, .emerald], "q.colour.commercial", "c.blue"),
        (.tanzanite, [.oval, .cushion], "q.colour.fine", "c.blue"),
        (.amethyst, [.roundBrilliant, .cushion], "q.colour.commercial", "c.purple"),
        (.topaz, [.oval, .emerald], "q.colour.commercial", "c.blue"),
        (.garnet, [.roundBrilliant, .oval], "q.colour.commercial", "c.red"),
        (.pearl, [.roundCabochon, .oval], "q.standard", "c.cream")
    ]

    public static let definitions: [GemDefinition] = definitionTable.flatMap { row in
        row.shapes.map { shape in
            GemDefinition(
                id: "gem.\(row.material.rawValue).\(shape.rawValue)",
                material: row.material,
                shape: shape,
                defaultColourID: row.colourID,
                defaultQualityID: row.qualityID,
                displayName: "\(row.material.displayName) \(shape.displayName)"
            )
        }
    }

    /// The vocabulary, ready to use.
    public static var catalog: GemCatalog {
        GemCatalog(
            schemaVersion: 1,
            definitions: definitions,
            qualities: qualities,
            colours: colours
        )
    }

    /// The record a shape change falls back on: the exact record when the
    /// material is cut that way, otherwise the material's first record, so a
    /// shape change never loses the material.
    public static func defaultDefinition(
        material: GemMaterial,
        shape: GemShape
    ) -> GemDefinition? {
        catalog.definition(material: material, shape: shape)
            ?? catalog.definitions.first { $0.material == material }
    }

    /// Whether the fixture is internally consistent: every definition's colour
    /// and grade exist, and every material has at least one definition.
    public static func integrityIssues() -> [String] {
        var issues: [String] = []
        let catalog = GemFixtures.catalog
        let qualityIDs = Set(qualities.map(\.id))
        let colourIDs = Set(colours.map(\.id))

        for definition in definitions {
            if !qualityIDs.contains(definition.defaultQualityID) {
                issues.append("gem definition \(definition.id) uses unknown grade \(definition.defaultQualityID)")
            }
            if !colourIDs.contains(definition.defaultColourID) {
                issues.append("gem definition \(definition.id) uses unknown colour \(definition.defaultColourID)")
            }
        }

        for material in GemMaterial.allCases where !definitions.contains(where: { $0.material == material }) {
            issues.append("material \(material.rawValue) has no gem definition")
        }

        for material in GemMaterial.allCases where catalog.colours(for: material).isEmpty {
            issues.append("material \(material.rawValue) offers no colour")
        }

        for material in GemMaterial.allCases where catalog.qualities(for: material).isEmpty {
            issues.append("material \(material.rawValue) offers no grade")
        }

        return issues
    }
}

// MARK: - The grade-to-lot mapping

/// The single place where the studio's grades meet whatever a supplier calls
/// them.
///
/// The recovered product kept this mapping in a dedicated adapter, and the
/// rebuild keeps it in one type for the same reason: an order document, a quote
/// line or a screen must never carry a supplier's code, because that code is
/// not the studio's to define and can change without a redesign.
public struct QualityVocabulary: Codable, Hashable, Sendable {

    public struct Entry: Codable, Hashable, Identifiable, Sendable {
        public var id: String { gradeID }
        public var gradeID: String
        /// The studio's own lot name, which is what a customer or a jeweller
        /// sees. Deliberately not a supplier's abbreviation.
        public var lotName: String
        public var summary: String

        public init(gradeID: String, lotName: String, summary: String) {
            self.gradeID = gradeID
            self.lotName = lotName
            self.summary = summary
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public static let standard = QualityVocabulary(entries: [
        Entry(gradeID: "q.standard", lotName: "Standard lot",
              summary: "One grade, quoted per stone; used where a graduated grade list would be meaningless."),
        Entry(gradeID: "q.diamond.signature", lotName: "Signature lot",
              summary: "The top of the offered range: hand-picked for colour and clarity."),
        Entry(gradeID: "q.diamond.premier", lotName: "Premier lot",
              summary: "The working grade for most commissions."),
        Entry(gradeID: "q.diamond.classic", lotName: "Classic lot",
              summary: "A commercial grade for a stated budget."),
        Entry(gradeID: "q.colour.fine", lotName: "Fine colour lot",
              summary: "Even saturation and no visible inclusions at arm's length."),
        Entry(gradeID: "q.colour.commercial", lotName: "Commercial colour lot",
              summary: "A workable colour grade at a lower price.")
    ])

    public func entry(forGrade gradeID: String) -> Entry? {
        entries.first { $0.gradeID == gradeID }
    }

    /// The customer-facing name for a grade, falling back to the grade id so a
    /// new grade still renders rather than disappearing from a screen.
    public func lotName(forGrade gradeID: String) -> String {
        entry(forGrade: gradeID)?.lotName ?? gradeID
    }

    public var gradeIDs: [String] {
        entries.map(\.gradeID)
    }

    /// Every grade a material may be quoted in, in display order.
    public func grades(for material: GemMaterial, catalog: GemCatalog = GemFixtures.catalog) -> [GemQuality] {
        catalog.qualities(for: material)
    }

    /// Every grade in the vocabulary should be offered for at least one
    /// material, or it is a dead entry in a picker.
    public func unusedGradeIDs(in catalog: GemCatalog = GemFixtures.catalog) -> [String] {
        let used = Set(GemMaterial.allCases.flatMap { catalog.qualities(for: $0).map(\.id) })
        return gradeIDs.filter { !used.contains($0) }
    }
}

// MARK: - Fixture conformance

extension GemCatalog: CodeFixture {
    public static var fixtureName: String { GemFixtures.fixtureName }
    public static func make() -> GemCatalog { GemFixtures.catalog }
}
