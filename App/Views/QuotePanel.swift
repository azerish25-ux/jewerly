//
//  QuotePanel.swift
//  Jewelcraft
//
//  The quote, as the pricing engine computed it.
//
//  Nothing here recomputes a number: the panel renders the engine's lines, its
//  category totals and its stored total. That is the whole point of the split —
//  a quote the customer sees is a document, not a running sum in a view.
//

import SwiftUI
import JewelcraftKit

struct QuotePanel: View {

    let quote: Quote?

    private var categories: [PriceCategory] {
        [.metal, .stone, .setting, .labour]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Quote")
                Spacer()
                if let quote {
                    Text(Format.money(quote.total, currency: quote.currency))
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(StudioTheme.parchment)
                        .accessibilityIdentifier("quote-total")
                }
            }

            if let quote {
                VStack(spacing: 5) {
                    ForEach(categories, id: \.self) { category in
                        MetricRow(
                            label: category.displayName,
                            value: Format.money(quote.total(for: category), currency: quote.currency)
                        )
                    }
                    HairlineDivider()
                    MetricRow(
                        label: "Subtotal",
                        value: Format.money(quote.subtotal, currency: quote.currency),
                        emphasised: true
                    )
                    if quote.discount > 0 {
                        MetricRow(
                            label: "Discount \(String(format: "%.1f", quote.discountPercent))%",
                            value: "−" + Format.money(quote.discount, currency: quote.currency)
                        )
                    }
                    MetricRow(
                        label: "Tax",
                        value: Format.money(quote.tax, currency: quote.currency)
                    )
                    HairlineDivider()
                    MetricRow(
                        label: "Total",
                        value: Format.money(quote.total, currency: quote.currency),
                        emphasised: true
                    )
                }

                HStack(spacing: 8) {
                    Text(quote.priceListID)
                    Spacer()
                    Text(quote.currency)
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(StudioTheme.muted)

                if !quote.isSelfConsistent {
                    Text("This quote does not reconcile with its own lines.")
                        .font(.system(size: 10))
                        .foregroundStyle(StudioTheme.danger)
                }
            } else {
                Text("Configure a ring to price it.")
                    .font(.system(size: 11))
                    .foregroundStyle(StudioTheme.muted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(StudioTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(StudioTheme.brass.opacity(quote == nil ? 0 : 0.25), lineWidth: 1)
        )
    }
}
