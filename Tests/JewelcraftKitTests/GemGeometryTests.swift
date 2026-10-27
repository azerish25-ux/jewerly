//
//  GemGeometryTests.swift
//  JewelcraftKitTests
//
//  Cut stones: the facet layouts, and the carat-to-millimetre relation that makes
//  a stone's size a physical quantity rather than a number in a table.
//
//  The carat test is the one that matters commercially. A one-carat round
//  brilliant is about 6.5 mm across; if the sizer disagrees, every stone in every
//  model is the wrong size, and the ring's proportions and metal weight are wrong
//  with it.
//

import XCTest
@testable import JewelcraftKit

final class GemGeometryTests: XCTestCase {

    func testEveryShapeHasAWatertightUnitSolid() {
        for shape in GemShape.allCases {
            let layout = GemFacetLayout.standard(for: shape)
            let solid = GemMeshBuilder.unitSolid(layout)

            XCTAssertTrue(solid.isWatertight, "\(shape.rawValue): \(solid.defectsDescription)")
            XCTAssertGreaterThan(solid.signedVolume, 0, "\(shape.rawValue) must be outward-wound")
            XCTAssertGreaterThan(solid.triangleCount, 12, "\(shape.rawValue) has too few facets")
        }
    }

    func testFacetLayoutsHaveSaneProportions() {
        for shape in GemShape.allCases {
            let layout = GemFacetLayout.standard(for: shape)

            XCTAssertGreaterThan(layout.crownHeightRatio, 0)
            XCTAssertLessThan(layout.crownHeightRatio, 0.6)
            XCTAssertGreaterThan(layout.pavilionDepthRatio, 0.2)
            XCTAssertLessThan(layout.pavilionDepthRatio, 1.2)
            XCTAssertGreaterThan(layout.tableRatio, 0.3)
            XCTAssertLessThan(layout.tableRatio, 0.95)
            XCTAssertGreaterThan(layout.massSizeCalibration, 0)

            // Every ring of facets must be inside the girdle and ordered from
            // the table down to the girdle.
            let crownRadii = layout.crownRows.map(\.radiusScale)
            XCTAssertEqual(crownRadii, crownRadii.sorted(), "\(shape.rawValue) crown rows must widen outward")
            let pavilionRadii = layout.pavilionRows.map(\.radiusScale)
            XCTAssertEqual(pavilionRadii, pavilionRadii.sorted(by: >), "\(shape.rawValue) pavilion rows must narrow downward")
        }
    }

    func testOneCaratRoundDiamondIsAboutSixAndAHalfMillimetres() {
        let sizer = GemSizer()
        let width = sizer.girdleWidthMillimetres(for: .roundBrilliant, carat: 1.0, material: .diamond)
        XCTAssertEqual(width, 6.5, accuracy: 0.35, "a 1.00 ct round brilliant is ~6.5 mm")
    }

    func testGirdleWidthGrowsWithCarat() {
        let sizer = GemSizer()
        var previous = 0.0
        for carat in [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0] {
            let width = sizer.girdleWidthMillimetres(for: .roundBrilliant, carat: carat, material: .diamond)
            XCTAssertGreaterThan(width, previous, "width must increase at \(carat) ct")
            previous = width
        }
    }

    func testWidthScalesWithTheCubeRootOfWeight() {
        let sizer = GemSizer()
        let one = sizer.girdleWidthMillimetres(for: .roundBrilliant, carat: 1.0, material: .diamond)
        let eight = sizer.girdleWidthMillimetres(for: .roundBrilliant, carat: 8.0, material: .diamond)
        // Eight times the weight is twice the diameter, because volume scales
        // with the cube of a linear dimension.
        XCTAssertEqual(eight / one, 2.0, accuracy: 0.12)
    }

    func testDenserMaterialIsSmallerAtTheSameCarat() {
        let sizer = GemSizer()
        let diamond = sizer.girdleWidthMillimetres(for: .roundBrilliant, carat: 1.0, material: .diamond)
        let zirconia = sizer.girdleWidthMillimetres(for: .roundBrilliant, carat: 1.0, material: .cubicZirconia)
        XCTAssertGreaterThan(diamond, zirconia, "cubic zirconia is denser, so 1 ct of it is smaller")
    }

    func testCaratAndWidthRoundTrip() {
        let sizer = GemSizer()
        for carat in [0.25, 0.5, 1.0, 2.25] {
            let width = sizer.girdleWidthMillimetres(for: .roundBrilliant, carat: carat, material: .diamond)
            let recovered = sizer.carats(for: .roundBrilliant, girdleWidthMillimetres: width, material: .diamond)
            XCTAssertEqual(recovered, carat, accuracy: carat * 0.02, "round trip at \(carat) ct")
        }
    }

    func testStoneMeshIsCentredAndSizedInMillimetres() {
        let sizer = GemSizer()
        let width = sizer.girdleWidthMillimetres(for: .roundBrilliant, carat: 1.0, material: .diamond)
        let mesh = GemMeshBuilder.mesh(GemFacetLayout.standard(for: .roundBrilliant),
                                       girdleWidthMillimetres: width)

        XCTAssertTrue(mesh.isWatertight, mesh.defectsDescription)
        XCTAssertEqual(mesh.maximumDistanceFromRingAxis * 2, width, accuracy: width * 0.05)
        // The pavilion must reach below the girdle plane and the crown above it.
        XCTAssertLessThan(mesh.bounds.minimum.y, 0)
        XCTAssertGreaterThan(mesh.bounds.maximum.y, 0)
    }

    func testEveryShapeSizesWithoutCollapsing() {
        let sizer = GemSizer()
        for shape in GemShape.allCases {
            let width = sizer.girdleWidthMillimetres(for: shape, carat: 0.5, material: .diamond)
            XCTAssertGreaterThan(width, 1.0, "\(shape.rawValue) sized to \(width) mm")
            let mesh = GemMeshBuilder.mesh(GemFacetLayout.standard(for: shape), girdleWidthMillimetres: width)
            XCTAssertTrue(mesh.isWatertight, "\(shape.rawValue): \(mesh.defectsDescription)")
        }
    }
}
