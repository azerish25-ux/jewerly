//
//  RGBColour.swift
//  JewelcraftKit
//
//  Linear-ish display colour as data.
//
//  Materials, gem colours and metal appearances all live in JSON rather than in
//  code. This mirrors a property recovered from the original application — its
//  appearance came from external `.vismat`/`.visopt`/HDR files, so artists could
//  change the look without a rebuild. Keeping colours in data preserves that,
//  and keeps every visual constant out of the renderer.
//

import Foundation

public struct RGBColour: Equatable, Hashable, Codable, Sendable {
    /// Components in 0...1.
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = RGBColour(red: 1, green: 1, blue: 1)
    public static let black = RGBColour(red: 0, green: 0, blue: 0)

    /// Parses `#RRGGBB`, `RRGGBB`, `#RRGGBBAA` or `RRGGBBAA`.
    ///
    /// Returns `nil` rather than a silent fallback so a typo in a material file
    /// surfaces as a failing test instead of a black ring.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6 || text.count == 8 else { return nil }
        guard let value = UInt32(text, radix: 16) else { return nil }

        if text.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0,
                alpha: 1
            )
        } else {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255.0,
                green: Double((value >> 16) & 0xFF) / 255.0,
                blue: Double((value >> 8) & 0xFF) / 255.0,
                alpha: Double(value & 0xFF) / 255.0
            )
        }
    }

    /// `#RRGGBB`, round-trippable through `init?(hex:)`.
    public var hexString: String {
        let r = Int((red.clamped(to: 0...1) * 255).rounded())
        let g = Int((green.clamped(to: 0...1) * 255).rounded())
        let b = Int((blue.clamped(to: 0...1) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// A version with the given opacity, used to build a gem's transparent
    /// material from its colour record.
    public func withAlpha(_ alpha: Double) -> RGBColour {
        RGBColour(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Perceptual luminance, used to pick readable contrasting label text over
    /// a swatch.
    public var relativeLuminance: Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}

extension Double {
    /// Clamps into `range`. Small helper used by colour maths and by the
    /// pricing engine's rounding step.
    public func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }

    /// Rounds to the nearest multiple of `increment`, half away from zero.
    ///
    /// Money rounding is explicit and testable rather than incidental: the
    /// pricing engine rounds through here so a quote's total can be
    /// re-derived from its own lines.
    public func rounded(toNearest increment: Double) -> Double {
        guard increment > 0 else { return self }
        let scaled = self / increment
        let rounded = (scaled).rounded(.toNearestOrAwayFromZero)
        return rounded * increment
    }
}
