//
//  Theme.swift
//  Jewelcraft
//
//  The studio's visual language: charcoal ground, brass accent, serif display
//  type for design names, monospaced digits for every measurement. A jeweller's
//  bench under a loupe light, not a pastel app.
//

import SwiftUI

enum StudioTheme {
    static let ink = Color(red: 0.051, green: 0.051, blue: 0.059)
    static let panel = Color(red: 0.086, green: 0.086, blue: 0.098)
    static let raised = Color(red: 0.125, green: 0.125, blue: 0.141)
    static let hairline = Color.white.opacity(0.09)
    static let brass = Color(red: 0.839, green: 0.678, blue: 0.353)
    static let parchment = Color(red: 0.937, green: 0.918, blue: 0.878)
    static let muted = Color.white.opacity(0.56)
    static let danger = Color(red: 0.902, green: 0.427, blue: 0.400)
}

extension Color {
    /// A colour from `#RRGGBB`, falling back to mid grey rather than failing —
    /// a swatch is decoration, never data.
    init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            self = Color(white: 0.5)
            return
        }
        self = Color(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}

// MARK: - Building blocks

/// A small all-caps label that heads a block of controls.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(StudioTheme.muted)
    }
}

/// A measurement: label on the left, digits on the right, aligned down the
/// column so a stack of them can be scanned.
struct MetricRow: View {
    let label: String
    let value: String
    var emphasised = false
    /// A breakdown line under the row it belongs to.
    var indented = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(StudioTheme.muted)
                .padding(.leading, indented ? 10 : 0)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: emphasised ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(emphasised ? StudioTheme.parchment : StudioTheme.parchment.opacity(0.8))
        }
    }
}

struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(StudioTheme.hairline)
            .frame(height: 1)
    }
}

/// A round metal swatch with a ringed edge, so a near-white metal still reads
/// against the panel.
struct MetalSwatch: View {
    let hex: String
    var isSelected = false

    var body: some View {
        Circle()
            .fill(Color(hex: hex))
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
            .overlay(
                Circle()
                    .stroke(isSelected ? StudioTheme.brass : .clear, lineWidth: 2)
                    .padding(-3)
            )
            .frame(width: 18, height: 18)
    }
}

/// A chip used for facets and stone shapes.
struct ChoiceChip: View {
    let title: String
    var detail: String?
    var isSelected: Bool
    var isEnabled = true

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            if let detail {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(StudioTheme.muted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? StudioTheme.brass.opacity(0.18) : StudioTheme.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? StudioTheme.brass.opacity(0.7) : StudioTheme.hairline, lineWidth: 1)
        )
        .foregroundStyle(isEnabled ? StudioTheme.parchment : StudioTheme.muted)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - Formatting

enum Format {
    /// Money, in the quote's own currency.
    static func money(_ amount: Double, currency: String) -> String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(2)))
    }

    static func grams(_ value: Double) -> String {
        String(format: "%.2f g", value)
    }

    static func millimetres(_ value: Double) -> String {
        String(format: "%.2f mm", value)
    }

    static func carat(_ value: Double) -> String {
        String(format: "%.2f ct", value)
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}
