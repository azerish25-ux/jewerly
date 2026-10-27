//
//  GemMesh.swift
//  JewelcraftKit
//
//  Gemstone solids, generated from facet layouts.
//
//  Carat to millimetre sizing is derived from physics rather than tabulated:
//  1 carat is 200 mg, and a material's specific gravity in g/cm³ is numerically
//  its density in mg/mm³, so a stone of a given carat has a known volume.
//  Dividing that by the generated solid's own volume gives the scale factor
//  directly. Carat, size and the rendered geometry therefore become *the same
//  fact* instead of three tables that drift apart.
//
//  `massSizeCalibration` reconciles the simplified solid with the published
//  mass-to-size behaviour of the real cut — a real round brilliant's pavilion
//  bulges below the girdle, so it holds slightly more material than a straight
//  cone of the same depth. It is a documented correlation constant, not a fudge
//  factor: the tests check that a 1.00 ct diamond still measures the 6.5 mm a
//  jeweller would expect, and that a 1.00 ct ruby (specific gravity 4.0) comes
//  out smaller than the diamond.
//

import Foundation

// MARK: - Girdle outline

/// The girdle's plan-view shape.
public struct GirdleOutline: Equatable, Sendable {

    public enum Family: String, Codable, Sendable {
        /// A smooth ellipse: round and oval stones.
        case ellipse
        /// A superellipse: square, rectangular and cushion outlines, whose
        /// corners are controlled by a power between 0 (square) and 1 (ellipse).
        case superellipse
        /// A regular polygon: octagon (asscher) and triangle (trillion).
        case polygon
        /// An ellipse pinched to one or two points: pear and marquise.
        case pointed
    }

    public var family: Family
    /// Multiplier on the depth (z) extent, giving the outline its aspect ratio.
    public var depthRatio: Double
    /// Superellipse corner power. 1 is an ellipse; smaller squares the corners.
    public var cornerPower: Double
    /// Number of sides for `polygon`.
    public var polygonSides: Int
    /// Pinch exponent for `pointed`, controlling how quickly the ends taper.
    public var pointedPower: Double
    /// How many tips a `pointed` outline has: 2 for a marquise, 1 for a pear.
    public var pointedTips: Int

    public init(
        family: Family,
        depthRatio: Double = 1,
        cornerPower: Double = 1,
        polygonSides: Int = 8,
        pointedPower: Double = 0.6,
        pointedTips: Int = 2
    ) {
        self.family = family
        self.depthRatio = depthRatio
        self.cornerPower = cornerPower
        self.polygonSides = polygonSides
        self.pointedPower = pointedPower
        self.pointedTips = pointedTips
    }

    /// The outline for a shape.
    public static func standard(for shape: GemShape) -> GirdleOutline {
        switch shape {
        case .roundBrilliant, .roundCabochon:
            return GirdleOutline(family: .ellipse)
        case .oval:
            return GirdleOutline(family: .ellipse, depthRatio: 0.72)
        case .princess:
            return GirdleOutline(family: .superellipse, cornerPower: 0.15)
        case .cushion:
            return GirdleOutline(family: .superellipse, cornerPower: 0.5)
        case .emerald:
            return GirdleOutline(family: .superellipse, depthRatio: 0.60, cornerPower: 0.12)
        case .radiant:
            return GirdleOutline(family: .superellipse, depthRatio: 0.65, cornerPower: 0.30)
        case .asscher:
            return GirdleOutline(family: .polygon, polygonSides: 8)
        case .baguette:
            return GirdleOutline(family: .superellipse, depthRatio: 0.45, cornerPower: 0.10)
        case .pear:
            return GirdleOutline(family: .pointed, depthRatio: 0.85, pointedPower: 0.6, pointedTips: 1)
        case .marquise:
            return GirdleOutline(family: .pointed, depthRatio: 0.85, pointedPower: 0.6, pointedTips: 2)
        case .trillion:
            return GirdleOutline(family: .polygon, polygonSides: 3)
        }
    }

    /// The raw outline, before normalisation.
    public func rawPoint(atAngle theta: Double) -> Vector2 {
        switch family {
        case .ellipse:
            return Vector2(cos(theta), depthRatio * sin(theta))

        case .superellipse:
            let c = cos(theta)
            let s = sin(theta)
            let power = Swift.max(0.02, Swift.min(1.0, cornerPower))
            return Vector2(
                (c < 0 ? -1 : 1) * pow(abs(c), power),
                depthRatio * (s < 0 ? -1 : 1) * pow(abs(s), power)
            )

        case .polygon:
            let sides = Swift.max(3, polygonSides)
            let sector = 2 * Double.pi / Double(sides)
            let half = Double.pi / Double(sides)
            var offset = (theta + half).truncatingRemainder(dividingBy: sector)
            if offset < 0 { offset += sector }
            let radius = cos(half) / cos(offset - half)
            return Vector2(radius * cos(theta), depthRatio * radius * sin(theta))

        case .pointed:
            let c = cos(theta)
            let s = sin(theta)
            if pointedTips >= 2 {
                // Two tips, at theta = 0 and theta = pi.
                return Vector2(c, depthRatio * s * pow(abs(c), pointedPower))
            }
            // One tip at theta = pi, a rounded end at theta = 0.
            let t = (1 - c) / 2
            let pinch = (Swift.max(0, 1 - t * t)).squareRoot()
            return Vector2(c, depthRatio * s * pinch)
        }
    }

    /// The outline sampled into a closed, counter-clockwise loop, normalised so
    /// the widest point sits at `x = ±1`.
    ///
    /// Normalising on the x extent rather than on a radius means the reported
    /// size means the same thing for every shape: the stone's overall width
    /// across its long axis, which for a round stone is its diameter.
    public func points(resolution: Int) -> [Vector2] {
        let count = Swift.max(6, resolution)
        var points: [Vector2] = []
        points.reserveCapacity(count)
        for index in 0..<count {
            let theta = 2 * Double.pi * Double(index) / Double(count)
            points.append(rawPoint(atAngle: theta))
        }
        let widest = points.map { abs($0.x) }.max() ?? 1
        guard widest > Tolerance.coincidence else { return points }
        return points.map { Vector2($0.x / widest, $0.y / widest) }
    }
}

// MARK: - Facet layout

/// One ring of vertices between the table and the girdle, or between the girdle
/// and the culet.
public struct GemRow: Equatable, Sendable {
    /// Radius as a fraction of the girdle's width.
    public var radiusScale: Double
    /// Position from the table (or the girdle) towards the girdle (or culet):
    /// 0 at the top of the run, 1 at the bottom.
    public var heightFraction: Double

    public init(radiusScale: Double, heightFraction: Double) {
        self.radiusScale = radiusScale
        self.heightFraction = heightFraction
    }
}

/// The cut: proportions and rows of facets, independent of size.
public struct GemFacetLayout: Equatable, Sendable {
    public var shape: GemShape
    public var outline: GirdleOutline
    /// Vertices around the girdle. Controls how faceted the stone looks.
    public var resolution: Int
    /// Table width as a fraction of the stone's width. 0 makes the crown come to
    /// a point, which is what a cabochon needs.
    public var tableRatio: Double
    /// Intermediate rows from the table down to the girdle, ordered top first.
    public var crownRows: [GemRow]
    /// Intermediate rows from the girdle down to the culet, ordered top first.
    public var pavilionRows: [GemRow]
    /// Culet facet width as a fraction of the stone's width. 0 makes a point.
    public var culetRatio: Double
    /// Girdle thickness as a fraction of the stone's width.
    public var girdleThicknessRatio: Double
    /// Crown height as a fraction of the stone's half width.
    public var crownHeightRatio: Double
    /// Pavilion depth as a fraction of the stone's half width.
    public var pavilionDepthRatio: Double
    /// Correlation constant reconciling this simplified solid with the real
    /// cut's mass-to-size behaviour. 1 takes the model at face value.
    public var massSizeCalibration: Double

    public init(
        shape: GemShape,
        outline: GirdleOutline,
        resolution: Int,
        tableRatio: Double,
        crownRows: [GemRow],
        pavilionRows: [GemRow],
        culetRatio: Double,
        girdleThicknessRatio: Double,
        crownHeightRatio: Double,
        pavilionDepthRatio: Double,
        massSizeCalibration: Double
    ) {
        self.shape = shape
        self.outline = outline
        self.resolution = resolution
        self.tableRatio = tableRatio
        self.crownRows = crownRows
        self.pavilionRows = pavilionRows
        self.culetRatio = culetRatio
        self.girdleThicknessRatio = girdleThicknessRatio
        self.crownHeightRatio = crownHeightRatio
        self.pavilionDepthRatio = pavilionDepthRatio
        self.massSizeCalibration = massSizeCalibration
    }

    /// The standard layout for a shape.
    ///
    /// These are stylised cut proportions, not a recovered specification: the
    /// original's exact facet data lived inside its Rhino geometry and was never
    /// recoverable. What matters here is that each shape is recognisable, is a
    /// closed solid, and sizes correctly by carat.
    public static func standard(for shape: GemShape) -> GemFacetLayout {
        let outline = GirdleOutline.standard(for: shape)

        switch shape {
        case .roundBrilliant:
            return GemFacetLayout(
                shape: shape, outline: outline, resolution: 16,
                tableRatio: 0.53,
                crownRows: [GemRow(radiusScale: 0.86, heightFraction: 0.55)],
                pavilionRows: [GemRow(radiusScale: 0.62, heightFraction: 0.45)],
                culetRatio: 0, girdleThicknessRatio: 0.04,
                crownHeightRatio: 0.29, pavilionDepthRatio: 0.86,
                massSizeCalibration: 1.137
            )

        case .oval:
            return GemFacetLayout(
                shape: shape, outline: outline, resolution: 20,
                tableRatio: 0.55,
                crownRows: [GemRow(radiusScale: 0.87, heightFraction: 0.55)],
                pavilionRows: [GemRow(radiusScale: 0.64, heightFraction: 0.45)],
                culetRatio: 0, girdleThicknessRatio: 0.04,
                crownHeightRatio: 0.30, pavilionDepthRatio: 0.90,
                massSizeCalibration: 1.08
            )

        case .princess:
            return GemFacetLayout(
                shape: shape, outline: outline, resolution: 16,
                tableRatio: 0.60,
                crownRows: [GemRow(radiusScale: 0.85, heightFraction: 0.60)],
                pavilionRows: [GemRow(radiusScale: 0.58, heightFraction: 0.50)],
                culetRatio: 0, girdleThicknessRatio: 0.05,
                crownHeightRatio: 0.28, pavilionDepthRatio: 0.95,
                massSizeCalibration: 1.10
            )

        case .cushion:
            return GemFacetLayout(
                shape: shape, outline: outline, resolution: 16,
                tableRatio: 0.58,
                crownRows: [GemRow(radiusScale: 0.86, heightFraction: 0.55)],
                pavilionRows: [GemRow(radiusScale: 0.60, heightFraction: 0.48)],
                culetRatio: 0, girdleThicknessRatio: 0.05,
                crownHeightRatio: 0.29, pavilionDepthRatio: 0.92,
                massSizeCalibration: 1.10
            )

        case .emerald, .asscher:
            // Step cuts: rows stack like terraces rather than radiating, and the
            // culet is a flat facet rather than a point.
            return GemFacetLayout(
                shape: shape, outline: outline, resolution: 24,
                tableRatio: 0.62,
                crownRows: [
                    GemRow(radiusScale: 0.74, heightFraction: 0.30),
                    GemRow(radiusScale: 0.89, heightFraction: 0.62)
                ],
                pavilionRows: [
                    GemRow(radiusScale: 0.90, heightFraction: 0.28),
                    GemRow(radiusScale: 0.70, heightFraction: 0.58),
                    GemRow(radiusScale: 0.42, heightFraction: 0.82)
                ],
                culetRatio: 0.22, girdleThicknessRatio: 0.06,
                crownHeightRatio: 0.26, pavilionDepthRatio: 1.00,
                massSizeCalibration: 1.12
            )

        case .radiant:
            return GemFacetLayout(
                shape: shape, outline: outline, resolution: 20,
                tableRatio: 0.60,
                crownRows: [
                    GemRow(radiusScale: 0.76, heightFraction: 0.30),
                    GemRow(radiusScale: 0.90, heightFraction: 0.62)
                ],
                pavilionRows: [GemRow(radiusScale: 0.60, heightFraction: 0.50)],
                culetRatio: 0, girdleThicknessRatio: 0.05,
                crownHeightRatio: 0.28, pavilionDepthRatio: 0.96,
                massSizeCalibration: 1.10
            )

        case .baguette:
            return GemFacetLayout(
                shape: shape, outline: outline, resolution: 20,
                tableRatio: 0.65,
                crownRows: [GemRow(radiusScale: 0.88, heightFraction: 0.60)],
                pavilionRows: [
                    GemRow(radiusScale: 0.86, heightFraction: 0.32),
                    GemRow(radiusScale: 0.52, heightFraction: 0.72)
                ],
                culetRatio: 0.30, girdleThicknessRatio: 0.06,
                crownHeightRatio: 0.24, pavilionDepthRatio: 0.90,
                massSizeCalibration: 1.12
            )

        case .pear, .marquise:
            return GemFacetLayout(
                shape: shape, outline: outline, resolution: 24,
                tableRatio: 0.55,
                crownRows: [GemRow(radiusScale: 0.87, heightFraction: 0.55)],
                pavilionRows: [GemRow(radiusScale: 0.63, heightFraction: 0.46)],
                culetRatio: 0, girdleThicknessRatio: 0.04,
                crownHeightRatio: 0.30, pavilionDepthRatio: 0.90,
                massSizeCalibration: 1.08
            )

        case .trillion:
            return GemFacetLayout(
                shape: shape, outline: outline, resolution: 18,
                tableRatio: 0.55,
                crownRows: [GemRow(radiusScale: 0.86, heightFraction: 0.55)],
                pavilionRows: [GemRow(radiusScale: 0.62, heightFraction: 0.46)],
                culetRatio: 0, girdleThicknessRatio: 0.05,
                crownHeightRatio: 0.28, pavilionDepthRatio: 0.88,
                massSizeCalibration: 1.08
            )

        case .roundCabochon:
            // No table and no culet: a smooth dome over a shallow back.
            return GemFacetLayout(
                shape: shape, outline: outline, resolution: 24,
                tableRatio: 0,
                crownRows: [
                    GemRow(radiusScale: 0.34, heightFraction: 0.10),
                    GemRow(radiusScale: 0.58, heightFraction: 0.25),
                    GemRow(radiusScale: 0.78, heightFraction: 0.45),
                    GemRow(radiusScale: 0.92, heightFraction: 0.65),
                    GemRow(radiusScale: 0.98, heightFraction: 0.85)
                ],
                pavilionRows: [GemRow(radiusScale: 0.72, heightFraction: 0.50)],
                culetRatio: 0, girdleThicknessRatio: 0.03,
                crownHeightRatio: 0.55, pavilionDepthRatio: 0.35,
                massSizeCalibration: 1.0
            )
        }
    }
}

// MARK: - Builder

public enum GemMeshBuilder {

    /// The solid at unit scale: the girdle's widest point sits at x = ±1, so the
    /// stone's width is exactly 2.
    ///
    /// The result is a closed solid with outward winding and smooth normals; a
    /// faceted appearance is applied by the caller, because flat shading
    /// duplicates vertices and would otherwise hide the topology from the
    /// structural checks.
    public static func unitSolid(_ layout: GemFacetLayout) -> Mesh {
        struct Ring {
            var radiusScale: Double
            var y: Double
        }

        let outline = layout.outline.points(resolution: layout.resolution)
        let resolution = outline.count
        guard resolution >= 6 else { return .empty }

        let crownHeight = layout.crownHeightRatio
        let pavilionDepth = layout.pavilionDepthRatio
        let girdleHalfThickness = Swift.max(0.0, layout.girdleThicknessRatio) / 2

        var rings: [Ring] = []
        let hasTableFacet = layout.tableRatio > 0.01
        if hasTableFacet {
            rings.append(Ring(radiusScale: layout.tableRatio, y: crownHeight))
        }
        for row in layout.crownRows.sorted(by: { $0.heightFraction < $1.heightFraction }) {
            rings.append(Ring(radiusScale: row.radiusScale, y: crownHeight * (1 - row.heightFraction)))
        }
        rings.append(Ring(radiusScale: 1, y: girdleHalfThickness))
        rings.append(Ring(radiusScale: 1, y: -girdleHalfThickness))
        for row in layout.pavilionRows.sorted(by: { $0.heightFraction < $1.heightFraction }) {
            rings.append(Ring(radiusScale: row.radiusScale, y: -pavilionDepth * row.heightFraction))
        }
        let hasCuletFacet = layout.culetRatio > 0.01
        if hasCuletFacet {
            rings.append(Ring(radiusScale: layout.culetRatio, y: -pavilionDepth))
        }
        guard rings.count >= 2 else { return .empty }

        var positions: [Vector3] = []
        var normals: [Vector3] = []
        positions.reserveCapacity(rings.count * resolution)
        normals.reserveCapacity(rings.count * resolution)

        for ring in rings {
            for point in outline {
                positions.append(Vector3(point.x * ring.radiusScale, ring.y, point.y * ring.radiusScale))
                // Provisional; the caller either shades flat or recomputes.
                normals.append(Vector3(0, 1, 0))
            }
        }

        var indices: [UInt32] = []
        let stride = UInt32(resolution)

        for ringIndex in 0..<(rings.count - 1) {
            for pointIndex in 0..<resolution {
                let nextPoint = (pointIndex + 1) % resolution
                let a = UInt32(ringIndex) * stride + UInt32(pointIndex)
                let b = UInt32(ringIndex) * stride + UInt32(nextPoint)
                let c = UInt32(ringIndex + 1) * stride + UInt32(pointIndex)
                let d = UInt32(ringIndex + 1) * stride + UInt32(nextPoint)
                // Winding: with rings ordered top to bottom and the outline
                // running counter-clockwise, this order faces outward.
                indices.append(contentsOf: [a, b, c])
                indices.append(contentsOf: [b, d, c])
            }
        }

        // Crown cap: a flat table when there is a table facet, otherwise a cone
        // rising to an apex above the first crown row.
        let topApexIndex = UInt32(positions.count)
        positions.append(Vector3(0, crownHeight, 0))
        normals.append(Vector3(0, 1, 0))
        for pointIndex in 0..<resolution {
            let nextPoint = (pointIndex + 1) % resolution
            indices.append(contentsOf: [topApexIndex, UInt32(nextPoint), UInt32(pointIndex)])
        }

        // Pavilion cap: a flat culet facet when there is one, otherwise a fan to
        // a point at the bottom.
        let bottomApexIndex = UInt32(positions.count)
        positions.append(Vector3(0, -pavilionDepth, 0))
        normals.append(Vector3(0, -1, 0))
        let lastRingBase = UInt32(rings.count - 1) * stride
        for pointIndex in 0..<resolution {
            let nextPoint = (pointIndex + 1) % resolution
            indices.append(contentsOf: [
                bottomApexIndex,
                lastRingBase + UInt32(pointIndex),
                lastRingBase + UInt32(nextPoint)
            ])
        }

        let solid = Mesh(positions: positions, normals: normals, indices: indices)
        return solid.recomputingSmoothNormals()
    }

    /// The solid at a given girdle width, flat-shaded so it reads as a cut stone
    /// rather than a moulded blob.
    public static func mesh(_ layout: GemFacetLayout, girdleWidthMillimetres: Double) -> Mesh {
        guard girdleWidthMillimetres > 0 else { return .empty }
        let scale = girdleWidthMillimetres / 2.0
        return unitSolid(layout)
            .transformed(by: .scale(scale))
            .flatShaded()
    }

    /// The solid for a shape, material and carat.
    public static func mesh(
        shape: GemShape,
        material: GemMaterial,
        carat: Double,
        sizer: GemSizer = GemSizer()
    ) -> Mesh {
        let layout = GemFacetLayout.standard(for: shape)
        let width = sizer.girdleWidthMillimetres(
            carat: carat,
            layout: layout,
            specificGravity: material.specificGravity
        )
        return mesh(layout, girdleWidthMillimetres: width)
    }
}

// MARK: - Sizing

/// Converts between carat weight and physical size.
///
/// Stateless and cheap enough to call per stone: the unit solids it measures are
/// a few hundred triangles each, and determinism is worth more here than a cache
/// that tests would have to worry about.
public struct GemSizer: Sendable {

    public init() {}

    /// Volume of the unit solid in cubic millimetres, with the cut's mass/size
    /// calibration applied.
    public func calibratedUnitVolume(_ layout: GemFacetLayout) -> Double {
        abs(GemMeshBuilder.unitSolid(layout).signedVolume) * layout.massSizeCalibration
    }

    /// The girdle width of a stone of `carat` weight, in millimetres. For a
    /// round stone this is its diameter — the number a jeweller quotes.
    public func girdleWidthMillimetres(
        carat: Double,
        layout: GemFacetLayout,
        specificGravity: Double
    ) -> Double {
        guard carat > 0, specificGravity > 0 else { return 0 }
        // One carat is 200 mg, and specific gravity in g/cm³ is numerically the
        // density in mg/mm³, so mass over density is cubic millimetres exactly.
        let requiredVolume = carat * 200.0 / specificGravity
        let unitVolume = calibratedUnitVolume(layout)
        guard unitVolume > Tolerance.coincidence else { return 0 }
        // The unit solid spans two units across, hence the factor of two.
        return 2.0 * pow(requiredVolume / unitVolume, 1.0 / 3.0)
    }

    /// The carat weight of a stone of the given girdle width, in millimetres.
    public func carats(
        girdleWidthMillimetres: Double,
        layout: GemFacetLayout,
        specificGravity: Double
    ) -> Double {
        guard girdleWidthMillimetres > 0, specificGravity > 0 else { return 0 }
        let scale = girdleWidthMillimetres / 2.0
        let unitVolume = calibratedUnitVolume(layout)
        let volume = unitVolume * scale * scale * scale
        return volume * specificGravity / 200.0
    }

    public func girdleWidthMillimetres(for shape: GemShape, carat: Double, material: GemMaterial) -> Double {
        girdleWidthMillimetres(
            carat: carat,
            layout: GemFacetLayout.standard(for: shape),
            specificGravity: material.specificGravity
        )
    }

    public func carats(for shape: GemShape, girdleWidthMillimetres: Double, material: GemMaterial) -> Double {
        carats(
            girdleWidthMillimetres: girdleWidthMillimetres,
            layout: GemFacetLayout.standard(for: shape),
            specificGravity: material.specificGravity
        )
    }
}
