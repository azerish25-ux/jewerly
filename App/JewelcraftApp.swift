//
//  JewelcraftApp.swift
//  Jewelcraft
//
//  Entry point and the three-column studio: library on the left, catalogue in
//  the middle, the ring on the bench on the right — the iPadOS shape of the
//  original's floating CAD panels.
//

import SwiftUI
import JewelcraftKit

@main
struct JewelcraftApp: App {

    @State private var model = StudioModel()

    var body: some Scene {
        WindowGroup {
            StudioRoot()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(StudioTheme.brass)
        }
    }
}

struct StudioRoot: View {

    @Environment(StudioModel.self) private var model
    @State private var showingOrders = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { presented in
                if !presented { model.errorMessage = nil }
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebar(showingOrders: $showingOrders)
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 300)
        } content: {
            CataloguePane()
                .navigationSplitViewColumnWidth(min: 340, ideal: 500)
        } detail: {
            ConfiguratorPane()
        }
        .navigationSplitViewStyle(.balanced)
        .background(StudioTheme.ink.ignoresSafeArea())
        .sheet(isPresented: $showingOrders) {
            OrdersPane()
        }
        .alert("That did not work", isPresented: errorBinding) {
            Button("Dismiss", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
