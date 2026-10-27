//
//  CataloguePane.swift
//  Jewelcraft
//
//  The catalogue: a keyword field, the facet rail, and the results grid.
//
//  Facets are shown with their *result count* and are disabled when selecting
//  them would dead-end, which is the guidance behaviour the recovered search
//  encoded in its own descriptor type rather than leaving to the client.
//

import SwiftUI
import JewelcraftKit

struct CataloguePane: View {

    @Environment(StudioModel.self) private var model
    @State private var showsFacets = false

    private let columns = [
        GridItem(.adaptive(minimum: 196, maximum: 280), spacing: 14)
    ]

    private var facetGroups: [FacetGroup] {
        FacetGroup.allCases.filter { !(model.facets[$0] ?? []).isEmpty }
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            header(searchText: $model.searchText)
            HairlineDivider()
            if showsFacets {
                FacetRail(groups: facetGroups)
                HairlineDivider()
            }
            results
        }
        .background(StudioTheme.ink)
        .navigationTitle(model.scopeTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private func header(searchText: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(StudioTheme.muted)
                    TextField("Spin number, name, keyword", text: searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(StudioTheme.raised)
                )

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showsFacets.toggle() }
                } label: {
                    Image(systemName: showsFacets ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(showsFacets ? StudioTheme.brass : StudioTheme.parchment.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filters")
                .accessibilityIdentifier("facet-toggle")
            }

            HStack(spacing: 8) {
                Text(model.scopeTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StudioTheme.parchment)
                Text("· \(Format.count(model.results.count)) designs")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(StudioTheme.muted)
                Spacer()
                if model.activeFacetCount > 0 || !model.searchText.isEmpty {
                    Button("Clear") { model.clearAll() }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(StudioTheme.brass)
                        .accessibilityIdentifier("clear-filters")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(StudioTheme.panel)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if model.results.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 30, weight: .ultraLight))
                    .foregroundStyle(StudioTheme.brass.opacity(0.6))
                Text("Nothing matches that yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StudioTheme.parchment)
                Text("Widen a facet or clear the search to see the library again.")
                    .font(.system(size: 12))
                    .foregroundStyle(StudioTheme.muted)
                Button("Clear filters") { model.clearAll() }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.brass)
                    .foregroundStyle(StudioTheme.ink)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudioTheme.ink)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(model.results) { summary in
                        Button {
                            model.open(summary)
                        } label: {
                            DesignTile(
                                summary: summary,
                                isOpen: model.design?.id == summary.id,
                                isBusy: model.isBusy
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("design-\(summary.id.rawValue)")
                    }
                }
                .padding(18)
            }
        }
    }
}

// MARK: - Facets

private struct FacetRail: View {
    let groups: [FacetGroup]

    @Environment(StudioModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(groups, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: group.displayName)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(model.facets[group] ?? []) { descriptor in
                                    Button {
                                        model.toggle(descriptor.id, in: group)
                                    } label: {
                                        ChoiceChip(
                                            title: descriptor.item.name,
                                            detail: descriptor.isSelected ? nil : Format.count(descriptor.resultCount),
                                            isSelected: descriptor.isSelected,
                                            isEnabled: descriptor.isAvailable || descriptor.isSelected
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!descriptor.isAvailable && !descriptor.isSelected)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 190)
        .background(StudioTheme.panel.opacity(0.65))
    }
}
