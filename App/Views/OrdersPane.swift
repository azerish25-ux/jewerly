//
//  OrdersPane.swift
//  Jewelcraft
//
//  The order register.
//
//  Orders are documents: a versioned payload with the configuration, the audited
//  quote and the images the order will need. The register shows their state and
//  lets the studio move one along the chain the model defines — it never offers a
//  transition the order's own state machine would refuse.
//

import SwiftUI
import JewelcraftKit

struct OrdersPane: View {

    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.orders.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 30, weight: .ultraLight))
                            .foregroundStyle(StudioTheme.brass.opacity(0.7))
                        Text("No orders yet")
                            .font(.system(size: 15, weight: .semibold, design: .serif))
                            .foregroundStyle(StudioTheme.parchment)
                        Text("Add a configured ring from the bench to start the register.")
                            .font(.system(size: 11))
                            .foregroundStyle(StudioTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(model.orders, id: \.ref) { order in
                            OrderRow(order: order)
                                .listRowBackground(StudioTheme.panel)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(StudioTheme.ink)
            .navigationTitle("Order register")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StudioTheme.brass)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct OrderRow: View {

    let order: Order

    @Environment(StudioModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(order.ref.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StudioTheme.parchment)
                    .accessibilityIdentifier("order-\(order.ref.rawValue)")
                Spacer()
                statusBadge
            }

            HStack(spacing: 8) {
                Text(order.customer.name)
                    .font(.system(size: 11))
                    .foregroundStyle(StudioTheme.parchment.opacity(0.85))
                Text("·")
                    .foregroundStyle(StudioTheme.muted)
                Text("\(order.itemCount) item\(order.itemCount == 1 ? "" : "s")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(StudioTheme.muted)
                Text("·")
                    .foregroundStyle(StudioTheme.muted)
                Text("\(order.totalStoneCount) stones")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(StudioTheme.muted)
                Spacer()
                Text(Format.money(order.total, currency: order.currency))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(StudioTheme.brass)
            }

            ForEach(order.lines) { line in
                HStack(spacing: 6) {
                    Text(line.spinNumber.rawValue)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(StudioTheme.muted)
                    Text(line.designName)
                        .font(.system(size: 10))
                        .foregroundStyle(StudioTheme.parchment.opacity(0.8))
                    Spacer()
                    Text(line.configuration.fingerSize.displayText)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(StudioTheme.muted)
                }
            }

            if !order.canSubmit && order.status == .draft {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(order.submissionIssues, id: \.self) { issue in
                        Text("• \(issue)")
                            .font(.system(size: 9))
                            .foregroundStyle(StudioTheme.danger)
                    }
                }
            }

            HStack(spacing: 10) {
                if order.status == .draft {
                    Button("Submit") { model.submit(order) }
                        .buttonStyle(.borderedProminent)
                        .tint(StudioTheme.brass)
                        .foregroundStyle(StudioTheme.ink)
                        .controlSize(.small)
                }
                ForEach(order.status.forwardStatuses.filter { $0 != .cancelled }, id: \.self) { next in
                    if next != .submitted {
                        Button("Mark \(next.displayName.lowercased())") {
                            model.advance(order, to: next)
                        }
                        .buttonStyle(.bordered)
                        .tint(StudioTheme.parchment)
                        .controlSize(.small)
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    model.remove(order)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(StudioTheme.muted)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusBadge: some View {
        Text(order.status.displayName.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.8)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    order.status == .cancelled
                        ? StudioTheme.danger.opacity(0.25)
                        : StudioTheme.brass.opacity(0.20)
                )
            )
            .foregroundStyle(order.status == .cancelled ? StudioTheme.danger : StudioTheme.brass)
    }
}
