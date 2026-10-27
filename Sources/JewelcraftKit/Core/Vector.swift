//
//  Vector.swift
//  JewelcraftKit
//
//  Geometric primitives for the CAD kernel.
//
//  Double precision throughout, not Float: the kernel chains many operations
//  (profile generation, revolution, placement, seating) and Float accumulation
//  error shows up as visibly broken facet alignment at ring scale (tens of
//  millimetres with sub-millimetre features). Conversion to Float happens once,
//  at the render boundary, in the app target.
//

import Foundation

// MARK: - Vector2

/// A 2D point or direction. Used for cross-section profiles, which are defined
/// in the (radial, axial) plane of the ring.
public struct Vector2: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ x: Double, _ y: Double) {
        self.init(x: x, y: y)
    }

    public static let zero = Vector2(0, 0)

    public static func + (lhs: Vector2, rhs: Vector2) -> Vector2 {
        Vector2(lhs.x + rhs.x, lhs.y + rhs.y)
    }

    public static func - (lhs: Vector2, rhs: Vector2) -> Vector2 {
        Vector2(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    public static func * (lhs: Vector2, rhs: Double) -> Vector2 {
        Vector2(lhs.x * rhs, lhs.y * rhs)
    }

    public static func / (lhs: Vector2, rhs: Double) -> Vector2 {
        Vector2(lhs.x / rhs, lhs.y / rhs)
    }

    public var length: Double {
        (x * x + y * y).squareRoot()
    }

    public var lengthSquared: Double {
        x * x + y * y
    }

    public func normalized() -> Vector2 {
        let len = length
        guard len > 0 else { return .zero }
        return self / len
    }

    /// Rotated 90 degrees counter-clockwise. Used to get an outward profile
    /// normal from a profile tangent.
    public var perpendicularCounterClockwise: Vector2 {
        Vector2(-y, x)
    }

    public static func dot(_ a: Vector2, _ b: Vector2) -> Double {
        a.x * b.x + a.y * b.y
    }

    public static func cross(_ a: Vector2, _ b: Vector2) -> Double {
        a.x * b.y - a.y * b.x
    }

    /// The signed area of a closed polygon through `points`, using the
    /// shoelace formula. Positive means counter-clockwise winding.
    public static func signedArea(ofClosedPolygon points: [Vector2]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            sum += current.x * next.y - next.x * current.y
        }
        return sum / 2
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}

extension Vector2: CustomStringConvertible {
    public var description: String {
        "(\(Self.format(x)), \(Self.format(y)))"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

// MARK: - Vector3

/// A 3D point or direction in millimetres.
public struct Vector3: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.init(x: x, y: y, z: z)
    }

    public static let zero = Vector3(0, 0, 0)

    public static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    public static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    public static func * (lhs: Vector3, rhs: Double) -> Vector3 {
        Vector3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }

    public static func * (lhs: Double, rhs: Vector3) -> Vector3 {
        rhs * lhs
    }

    public static func / (lhs: Vector3, rhs: Double) -> Vector3 {
        Vector3(lhs.x / rhs, lhs.y / rhs, lhs.z / rhs)
    }

    public static prefix func - (value: Vector3) -> Vector3 {
        Vector3(-value.x, -value.y, -value.z)
    }

    public var length: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    public var lengthSquared: Double {
        x * x + y * y + z * z
    }

    public func normalized() -> Vector3 {
        let len = length
        guard len > 0 else { return .zero }
        return self / len
    }

    public static func dot(_ a: Vector3, _ b: Vector3) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    public static func cross(_ a: Vector3, _ b: Vector3) -> Vector3 {
        Vector3(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }

    /// The distance from this point to the ring's main axis (the Y axis),
    /// ignoring the axial component. The drawing tools measure ring size this
    /// way, and so do the tests.
    public var distanceFromRingAxis: Double {
        (x * x + z * z).squareRoot()
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

extension Vector3: CustomStringConvertible {
    public var description: String {
        "(\(Self.format(x)), \(Self.format(y)), \(Self.format(z)))"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

// MARK: - BoundingBox

public struct BoundingBox: Equatable, Hashable, Codable, Sendable {
    public var minimum: Vector3
    public var maximum: Vector3

    public init(minimum: Vector3, maximum: Vector3) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public init(points: [Vector3]) {
        guard let first = points.first else {
            self.minimum = .zero
            self.maximum = .zero
            return
        }
        var minPoint = first
        var maxPoint = first
        for point in points.dropFirst() {
            minPoint = Vector3(
                x: Swift.min(minPoint.x, point.x),
                y: Swift.min(minPoint.y, point.y),
                z: Swift.min(minPoint.z, point.z)
            )
            maxPoint = Vector3(
                x: Swift.max(maxPoint.x, point.x),
                y: Swift.max(maxPoint.y, point.y),
                z: Swift.max(maxPoint.z, point.z)
            )
        }
        self.minimum = minPoint
        self.maximum = maxPoint
    }

    public var size: Vector3 {
        maximum - minimum
    }

    public var center: Vector3 {
        (minimum + maximum) / 2
    }

    /// Union of two boxes. `nil` behaves as the identity for a fold.
    public func union(_ other: BoundingBox?) -> BoundingBox {
        guard let other else { return self }
        return BoundingBox(
            minimum: Vector3(
                x: Swift.min(minimum.x, other.minimum.x),
                y: Swift.min(minimum.y, other.minimum.y),
                z: Swift.min(minimum.z, other.minimum.z)
            ),
            maximum: Vector3(
                x: Swift.max(maximum.x, other.maximum.x),
                y: Swift.max(maximum.y, other.maximum.y),
                z: Swift.max(maximum.z, other.maximum.z)
            )
        )
    }
}

// MARK: - Matrix4x4

/// A 4x4 affine transform in column-major order, matching the layout the render
/// layer expects, so handing a matrix to RealityKit is a reinterpretation
/// rather than a transpose-and-hope.
public struct Matrix4x4: Equatable, Hashable, Codable, Sendable {
    /// Column-major: `columns[column][row]`.
    public var columns: [[Double]]

    public init(columns: [[Double]]) {
        precondition(columns.count == 4 && columns.allSatisfy { $0.count == 4 },
                     "Matrix4x4 requires four columns of four elements")
        self.columns = columns
    }

    public static let identity = Matrix4x4(columns: [
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        [0, 0, 0, 1]
    ])

    public static func translation(x: Double, y: Double, z: Double) -> Matrix4x4 {
        Matrix4x4(columns: [
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [x, y, z, 1]
        ])
    }

    public static func translation(_ offset: Vector3) -> Matrix4x4 {
        translation(x: offset.x, y: offset.y, z: offset.z)
    }

    public static func scale(x: Double, y: Double, z: Double) -> Matrix4x4 {
        Matrix4x4(columns: [
            [x, 0, 0, 0],
            [0, y, 0, 0],
            [0, 0, z, 0],
            [0, 0, 0, 1]
        ])
    }

    public static func scale(_ factor: Double) -> Matrix4x4 {
        scale(x: factor, y: factor, z: factor)
    }

    /// Uniform scale-and-translate, the only non-rotational transform the
    /// kernel needs for gem placement.
    public static func scaleAndTranslate(scale factor: Double, translate offset: Vector3) -> Matrix4x4 {
        Matrix4x4(columns: [
            [factor, 0, 0, 0],
            [0, factor, 0, 0],
            [0, 0, factor, 0],
            [offset.x, offset.y, offset.z, 1]
        ])
    }

    /// Rotation about the Y axis, the ring's main axis, by `radians`.
    public static func rotationY(_ radians: Double) -> Matrix4x4 {
        let c = cos(radians)
        let s = sin(radians)
        return Matrix4x4(columns: [
            [c, 0, -s, 0],
            [0, 1, 0, 0],
            [s, 0, c, 0],
            [0, 0, 0, 1]
        ])
    }

    /// Rotation about an arbitrary unit axis, by `radians`.
    public static func rotation(axis: Vector3, radians: Double) -> Matrix4x4 {
        let a = axis.normalized()
        let c = cos(radians)
        let s = sin(radians)
        let t = 1 - c
        let x = a.x, y = a.y, z = a.z
        return Matrix4x4(columns: [
            [t * x * x + c, t * x * y + s * z, t * x * z - s * y, 0],
            [t * x * y - s * z, t * y * y + c, t * y * z + s * x, 0],
            [t * x * z + s * y, t * y * z - s * x, t * z * z + c, 0],
            [0, 0, 0, 1]
        ])
    }

    public static func * (lhs: Matrix4x4, rhs: Matrix4x4) -> Matrix4x4 {
        var result = [[Double]](repeating: [0, 0, 0, 0], count: 4)
        for column in 0..<4 {
            for row in 0..<4 {
                var sum = 0.0
                for k in 0..<4 {
                    sum += lhs.columns[k][row] * rhs.columns[column][k]
                }
                result[column][row] = sum
            }
        }
        return Matrix4x4(columns: result)
    }

    /// Transforms a point (the translation column participates).
    public func apply(to point: Vector3) -> Vector3 {
        let x = point.x, y = point.y, z = point.z
        return Vector3(
            x: columns[0][0] * x + columns[1][0] * y + columns[2][0] * z + columns[3][0],
            y: columns[0][1] * x + columns[1][1] * y + columns[2][1] * z + columns[3][1],
            z: columns[0][2] * x + columns[1][2] * y + columns[2][2] * z + columns[3][2]
        )
    }

    /// Transforms a direction (the translation column is ignored).
    public func apply(toDirection direction: Vector3) -> Vector3 {
        let x = direction.x, y = direction.y, z = direction.z
        return Vector3(
            x: columns[0][0] * x + columns[1][0] * y + columns[2][0] * z,
            y: columns[0][1] * x + columns[1][1] * y + columns[2][1] * z,
            z: columns[0][2] * x + columns[1][2] * y + columns[2][2] * z
        )
    }

    public var determinantOfLinearPart: Double {
        let a = columns[0], b = columns[1], c = columns[2]
        return a[0] * (b[1] * c[2] - b[2] * c[1])
             - b[0] * (a[1] * c[2] - a[2] * c[1])
             + c[0] * (a[1] * b[2] - a[2] * b[1])
    }
}

// MARK: - Numeric tolerance helpers

/// A single place for the kernel's comparison tolerances, so tests and code
/// argue from the same numbers instead of scattering magic epsilons.
public enum Tolerance {
    /// Positions closer than this (in millimetres) are the same point.
    public static let coincidence: Double = 1e-6

    /// Positions closer than this are the same point *for welding purposes*,
    /// where independently generated parts meet.
    public static let welding: Double = 1e-4

    /// Relative tolerance for volume, area and other accumulated quantities.
    public static let relative: Double = 1e-9
}

/// Approximate equality with an absolute tolerance.
public func approximatelyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double) -> Bool {
    abs(lhs - rhs) <= tolerance
}

/// Approximate equality with a relative tolerance, falling back to absolute
/// near zero.
public func approximatelyEqualRelative(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
    let scale = Swift.max(abs(lhs), abs(rhs))
    if scale < 1e-12 { return abs(lhs - rhs) <= 1e-12 }
    return abs(lhs - rhs) / scale <= tolerance
}
