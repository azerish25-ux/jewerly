//
//  GemReportSection.swift
//  Jewelcraft
//
//  The gem report: every stone in the ring, in slot order, with the numbers a
//  setter works from. The original called this out as a first-class panel, and
//  it is the part of the product a customer most often asks to see.
//

import SwiftUI
import JewelcraftKit

struct GemReportSection: View {

    let lines: [GemReportLine]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(StudioTheme.muted)
                    SectionLabel(text: "Gem report")
                    Spacer()
                    Text("\(lines.count) stones")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(StudioTheme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("gem-report-toggle")

            if isExpanded {
                VStack(spacing: 0) {
                    headerRow
                    ForEach(lines) { line in
                        HairlineDivider()
                        row(line)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(StudioTheme.panel)
                )
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("SLOT").frame(width: 34, alignment: .leading)
            Text("STONE").frame(maxWidth: .infinity, alignment: .leading)
            Text("CARAT").frame(width: 54, alignment: .trailing)
            Text("GIRDLE").frame(width: 62, alignment: .trailing)
        }
        .font(.system(size: 8, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(StudioTheme.muted)
        .padding(.bottom, 4)
    }

    private func row(_ line: GemReportLine) -> some View {
        HStack(spacing: 6) {
            Text("\(line.slotIndex)")
                .frame(width: 34, alignment: .leading)
                .foregroundStyle(StudioTheme.brass)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("\(line.shape.displayName) \(line.material.displayName.lowercased())")
                        .lineLimit(1)
                    if line.role == .centre {
                        Text("CENTRE")
                            .font(.system(size: 7, weight: .bold))
                            .tracking(0.5)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(StudioTheme.brass.opacity(0.22)))
                            .foregroundStyle(StudioTheme.brass)
                    }
                    if line.isManualSize {
                        Text("MANUAL")
                            .font(.system(size: 7, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(StudioTheme.muted)
                    }
                }
                Text("\(line.qualityID) · \(line.colourID)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(StudioTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.2f", line.carat))
                .frame(width: 54, alignment: .trailing)
            Text(String(format: "%.2f", line.girdleWidthMillimetres))
                .frame(width: 62, alignment: .trailing)
                .foregroundStyle(StudioTheme.parchment.opacity(0.8))
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(StudioTheme.parchment)
        .padding(.vertical, 5)
    }
}
