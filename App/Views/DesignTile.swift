//
//  DesignTile.swift
//  Jewelcraft
//
//  One catalogue plate.
//
//  The original shipped rendered tiles at two fixed sizes. The rebuild has no
//  pre-rendered bitmaps — every image in the catalogue is generated at runtime —
//  so the plate draws a *glyph* from the design's own attributes instead: the
//  band width from its shank, the centre stone from its supported cut, the
//  accent count from its facet count. It is a diagram of the design, not a
//  photograph pretending to be one.
//

import SwiftUI
import JewelcraftKit

struct DesignTile: View {

    let summary: DesignSummary
    var isOpen = false
    var isBusy = false

    private var metalHex: String {
        summary.metalIDs
            .compactMap { StandardMetals.catalog.metal(id: $0)?.swatchHex }
            .first ?? "#D4AF37"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            plate
                .frame(height: 116)
                .frame(maxWidth: .infinity)
                .background(StudioTheme.raised)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.spinNumber.rawValue)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(StudioTheme.brass.opacity(0.9))
                    Text(summary.baseRingType.displayName)
                        .font(.system(size: 9))
                        .foregroundStyle(StudioTheme.muted)
                    Spacer(minLength: 0)
                }
                Text(summary.name)
                    .font(.system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(StudioTheme.parchment)
                    .lineLimit(1)
                Text(detailLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(StudioTheme.muted)
                    .lineLimit(1)
            }
            .padding(.top, 9)
            .padding(.horizontal, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(StudioTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(isOpen ? StudioTheme.brass.opacity(0.85) : StudioTheme.hairline, lineWidth: isOpen ? 1.4 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if isOpen {
                Text(isBusy ? "BUILDING" : "ON THE BENCH")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(StudioTheme.brass))
                    .padding(8)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var detailLine: String {
        let range = summary.centreGemCaratRange
        let carats = String(format: "%.2f–%.2f ct", range.lowerBound, range.upperBound)
        if summary.accentGemCount == 0 { return carats }
        return "\(carats) · \(summary.accentGemCount) accents"
    }

    // MARK: Glyph

    private var plate: some View {
        Canvas { context, size in
            let metal = Color(hex: metalHex)
            let centre = centre(size)
            let bandWidth = max(2.5, size.height * 0.055)

            // Band: an ellipse with the head opening at the top.
            let bandRect = CGRect(
                x: size.width * 0.5 - centre.width * 0.5,
                y: size.height * 0.42 - centre.height * 0.5 + 6,
                width: centre.width,
                height: centre.height
            )
            let band = Path(ellipseIn: bandRect)
            context.stroke(
                band,
                with: .linearGradient(
                    Gradient(colors: [metal.opacity(0.95), metal.opacity(0.55), metal]),
                    startPoint: CGPoint(x: bandRect.minX, y: bandRect.minY),
                    endPoint: CGPoint(x: bandRect.maxX, y: bandRect.maxY)
                ),
                lineWidth: bandWidth
            )

            // Head: two shoulders rising to the stone.
            let stoneCentre = CGPoint(x: size.width * 0.5, y: bandRect.minY - 2)
            let left = CGPoint(x: bandRect.midX - centre.width * 0.20, y: bandRect.minY + 1)
            let right = CGPoint(x: bandRect.midX + centre.width * 0.20, y: bandRect.minY + 1)
            var head = Path()
            head.move(to: left)
            head.addQuadCurve(to: stoneCentre, control: CGPoint(x: left.x + 4, y: stoneCentre.y + 8))
            head.addQuadCurve(to: right, control: CGPoint(x: right.x - 4, y: stoneCentre.y + 8))
            context.stroke(head, with: .color(metal.opacity(0.85)), lineWidth: bandWidth * 0.7)

            // Centre stone, sized by the design's suggested weight.
            let stoneSize = stoneDiameter(size, carat: summary.centreGemCaratRange.lowerBound)
            context.fill(
                stonePath(centre: stoneCentre, size: stoneSize, shape: summary.supportedCentreShapes.first ?? .roundBrilliant),
                with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.95), Color(hex: "#BFD8E8").opacity(0.8)]),
                    startPoint: CGPoint(x: stoneCentre.x - stoneSize, y: stoneCentre.y - stoneSize),
                    endPoint: CGPoint(x: stoneCentre.x + stoneSize, y: stoneCentre.y + stoneSize)
                )
            )

            // Accents: a dot per gem, spread down both shoulders.
            let accents = min(summary.accentGemCount, 18)
            guard accents > 0 else { return }
            for index in 0..<accents {
                let fraction = Double(index) / Double(max(accents, 2))
                let angle = Double.pi * (0.12 + fraction * 0.76) * (index.isMultiple(of: 2) ? 1 : -1)
                let point = CGPoint(
                    x: bandRect.midX + cos(angle) * bandRect.width * 0.5,
                    y: bandRect.midY + sin(angle) * bandRect.height * 0.5
                )
                let dot = 1.9
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)),
                    with: .color(.white.opacity(0.85))
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text(summary.supportedCentreShapes.first?.displayName ?? "")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(StudioTheme.muted)
                .padding(8)
        }
    }

    private func centre(_ size: CGSize) -> CGSize {
        let width = min(size.width * 0.56, 132)
        return CGSize(width: width, height: width * 0.82)
    }

    private func stoneDiameter(_ size: CGSize, carat: Double) -> Double {
        let normalised = max(0.35, min(1.6, carat / 1.6))
        return max(6, min(size.height * 0.30, size.height * 0.30 * normalised + 6))
    }

    private func stonePath(centre: CGPoint, size: Double, shape: GemShape) -> Path {
        let radius = size / 2
        let rect = CGRect(x: centre.x - radius, y: centre.y - radius, width: size, height: size)
        switch shape {
        case .roundBrilliant, .roundCabochon:
            return Path(ellipseIn: rect)
        case .oval:
            return Path(ellipseIn: rect.insetBy(dx: radius * 0.18, dy: 0))
        case .emerald, .radiant, .baguette, .princess, .asscher:
            return Path(rect.insetBy(dx: radius * 0.12, dy: radius * 0.12))
        case .pear, .marquise, .trillion, .cushion:
            var path = Path()
            path.move(to: CGPoint(x: centre.x, y: centre.y - radius * 1.25))
            path.addQuadCurve(
                to: CGPoint(x: centre.x, y: centre.y + radius * 1.25),
                control: CGPoint(x: centre.x + radius * 1.5, y: centre.y)
            )
            path.addQuadCurve(
                to: CGPoint(x: centre.x, y: centre.y - radius * 1.25),
                control: CGPoint(x: centre.x - radius * 1.5, y: centre.y)
            )
            return path
        }
    }
}
