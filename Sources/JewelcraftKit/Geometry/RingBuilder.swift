//
//  RingBuilder.swift
//  JewelcraftKit
//
//  Assembles a configured ring from parameters.
//
//  Geometry conventions, fixed here so every module agrees:
//
//    * The ring's main axis is **Y**. The finger passes along Y, so the shank
//      lies in the XZ plane and "ring size" is measured as a distance from that
//      axis — the same measurement the sizing tools use.
//    * The head (the centre stone and its setting) sits at **+X**, at angle
//      theta = 0.
//    * A gemstone's local **+Y** is the table direction, so placing a stone
//      radially means rotating its local +Y onto the outward radial direction.
//    * Winding is outward-facing, so `Mesh.signedVolume` is positive for solid
//      metal and converts straight into a gram weight.
//
//  Every mesh this module returns is closed, and no part is ever emitted with an
//  empty mesh. That is not stylistic: a configured ring is meant to be printable,
//  and a ring with a hole in it is scrap metal. The test suite asserts closure
//  for every part, at every profile and every head style.
//

import Foundation

// MARK: - Parts

/// What a mesh represents in the assembled ring.
public enum PartKind: String, Codable, CaseIterable, Sendable {
    case shank
    case railGuide
    case prong
    case basket
    case bezel
    case bead
    case channel
    case haloRail
    case centreStone
    case accentStone
    case haloStone

    /// The kinds a two-tone configuration casts in its second metal: everything
    /// in the head. The builder assigns every metal part its metal from this one
    /// set and weighs it in that metal, so the model, the scene graph and the
    /// quote all describe the same ring.
    public static let headPartKinds: Set<PartKind> = [.prong, .basket, .bezel, .haloRail]

    /// Metal parts contribute to the ring's measured weight; stones do not.
    public var isMetal: Bool {
        switch self {
        case .shank, .prong, .basket, .bezel, .bead, .channel, .haloRail:
            return true
        case .railGuide, .centreStone, .accentStone, .haloStone:
            return false
        }
    }

    public var isStone: Bool {
        switch self {
        case .centreStone, .accentStone, .haloStone:
            return true
        default:
            return false
        }
    }
}

/// A named, addressable piece of the assembled ring.
///
/// This is the rebuilt equivalent of the original's part groups and graph items:
/// the CAD service addressed its geometry by id and GUID, carried per-item user
/// data, and let the UI highlight an item by identity. A part that cannot be
/// named cannot be highlighted, selected or replaced, so identity is part of the
/// data model rather than an afterthought.
public struct PartGroup: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: PartKind
    public var mesh: Mesh
    public var userData: [String: String]
    /// Which metal this part is cast in. Stones, construction geometry and any
    /// part built outside the ring builder carry none.
    public var metalID: String?
    /// Which configured gem slot this part belongs to, when it is a stone or a
    /// stone's setting.
    public var gemSlotIndex: Int?
    /// Guides start hidden; the viewport can reveal them on request.
    public var isVisibleByDefault: Bool

    public init(
        id: String,
        name: String,
        kind: PartKind,
        mesh: Mesh,
        userData: [String: String] = [:],
        metalID: String? = nil,
        gemSlotIndex: Int? = nil,
        isVisibleByDefault: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.mesh = mesh
        self.userData = userData
        self.metalID = metalID
        self.gemSlotIndex = gemSlotIndex
        self.isVisibleByDefault = isVisibleByDefault
    }

    public var triangleCount: Int { mesh.triangleCount }
}

// MARK: - Placement

/// Where a stone ended up, and how it is turned.
public struct GemPlacement: Equatable, Sendable {
    public var slotIndex: Int
    public var role: GemRole
    public var shape: GemShape
    public var material: GemMaterial
    public var colourID: String
    public var qualityID: String
    public var carat: Double
    /// Girdle width in millimetres; the diameter for a round stone.
    public var girdleWidthMillimetres: Double
    /// Centre of the girdle plane, in world space.
    public var position: Vector3
    public var orientation: Matrix4x4
    public var isManualSize: Bool

    /// The stone's mesh, in world space.
    public func mesh() -> Mesh {
        let layout = GemFacetLayout.standard(for: shape)
        let local = GemMeshBuilder.mesh(layout, girdleWidthMillimetres: girdleWidthMillimetres)
        return local.transformed(by: orientation).translated(by: position)
    }
}

// MARK: - Parameters

/// The parametric description of a ring, independent of any one design.
public struct RingParameters: Equatable, Sendable {
    /// The wearer's ring size, as the inside diameter in millimetres.
    public var innerDiameterMillimetres: Double
    public var shankWidthMillimetres: Double
    public var shankThicknessMillimetres: Double
    public var shankProfile: ShankProfileShape
    /// Extra radial thickness at the shoulders, tapering to nothing at the base.
    public var shoulderTaperMillimetres: Double
    /// How much narrower the shank becomes at its base, as a fraction of its
    /// width. 0 keeps the shank parallel.
    public var baseWidthTaperFraction: Double
    public var head: HeadSpec
    public var accentMetalWidthMillimetres: Double
    /// Divisions around the ring.
    public var resolution: Int

    public init(
        innerDiameterMillimetres: Double,
        shankWidthMillimetres: Double,
        shankThicknessMillimetres: Double,
        shankProfile: ShankProfileShape,
        shoulderTaperMillimetres: Double,
        baseWidthTaperFraction: Double,
        head: HeadSpec,
        accentMetalWidthMillimetres: Double,
        resolution: Int = 96
    ) {
        self.innerDiameterMillimetres = innerDiameterMillimetres
        self.shankWidthMillimetres = shankWidthMillimetres
        self.shankThicknessMillimetres = shankThicknessMillimetres
        self.shankProfile = shankProfile
        self.shoulderTaperMillimetres = shoulderTaperMillimetres
        self.baseWidthTaperFraction = baseWidthTaperFraction
        self.head = head
        self.accentMetalWidthMillimetres = accentMetalWidthMillimetres
        self.resolution = resolution
    }

    // MARK: Derived measures

    public var innerRadiusMillimetres: Double {
        innerDiameterMillimetres / 2
    }

    /// Radius to the middle of the shank's cross-section, before shoulder taper.
    public var baseCentrelineRadiusMillimetres: Double {
        innerRadiusMillimetres + shankThicknessMillimetres / 2
    }

    /// 1 at the head, falling smoothly to 0 at the opposite side of the ring.
    /// Drives both the shoulder taper and the width taper.
    public func shoulderFactor(at angle: Double) -> Double {
        (1 + cos(angle)) / 2
    }

    public func centrelineRadius(at angle: Double) -> Double {
        baseCentrelineRadiusMillimetres + shoulderTaperMillimetres * shoulderFactor(at: angle)
    }

    /// The shank's outer face at an angle, away from the ring's axis.
    public func outerRadius(at angle: Double) -> Double {
        centrelineRadius(at: angle) + shankThicknessMillimetres / 2
    }

    /// Cross-section width at an angle, after the base taper.
    public func shankWidth(at angle: Double) -> Double {
        let taper = baseWidthTaperFraction * (1 - shoulderFactor(at: angle))
        return shankWidthMillimetres * (1 - Swift.max(0, Swift.min(0.6, taper)))
    }
}

/// Which stones to place, and in what pattern.
public struct GemPlan: Equatable, Sendable {
    public var centre: GemSelection?
    public var accents: [GemSelection]
    public var accentPattern: AccentPattern

    public init(centre: GemSelection?, accents: [GemSelection], accentPattern: AccentPattern) {
        self.centre = centre
        self.accents = accents
        self.accentPattern = accentPattern
    }

    public static let empty = GemPlan(centre: nil, accents: [], accentPattern: .none)
}

// MARK: - Weight

/// How much of the ring is made of one metal.
///
/// A single-metal ring has one of these; a two-tone ring has two. Each is a
/// measured volume, not a share of the total: the parts assigned to a metal are
/// summed and weighed in that metal's own density.
public struct MetalWeight: Equatable, Sendable {
    public var metal: Metal
    public var volumeCubicMillimetres: Double
    public var grams: Double

    public init(metal: Metal, volumeCubicMillimetres: Double, grams: Double) {
        self.metal = metal
        self.volumeCubicMillimetres = volumeCubicMillimetres
        self.grams = grams
    }

    /// What the metric rows and the quote line print.
    public var gramsText: String {
        String(format: "%.2f g", grams)
    }
}

// MARK: - Result

/// The assembled ring.
public struct BuiltRing: Equatable, Sendable {
    public var designID: DesignID
    public var parts: [PartGroup]
    public var gemPlacements: [GemPlacement]
    /// Displaced metal volume, from the metal meshes' own geometry.
    public var metalVolumeCubicMillimetres: Double
    /// Estimated cast weight in grams.
    public var metalGrams: Double
    /// That weight by metal, in the order the metals were supplied.
    public var metalBreakdown: [MetalWeight]
    public var bounds: BoundingBox
    public var defects: [MeshDefect]

    public init(
        designID: DesignID,
        parts: [PartGroup],
        gemPlacements: [GemPlacement],
        metalVolumeCubicMillimetres: Double,
        metalGrams: Double,
        metalBreakdown: [MetalWeight] = [],
        bounds: BoundingBox,
        defects: [MeshDefect]
    ) {
        self.designID = designID
        self.parts = parts
        self.gemPlacements = gemPlacements
        self.metalVolumeCubicMillimetres = metalVolumeCubicMillimetres
        self.metalGrams = metalGrams
        self.metalBreakdown = metalBreakdown
        self.bounds = bounds
        self.defects = defects
    }

    public var triangleCount: Int {
        parts.reduce(0) { $0 + $1.mesh.triangleCount }
    }

    /// Every part's topology is sound. Asserted by the geometry tests.
    public var isWatertight: Bool { defects.isEmpty }

    public func parts(ofKind kind: PartKind) -> [PartGroup] {
        parts.filter { $0.kind == kind }
    }

    public var metalParts: [PartGroup] {
        parts.filter { $0.kind.isMetal }
    }

    public var stoneParts: [PartGroup] {
        parts.filter { $0.kind.isStone }
    }

    public var metalMesh: Mesh {
        Mesh.union(metalParts.map(\.mesh))
    }

    public var stoneMesh: Mesh {
        Mesh.union(stoneParts.map(\.mesh))
    }

    public var allMesh: Mesh {
        Mesh.union(parts.map(\.mesh))
    }

    /// The gem report the original surfaced to the user, listing every stone by
    /// number with its size and material.
    public var gemReportLines: [GemReportLine] {
        gemPlacements
            .sorted { $0.slotIndex < $1.slotIndex }
            .enumerated()
            .map { position, placement in
                GemReportLine(
                    id: placement.slotIndex,
                    index: position + 1,
                    slotIndex: placement.slotIndex,
                    role: placement.role,
                    shape: placement.shape,
                    material: placement.material,
                    colourID: placement.colourID,
                    qualityID: placement.qualityID,
                    carat: placement.carat,
                    girdleWidthMillimetres: placement.girdleWidthMillimetres,
                    isManualSize: placement.isManualSize
                )
            }
    }
}

// MARK: - Builder

public enum RingBuilder {

    public static func build(
        designID: DesignID,
        parameters: RingParameters,
        plan: GemPlan,
        metal: Metal,
        metal2: Metal? = nil,
        sizer: GemSizer = GemSizer()
    ) -> BuiltRing {
        var parts: [PartGroup] = []
        var placements: [GemPlacement] = []

        // A two-tone ring is two metals: the head assembly is cast in the second
        // metal, and everything that follows the shank in the first. The
        // assignment happens here, once, so that no caller has to remember it.
        let headMetal = metal2 ?? metal

        // A part with no geometry is a defect, not a placeholder: an empty mesh
        // reads as a hole in the model. Everything is filtered through here.
        func add(_ part: PartGroup) {
            guard !part.mesh.isEmpty else { return }
            var part = part
            if part.kind.isMetal {
                let assigned = PartKind.headPartKinds.contains(part.kind) ? headMetal : metal
                part.metalID = assigned.id
                part.userData["metal"] = assigned.id
            }
            parts.append(part)
        }

        let shank = buildShank(parameters: parameters)
        add(PartGroup(
            id: "part.shank",
            name: "Shank",
            kind: .shank,
            mesh: shank,
            userData: [
                "innerDiameterMM": format(parameters.innerDiameterMillimetres),
                "widthMM": format(parameters.shankWidthMillimetres),
                "thicknessMM": format(parameters.shankThicknessMillimetres),
                "profile": parameters.shankProfile.rawValue,
                "metal": metal.id
            ]
        ))

        // The rail guide the original exposed as a first-class import-group
        // operation: a construction curve along the shank's centreline.
        add(PartGroup(
            id: "part.railGuide",
            name: "Ring rail guide",
            kind: .railGuide,
            mesh: Mesh.band(
                centre: .zero,
                centrelineRadius: parameters.baseCentrelineRadiusMillimetres,
                radialHalfThickness: 0.05,
                axialHalfWidth: Swift.max(0.05, parameters.accentMetalWidthMillimetres / 4),
                segments: parameters.resolution
            ),
            userData: ["purpose": "construction"],
            isVisibleByDefault: false
        ))

        // Accent metalwork that follows the shank.
        for part in buildAccentMetalwork(parameters: parameters, plan: plan, metal: metal) {
            add(part)
        }

        // Setting beads grip the accent stones and carry metal weight.
        let beads = buildSettingBeads(parameters: parameters, plan: plan)
        add(PartGroup(
            id: "part.beads",
            name: "Setting beads",
            kind: .bead,
            mesh: beads,
            userData: ["count": "\(Swift.max(0, plan.accents.count - 1))"]
        ))

        // Head assembly, its metalwork, and the centre stone.
        if let centreSelection = plan.centre {
            let head = buildHead(parameters: parameters, centreSelection: centreSelection, sizer: sizer)
            for part in head.parts {
                add(part)
            }
            if let placement = head.placement {
                placements.append(placement)
                add(stonePart(for: placement, kind: .centreStone, name: "\(placement.shape.displayName) centre stone"))
            }
            placements.append(contentsOf: head.haloPlacements)
            for placement in head.haloPlacements {
                add(stonePart(for: placement, kind: .haloStone, name: "\(placement.shape.displayName) halo stone \(placement.slotIndex)"))
            }
        }

        // Accent stones, seated into the metalwork built above.
        let accentPlacements = buildAccentPlacements(parameters: parameters, plan: plan, sizer: sizer)
        placements.append(contentsOf: accentPlacements)
        for placement in accentPlacements {
            add(stonePart(for: placement, kind: .accentStone, name: "\(placement.shape.displayName) accent stone \(placement.slotIndex)"))
        }

        // Each metal's parts are weighed in that metal. One multiplication
        // cannot weigh a two-tone ring: the head's volume is weighed as the
        // head's metal and the body's as the body's, and the total is their sum.
        var metalBreakdown: [MetalWeight] = []
        for candidate in [metal, metal2].compactMap({ $0 }) {
            guard !metalBreakdown.contains(where: { $0.metal.id == candidate.id }) else { continue }
            let metalVolume = parts
                .filter { $0.kind.isMetal && $0.metalID == candidate.id }
                .reduce(0.0) { $0 + abs($1.mesh.signedVolume) }
            metalBreakdown.append(MetalWeight(
                metal: candidate,
                volumeCubicMillimetres: metalVolume,
                grams: candidate.grams(forCubicMillimetres: metalVolume)
            ))
        }
        let volume = metalBreakdown.reduce(0.0) { $0 + $1.volumeCubicMillimetres }
        let grams = metalBreakdown.reduce(0.0) { $0 + $1.grams }

        let bounds = parts.reduce(nil as BoundingBox?) { box, part in
            part.mesh.bounds.union(box)
        } ?? BoundingBox(minimum: .zero, maximum: .zero)

        let defects = parts.flatMap { $0.mesh.validate() }

        return BuiltRing(
            designID: designID,
            parts: parts,
            gemPlacements: placements,
            metalVolumeCubicMillimetres: volume,
            metalGrams: grams,
            metalBreakdown: metalBreakdown,
            bounds: bounds,
            defects: defects
        )
    }

    private static func stonePart(for placement: GemPlacement, kind: PartKind, name: String) -> PartGroup {
        PartGroup(
            id: "part.stone.\(placement.slotIndex)",
            name: name,
            kind: kind,
            mesh: placement.mesh(),
            userData: [
                "carat": format(placement.carat),
                "girdleWidthMM": format(placement.girdleWidthMillimetres),
                "material": placement.material.rawValue,
                "manualSize": placement.isManualSize ? "true" : "false"
            ],
            gemSlotIndex: placement.slotIndex
        )
    }

    // MARK: - Shank

    public static func buildShank(parameters: RingParameters) -> Mesh {
        let radialHalf = parameters.shankThicknessMillimetres / 2
        let axialHalf = parameters.shankWidthMillimetres / 2

        let profile: [Vector2]
        switch parameters.shankProfile {
        case .domed, .cathedral:
            profile = Mesh.ellipseProfile(radialRadius: radialHalf, axialRadius: axialHalf, pointCount: 20)
        case .flat:
            profile = Mesh.roundedRectangleProfile(
                radialRadius: radialHalf, axialRadius: axialHalf,
                cornerFraction: 0.85, pointCount: 20
            )
        case .euroComfort:
            profile = Mesh.roundedRectangleProfile(
                radialRadius: radialHalf, axialRadius: axialHalf,
                cornerFraction: 0.55, pointCount: 20
            )
        case .knifeEdge:
            profile = Mesh.lensProfile(radialRadius: radialHalf, axialRadius: axialHalf, pointCount: 20)
        }

        let taperFraction = Swift.max(0, Swift.min(0.6, parameters.baseWidthTaperFraction))
        let usesTaper = taperFraction > Tolerance.coincidence

        return Mesh.revolved(
            profile: profile,
            segments: parameters.resolution,
            centrelineRadius: { angle in parameters.centrelineRadius(at: angle) },
            // Below the shoulders the shank narrows axially. Scaling the
            // cross-section rather than the centreline is what keeps a tapered
            // shank's sides parallel instead of its tapers pinching.
            profileScaleAtAngle: { angle in
                guard usesTaper else { return Vector2(1, 1) }
                return Vector2(1, 1 - taperFraction * (1 - parameters.shoulderFactor(at: angle)))
            }
        )
    }

    // MARK: - Head

    struct HeadAssembly {
        var parts: [PartGroup]
        var placement: GemPlacement?
        var haloPlacements: [GemPlacement]
    }

    private static func buildHead(
        parameters: RingParameters,
        centreSelection: GemSelection,
        sizer: GemSizer
    ) -> HeadAssembly {
        var parts: [PartGroup] = []
        var haloPlacements: [GemPlacement] = []

        let girdleWidth = sizer.girdleWidthMillimetres(
            for: centreSelection.shape,
            carat: centreSelection.carat,
            material: centreSelection.material
        )
        let girdleRadius = girdleWidth / 2
        guard girdleRadius > Tolerance.coincidence else {
            return HeadAssembly(parts: [], placement: nil, haloPlacements: [])
        }

        let layout = GemFacetLayout.standard(for: centreSelection.shape)
        let pavilionDepth = layout.pavilionDepthRatio * girdleRadius
        let crownHeight = layout.crownHeightRatio * girdleRadius

        // The girdle plane sits one basket height above the shank's outer face
        // at the head.
        let seatRadius = parameters.outerRadius(at: 0) + parameters.head.basketHeightMillimetres
        let rotation = Matrix4x4.rotation(axis: Vector3(0, 0, 1), radians: -Double.pi / 2)
        let toWorld = Matrix4x4.translation(x: seatRadius, y: 0, z: 0) * rotation
        let style = parameters.head.style

        if style == .prongBasket || style == .halo {
            let prongCount = Swift.max(3, parameters.head.prongCount)
            let baseRadius = Swift.max(0.18, girdleRadius * 0.14)
            let tipRadius = Swift.max(0.14, girdleRadius * 0.10)

            for index in 0..<prongCount {
                let angle = 2 * Double.pi * Double(index) / Double(prongCount) + Double.pi / Double(prongCount)
                let radial = Vector3(cos(angle), 0, sin(angle))
                let base = radial * (girdleRadius * 0.92) + Vector3(0, -pavilionDepth * 0.62, 0)
                let tip = radial * (girdleRadius * 1.08) + Vector3(0, crownHeight * 0.55, 0)
                parts.append(PartGroup(
                    id: "part.prong.\(index)",
                    name: "Prong \(index + 1) of \(prongCount)",
                    kind: .prong,
                    mesh: Mesh.cone(
                        from: toWorld.apply(to: base),
                        to: toWorld.apply(to: tip),
                        startRadius: baseRadius,
                        endRadius: tipRadius,
                        segments: 12
                    ),
                    userData: ["index": "\(index)", "style": style.rawValue]
                ))
            }
        }

        if style == .prongBasket || style == .halo || style == .tension {
            // The basket: the gallery the stone's pavilion sits inside.
            parts.append(PartGroup(
                id: "part.basket",
                name: "Basket",
                kind: .basket,
                mesh: Mesh.torus(
                    centre: toWorld.apply(toDirection: Vector3(0, -pavilionDepth * 0.34, 0)),
                    majorRadius: girdleRadius * 0.80,
                    minorRadius: Swift.max(0.16, girdleRadius * 0.11),
                    majorSegments: 32,
                    minorSegments: 10
                ),
                userData: ["style": style.rawValue]
            ))
        }

        if style == .bezel || style == .tension {
            // A collar around the girdle instead of prongs.
            parts.append(PartGroup(
                id: "part.bezel",
                name: style == .bezel ? "Bezel" : "Tension collar",
                kind: .bezel,
                mesh: Mesh.band(
                    centre: .zero,
                    centrelineRadius: girdleRadius * 1.02,
                    radialHalfThickness: Swift.max(0.18, girdleRadius * 0.10),
                    axialHalfWidth: Swift.max(0.20, girdleRadius * 0.20),
                    segments: 40,
                    cornerFraction: 0.7
                ).transformed(by: toWorld),
                userData: ["style": style.rawValue]
            ))
        }

        if style == .halo {
            let haloRadius = girdleRadius * 1.32
            let haloCount = 16
            let haloCarat = Swift.max(0.005, centreSelection.carat * 0.012)

            // The metal the halo stones sit in.
            parts.append(PartGroup(
                id: "part.haloRail",
                name: "Halo rail",
                kind: .haloRail,
                mesh: Mesh.torus(
                    centre: toWorld.apply(toDirection: .zero),
                    majorRadius: haloRadius,
                    minorRadius: Swift.max(0.14, girdleRadius * 0.09),
                    majorSegments: 40,
                    minorSegments: 10
                ),
                userData: ["count": "\(haloCount)"]
            ))

            for index in 0..<haloCount {
                let angle = 2 * Double.pi * Double(index) / Double(haloCount)
                let local = Vector3(haloRadius * cos(angle), 0, haloRadius * sin(angle))
                let width = sizer.girdleWidthMillimetres(
                    for: .roundBrilliant, carat: haloCarat, material: centreSelection.material
                )
                haloPlacements.append(GemPlacement(
                    slotIndex: 1000 + index,
                    role: .halo,
                    shape: .roundBrilliant,
                    material: centreSelection.material,
                    colourID: centreSelection.colourID,
                    qualityID: centreSelection.qualityID,
                    carat: haloCarat,
                    girdleWidthMillimetres: width,
                    position: toWorld.apply(to: local),
                    orientation: toWorld,
                    isManualSize: false
                ))
            }
        }

        let placement = GemPlacement(
            slotIndex: centreSelection.slotIndex,
            role: .centre,
            shape: centreSelection.shape,
            material: centreSelection.material,
            colourID: centreSelection.colourID,
            qualityID: centreSelection.qualityID,
            carat: centreSelection.carat,
            girdleWidthMillimetres: girdleWidth,
            position: toWorld.apply(to: .zero),
            orientation: toWorld,
            isManualSize: centreSelection.manualSize
        )

        return HeadAssembly(parts: parts, placement: placement, haloPlacements: haloPlacements)
    }

    // MARK: - Accents

    private static func buildAccentMetalwork(
        parameters: RingParameters,
        plan: GemPlan,
        metal: Metal
    ) -> [PartGroup] {
        let pattern = plan.accentPattern
        guard pattern.kind != .none else { return [] }
        guard !plan.accents.isEmpty || pattern.count > 0 else { return [] }

        guard pattern.kind == .channel || pattern.kind == .pave else { return [] }

        // The channel the accents sit in, running along the shank's outer face
        // across the pattern's coverage.
        return [PartGroup(
            id: "part.channel",
            name: "Accent channel",
            kind: .channel,
            mesh: Mesh.band(
                centre: .zero,
                centrelineRadius: parameters.baseCentrelineRadiusMillimetres
                    + parameters.shankThicknessMillimetres * 0.15,
                radialHalfThickness: Swift.max(0.10, parameters.shankThicknessMillimetres * 0.18),
                axialHalfWidth: Swift.max(0.15, parameters.accentMetalWidthMillimetres / 2),
                segments: parameters.resolution,
                cornerFraction: 0.8
            ),
            userData: ["pattern": pattern.kind.rawValue, "metal": metal.id]
        )]
    }

    /// Beads are metal, so they are their own part and they count towards the
    /// ring's weight — a bead setting is a real amount of gold.
    public static func buildSettingBeads(parameters: RingParameters, plan: GemPlan) -> Mesh {
        guard plan.accentPattern.kind == .beadSet, plan.accents.count > 1 else { return .empty }
        let count = plan.accents.count
        let coverage = Swift.max(10, Swift.min(360, plan.accentPattern.coverageDegrees))
        let coverageRadians = coverage * Double.pi / 180
        let sizer = GemSizer()

        var meshes: [Mesh] = []
        for index in 0..<(count - 1) {
            let fraction = Double(index) / Double(count - 1)
            let nextFraction = Double(index + 1) / Double(count - 1)
            let midAngle = -coverageRadians / 2 + coverageRadians * (fraction + nextFraction) / 2

            let selection = plan.accents[index]
            let girdleWidth = sizer.girdleWidthMillimetres(
                for: selection.shape, carat: selection.carat, material: selection.material
            )
            let beadRadius = Swift.max(0.12, girdleWidth / 2 * 0.40)
            let beadDistance = parameters.outerRadius(at: midAngle) + beadRadius * 0.15
            let beadCentre = Vector3(
                beadDistance * cos(midAngle),
                0,
                beadDistance * sin(midAngle)
            )
            meshes.append(Mesh.sphere(center: beadCentre, radius: beadRadius, segments: 10, rings: 6))
        }

        return Mesh.union(meshes)
    }

    private static func buildAccentPlacements(
        parameters: RingParameters,
        plan: GemPlan,
        sizer: GemSizer
    ) -> [GemPlacement] {
        guard !plan.accents.isEmpty else { return [] }
        let pattern = plan.accentPattern
        let count = plan.accents.count
        let coverage = Swift.max(10, Swift.min(360, pattern.coverageDegrees))
        let coverageRadians = coverage * Double.pi / 180

        var placements: [GemPlacement] = []
        placements.reserveCapacity(count)

        for (index, selection) in plan.accents.enumerated() {
            // Spread the stones symmetrically about the head at theta = 0.
            let fraction: Double = count == 1 ? 0.5 : Double(index) / Double(count - 1)
            let angle = -coverageRadians / 2 + coverageRadians * fraction

            let girdleWidth = sizer.girdleWidthMillimetres(
                for: selection.shape,
                carat: selection.carat,
                material: selection.material
            )
            let girdleRadius = girdleWidth / 2

            // Bead, pave and channel settings sink the stone into the metal, by
            // different amounts.
            let sink: Double
            switch pattern.kind {
            case .beadSet: sink = girdleRadius * 0.35
            case .pave: sink = girdleRadius * 0.45
            case .channel, .none: sink = girdleRadius * 0.55
            }

            let radialDistance = parameters.outerRadius(at: angle) - sink
            let position = Vector3(radialDistance * cos(angle), 0, radialDistance * sin(angle))
            // Rotate the stone's local table direction onto the outward radial
            // direction at this angle, then bring the table up to radial.
            let orientation = Matrix4x4.rotation(axis: Vector3(0, 1, 0), radians: -angle)
                * Matrix4x4.rotation(axis: Vector3(0, 0, 1), radians: -Double.pi / 2)

            placements.append(GemPlacement(
                slotIndex: selection.slotIndex,
                role: selection.role,
                shape: selection.shape,
                material: selection.material,
                colourID: selection.colourID,
                qualityID: selection.qualityID,
                carat: selection.carat,
                girdleWidthMillimetres: girdleWidth,
                position: position,
                orientation: orientation,
                isManualSize: selection.manualSize
            ))
        }

        return placements
    }

    // MARK: - Helpers

    private static func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}
