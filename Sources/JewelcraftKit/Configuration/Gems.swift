//
//  Gems.swift
//  JewelcraftKit
//
//  Gemstones as records, separate from gemstone geometry.
//
//  The original application shipped 57 `.gem` definition files alongside its
//  Rhino `.csg` geometry, and its search could filter on gem setting, colour and
//  shape independently of the metal. That separation is reproduced here and is
//  load-bearing: a gem is a *record* (material, shape, colour, quality, physical
//  constants) and its solid is *generated* from that record by the geometry
//  kernel. Adding a stone therefore means adding data, not code.
//
//  Physical constants (specific gravity, refractive index, dispersion) are
//  published reference values for the materials named — facts about the world,
//  not assets belonging to anyone.
//

import Foundation

// MARK: - Shape

/// A gemstone's outline family.
///
/// The set is deliberately the one the geometry kernel can build correctly.
/// Recognisable shapes that were not implemented are listed in
/// `docs/FIDELITY.md` as deferred rather than approximated badly.
public enum GemShape: String, Codable, CaseIterable, Sendable {
    case roundBrilliant
    case oval
    case princess
    case cushion
    case emerald
    case radiant
    case asscher
    case pear
    case marquise
    case trillion
    case baguette
    case roundCabochon

    public var displayName: String {
        switch self {
        case .roundBrilliant: return "Round brilliant"
        case .oval: return "Oval"
        case .princess: return "Princess"
        case .cushion: return "Cushion"
        case .emerald: return "Emerald"
        case .radiant: return "Radiant"
        case .asscher: return "Asscher"
        case .pear: return "Pear"
        case .marquise: return "Marquise"
        case .trillion: return "Trillion"
        case .baguette: return "Baguette"
        case .roundCabochon: return "Round cabochon"
        }
    }

    /// The shape's index in a stable ordering, used when a deterministic
    /// sequence is needed (fixture generation, sorting).
    public var order: Int {
        GemShape.allCases.firstIndex(of: self) ?? 0
    }

    /// Aspect of the outline's long axis to its short axis. Used by the UI to
    /// show sizes the way a jeweller would read them.
    public var typicalAspectRatio: Double {
        switch self {
        case .roundBrilliant, .roundCabochon, .princess, .cushion, .asscher, .trillion:
            return 1.0
        case .oval:
            return 0.72
        case .emerald:
            return 0.60
        case .radiant:
            return 0.65
        case .baguette:
            return 0.45
        case .pear, .marquise:
            return 0.50
        }
    }
}

// MARK: - Material

/// The gem material. Specific gravity drives the carat-to-size relation, so it
/// is carried per material rather than assumed.
public enum GemMaterial: String, Codable, CaseIterable, Sendable {
    case diamond
    case moissanite
    case ruby
    case sapphire
    case emerald
    case morganite
    case aquamarine
    case tanzanite
    case amethyst
    case topaz
    case garnet
    case pearl
    case cubicZirconia
    case imitation

    public var displayName: String {
        switch self {
        case .diamond: return "Diamond"
        case .moissanite: return "Moissanite"
        case .ruby: return "Ruby"
        case .sapphire: return "Sapphire"
        case .emerald: return "Emerald"
        case .morganite: return "Morganite"
        case .aquamarine: return "Aquamarine"
        case .tanzanite: return "Tanzanite"
        case .amethyst: return "Amethyst"
        case .topaz: return "Topaz"
        case .garnet: return "Garnet"
        case .pearl: return "Pearl"
        case .cubicZirconia: return "Cubic zirconia"
        case .imitation: return "Imitation stone"
        }
    }

    /// Specific gravity in g/cm³, which equals milligrams per cubic millimetre.
    /// Published reference values.
    public var specificGravity: Double {
        switch self {
        case .diamond: return 3.52
        case .moissanite: return 3.21
        case .ruby: return 4.00
        case .sapphire: return 4.00
        case .emerald: return 2.76
        case .morganite: return 2.80
        case .aquamarine: return 2.72
        case .tanzanite: return 3.35
        case .amethyst: return 2.65
        case .topaz: return 3.53
        case .garnet: return 3.80
        case .pearl: return 2.70
        case .cubicZirconia: return 5.70
        case .imitation: return 2.50
        }
    }

    /// Refractive index, used by the renderer to pick a specular response.
    public var refractiveIndex: Double {
        switch self {
        case .diamond: return 2.417
        case .moissanite: return 2.648
        case .ruby, .sapphire: return 1.770
        case .emerald: return 1.577
        case .morganite: return 1.580
        case .aquamarine: return 1.577
        case .tanzanite: return 1.690
        case .amethyst: return 1.544
        case .topaz: return 1.620
        case .garnet: return 1.730
        case .pearl: return 1.530
        case .cubicZirconia: return 2.170
        case .imitation: return 1.520
        }
    }

    /// Dispersion (fire). Diamonds and moissanite are the reason a gemstone
    /// looks alive rather than glassy, and it is what the original's dedicated
    /// refraction maps were there to sell.
    public var dispersion: Double {
        switch self {
        case .diamond: return 0.044
        case .moissanite: return 0.104
        case .cubicZirconia: return 0.060
        case .sapphire: return 0.018
        case .ruby: return 0.018
        case .emerald: return 0.014
        case .topaz: return 0.014
        case .garnet: return 0.022
        case .tanzanite: return 0.021
        default: return 0.012
        }
    }

    /// Whether the material is a stone substitute. The recovered product
    /// carried an explicit flag of this kind on its materials, and it gates
    /// whether a design may offer the material at all.
    public var isStoneSubstitute: Bool {
        switch self {
        case .imitation, .cubicZirconia, .moissanite:
            return true
        default:
            return false
        }
    }

    /// Whether the collected quality vocabulary may include this material.
    /// Pearls are sold on luster rather than graduated quality grades, so the
    /// UI must not offer a diamond-style grade list for them.
    public var usesGraduatedQualityGrades: Bool {
        self != .pearl
    }
}

// MARK: - Quality and colour

/// A quality grade in the studio's own vocabulary.
///
/// The grade list is *our* vocabulary. The original mapped between its own
/// grade names and its supplier's codes in a dedicated adapter, and that
/// mapping is reproduced by `QualityVocabulary` — the app never hardcodes a
/// supplier's code.
public struct GemQuality: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var rank: Int
    public var appliesToMaterials: [GemMaterial]

    public init(id: String, name: String, rank: Int, appliesToMaterials: [GemMaterial]) {
        self.id = id
        self.name = name
        self.rank = rank
        self.appliesToMaterials = appliesToMaterials
    }

    public func applies(to material: GemMaterial) -> Bool {
        appliesToMaterials.isEmpty || appliesToMaterials.contains(material)
    }
}

/// A colour a stone can be offered in.
public struct GemColour: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Display swatch, so the UI can tint a stone without its own colour table.
    public var swatchHex: String
    public var appliesToMaterials: [GemMaterial]

    public init(id: String, name: String, swatchHex: String, appliesToMaterials: [GemMaterial]) {
        self.id = id
        self.name = name
        self.swatchHex = swatchHex
        self.appliesToMaterials = appliesToMaterials
    }

    public func applies(to material: GemMaterial) -> Bool {
        appliesToMaterials.isEmpty || appliesToMaterials.contains(material)
    }

    public var swatch: RGBColour {
        RGBColour(hex: swatchHex) ?? RGBColour(red: 1, green: 1, blue: 1)
    }
}

// MARK: - Gem definition record

/// A gemstone definition record: the rebuilt equivalent of one `.gem` file.
///
/// The original kept 57 of these next to its geometry, and its `GemAttribFix`
/// library member shows that shifting attributes between records was a real
/// maintenance concern. Versioning the records from the first commit is the
/// cheap insurance against rediscovering that.
public struct GemDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var material: GemMaterial
    public var shape: GemShape
    /// Default colour for this record; the configuration may override it.
    public var defaultColourID: String
    public var defaultQualityID: String
    public var displayName: String

    public init(
        id: String,
        material: GemMaterial,
        shape: GemShape,
        defaultColourID: String,
        defaultQualityID: String,
        displayName: String
    ) {
        self.id = id
        self.material = material
        self.shape = shape
        self.defaultColourID = defaultColourID
        self.defaultQualityID = defaultQualityID
        self.displayName = displayName
    }
}

/// The loaded gem catalogue: definitions plus their vocabularies.
public struct GemCatalog: Codable, Sendable {
    public var schemaVersion: Int
    public var definitions: [GemDefinition]
    public var qualities: [GemQuality]
    public var colours: [GemColour]

    public init(schemaVersion: Int, definitions: [GemDefinition], qualities: [GemQuality], colours: [GemColour]) {
        self.schemaVersion = schemaVersion
        self.definitions = definitions
        self.qualities = qualities
        self.colours = colours
    }

    public func definition(id: String) -> GemDefinition? {
        definitions.first { $0.id == id }
    }

    public func definition(material: GemMaterial, shape: GemShape) -> GemDefinition? {
        definitions.first { $0.material == material && $0.shape == shape }
    }

    public func quality(id: String) -> GemQuality? {
        qualities.first { $0.id == id }
    }

    public func colour(id: String) -> GemColour? {
        colours.first { $0.id == id }
    }

    /// Qualities that may be offered for a material, cheapest first.
    public func qualities(for material: GemMaterial) -> [GemQuality] {
        guard material.usesGraduatedQualityGrades else {
            // A material with no graduated grades still needs one selectable
            // state, or the configurator has an unrepresentable choice.
            return qualities.filter { $0.rank == 0 }
        }
        return qualities.filter { $0.applies(to: material) }.sorted { $0.rank < $1.rank }
    }

    /// Colours that may be offered for a material.
    public func colours(for material: GemMaterial) -> [GemColour] {
        colours.filter { $0.applies(to: material) }
    }

    public func shapes(for material: GemMaterial) -> [GemShape] {
        let shapes = definitions.filter { $0.material == material }.map(\.shape)
        // Keep the canonical shape order rather than discovery order, so pickers
        // do not reshuffle when a definition is added.
        return GemShape.allCases.filter { shapes.contains($0) }
    }
}
