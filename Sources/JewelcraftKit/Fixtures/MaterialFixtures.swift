//
//  MaterialFixtures.swift
//  JewelcraftKit
//
//  The material library and the render options, as data.
//
//  The recovered product loaded its appearance from 265 `.vismat` material
//  files, 15 render-option sets and 35 HDR environments, which is why its look
//  could change without a rebuild. The rebuild keeps that property — materials
//  and options are values, not constants inside a view — while replacing the
//  look itself: a physically based metal and a tinted dielectric stone, not a
//  copy of anyone's shader.
//
//  What is approximated is recorded in docs/FIDELITY.md: a faceted stone here is
//  a tinted, semi-transparent dielectric with an environment reflection, which
//  is not the same thing as traced dispersion through a brilliant.
//

import Foundation

public enum MaterialFixtures {

    public static let fixtureName = "materials"

    // MARK: - Metals

    /// Roughness by family: platinum and palladium take a softer polish than
    /// gold, and titanium a duller one than either.
    static func roughness(for metal: Metal) -> Double {
        switch metal.family {
        case .gold: return metal.karat >= 18 ? 0.16 : 0.19
        case .platinum: return 0.14
        case .palladium: return 0.17
        case .silver: return 0.22
        case .titanium: return 0.30
        case .steel: return 0.25
        }
    }

    public static var metalMaterials: [MaterialDefinition] {
        StandardMetals.all.map { metal in
            MaterialDefinition(
                id: "metal.\(metal.id)",
                displayName: "\(metal.karat > 0 ? "\(metal.karat)k " : "")\(metal.name)",
                kind: .metal,
                baseColourHex: metal.swatchHex,
                metallic: 1.0,
                roughness: roughness(for: metal),
                clearcoat: 0.0,
                opacity: 1.0,
                indexOfRefraction: 2.4,
                emissiveHex: nil,
                colourTintStrength: 0.0
            )
        }
    }

    // MARK: - Stones

    /// How transparent a stone reads. A diamond is the most transparent; an
    /// opaque cabochon material is nearly solid.
    static func opacity(for material: GemMaterial) -> Double {
        switch material {
        case .diamond: return 0.55
        case .moissanite: return 0.60
        case .cubicZirconia: return 0.58
        case .imitation: return 0.65
        case .ruby, .sapphire, .emerald, .tanzanite: return 0.78
        case .morganite, .aquamarine, .amethyst, .topaz, .garnet: return 0.72
        case .pearl: return 0.95
        }
    }

    /// How strongly the stone's own colour tints the material. A blue sapphire
    /// should read blue; a white diamond should stay white.
    static func tintStrength(for material: GemMaterial) -> Double {
        switch material {
        case .diamond, .moissanite, .cubicZirconia, .imitation: return 0.35
        case .pearl: return 0.6
        default: return 0.85
        }
    }

    public static var gemMaterials: [MaterialDefinition] {
        GemMaterial.allCases.map { material in
            MaterialDefinition(
                id: "gem.\(material.rawValue)",
                displayName: material.displayName,
                kind: .gem,
                baseColourHex: "#F4F6F8",
                metallic: 0.0,
                roughness: 0.05,
                clearcoat: 1.0,
                opacity: opacity(for: material),
                indexOfRefraction: material.refractiveIndex,
                emissiveHex: nil,
                colourTintStrength: tintStrength(for: material)
            )
        }
    }

    // MARK: - Neutral

    public static let neutralMaterials: [MaterialDefinition] = [
        MaterialDefinition(
            id: "neutral.white-metal",
            displayName: "White metal",
            kind: .neutral,
            baseColourHex: "#D9DEE4",
            metallic: 1.0,
            roughness: 0.24
        ),
        MaterialDefinition(
            id: "neutral.ground",
            displayName: "Ground",
            kind: .neutral,
            baseColourHex: "#11151B",
            metallic: 0.0,
            roughness: 0.65
        )
    ]

    /// A generic stone, used when a material has no entry of its own. Carries a
    /// diamond's refraction so an unknown stone still looks like a stone.
    public static let genericGemMaterial = MaterialDefinition(
        id: "gem.default",
        displayName: "Stone",
        kind: .gem,
        baseColourHex: "#EEF2F6",
        metallic: 0.0,
        roughness: 0.06,
        clearcoat: 1.0,
        opacity: 0.65,
        indexOfRefraction: 2.0,
        emissiveHex: nil,
        colourTintStrength: 0.5
    )

    // MARK: - Render options

    /// A soft studio key with a dim bounce, which is the lighting the product's
    /// catalogue tiles used: a bright key from the upper left, a fill low right,
    /// and a dark background so the metal reads.
    public static let renderOptions = RenderOptions(
        environmentID: "env.studio-softbox",
        exposure: 0.12,
        ambientIntensity: 0.35,
        backgroundHex: "#0E1116",
        showsGroundShadow: true,
        environmentIntensity: 1.15
    )

    // MARK: - Library

    public static var materials: [MaterialDefinition] {
        metalMaterials + gemMaterials + neutralMaterials + [genericGemMaterial]
    }

    public static var library: MaterialLibrary {
        MaterialLibrary(
            schemaVersion: 1,
            materials: materials,
            renderOptions: renderOptions,
            fallbackMaterialID: "neutral.white-metal"
        )
    }

    // MARK: - Integrity

    /// Problems that would make the library unusable. The render tests require
    /// this to be empty.
    public static func integrityIssues() -> [String] {
        var issues: [String] = []
        let library = MaterialFixtures.library

        if Set(library.materials.map(\.id)).count != library.materials.count {
            issues.append("material library contains duplicate ids")
        }

        for material in library.materials {
            if RGBColour(hex: material.baseColourHex) == nil {
                issues.append("material \(material.id) has an unparseable base colour")
            }
            if !(0...1).contains(material.metallic) {
                issues.append("material \(material.id) has metallic outside 0...1")
            }
            if !(0...1).contains(material.roughness) {
                issues.append("material \(material.id) has roughness outside 0...1")
            }
            if !(0...1).contains(material.opacity) {
                issues.append("material \(material.id) has opacity outside 0...1")
            }
            if material.indexOfRefraction < 1.0 {
                issues.append("material \(material.id) has a refractive index below 1")
            }
        }

        for metalID in library.missingMetalMaterials(in: StandardMetals.catalog) {
            issues.append("metal \(metalID) has no usable material")
        }

        for gemID in library.missingGemMaterials() {
            issues.append("gem material \(gemID) has no usable material")
        }

        if RGBColour(hex: library.renderOptions.backgroundHex) == nil {
            issues.append("render options have an unparseable background")
        }

        return issues
    }
}

// MARK: - Fixture conformance

extension MaterialLibrary: CodeFixture {
    public static var fixtureName: String { MaterialFixtures.fixtureName }
    public static func make() -> MaterialLibrary { MaterialFixtures.library }
}
