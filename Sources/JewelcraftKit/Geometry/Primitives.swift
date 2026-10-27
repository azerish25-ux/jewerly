//
//  Primitives.swift
//  JewelcraftKit
//
//  Mesh generators for the shapes the ring builder needs.
//
//  Every generator here produces a closed surface with outward-facing winding,
//  so `Mesh.isWatertight` holds for each one in isolation and for any
//  concatenation of them. That property is asserted directly in the test suite:
//  the tolerance for a hole in a ring that will be sent to a 3D printer is
//  zero, not "small".
//

import Foundation

extension Mesh {

    // MARK: - Revolution / sweep

    /// Sweeps a closed 2D profile around the ring's main axis.
    ///
    /// The profile is expressed in the cross-section plane: `x` is the offset
    /// outward from the centreline, `y` is the axial offset. `centrelineRadius`
    /// supplies the distance from the axis to the profile origin at each angle,
    /// which is what allows a tapered shank — the profile stays the same while
    /// the ring's centreline follows a smooth curve.
    ///
    /// - Parameters:
    ///   - profile: closed loop, counter-clockwise in the cross-section plane.
    ///   - segments: divisions around the ring.
    ///   - centrelineRadius: called with the angle in `0..<2π`.
    ///   - angularRange: the sweep's extent. A full ring is `nil`.
    ///   - capEnds: whether to close the ends with fans. Only meaningful for a
    ///     partial sweep; a full revolution is already closed.
    ///   - profileScaleAtAngle: scales the cross-section radially (x) and
    ///     axially (y) per angle. This is how a shank tapers from its full
    ///     width at the shoulders to its narrowest at the base without changing
    ///     the profile's shape. When supplied, vertex normals are recomputed
    ///     from the resulting geometry, because a scaled sweep's true surface
    ///     normal is no longer the profile normal carried around the ring.
    public static func revolved(
        profile: [Vector2],
        segments: Int,
        centrelineRadius: (Double) -> Double,
        angularRange: ClosedRange<Double>? = nil,
        capEnds: Bool = false,
        profileScaleAtAngle: ((Double) -> Vector2)? = nil
    ) -> Mesh {
        precondition(profile.count >= 3, "A profile needs at least three points")
        precondition(segments >= 3, "A revolution needs at least three segments")

        let isFullRevolution = angularRange == nil
        let range = angularRange ?? 0...(2 * Double.pi)
        // A closed sweep must not repeat the first ring, or the seam produces
        // non-manifold edges; an open sweep needs both endpoints.
        let ringCount = isFullRevolution ? segments : segments + 1

        // Outward normal in the cross-section plane: the tangent rotated
        // clockwise. For a counter-clockwise loop that points away from the
        // profile's interior.
        var profileNormals: [Vector2] = []
        profileNormals.reserveCapacity(profile.count)
        for index in profile.indices {
            let previous = profile[(index - 1 + profile.count) % profile.count]
            let next = profile[(index + 1) % profile.count]
            let tangent = (next - previous).normalized()
            profileNormals.append(Vector2(tangent.y, -tangent.x))
        }

        var positions: [Vector3] = []
        var normals: [Vector3] = []
        positions.reserveCapacity(ringCount * profile.count)
        normals.reserveCapacity(ringCount * profile.count)

        for ringIndex in 0..<ringCount {
            let fraction = Double(ringIndex) / Double(segments)
            let angle = range.lowerBound + (range.upperBound - range.lowerBound) * fraction
            let radius = centrelineRadius(angle)
            let cosAngle = cos(angle)
            let sinAngle = sin(angle)
            let scale = profileScaleAtAngle?(angle) ?? Vector2(1, 1)

            for profileIndex in profile.indices {
                let source = profile[profileIndex]
                let point = Vector2(source.x * scale.x, source.y * scale.y)
                let radial = radius + point.x
                positions.append(Vector3(radial * cosAngle, point.y, radial * sinAngle))

                let sectionNormal = profileNormals[profileIndex]
                normals.append(Vector3(
                    sectionNormal.x * cosAngle,
                    sectionNormal.y,
                    sectionNormal.x * sinAngle
                ).normalized())
            }
        }

        var indices: [UInt32] = []
        let ringStride = UInt32(profile.count)
        let ringWrap: (Int) -> Int = { index in
            if isFullRevolution {
                return index % ringCount
            }
            return Swift.min(index, ringCount - 1)
        }

        for ringIndex in 0..<(isFullRevolution ? ringCount : ringCount - 1) {
            let nextRing = ringWrap(ringIndex + 1)
            for profileIndex in 0..<profile.count {
                let nextProfile = (profileIndex + 1) % profile.count
                let a = UInt32(ringIndex) * ringStride + UInt32(profileIndex)
                let b = UInt32(ringIndex) * ringStride + UInt32(nextProfile)
                let c = UInt32(nextRing) * ringStride + UInt32(profileIndex)
                let d = UInt32(nextRing) * ringStride + UInt32(nextProfile)
                // Winding: a counter-clockwise profile swept along increasing
                // angle gives outward normals with this order. Verified against
                // a known solid's volume in the geometry tests.
                indices.append(contentsOf: [a, b, c])
                indices.append(contentsOf: [b, d, c])
            }
        }

        if !isFullRevolution && capEnds {
            // Start cap: the first ring, fanned from its centroid, facing the
            // opposite way to the sweep direction.
            let startCentreIndex = UInt32(positions.count)
            positions.append(Self.centroid(of: Array(positions[0..<profile.count])))
            normals.append(.zero)
            for profileIndex in 0..<profile.count {
                let nextProfile = (profileIndex + 1) % profile.count
                indices.append(contentsOf: [startCentreIndex, UInt32(nextProfile), UInt32(profileIndex)])
            }

            // End cap: the last ring, wound the other way.
            let endBase = (ringCount - 1) * profile.count
            let endCentreIndex = UInt32(positions.count)
            positions.append(Self.centroid(of: Array(positions[endBase..<(endBase + profile.count)])))
            normals.append(.zero)
            for profileIndex in 0..<profile.count {
                let nextProfile = (profileIndex + 1) % profile.count
                indices.append(contentsOf: [
                    endCentreIndex,
                    UInt32(endBase + profileIndex),
                    UInt32(endBase + nextProfile)
                ])
            }
        }

        var mesh = Mesh(positions: positions, normals: normals, indices: indices)
        mesh.fillDegenerateNormals()
        if profileScaleAtAngle != nil {
            mesh = mesh.recomputingSmoothNormals()
        }
        return mesh
    }

    private static func centroid(of points: [Vector3]) -> Vector3 {
        guard !points.isEmpty else { return .zero }
        var sum = Vector3.zero
        for point in points { sum = sum + point }
        return sum / Double(points.count)
    }

    /// Cap centroids are added with a zero normal; they only affect shading at
    /// a point that is never visible on a closed solid, but a zero normal would
    /// fail the finite and unit-length checks, so give each one the normal of
    /// the first triangle that touches it.
    private mutating func fillDegenerateNormals() {
        for index in normals.indices where normals[index].lengthSquared < 0.5 {
            var derived = Vector3.zero
            for triangleIndex in 0..<triangleCount {
                let (i0, i1, i2) = triangle(at: triangleIndex)
                if i0 == UInt32(index) || i1 == UInt32(index) || i2 == UInt32(index) {
                    let a = positions[Int(i0)]
                    let b = positions[Int(i1)]
                    let c = positions[Int(i2)]
                    derived = Vector3.cross(b - a, c - a)
                    if derived.lengthSquared > 0 { break }
                }
            }
            normals[index] = derived.normalized()
        }
    }

    // MARK: - Profiles

    /// A counter-clockwise ellipse profile: the rounded "domed" shank
    /// cross-section, and the cross-section of a torus.
    public static func ellipseProfile(radialRadius: Double, axialRadius: Double, pointCount: Int) -> [Vector2] {
        precondition(pointCount >= 3, "An ellipse profile needs at least three points")
        var points: [Vector2] = []
        points.reserveCapacity(pointCount)
        for index in 0..<pointCount {
            let angle = 2 * Double.pi * Double(index) / Double(pointCount)
            points.append(Vector2(radialRadius * cos(angle), axialRadius * sin(angle)))
        }
        return points
    }

    /// A counter-clockwise rounded rectangle profile: the flatter, wider
    /// cross-sections (flat, European comfort, cathedral shoulders).
    ///
    /// Sampled from a superellipse: `cornerFraction` of 1 is an ellipse, and
    /// smaller values square the corners off, while the point count and winding
    /// stay identical to the ellipse so the two are interchangeable.
    public static func roundedRectangleProfile(
        radialRadius: Double,
        axialRadius: Double,
        cornerFraction: Double,
        pointCount: Int
    ) -> [Vector2] {
        precondition(pointCount >= 4, "A rounded rectangle needs at least four points")
        let power = Swift.max(0.05, Swift.min(1.0, cornerFraction))
        var points: [Vector2] = []
        points.reserveCapacity(pointCount)
        for index in 0..<pointCount {
            let angle = 2 * Double.pi * Double(index) / Double(pointCount)
            let cosAngle = cos(angle)
            let sinAngle = sin(angle)
            let x = radialRadius * (cosAngle < 0 ? -1 : 1) * pow(abs(cosAngle), power)
            let y = axialRadius * (sinAngle < 0 ? -1 : 1) * pow(abs(sinAngle), power)
            points.append(Vector2(x, y))
        }
        return points
    }

    /// A counter-clockwise lens profile with sharp outer edges: the knife-edge
    /// and pointed shank cross-sections.
    public static func lensProfile(radialRadius: Double, axialRadius: Double, pointCount: Int) -> [Vector2] {
        precondition(pointCount >= 4, "A lens profile needs at least four points")
        let half = pointCount / 2
        var points: [Vector2] = []
        points.reserveCapacity(pointCount)
        // Upper arc from the (+radial, 0) tip to the (-radial, 0) tip.
        for index in 0...half {
            let t = Double(index) / Double(half)
            let angle = Double.pi * t
            points.append(Vector2(radialRadius * cos(angle), axialRadius * sin(angle)))
        }
        // Lower arc back to the starting tip, without repeating either tip.
        for index in 1..<half {
            let t = Double(index) / Double(half)
            let angle = Double.pi * (1 + t)
            points.append(Vector2(radialRadius * cos(angle), axialRadius * sin(angle)))
        }
        return points
    }

    // MARK: - Solids

    /// A closed sphere, used for setting beads and for rounded stone seats.
    public static func sphere(center: Vector3, radius: Double, segments: Int = 16, rings: Int = 8) -> Mesh {
        precondition(segments >= 3 && rings >= 2, "A sphere needs at least 3 segments and 2 rings")

        var positions: [Vector3] = []
        var normals: [Vector3] = []

        // North pole.
        positions.append(center + Vector3(0, radius, 0))
        normals.append(Vector3(0, 1, 0))

        // Intermediate rows; the poles are single vertices so no row degenerates.
        for row in 1..<rings {
            let theta = Double.pi * Double(row) / Double(rings)
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)
            for column in 0..<segments {
                let phi = 2 * Double.pi * Double(column) / Double(segments)
                let direction = Vector3(sinTheta * cos(phi), cosTheta, sinTheta * sin(phi))
                positions.append(center + direction * radius)
                normals.append(direction)
            }
        }

        // South pole.
        let southIndex = UInt32(positions.count)
        positions.append(center + Vector3(0, -radius, 0))
        normals.append(Vector3(0, -1, 0))

        var indices: [UInt32] = []
        let northIndex: UInt32 = 0

        // North cap fan.
        for column in 0..<segments {
            let current = UInt32(1 + column)
            let next = UInt32(1 + (column + 1) % segments)
            indices.append(contentsOf: [northIndex, next, current])
        }

        // Middle bands.
        if rings > 2 {
            for row in 0..<(rings - 2) {
                let rowStart = 1 + row * segments
                let nextRowStart = rowStart + segments
                for column in 0..<segments {
                    let nextColumn = (column + 1) % segments
                    let a = UInt32(rowStart + column)
                    let b = UInt32(rowStart + nextColumn)
                    let c = UInt32(nextRowStart + column)
                    let d = UInt32(nextRowStart + nextColumn)
                    indices.append(contentsOf: [a, b, c])
                    indices.append(contentsOf: [b, d, c])
                }
            }
        }

        // South cap fan.
        let lastRowStart = 1 + Swift.max(0, rings - 2) * segments
        for column in 0..<segments {
            let current = UInt32(lastRowStart + column)
            let next = UInt32(lastRowStart + (column + 1) % segments)
            indices.append(contentsOf: [current, next, southIndex])
        }

        return Mesh(positions: positions, normals: normals, indices: indices)
    }

    /// A closed cone or truncated cone along an arbitrary axis: prongs,
    /// gallery posts and tapered details.
    public static func cone(
        from start: Vector3,
        to end: Vector3,
        startRadius: Double,
        endRadius: Double,
        segments: Int = 16
    ) -> Mesh {
        precondition(segments >= 3, "A cone needs at least three segments")

        let axis = end - start
        let axisLength = axis.length
        guard axisLength > Tolerance.coincidence else { return .empty }
        let w = axis / axisLength

        // A right-handed orthonormal basis with w as its third axis.
        let reference = abs(w.y) < 0.9 ? Vector3(0, 1, 0) : Vector3(1, 0, 0)
        let u = Vector3.cross(reference, w).normalized()
        let v = Vector3.cross(w, u).normalized()

        var positions: [Vector3] = []
        var normals: [Vector3] = []

        // Side normals tilt with the taper.
        let slopeAngle = atan2(endRadius - startRadius, axisLength)

        func sideNormal(angle: Double) -> Vector3 {
            let radial = u * cos(angle) + v * sin(angle)
            return (radial * cos(slopeAngle) - w * sin(slopeAngle)).normalized()
        }

        for column in 0..<segments {
            let angle = 2 * Double.pi * Double(column) / Double(segments)
            positions.append(start + (u * cos(angle) + v * sin(angle)) * startRadius)
            normals.append(sideNormal(angle: angle))
        }
        for column in 0..<segments {
            let angle = 2 * Double.pi * Double(column) / Double(segments)
            positions.append(end + (u * cos(angle) + v * sin(angle)) * endRadius)
            normals.append(sideNormal(angle: angle))
        }

        var indices: [UInt32] = []
        for column in 0..<segments {
            let next = (column + 1) % segments
            let a = UInt32(column)
            let b = UInt32(next)
            let c = UInt32(segments + column)
            let d = UInt32(segments + next)
            indices.append(contentsOf: [a, b, c])
            indices.append(contentsOf: [b, d, c])
        }

        // Start cap faces away from the end cap.
        let startCentreIndex = UInt32(positions.count)
        positions.append(start)
        normals.append(-w)
        for column in 0..<segments {
            let next = (column + 1) % segments
            indices.append(contentsOf: [startCentreIndex, UInt32(next), UInt32(column)])
        }

        let endCentreIndex = UInt32(positions.count)
        positions.append(end)
        normals.append(w)
        for column in 0..<segments {
            let next = (column + 1) % segments
            indices.append(contentsOf: [endCentreIndex, UInt32(segments + column), UInt32(segments + next)])
        }

        return Mesh(positions: positions, normals: normals, indices: indices)
    }

    /// A closed ring torus: the basket under a centre stone, and the gallery
    /// beneath a shank.
    public static func torus(
        centre: Vector3,
        majorRadius: Double,
        minorRadius: Double,
        majorSegments: Int = 48,
        minorSegments: Int = 12
    ) -> Mesh {
        let profile = ellipseProfile(
            radialRadius: minorRadius,
            axialRadius: minorRadius,
            pointCount: minorSegments
        )
        let mesh = Mesh.revolved(
            profile: profile,
            segments: majorSegments,
            centrelineRadius: { _ in majorRadius }
        )
        return mesh.translated(by: centre)
    }

    /// A closed band with a rounded-rectangular section: the shank's rail guide,
    /// a channel, and the collar of a bezel setting.
    public static func band(
        centre: Vector3,
        centrelineRadius: Double,
        radialHalfThickness: Double,
        axialHalfWidth: Double,
        segments: Int = 96,
        cornerFraction: Double = 0.35
    ) -> Mesh {
        let profile = roundedRectangleProfile(
            radialRadius: radialHalfThickness,
            axialRadius: axialHalfWidth,
            cornerFraction: cornerFraction,
            pointCount: 12
        )
        let mesh = Mesh.revolved(
            profile: profile,
            segments: segments,
            centrelineRadius: { _ in centrelineRadius }
        )
        return mesh.translated(by: centre)
    }
}
