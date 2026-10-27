//
//  LibrarySidebar.swift
//  Jewelcraft
//
//  The library: collections, packages and the order register. Scoping is a
//  catalogue filter, not a navigation push, so the middle column keeps its
//  results in place while the scope changes — the same way the original's
//  library tree behaved.
//

import SwiftUI
import JewelcraftKit

struct LibrarySidebar: View {

    @Environment(StudioModel.self) private var model
    @Binding var showingOrders: Bool

    private var showingEverything: Bool {
        model.filter.collectionID == nil && model.filter.packageName == nil
    }

    var body: some View {
        List {
            Section {
                scopeRow(
                    title: "All designs",
                    detail: Format.count(model.catalog.allSummaries.count),
                    selected: showingEverything
                ) {
                    model.clearAll()
                }
            } header: {
                SectionLabel(text: "Catalogue")
            }

            Section {
                ForEach(model.catalog.collections, id: \.id) { collection in
                    scopeRow(
                        title: collection.name,
                        detail: Format.count(model.catalog.designs(inCollection: collection.id).count),
                        selected: model.filter.collectionID == collection.id
                    ) {
                        model.scope(to: collection)
                    }
                }
            } header: {
                SectionLabel(text: "Collections")
            } footer: {
                Text("Curated groupings from the recovered library tree.")
                    .font(.system(size: 10))
                    .foregroundStyle(StudioTheme.muted)
            }

            Section {
                ForEach(model.catalog.packages, id: \.id) { package in
                    scopeRow(
                        title: package.name,
                        detail: Format.count(package.designIDs.count),
                        selected: model.filter.packageName == package.name
                    ) {
                        model.scope(toPackage: package.name)
                    }
                }
            } header: {
                SectionLabel(text: "Packages")
            }

            Section {
                Button {
                    showingOrders = true
                } label: {
                    HStack {
                        Label("Order register", systemImage: "shippingbox")
                            .font(.system(size: 13))
                        Spacer()
                        Text(Format.count(model.orders.count))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(StudioTheme.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(StudioTheme.parchment)
            } header: {
                SectionLabel(text: "Studio")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(StudioTheme.panel)
        .navigationTitle("Jewelcraft")
    }

    private func scopeRow(
        title: String,
        detail: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(selected ? StudioTheme.brass : .clear)
                    .frame(width: 2, height: 14)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(StudioTheme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? StudioTheme.parchment : StudioTheme.parchment.opacity(0.78))
        .listRowBackground(
            selected ? StudioTheme.brass.opacity(0.10) : Color.clear
        )
    }
}
