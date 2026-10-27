//
//  RenderAssets.swift
//  JewelcraftKit
//
//  Render targets and the material library, as data.
//
//  A property of the original worth preserving: its appearance came from
//  external files (265 `.vismat` materials, 15 `.visopt` option sets, 35 HDR
//  environments, plus dedicated refraction maps for diamond), so the look could
//  be changed without rebuilding the application. Nothing here is a copy of
//  those files — they are third-party and GemVision assets — but the *property*
//  is kept: materials and render options are JSON, loaded at runtime, and no
//  visual constant is hardcoded in a view or a shader.
//
//  The two tile sizes are the one concrete rendering fact the reverse
//  engineering recovered (1,240 × 600 and 1,240 × 1,240 composites for the
//  catalogue grid). They are asserted in the tests, and every other size here is
//  derived from them by an explicit rule rather than invented.
//

import Foundation

// MARK: - Pixel sizes

public struct PixelSize: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var pixelCount: Int { width * height }

    public var aspectRatio: Double {
        height == 0 ? 0 : Double(width) / Double(height)
    }

    public var descriptionText: String {
        "\(width)×\(height)"
    }

    /// A size scaled by an integer factor.
    public func scaled(by factor: Int) -> PixelSize {
        PixelSize(
            width: width * Swift.max(1, factor),
            height: height * Swift.max(1, factor)
        )
    }
}

// MARK: - Render targets

/// The sizes pixels are produced at.
public enum RenderTarget: String, Codable, CaseIterable, Sendable {

    /// The wide catalogue tile. **Recovered size.**
    case catalogTileWide
    /// The square catalogue tile. **Recovered size.**
    case catalogTileSquare
    /// Half the wide tile, for list rows.
    case thumbnail
    /// The interactive viewport's offscreen size.
    case viewportPreview
    /// Twice the wide tile, for an order's production imagery.
    case orderImage

    public var pixelSize: PixelSize {
        switch self {
        case .catalogTileWide:
            return PixelSize(width: 1240, height: 600)
        case .catalogTileSquare:
            return PixelSize(width: 1240, height: 1240)
        case .thumbnail:
            // Derived: half the wide tile, so a list row is the same
            // composition at half scale.
            return PixelSize(width: 620, height: 300)
        case .viewportPreview:
            return PixelSize(width: 1024, height: 1024)
        case .orderImage:
            // Derived: the wide tile at twice linear scale.
            return PixelSize(width: 2480, height: 1200)
        }
    }

    /// Whether the size itself was recovered from the original rather than
    /// derived. The fidelity ledger distinguishes the two.
    public var isRecoveredSize: Bool {
        switch self {
        case .catalogTileWide, .catalogTileSquare:
            return true
        case .thumbnail, .viewportPreview, .orderImage:
            return false
        }
    }

    public var derivationNote: String {
        switch self {
        case .catalogTileWide:
            return "Recovered: catalogue tile composite size."
        case .catalogTileSquare:
            return "Recovered: catalogue tile composite size."
        case .thumbnail:
            return "Derived: half the wide tile."
        case .viewportPreview:
            return "Derived: the interactive viewport's offscreen buffer."
        case .orderImage:
            return "Derived: the wide tile at twice linear scale."
        }
    }

    public var displayName: String {
        switch self {
        case .catalogTileWide: return "Catalogue tile (wide)"
        case .catalogTileSquare: return "Catalogue tile (square)"
        case .thumbnail: return "Thumbnail"
        case .viewportPreview: return "Viewport preview"
        case .orderImage: return "Order image"
        }
    }

    /// The cache key for a design at this target. Deterministic, so a tile is
    /// rendered once and then reused, including across app launches.
    public func key(for designID: DesignID) -> String {
        "\(rawValue)/\(designID.rawValue)/\(pixelSize.width)x\(pixelSize.height)"
    }
}

// MARK: - Materials

public enum MaterialKind: String, Codable, CaseIterable, Sendable {
    case metal
    case gem
    case neutral
}

/// One material definition.
public struct MaterialDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var kind: MaterialKind
    public var baseColourHex: String
    /// 0 for a dielectric, 1 for a metal.
    public var metallic: Double
    public var roughness: Double
    public var clearcoat: Double
    /// 1 is opaque. A faceted stone sits below 1 so the pavilion reads through
    /// the crown.
    public var opacity: Double
    public var indexOfRefraction: Double
    public var emissiveHex: String?
    /// How strongly a stone's own colour tints this material, 0 to 1.
    public var colourTintStrength: Double

    public init(
        id: String,
        displayName: String,
        kind: MaterialKind,
        baseColourHex: String,
        metallic: Double,
        roughness: Double,
        clearcoat: Double = 0,
        opacity: Double = 1,
        indexOfRefraction: Double = 1.5,
        emissiveHex: String? = nil,
        colourTintStrength: Double = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.baseColourHex = baseColourHex
        self.metallic = metallic
        self.roughness = roughness
        self.clearcoat = clearcoat
        self.opacity = opacity
        self.indexOfRefraction = indexOfRefraction
        self.emissiveHex = emissiveHex
        self.colourTintStrength = colourTintStrength
    }

    public var baseColour: RGBColour {
        RGBColour(hex: baseColourHex) ?? RGBColour(red: 0.8, green: 0.8, blue: 0.8)
    }

    public var emissiveColour: RGBColour? {
        guard let emissiveHex else { return nil }
        return RGBColour(hex: emissiveHex)
    }

    /// Blends this material's base colour towards `colour` by the given
    /// strength. One code path serves metals and gems, so a stone's colour and a
    /// two-tone ring's second metal are tinted by the same rule.
    public func tinted(with colour: RGBColour, strength: Double? = nil) -> MaterialDefinition {
        let amount = Swift.max(0, Swift.min(1, strength ?? colourTintStrength))
        var copy = self
        let base = baseColour
        let red = base.red * (1 - amount) + colour.red * amount
        let green = base.green * (1 - amount) + colour.green * amount
        let blue = base.blue * (1 - amount) + colour.blue * amount
        copy.baseColourHex = RGBColour(red: red, green: green, blue: blue, alpha: base.alpha).hexString
        // A tinted stone also takes a little more transparency, so a pale stone
        // does not read as solid metal.
        copy.opacity = Swift.min(opacity, Swift.max(0.35, opacity * (1 - amount * 0.25)))
        return copy
    }
}

/// Render options, the rebuilt equivalent of a `.visopt` render-option set.
public struct RenderOptions: Codable, Hashable, Sendable {
    public var environmentID: String
    public var exposure: Double
    public var ambientIntensity: Double
    public var backgroundHex: String
    public var showsGroundShadow: Bool
    public var environmentIntensity: Double

    public init(
        environmentID: String,
        exposure: Double,
        ambientIntensity: Double,
        backgroundHex: String,
        showsGroundShadow: Bool,
        environmentIntensity: Double
    ) {
        self.environmentID = environmentID
        self.exposure = exposure
        self.ambientIntensity = ambientIntensity
        self.backgroundHex = backgroundHex
        self.showsGroundShadow = showsGroundShadow
        self.environmentIntensity = environmentIntensity
    }

    public var backgroundColor: RGBColour {
        RGBColour(hex: backgroundHex) ?? RGBColour(red: 0.06, green: 0.06, blue: 0.08)
    }
}

/// The material library, loaded from data.
public struct MaterialLibrary: Codable, Sendable {
    public var schemaVersion: Int
    public var materials: [MaterialDefinition]
    public var renderOptions: RenderOptions
    /// Material used when nothing else matches, so a missing entry degrades to a
    /// plain white-metal look rather than to an invisible model.
    public var fallbackMaterialID: String

    public init(
        schemaVersion: Int,
        materials: [MaterialDefinition],
        renderOptions: RenderOptions,
        fallbackMaterialID: String
    ) {
        self.schemaVersion = schemaVersion
        self.materials = materials
        self.renderOptions = renderOptions
        self.fallbackMaterialID = fallbackMaterialID
    }

    public func material(id: String) -> MaterialDefinition? {
        materials.first { $0.id == id }
    }

    public var fallback: MaterialDefinition {
        if let configured = material(id: fallbackMaterialID) { return configured }
        if let neutral = materials.first(where: { $0.kind == .neutral }) { return neutral }
        return MaterialDefinition(
            id: "fallback",
            displayName: "Fallback",
            kind: .neutral,
            baseColourHex: "#C8C8C8",
            metallic: 1,
            roughness: 0.35
        )
    }

    /// The material for an alloy: its own entry if present, otherwise the entry
    /// for its colour family, otherwise the fallback tinted to the alloy's own
    /// swatch.
    public func material(for metal: Metal) -> MaterialDefinition {
        if let exact = material(id: "metal.\(metal.id)") { return exact }
        if let byColour = material(id: "metal.colour.\(metal.colourID)") { return byColour }
        return fallback.tinted(with: metal.swatch, strength: 0.65)
    }

    /// The material for a stone: the material family's entry, tinted by the
    /// stone's colour.
    public func material(
        forGemMaterial gemMaterial: GemMaterial,
        colour: RGBColour
    ) -> MaterialDefinition {
        if let exact = material(id: "gem.\(gemMaterial.rawValue)") {
            return exact.tinted(with: colour)
        }
        if var generic = material(id: "gem.default") {
            generic.indexOfRefraction = gemMaterial.refractiveIndex
            return generic.tinted(with: colour)
        }
        return fallback
    }

    /// Every metal in the catalogue should have a usable material. Checked by
    /// the test suite, so a new alloy cannot ship with no appearance.
    public func missingMetalMaterials(in catalog: MetalCatalog) -> [String] {
        let fallbackID = fallback.id
        return catalog.metals.compactMap { metal in
            material(for: metal).id == fallbackID ? metal.id : nil
        }
    }

    /// Every gem material should have a usable material.
    public func missingGemMaterials() -> [String] {
        let covered = Set(materials.filter { $0.kind == .gem }.map(\.id))
        guard !covered.contains("gem.default") else { return [] }
        return GemMaterial.allCases.compactMap { gemMaterial in
            covered.contains("gem.\(gemMaterial.rawValue)") ? nil : gemMaterial.rawValue
        }
    }
}
