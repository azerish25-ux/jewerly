//
//  RingViewport.swift
//  Jewelcraft
//
//  The bench view.
//
//  The engine hands back world-space triangle meshes and gem placements; this
//  file is the only place in the app that knows about RealityKit. Keeping it to
//  one file is deliberate — the original's viewport was a plugin to a separate
//  CAD process, and the equivalent boundary here is "meshes in, pixels out".
//

import SwiftUI
import RealityKit
import UIKit
import simd
import JewelcraftKit

struct RingViewport: View {

    let built: BuiltRing?
    let metalHex: String
    var highlightedSlot: Int?

    @State private var yaw: Double = -24
    @State private var pitch: Double = 14
    @State private var committedYaw: Double = -24
    @State private var committedPitch: Double = 14
    @State private var magnification: Double = 1
    @State private var committedMagnification: Double = 1

    private static let rootName = "ring.root"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.13, blue: 0.15), StudioTheme.ink],
                startPoint: .top,
                endPoint: .bottom
            )

            RealityView { content in
                let root = Entity()
                root.name = Self.rootName
                content.add(root)
                content.add(RingScene.lighting())
            } update: { content in
                guard let root = content.entities.first(where: { $0.name == Self.rootName }) else { return }
                RingScene.populate(
                    root,
                    built: built,
                    metalHex: metalHex,
                    highlightedSlot: highlightedSlot
                )
                root.transform = Transform(
                    scale: SIMD3<Float>(repeating: Float(0.0011 * magnification)),
                    rotation: simd_quatf(angle: Float(yaw * .pi / 180), axis: [0, 1, 0])
                        * simd_quatf(angle: Float(pitch * .pi / 180), axis: [1, 0, 0]),
                    translation: [0, 0, -0.085]
                )
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        yaw = committedYaw + Double(value.translation.width) * 0.35
                        pitch = min(85, max(-85, committedPitch - Double(value.translation.height) * 0.35))
                    }
                    .onEnded { _ in
                        committedYaw = yaw
                        committedPitch = pitch
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        magnification = min(4, max(0.4, committedMagnification * value.magnification))
                    }
                    .onEnded { _ in
                        committedMagnification = magnification
                    }
            )

            if built == nil {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(StudioTheme.brass)
                    Text("Nothing on the bench")
                        .font(.system(size: 12))
                        .foregroundStyle(StudioTheme.muted)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            yaw = -24
                            pitch = 14
                            committedYaw = yaw
                            committedPitch = pitch
                            magnification = 1
                            committedMagnification = 1
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(7)
                            .background(Circle().fill(StudioTheme.panel.opacity(0.8)))
                            .foregroundStyle(StudioTheme.parchment.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset view")
                }
                Spacer()
                hud
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StudioTheme.hairline, lineWidth: 1)
        )
    }

    private var hud: some View {
        HStack(spacing: 10) {
            Text(built.map { Format.grams($0.metalGrams) } ?? "—")
            Text("·")
                .foregroundStyle(StudioTheme.muted)
            Text(built.map { "\(Format.count($0.gemPlacements.count)) stones" } ?? "—")
            Text("·")
                .foregroundStyle(StudioTheme.muted)
            Text(built.map { "\(Format.count($0.triangleCount)) tris" } ?? "—")
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(StudioTheme.parchment.opacity(0.65))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(StudioTheme.ink.opacity(0.7)))
    }
}

// MARK: - Scene construction

enum RingScene {

    /// Three directional lights rather than an image-based environment: no HDR
    /// asset to ship, and a bench lamp is easier to read than a studio HDRI.
    static func lighting() -> Entity {
        let container = Entity()
        container.name = "lighting"

        let key = Entity()
        key.components.set(DirectionalLightComponent(color: .white, intensity: 9_000, isRealWorldProxy: false))
        key.orientation = simd_quatf(angle: 0.7, axis: [1, 0, 0]) * simd_quatf(angle: -0.6, axis: [0, 1, 0])

        let fill = Entity()
        fill.components.set(DirectionalLightComponent(
            color: UIColor(red: 0.82, green: 0.88, blue: 1, alpha: 1),
            intensity: 3_200,
            isRealWorldProxy: false
        ))
        fill.orientation = simd_quatf(angle: -0.5, axis: [1, 0, 0]) * simd_quatf(angle: 1.9, axis: [0, 1, 0])

        let rim = Entity()
        rim.components.set(DirectionalLightComponent(
            color: UIColor(red: 1, green: 0.92, blue: 0.78, alpha: 1),
            intensity: 4_600,
            isRealWorldProxy: false
        ))
        rim.orientation = simd_quatf(angle: 0.2, axis: [1, 0, 0]) * simd_quatf(angle: 2.6, axis: [0, 1, 0])

        container.addChild(key)
        container.addChild(fill)
        container.addChild(rim)
        return container
    }

    static func populate(
        _ root: Entity,
        built: BuiltRing?,
        metalHex: String,
        highlightedSlot: Int?
    ) {
        root.children.removeAll()
        guard let built else { return }

        let centre = built.bounds.center
        let metal: [any Material] = [material(hex: metalHex, metallic: 0.95, roughness: 0.22)]

        for part in built.parts where part.isVisibleByDefault {
            guard let resource = resource(for: part.mesh, offsetBy: centre) else { continue }
            let entity = ModelEntity(mesh: resource, materials: metal)
            entity.name = "part.\(part.id)"
            root.addChild(entity)
        }

        for placement in built.gemPlacements {
            guard let resource = resource(for: placement.mesh(), offsetBy: centre) else { continue }
            let isHighlighted = placement.slotIndex == highlightedSlot
            let stone: [any Material] = [
                isHighlighted
                    ? material(hex: "#F2C14E", metallic: 0.3, roughness: 0.05)
                    : material(hex: gemHex(placement), metallic: 0.05, roughness: 0.03)
            ]
            let entity = ModelEntity(mesh: resource, materials: stone)
            entity.name = "gem.\(placement.slotIndex)"
            root.addChild(entity)
        }
    }

    /// A stone's colour comes from the gem catalogue, so a blue sapphire centre
    /// renders blue without this file knowing what a sapphire is.
    private static func gemHex(_ placement: GemPlacement) -> String {
        GemFixtures.catalog.colour(id: placement.colourID)?.swatchHex ?? "#E8EEF4"
    }

    private static func material(hex: String, metallic: Float, roughness: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(Color(hex: hex)))
        material.metallic = .init(floatLiteral: metallic)
        material.roughness = .init(floatLiteral: roughness)
        return material
    }

    private static func resource(for mesh: Mesh, offsetBy offset: Vector3) -> MeshResource? {
        guard !mesh.isEmpty, mesh.indices.count % 3 == 0 else { return nil }
        let positions = mesh.positions.map { point in
            SIMD3<Float>(Float(point.x - offset.x), Float(point.y - offset.y), Float(point.z - offset.z))
        }
        guard positions.count == mesh.normals.count else { return nil }

        var descriptor = MeshDescriptor()
        descriptor.name = "jewelcraft.part"
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(
            mesh.normals.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
        )
        descriptor.primitives = .triangles(mesh.indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
