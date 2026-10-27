//
//  GeometryTests.swift
//  JewelcraftKitTests
//
//  The geometry kernel's correctness load sits here.
//
//  The point of these tests is not "a mesh came back". It is that a mesh is a
//  *solid*: closed, consistently wound, with a volume that matches the analytic
//  answer for shapes whose volume is known. Without that, the metal weight — and
//  therefore the price — is fiction.
//

import XCTest
@testable import JewelcraftKit

final class GeometryTests: XCTestCase {

    // MARK: - Vectors and transforms

    func testVectorArithmeticAndProducts() {
        let a = Vector3(1, 2, 3)
        let b = Vector3(4, 5, 6)
        XCTAssertEqual(Vector3.dot(a, b), 32, accuracy: 1e-12)
        XCTAssertEqual(Vector3.cross(a, b), Vector3(-3, 6, -3))
        XCTAssertEqual(a + b, Vector3(5, 7, 9))
        XCTAssertEqual(a * 2, Vector3(2, 4, 6))
        XCTAssertEqual(a.length, sqrt(14), accuracy: 1e-12)
        XCTAssertEqual(a.normalized().length, 1, accuracy: 1e-12)
    }

    func testNormalisingZeroLengthVectorIsSafe() {
        // A zero-length normal would otherwise produce NaN and poison every
        // triangle sharing that vertex.
        let zero = Vector3.zero.normalized()
        XCTAssertTrue(zero.isFinite)
        XCTAssertEqual(zero, .zero)
    }

    func testSignedAreaDistinguishesWinding() {
        let counterClockwise = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
        XCTAssertEqual(Vector2.signedArea(ofClosedPolygon: counterClockwise), 1, accuracy: 1e-12)
        XCTAssertEqual(Vector2.signedArea(ofClosedPolygon: Array(counterClockwise.reversed())), -1, accuracy: 1e-12)
    }

    func testMatrixTransformsPointsButNotDirections() {
        let rotation = Matrix4x4.rotationY(Double.pi / 2)
        let rotated = rotation.apply(to: Vector3(1, 0, 0))
        XCTAssertEqual(rotated.x, 0, accuracy: 1e-12)
        XCTAssertEqual(rotated.z, -1, accuracy: 1e-12)

        let translation = Matrix4x4.translation(x: 1, y: 2, z: 3)
        XCTAssertEqual(translation.apply(to: .zero), Vector3(1, 2, 3))
        XCTAssertEqual(translation.apply(toDirection: Vector3(1, 0, 0)), Vector3(1, 0, 0))
    }

    func testMatrixCompositionAppliesRightHandFirst() {
        let combined = Matrix4x4.translation(x: 10, y: 0, z: 0) * Matrix4x4.scale(2)
        XCTAssertEqual(combined.apply(to: Vector3(1, 0, 0)), Vector3(12, 0, 0))
    }

    // MARK: - Hashing

    func testSHA256MatchesPublishedVectors() {
        XCTAssertEqual(
            SHA256.hexDigest(Data()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            SHA256.hexDigest(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            SHA256.hexDigest(Data("The quick brown fox jumps over the lazy dog".utf8)),
            "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
        )
    }

    // MARK: - Mesh structure

    func testSingleTriangleIsReportedAsOpen() {
        let mesh = Mesh(
            positions: [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)],
            normals: [Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)],
            indices: [0, 1, 2]
        )
        XCTAssertFalse(mesh.isWatertight)
        XCTAssertTrue(mesh.validate().contains { defect in
            if case .boundaryEdges = defect { return true }
            return false
        })
    }

    func testEmptyMeshIsReportedAsEmpty() {
        XCTAssertEqual(Mesh.empty.validate(), [.empty])
        XCTAssertFalse(Mesh.empty.isWatertight)
    }

    func testWeldingMergesCoincidentVertices() {
        let positions = [
            Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0),
            Vector3(0, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)
        ]
        let normals = Array(repeating: Vector3(0, 0, 1), count: 6)
        let quad = Mesh(positions: positions, normals: normals, indices: [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(quad.welded().vertexCount, 4)
        // A flat quad is a surface, not a solid, so it stays open.
        XCTAssertFalse(quad.welded().isWatertight)
    }

    // MARK: - Revolved solids

    func testFullRevolutionOfAClosedProfileIsWatertightWithPositiveVolume() {
        let profile = Mesh.ellipseProfile(radialRadius: 0.8, axialRadius: 1.1, pointCount: 24)
        let mesh = Mesh.revolved(profile: profile, segments: 96, centrelineRadius: { _ in 8.0 })

        XCTAssertTrue(mesh.isWatertight, mesh.defectsDescription)
        XCTAssertGreaterThan(mesh.signedVolume, 0, "winding must be outward")

        // Pappus: a revolved closed profile subtends 2 pi R A.
        let area = Double.pi * 0.8 * 1.1
        let expected = 2 * Double.pi * 8.0 * area
        XCTAssertEqual(mesh.signedVolume, expected, accuracy: expected * 0.02)
    }

    func testScaledRevolutionStaysWatertightAndTapers() {
        // The tapered shank: same profile, scaled axially per angle.
        let profile = Mesh.ellipseProfile(radialRadius: 0.7, axialRadius: 1.0, pointCount: 20)
        let mesh = Mesh.revolved(
            profile: profile,
            segments: 96,
            centrelineRadius: { _ in 8.0 },
            profileScaleAtAngle: { angle in
                Vector2(1, 1 - 0.35 * (1 - (1 + cos(angle)) / 2))
            }
        )
        XCTAssertTrue(mesh.isWatertight, mesh.defectsDescription)

        let headFacing = mesh.positions.filter { $0.x > 0 }.map(\.y)
        let baseFacing = mesh.positions.filter { $0.x < 0 }.map(\.y)
        let headSpan = (headFacing.max() ?? 0) - (headFacing.min() ?? 0)
        let baseSpan = (baseFacing.max() ?? 0) - (baseFacing.min() ?? 0)
        XCTAssertGreaterThan(headSpan, baseSpan)
    }

    // MARK: - Primitives against their analytic volumes

    func testSphereVolumeMatchesAnalytic() {
        let radius = 2.0
        let mesh = Mesh.sphere(center: Vector3(1, 2, 3), radius: radius, segments: 32, rings: 16)
        let expected = 4.0 / 3.0 * Double.pi * pow(radius, 3)

        XCTAssertTrue(mesh.isWatertight, mesh.defectsDescription)
        XCTAssertEqual(mesh.signedVolume, expected, accuracy: expected * 0.03)
        XCTAssertEqual(mesh.bounds.center.x, 1, accuracy: 1e-9)
        XCTAssertEqual(mesh.bounds.center.y, 2, accuracy: 1e-9)
    }

    func testTruncatedConeVolumeMatchesAnalytic() {
        let startRadius = 1.0
        let endRadius = 0.5
        let height = 4.0
        let mesh = Mesh.cone(
            from: .zero, to: Vector3(0, height, 0),
            startRadius: startRadius, endRadius: endRadius, segments: 64
        )
        let expected = Double.pi * height / 3.0
            * (startRadius * startRadius + startRadius * endRadius + endRadius * endRadius)

        XCTAssertTrue(mesh.isWatertight, mesh.defectsDescription)
        XCTAssertEqual(mesh.signedVolume, expected, accuracy: expected * 0.02)
    }

    func testTorusVolumeMatchesAnalytic() {
        let major = 5.0
        let minor = 0.8
        let mesh = Mesh.torus(centre: .zero, majorRadius: major, minorRadius: minor,
                              majorSegments: 96, minorSegments: 16)
        let expected = 2 * Double.pi * Double.pi * major * minor * minor

        XCTAssertTrue(mesh.isWatertight, mesh.defectsDescription)
        XCTAssertEqual(mesh.signedVolume, expected, accuracy: expected * 0.03)
    }

    func testProfilesAreCounterClockwise() {
        // Winding is a contract: the revolve relies on it for outward normals.
        let ellipse = Mesh.ellipseProfile(radialRadius: 1, axialRadius: 2, pointCount: 24)
        let rounded = Mesh.roundedRectangleProfile(radialRadius: 1, axialRadius: 2,
                                                   cornerFraction: 0.6, pointCount: 24)
        let lens = Mesh.lensProfile(radialRadius: 1, axialRadius: 0.6, pointCount: 24)
        for profile in [ellipse, rounded, lens] {
            XCTAssertGreaterThan(Vector2.signedArea(ofClosedPolygon: profile), 0)
        }
    }

    func testBoundingBoxUnionAndSize() {
        let a = BoundingBox(minimum: Vector3(0, 0, 0), maximum: Vector3(1, 1, 1))
        let b = BoundingBox(minimum: Vector3(-1, 2, 0), maximum: Vector3(0, 3, 1))
        let union = a.union(b)
        XCTAssertEqual(union.minimum, Vector3(-1, 0, 0))
        XCTAssertEqual(union.maximum, Vector3(1, 3, 1))
        XCTAssertEqual(union.size, Vector3(2, 3, 1))
    }
}
