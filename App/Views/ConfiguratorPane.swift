//
//  ConfiguratorPane.swift
//  Jewelcraft
//
//  The bench: viewport on top, then the controls that change the ring, then the
//  gem report and the quote. Every control calls an intent on the model and
//  waits for the engine to push the new state back — the view never edits a
//  configuration itself.
//

import SwiftUI
import JewelcraftKit

struct ConfiguratorPane: View {

    @Environment(StudioModel.self) private var model
    @State private var caratDraft: Double = 1
    @State private var showsGemReport = false

    private var snapshot: ConfigurationSnapshot? { model.snapshot }

    private var caratRange: ClosedRange<Double> {
        model.design?.summary.centreGemCaratRange ?? 0.25...5.0
    }

    var body: some View {
        Group {
            if let design = model.design {
                content(design)
            } else {
                emptyState
            }
        }
        .background(StudioTheme.ink)
        .navigationTitle(model.design?.summary.name ?? "Bench")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(StudioTheme.brass.opacity(0.7))
            Text("Choose a design")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(StudioTheme.parchment)
            Text("Pick a plate from the catalogue to put it on the bench.")
                .font(.system(size: 12))
                .foregroundStyle(StudioTheme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StudioTheme.ink)
    }

    // MARK: Content

    private func content(_ design: DesignDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(design)
                RingViewport(
                    built: model.built,
                    metalHex: model.selectedMetal?.swatchHex ?? "#D4AF37",
                    highlightedSlot: nil
                )
                .frame(height: 290)

                metalSection
                centreStoneSection(design)
                sizeSection
                structureSection(design)
                GemReportSection(
                    lines: model.gemReport,
                    isExpanded: $showsGemReport
                )
                QuotePanel(quote: model.quote)
                orderSection
            }
            .padding(16)
        }
        .onChange(of: snapshot?.centreCarat) { _, newValue in
            if let newValue { caratDraft = newValue }
        }
        .onAppear {
            if let carat = snapshot?.centreCarat { caratDraft = carat }
        }
    }

    private func header(_ design: DesignDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(design.summary.spinNumber.rawValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(StudioTheme.brass)
                Text(design.summary.baseRingType.displayName.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(StudioTheme.muted)
                Spacer()
                Button {
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .disabled(!model.canUndo)
                .foregroundStyle(model.canUndo ? StudioTheme.parchment : StudioTheme.muted)
                .accessibilityLabel("Undo")

                Button {
                    model.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.plain)
                .disabled(!model.canRedo)
                .foregroundStyle(model.canRedo ? StudioTheme.parchment : StudioTheme.muted)
                .accessibilityLabel("Redo")
            }

            Text(design.summary.name)
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .foregroundStyle(StudioTheme.parchment)

            Text(design.longDescription)
                .font(.system(size: 11))
                .foregroundStyle(StudioTheme.muted)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Metal

    private var metalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Metal")
                Spacer()
                Text(model.selectedMetal?.displayName ?? "—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(StudioTheme.muted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.offeredMetals, id: \.id) { metal in
                        Button {
                            model.setMetal(metal, second: model.selectedSecondMetal)
                        } label: {
                            HStack(spacing: 6) {
                                MetalSwatch(
                                    hex: metal.swatchHex,
                                    isSelected: metal.id == model.selectedMetal?.id
                                )
                                Text(metal.displayName)
                                    .font(.system(size: 11, weight: metal.id == model.selectedMetal?.id ? .semibold : .regular))
                                    .foregroundStyle(StudioTheme.parchment)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(metal.id == model.selectedMetal?.id ? StudioTheme.brass.opacity(0.16) : StudioTheme.panel)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }

            if let metal = model.selectedMetal, !model.pairingMetals.isEmpty {
                Menu {
                    Button("Single tone") { model.setMetal(metal, second: nil) }
                    Divider()
                    ForEach(model.pairingMetals, id: \.id) { second in
                        Button("Two-tone · \(second.displayName)") {
                            model.setMetal(metal, second: second)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 10))
                        Text(model.selectedSecondMetal.map { "Two-tone with \($0.displayName)" } ?? "Single tone")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(StudioTheme.brass)
                }
            }
        }
    }

    // MARK: Centre stone

    private func centreStoneSection(_ design: DesignDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Centre stone")
                Spacer()
                Text(centreSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(StudioTheme.muted)
            }

            HStack(spacing: 10) {
                Text(CaratRounding.text(for: caratDraft))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StudioTheme.parchment)
                    .frame(width: 46, alignment: .leading)

                Slider(
                    value: $caratDraft,
                    in: caratRange,
                    step: 0.05,
                    onEditingChanged: { editing in
                        if !editing { model.setCentreCarat(caratDraft) }
                    }
                )
                .tint(StudioTheme.brass)

                Button {
                    model.toggleRounding()
                } label: {
                    Text(snapshot?.quarterCaratRounding == true ? "¼ ct" : "exact")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                snapshot?.quarterCaratRounding == true
                                    ? StudioTheme.brass.opacity(0.18)
                                    : StudioTheme.raised
                            )
                        )
                        .foregroundStyle(StudioTheme.parchment)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quarter carat rounding")
            }

            if !model.offeredShapes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.offeredShapes, id: \.self) { shape in
                            Button {
                                model.setCentreShape(shape)
                            } label: {
                                ChoiceChip(
                                    title: shape.displayName,
                                    isSelected: shape == model.centreSelection?.shape
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!design.summary.supportsCentreShape(shape))
                        }
                    }
                }
            }

            if !model.offeredColours.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.offeredColours, id: \.id) { colour in
                            Button {
                                model.setCentreColour(colour.id)
                            } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color(hex: colour.swatchHex))
                                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.5))
                                        .frame(width: 12, height: 12)
                                    Text(colour.name)
                                        .font(.system(size: 10))
                                        .foregroundStyle(StudioTheme.parchment.opacity(0.9))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(
                                        colour.id == model.centreSelection?.colourID
                                            ? StudioTheme.brass.opacity(0.18)
                                            : StudioTheme.panel
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var centreSummary: String {
        guard let selection = model.centreSelection else { return "—" }
        return "\(selection.material.displayName) · \(selection.qualityID) · \(Format.carat(selection.carat))"
    }

    // MARK: Size

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Finger size")
                Spacer()
                Text(snapshot.map { "\($0.fingerSizeText) · \(Format.millimetres($0.innerDiameterMillimetres)) inside" } ?? "—")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(StudioTheme.muted)
            }
            Picker("Finger size", selection: Binding(
                get: { snapshot?.fingerSizeUS ?? FingerSize.defaultValue.usSize },
                set: { model.setFingerSize($0) }
            )) {
                ForEach(FingerSize.allOfferedSizes, id: \.usSize) { size in
                    Text(size.displayText).tag(size.usSize)
                }
            }
            .pickerStyle(.menu)
            .tint(StudioTheme.brass)
            .accessibilityIdentifier("finger-size")
        }
    }

    // MARK: Structure

    private func structureSection(_ design: DesignDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Structure")
            VStack(spacing: 5) {
                MetricRow(label: "Head", value: snapshot?.headStyle.displayName ?? design.head.style.displayName)
                MetricRow(label: "Metal", value: String(format: "%.2f cm³", snapshot?.metalVolumeCubicMillimetres ?? 0))
                MetricRow(label: "Cast weight", value: Format.grams(snapshot?.metalGrams ?? 0), emphasised: true)
                // A two-tone ring is two metals, and the quote prices them apart:
                // showing one total would hide which metal the weight is in.
                if let breakdown = snapshot?.metalBreakdown, breakdown.count > 1 {
                    ForEach(breakdown, id: \.metal.id) { entry in
                        MetricRow(label: entry.metal.displayName, value: entry.gramsText, indented: true)
                    }
                }
                MetricRow(label: "Parts", value: Format.count(snapshot?.partCount ?? 0))
                MetricRow(label: "Triangles", value: Format.count(snapshot?.triangleCount ?? 0))
                MetricRow(label: "Watertight", value: (model.built?.isWatertight ?? false) ? "yes" : "check")
            }
            if let issues = snapshot?.issues, !issues.isEmpty {
                ForEach(issues, id: \.self) { issue in
                    Text("• \(issue)")
                        .font(.system(size: 10))
                        .foregroundStyle(StudioTheme.danger)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(StudioTheme.panel)
        )
    }

    // MARK: Order

    private var orderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Customer")
            TextField("Name", text: Binding(
                get: { model.customerName },
                set: { model.customerName = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            TextField("E-mail", text: Binding(
                get: { model.customerEmail },
                set: { model.customerEmail = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)

            Button {
                model.addCurrentRingToOrder()
            } label: {
                HStack {
                    Image(systemName: "plus.rectangle.on.folder")
                    Text("Add to order register")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(StudioTheme.brass)
                )
                .foregroundStyle(StudioTheme.ink)
            }
            .buttonStyle(.plain)
            .disabled(model.quote == nil)
            .opacity(model.quote == nil ? 0.5 : 1)
            .accessibilityIdentifier("add-to-order")

            if let receipt = model.lastReceipt {
                Text(receipt)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(StudioTheme.muted)
                    .textSelection(.enabled)
            }
        }
    }
}
