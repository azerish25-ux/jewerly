//
//  Mesh.swift
//  JewelcraftKit
//
//  A triangulated surface with structural invariants.
//
//  The original application delegated all geometry to Rhino, so no geometry
//  code was recoverable and nothing about the kernel could be checked against a
//  reference implementation. That makes *verification by construction* the only
//  honest substitute: this type carries the invariants (closed surfaces,
//  consistent winding, physically plausible volume) that the test suite asserts,
//  so a broken ring fails `swift test` instead of shipping as a pretty render.
//

import Foundation

/// A directed edge, used for topology checks.
private struct DirectedEdge: Hashable {
    let from: UInt32
    let to: UInt32
}

/// A structural problem found in a mesh.
public enum MeshDefect: Equatable, Hashable, CustomStringConvertible {
    /// The mesh has no triangles.
    case empty
    /// Some position or normal is NaN or infinite.
    case nonFiniteCoordinates(count: Int)
    /// The index buffer references a vertex that does not exist.
    case indexOutOfRange(count: Int)
    /// A triangle with two or three identical corners, contributing no area.
    case degenerateTriangles(count: Int)
    /// Edges used by only one triangle: the surface has holes.
    case boundaryEdges(count: Int)
    /// Edges used by more than two triangles: the surface self-intersects
    /// topologically or two shells share an edge.
    case nonManifoldEdges(count: Int)

    public var description: String {
        switch self {
        case .empty:
            return "mesh is empty"
        case .nonFiniteCoordinates(let count):
            return "\(count) non-finite coordinate(s)"
        case .indexOutOfRange(let count):
            return "\(count) out-of-range index reference(s)"
        case .degenerateTriangles(let count):
            return "\(count) degenerate triangle(s)"
        case .boundaryEdges(let count):
            return "\(count) boundary edge(s) — surface is not closed"
        case .nonManifoldEdges(let count):
            return "\(count) non-manifold edge(s)"
        }
    }
}

/// An indexed triangle mesh.
public struct Mesh: Equatable {
    public var positions: [Vector3]
    public var normals: [Vector3]
    public var indices: [UInt32]

    public init(positions: [Vector3], normals: [Vector3], indices: [UInt32]) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
    }

    public static let empty = Mesh(positions: [], normals: [], indices: [])

    // MARK: - Cardinality

    public var vertexCount: Int { positions.count }
    public var triangleCount: Int { indices.count / 3 }
    public var isEmpty: Bool { indices.isEmpty }

    /// The three vertex indices of triangle `index`.
    public func triangle(at index: Int) -> (UInt32, UInt32, UInt32) {
        let base = index * 3
        return (indices[base], indices[base + 1], indices[base + 2])
    }

    // MARK: - Measurement

    public var bounds: BoundingBox {
        BoundingBox(points: positions)
    }

    /// Signed volume via the divergence theorem. Positive for outward-facing
    /// winding, which is the kernel's winding convention.
    public var signedVolume: Double {
        var total = 0.0
        for triangleIndex in 0..<triangleCount {
            let (i0, i1, i2) = triangle(at: triangleIndex)
            guard Int(i0) < positions.count, Int(i1) < positions.count, Int(i2) < positions.count else {
                continue
            }
            let a = positions[Int(i0)]
            let b = positions[Int(i1)]
            let c = positions[Int(i2)]
            total += Vector3.dot(a, Vector3.cross(b, c))
        }
        return total / 6.0
    }

    /// Total surface area, in square millimetres.
    public var surfaceArea: Double {
        var total = 0.0
        for triangleIndex in 0..<triangleCount {
            let (i0, i1, i2) = triangle(at: triangleIndex)
            guard Int(i0) < positions.count, Int(i1) < positions.count, Int(i2) < positions.count else {
                continue
            }
            let a = positions[Int(i0)]
            let b = positions[Int(i1)]
            let c = positions[Int(i2)]
            total += Vector3.cross(b - a, c - a).length / 2.0
        }
        return total
    }

    /// The largest distance from the ring's main axis (Y) to any vertex.
    public var maximumDistanceFromRingAxis: Double {
        positions.map { $0.distanceFromRingAxis }.max() ?? 0
    }

    /// The smallest distance from the ring's main axis to any vertex.
    public var minimumDistanceFromRingAxis: Double {
        positions.map { $0.distanceFromRingAxis }.min() ?? 0
    }

    // MARK: - Structural validation

    /// Counts directed edges so boundary and non-manifold defects can be
    /// distinguished.
    private func directedEdgeCounts() -> [DirectedEdge: Int] {
        var counts: [DirectedEdge: Int] = [:]
        counts.reserveCapacity(indices.count)
        for triangleIndex in 0..<triangleCount {
            let (i0, i1, i2) = triangle(at: triangleIndex)
            for edge in [DirectedEdge(from: i0, to: i1),
                         DirectedEdge(from: i1, to: i2),
                         DirectedEdge(from: i2, to: i0)] {
                counts[edge, default: 0] += 1
            }
        }
        return counts
    }

    /// Every structural problem with the mesh, in a stable order.
    public func validate() -> [MeshDefect] {
        var defects: [MeshDefect] = []

        if indices.isEmpty || positions.isEmpty {
            return [.empty]
        }

        let nonFinite = positions.filter { !$0.isFinite }.count
            + normals.filter { !$0.isFinite }.count
        if nonFinite > 0 {
            defects.append(.nonFiniteCoordinates(count: nonFinite))
        }

        let outOfRange = indices.filter { Int($0) >= positions.count }.count
        if outOfRange > 0 {
            defects.append(.indexOutOfRange(count: outOfRange))
        }

        var degenerate = 0
        for triangleIndex in 0..<triangleCount {
            let (i0, i1, i2) = triangle(at: triangleIndex)
            if i0 == i1 || i1 == i2 || i0 == i2 {
                degenerate += 1
                continue
            }
            guard Int(i0) < positions.count, Int(i1) < positions.count, Int(i2) < positions.count else {
                continue
            }
            let area = Vector3.cross(positions[Int(i1)] - positions[Int(i0)],
                                     positions[Int(i2)] - positions[Int(i0)]).length / 2.0
            if area <= Tolerance.coincidence {
                degenerate += 1
            }
        }
        if degenerate > 0 {
            defects.append(.degenerateTriangles(count: degenerate))
        }

        if outOfRange == 0 {
            // The closed-surface test is a property of the *shape*, not of how
            // the vertex buffer happens to be laid out: a flat-shaded mesh
            // legitimately splits every vertex, so walking edge adjacency on
            // the raw indices would report a perfectly closed stone as open.
            // Welding by position first makes the test describe the surface.
            let counts = welded().directedEdgeCounts()
            var boundary = 0
            var nonManifold = 0
            for (edge, count) in counts {
                if count > 1 {
                    nonManifold += 1
                }
                if counts[DirectedEdge(from: edge.to, to: edge.from)] == nil {
                    boundary += 1
                }
            }
            if boundary > 0 {
                defects.append(.boundaryEdges(count: boundary))
            }
            if nonManifold > 0 {
                defects.append(.nonManifoldEdges(count: nonManifold))
            }
        }

        return defects
    }

    /// A closed surface with consistent winding: every directed edge has
    /// exactly one opposing twin.
    public var isWatertight: Bool {
        let defects = validate()
        return !defects.contains { defect in
            switch defect {
            case .boundaryEdges, .nonManifoldEdges, .degenerateTriangles, .empty,
                 .indexOutOfRange, .nonFiniteCoordinates:
                return true
            }
        }
    }

    public var defectsDescription: String {
        let defects = validate()
        return defects.isEmpty ? "clean" : defects.map(\.description).joined(separator: "; ")
    }

    // MARK: - Welding

    /// Merges vertices that occupy the same position, within `tolerance`.
    ///
    /// Flat-shaded geometry — which faceted gemstones must be, or they read as
    /// blobs rather than as stones — duplicates vertices at every facet
    /// boundary. That duplication is correct for rendering, and it makes the
    /// surface look non-manifold to a purely index-based check. Welding gives
    /// the topology a fair hearing, so the test suite can assert that a gem is
    /// a genuinely closed solid underneath its flat facets.
    public func welded(tolerance: Double = Tolerance.welding) -> Mesh {
        guard !positions.isEmpty else { return self }

        let cellSize = Swift.max(tolerance, 1e-9)
        struct Cell: Hashable {
            let x: Int64, y: Int64, z: Int64
        }

        var cellToVertex: [Cell: UInt32] = [:]
        var remap = [UInt32](repeating: 0, count: positions.count)
        var newPositions: [Vector3] = []
        var newNormals: [Vector3] = []
        var accumulatedNormals: [Vector3] = []

        func cell(for point: Vector3) -> Cell {
            Cell(x: Int64((point.x / cellSize).rounded()),
                 y: Int64((point.y / cellSize).rounded()),
                 z: Int64((point.z / cellSize).rounded()))
        }

        for (index, point) in positions.enumerated() {
            let key = cell(for: point)
            var match: UInt32?
            // Neighbouring cells are checked too, so points that straddle a
            // cell boundary still weld.
            outer: for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        let neighbour = Cell(x: key.x + Int64(dx), y: key.y + Int64(dy), z: key.z + Int64(dz))
                        if let candidate = cellToVertex[neighbour] {
                            if (newPositions[Int(candidate)] - point).length <= tolerance {
                                match = candidate
                                break outer
                            }
                        }
                    }
                }
            }

            if let existing = match {
                remap[index] = existing
                if index < normals.count {
                    accumulatedNormals[Int(existing)] = accumulatedNormals[Int(existing)] + normals[index]
                }
            } else {
                let newIndex = UInt32(newPositions.count)
                cellToVertex[key] = newIndex
                remap[index] = newIndex
                newPositions.append(point)
                accumulatedNormals.append(index < normals.count ? normals[index] : .zero)
                newNormals.append(index < normals.count ? normals[index] : .zero)
            }
        }

        for index in accumulatedNormals.indices {
            let accumulated = accumulatedNormals[index]
            newNormals[index] = accumulated.lengthSquared > 0 ? accumulated.normalized() : .zero
        }

        var newIndices: [UInt32] = []
        newIndices.reserveCapacity(indices.count)
        for index in indices {
            newIndices.append(remap[Int(index)])
        }

        return Mesh(positions: newPositions, normals: newNormals, indices: newIndices)
    }

    // MARK: - Transforms

    public func transformed(by matrix: Matrix4x4) -> Mesh {
        Mesh(
            positions: positions.map { matrix.apply(to: $0) },
            normals: normals.map { matrix.apply(toDirection: $0).normalized() },
            indices: indices
        )
    }

    public func translated(by offset: Vector3) -> Mesh {
        transformed(by: .translation(offset))
    }

    public mutating func append(_ other: Mesh) {
        guard !other.isEmpty else { return }
        let base = UInt32(positions.count)
        positions.append(contentsOf: other.positions)
        normals.append(contentsOf: other.normals)
        indices.append(contentsOf: other.indices.map { $0 &+ base })
    }

    /// Concatenates two meshes without merging vertices. Each source mesh keeps
    /// its own shells, so a watertight mesh plus a watertight mesh is still
    /// watertight: the edge count of every shell is unchanged.
    public func merged(with other: Mesh) -> Mesh {
        var result = self
        result.append(other)
        return result
    }

    public static func + (lhs: Mesh, rhs: Mesh) -> Mesh {
        lhs.merged(with: rhs)
    }

    /// Merges a list of meshes.
    public static func union(_ meshes: [Mesh]) -> Mesh {
        var result = Mesh.empty
        for mesh in meshes {
            result.append(mesh)
        }
        return result
    }

    /// Replaces vertex normals with the flat normal of each triangle, expanding
    /// vertices so each facet keeps its own normal. This is what makes a
    /// generated gemstone look cut instead of moulded.
    public func flatShaded() -> Mesh {
        var newPositions: [Vector3] = []
        var newNormals: [Vector3] = []
        var newIndices: [UInt32] = []
        newPositions.reserveCapacity(indices.count)
        newNormals.reserveCapacity(indices.count)
        newIndices.reserveCapacity(indices.count)

        for triangleIndex in 0..<triangleCount {
            let (i0, i1, i2) = triangle(at: triangleIndex)
            guard Int(i0) < positions.count, Int(i1) < positions.count, Int(i2) < positions.count else {
                continue
            }
            let a = positions[Int(i0)]
            let b = positions[Int(i1)]
            let c = positions[Int(i2)]
            let normal = Vector3.cross(b - a, c - a).normalized()
            let base = UInt32(newPositions.count)
            newPositions.append(contentsOf: [a, b, c])
            newNormals.append(contentsOf: [normal, normal, normal])
            newIndices.append(contentsOf: [base, base &+ 1, base &+ 2])
        }

        return Mesh(positions: newPositions, normals: newNormals, indices: newIndices)
    }

    /// Duplicates the vertices of a closed mesh so a seam can be shaded
    /// separately without relying on texture wrapping.
    public func duplicated() -> Mesh {
        Mesh(positions: positions, normals: normals, indices: indices)
    }

    /// Replaces vertex normals with the area-weighted average of the incident
    /// face normals.
    ///
    /// Needed whenever geometry is deformed after generation — a scaled sweep,
    /// for instance — because the analytic normal that was correct before the
    /// deformation is not the real surface normal afterwards. Deriving normals
    /// from the geometry as built removes that class of shading bug rather than
    /// approximating it away.
    public func recomputingSmoothNormals() -> Mesh {
        var accumulated = [Vector3](repeating: .zero, count: positions.count)

        for triangleIndex in 0..<triangleCount {
            let (i0, i1, i2) = triangle(at: triangleIndex)
            guard Int(i0) < positions.count, Int(i1) < positions.count, Int(i2) < positions.count else {
                continue
            }
            let a = positions[Int(i0)]
            let b = positions[Int(i1)]
            let c = positions[Int(i2)]
            // Un-normalised cross product: its magnitude is twice the triangle
            // area, which makes this an area-weighted average for free.
            let faceNormal = Vector3.cross(b - a, c - a)
            accumulated[Int(i0)] = accumulated[Int(i0)] + faceNormal
            accumulated[Int(i1)] = accumulated[Int(i1)] + faceNormal
            accumulated[Int(i2)] = accumulated[Int(i2)] + faceNormal
        }

        var newNormals = [Vector3](repeating: .zero, count: positions.count)
        for index in accumulated.indices {
            newNormals[index] = accumulated[index].lengthSquared > 0
                ? accumulated[index].normalized()
                : (normals.indices.contains(index) ? normals[index] : Vector3(0, 1, 0))
        }

        return Mesh(positions: positions, normals: newNormals, indices: indices)
    }
}
