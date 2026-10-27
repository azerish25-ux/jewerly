//
//  Configuration.swift
//  JewelcraftKit
//
//  The configuration domain: stones, ring size, quarter-carat rounding, and
//  the freehand (curve-editing) state.
//
//  This is the part of the recovered product that was pure logic, and it is
//  reproduced rather than approximated:
//
//    * A design owns its gem *slots*; a configuration owns the *selection* for
//      each slot (material, shape, colour, quality, carat).
//    * Ring size is a US size with an inside diameter, and sizes quantise to
//      quarter steps exactly as the original's size list did.
//    * Quarter-carat rounding is a toggle that snaps the centre stone to 0.25 ct
//      steps; the geometry follows because the carat drives the stone's size.
//    * Two-tone configurations are a first-class pairing, restricted to the
//      metal families that can be joined (see `Metal.canPair(with:)`).
//
//  Where a rule is a choice rather than a recovered fact, the comment says so
//  and `docs/FIDELITY.md` lists it.
//

import Foundation

// MARK: - Roles

/// What a stone is for. The three roles the original's gem report and pricing
/// both distinguished.
public enum GemRole: String, Codable, CaseIterable, Hashable, Sendable {
    case centre
    case accent
    case halo

    public var displayName: String {
        switch self {
        case .centre: return "Centre"
        case .accent: return "Accent"
        case .halo: return "Halo"
        }
    }

    /// Presentation order: the centre stone first, then the melee.
    public var order: Int {
        switch self {
        case .centre: return 0
        case .accent: return 1
        case .halo: return 2
        }
    }

    /// Accents and halo stones are the small stones; a centre stone never
    /// quantises to quarter-carat steps implicitly.
    public var isMelee: Bool { self != .centre }
}

// MARK: - Labour

/// The complexity tier a design is costed at. Three tiers, because a pricing
/// table with two cannot express hand-work.
public enum LabourTier: String, Codable, CaseIterable, Hashable, Sendable {
    case standard
    case premium
    case master

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .premium: return "Premium"
        case .master: return "Master"
        }
    }

    public var order: Int {
        switch self {
        case .standard: return 0
        case .premium: return 1
        case .master: return 2
        }
    }
}

// MARK: - Head

/// How the centre stone is held. The setting is a property of the *design*
/// (chosen through the gem-setting facet), not of the configuration.
public enum HeadStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case prongBasket
    case bezel
    case halo
    case tension

    public var displayName: String {
        switch self {
        case .prongBasket: return "Prong basket"
        case .bezel: return "Bezel"
        case .halo: return "Halo"
        case .tension: return "Tension"
        }
    }

    /// The default prong count for this style. Four-prong is the common case;
    /// a bezel has no prongs at all.
    public var defaultProngCount: Int {
        switch self {
        case .prongBasket: return 4
        case .bezel: return 0
        case .halo: return 4
        case .tension: return 0
        }
    }
}

/// The parametric head.
public struct HeadSpec: Codable, Hashable, Sendable {
    public var style: HeadStyle
    public var prongCount: Int
    /// Height from the shank's outer face to the girdle plane.
    public var basketHeightMillimetres: Double

    public init(style: HeadStyle, prongCount: Int? = nil, basketHeightMillimetres: Double = 1.6) {
        self.style = style
        self.prongCount = Swift.max(0, prongCount ?? style.defaultProngCount)
        self.basketHeightMillimetres = Swift.max(0, basketHeightMillimetres)
    }
}

// MARK: - Shank

/// The shank's cross-section.
public enum ShankProfileShape: String, Codable, CaseIterable, Hashable, Sendable {
    case domed
    case flat
    case euroComfort
    case knifeEdge
    case cathedral

    public var displayName: String {
        switch self {
        case .domed: return "Domed"
        case .flat: return "Flat"
        case .euroComfort: return "European comfort"
        case .knifeEdge: return "Knife edge"
        case .cathedral: return "Cathedral"
        }
    }
}

// MARK: - Accent pattern

public enum AccentPatternKind: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case beadSet
    case pave
    case channel

    public var displayName: String {
        switch self {
        case .none: return "No accents"
        case .beadSet: return "Bead set"
        case .pave: return "Pave"
        case .channel: return "Channel"
        }
    }

    /// How far a stone sits sunk into the metal, as a fraction of its girdle
    /// radius. Channel-set stones sit deepest; bead-set stones stand proudest
    /// because the beads are raised around them.
    public var sinkFraction: Double {
        switch self {
        case .none: return 0
        case .beadSet: return 0.35
        case .pave: return 0.45
        case .channel: return 0.55
        }
    }
}

/// Where the small stones go and how many there are.
public struct AccentPattern: Codable, Hashable, Sendable {
    public var kind: AccentPatternKind
    public var count: Int
    /// How far around the shank the pattern travels, in degrees. It runs
    /// symmetrically about the head.
    public var coverageDegrees: Double

    public init(kind: AccentPatternKind, count: Int, coverageDegrees: Double = 90) {
        self.kind = kind
        self.count = Swift.max(0, count)
        self.coverageDegrees = Swift.max(0, Swift.min(360, coverageDegrees))
    }

    public static let none = AccentPattern(kind: .none, count: 0, coverageDegrees: 0)

    public var displayName: String {
        guard kind != .none, count > 0 else { return "No accents" }
        return "\(kind.displayName) - \(count) stones"
    }
}

// MARK: - Carat rounding

/// Quarter-carat rounding, recovered as an explicit toggle in the original.
///
/// The rule: with rounding on, a centre stone's weight snaps to the nearest
/// 0.25 ct. With it off, the customer's exact weight is used. Accent stones are
/// never rounded - their weights come from the design, not the customer.
public enum CaratRounding {

    public static let increment: Double = 0.25

    public static func rounded(_ carat: Double, enabled: Bool) -> Double {
        guard enabled else { return carat }
        let steps = (carat / increment).rounded()
        return Swift.max(increment, steps * increment)
    }

    public static func nearestQuarter(_ carat: Double) -> Double {
        rounded(carat, enabled: true)
    }

    public static func isQuarterCarat(_ carat: Double) -> Bool {
        let steps = carat / increment
        return abs(steps - steps.rounded()) < 1e-9
    }

    /// A readable label for an increment, e.g. `7.25` -> `"7 1/4"`.
    public static func text(for carat: Double) -> String {
        let whole = Int(carat)
        let fraction = carat - Double(whole)
        let fractionText: String
        switch Int((fraction / increment).rounded()) {
        case 1: fractionText = " 1/4"
        case 2: fractionText = " 1/2"
        case 3: fractionText = " 3/4"
        default: fractionText = ""
        }
        return "\(whole)\(fractionText)"
    }
}

// MARK: - Ring size

/// A US ring size and the inside diameter it implies.
///
/// The diameter follows the standard US sizing table, `d = 11.63 + 0.8128 *
/// size` millimetres, which is the table jewellers' sizing mandrels are cut to.
/// Sizes quantise to quarter steps: a customer can ask for 7 1/2, not 7.31.
public struct FingerSize: Codable, Hashable, Sendable {

    public var usSize: Double
    public var innerDiameterMillimetres: Double

    public init(usSize: Double) {
        let quantised = FingerSize.quantise(usSize)
        self.usSize = quantised
        self.innerDiameterMillimetres = FingerSize.diameter(forUSSize: quantised)
    }

    public init(usSize: Double, innerDiameterMillimetres: Double) {
        self.usSize = usSize
        self.innerDiameterMillimetres = innerDiameterMillimetres
    }

    /// The size the app opens on: US 7, the most common stock size.
    public static let defaultValue = FingerSize(usSize: 7)

    /// The offered range, US 3 to US 16. Wider than any single style is stocked
    /// in, but every size in it is one a jeweller can size to.
    public static let offeredRange: ClosedRange<Double> = 3...16

    public static func diameter(forUSSize size: Double) -> Double {
        11.63 + 0.8128 * size
    }

    public static func quantise(_ size: Double) -> Double {
        let quarter = 0.25
        let snapped = (size / quarter).rounded() * quarter
        return Swift.max(offeredRange.lowerBound, Swift.min(offeredRange.upperBound, snapped))
    }

    public func quantised() -> FingerSize {
        FingerSize(usSize: usSize)
    }

    public var isWithinOfferedRange: Bool {
        FingerSize.offeredRange.contains(usSize) && FingerSize.isQuarterStep(usSize)
    }

    public static func isQuarterStep(_ size: Double) -> Bool {
        let steps = size / 0.25
        return abs(steps - steps.rounded()) < 1e-9
    }

    /// `"US 7 1/2"`.
    public var displayText: String {
        "US \(CaratRounding.text(for: usSize))"
    }

    public var diameterText: String {
        String(format: "%.2f mm inside", innerDiameterMillimetres)
    }

    /// The inside circumference, which is what a sizing gauge measures.
    public var insideCircumferenceMillimetres: Double {
        Double.pi * innerDiameterMillimetres
    }

    public static var allOfferedSizes: [FingerSize] {
        var sizes: [FingerSize] = []
        var size = offeredRange.lowerBound
        while size <= offeredRange.upperBound + 1e-9 {
            sizes.append(FingerSize(usSize: size))
            size += 0.25
        }
        return sizes
    }
}

// MARK: - A chosen stone

/// The customer's choice for one of a design's gem slots.
public struct GemSelection: Codable, Hashable, Identifiable, Sendable {
    public var slotIndex: Int
    public var role: GemRole
    public var material: GemMaterial
    public var shape: GemShape
    public var colourID: String
    public var qualityID: String
    public var carat: Double
    /// Set when the customer typed a weight rather than accepting the design's
    /// suggestion. The gem report calls these out separately.
    public var manualSize: Bool
    /// The design's graph index for this slot, carried through so a selection
    /// can still be addressed after the graph is rebuilt.
    public var graphicIndex: Int

    public var id: Int { slotIndex }

    public init(
        slotIndex: Int,
        role: GemRole,
        material: GemMaterial,
        shape: GemShape,
        colourID: String,
        qualityID: String,
        carat: Double,
        manualSize: Bool,
        graphicIndex: Int
    ) {
        self.slotIndex = slotIndex
        self.role = role
        self.material = material
        self.shape = shape
        self.colourID = colourID
        self.qualityID = qualityID
        self.carat = carat
        self.manualSize = manualSize
        self.graphicIndex = graphicIndex
    }

    public var caratText: String {
        String(format: "%.2f ct", carat)
    }

    public var isQuarterCarat: Bool {
        CaratRounding.isQuarterCarat(carat)
    }

    public func with(carat: Double, manual: Bool) -> GemSelection {
        var copy = self
        copy.carat = carat
        copy.manualSize = manual
        return copy
    }
}

// MARK: - Freehand

/// The kind of component a freehand edit touches.
public enum FreehandPartKind: String, Codable, CaseIterable, Hashable, Sendable {
    case curve
    case valueChooser
    case handle

    public var displayName: String {
        switch self {
        case .curve: return "Curve"
        case .valueChooser: return "Value chooser"
        case .handle: return "Handle"
        }
    }
}

/// One editable component of a freehand edit.
public struct FreehandPart: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: FreehandPartKind
    public var isVisible: Bool
    public var controlPoints: [Vector2]

    public init(
        id: String,
        name: String,
        kind: FreehandPartKind,
        isVisible: Bool = true,
        controlPoints: [Vector2] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isVisible = isVisible
        self.controlPoints = controlPoints
    }
}

/// The freehand editing state: which components are editable, whether they
/// share a centre, how large their handles draw, and the value chooser.
public struct FreehandState: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var commonCentreMode: Bool
    public var handleDrawScale: Double
    public var valueChooserValue: Double
    public var parts: [FreehandPart]

    public init(
        isEnabled: Bool,
        commonCentreMode: Bool = false,
        handleDrawScale: Double = 1,
        valueChooserValue: Double = 0,
        parts: [FreehandPart] = []
    ) {
        self.isEnabled = isEnabled
        self.commonCentreMode = commonCentreMode
        self.handleDrawScale = handleDrawScale
        self.valueChooserValue = valueChooserValue
        self.parts = parts
    }

    public static let disabled = FreehandState(isEnabled: false)

    /// A freehand editing state over the shank's top curve, which is the part a
    /// jeweller actually adjusts by hand.
    public static func standard() -> FreehandState {
        FreehandState(
            isEnabled: true,
            commonCentreMode: false,
            handleDrawScale: 1,
            valueChooserValue: 0.5,
            parts: [
                FreehandPart(
                    id: "freehand.shankCurve",
                    name: "Shank top curve",
                    kind: .curve,
                    controlPoints: [
                        Vector2(-4, 0), Vector2(-2, 0.6), Vector2(0, 0.9),
                        Vector2(2, 0.6), Vector2(4, 0)
                    ]
                ),
                FreehandPart(
                    id: "freehand.headHeight",
                    name: "Head height",
                    kind: .valueChooser
                )
            ]
        )
    }

    public mutating func setVisibility(_ isVisible: Bool, ofPartNamed name: String) {
        for index in parts.indices where parts[index].name == name || parts[index].id == name {
            parts[index].isVisible = isVisible
        }
    }

    public var visibleParts: [FreehandPart] {
        parts.filter(\.isVisible)
    }

    public var hasCurves: Bool {
        parts.contains { $0.kind == .curve }
    }
}

// MARK: - Gem report

/// One row of the gem report the original showed the user: every stone, in
/// slot order, with its size and material.
public struct GemReportLine: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var index: Int
    public var slotIndex: Int
    public var role: GemRole
    public var shape: GemShape
    public var material: GemMaterial
    public var colourID: String
    public var qualityID: String
    public var carat: Double
    public var girdleWidthMillimetres: Double
    public var isManualSize: Bool

    public init(
        id: Int,
        index: Int,
        slotIndex: Int,
        role: GemRole,
        shape: GemShape,
        material: GemMaterial,
        colourID: String,
        qualityID: String,
        carat: Double,
        girdleWidthMillimetres: Double,
        isManualSize: Bool
    ) {
        self.id = id
        self.index = index
        self.slotIndex = slotIndex
        self.role = role
        self.shape = shape
        self.material = material
        self.colourID = colourID
        self.qualityID = qualityID
        self.carat = carat
        self.girdleWidthMillimetres = girdleWidthMillimetres
        self.isManualSize = isManualSize
    }

    public var caratText: String {
        String(format: "%.2f ct", carat)
    }

    public var sizeText: String {
        String(format: "%.2f mm", girdleWidthMillimetres)
    }

    public var description: String {
        let manual = isManualSize ? " (manual size)" : ""
        return "#\(index) \(role.displayName) - \(material.displayName) "
            + "\(shape.displayName), \(caratText), \(sizeText)\(manual)"
    }
}

// MARK: - Configuration

/// Everything the customer chose, for one design.
public struct Configuration: Codable, Hashable, Sendable {

    public var id: String
    public var designID: DesignID
    public var iterationIndex: Int
    public var metal1: Metal
    public var metal2: Metal?
    public var gems: [GemSelection]
    public var fingerSize: FingerSize
    public var quarterCaratRounding: Bool
    public var freehand: FreehandState
    public var highlightedGemSlots: Set<Int>

    public init(
        id: String,
        designID: DesignID,
        iterationIndex: Int = 0,
        metal1: Metal,
        metal2: Metal? = nil,
        gems: [GemSelection],
        fingerSize: FingerSize = .defaultValue,
        quarterCaratRounding: Bool = true,
        freehand: FreehandState = .disabled,
        highlightedGemSlots: Set<Int> = []
    ) {
        self.id = id
        self.designID = designID
        self.iterationIndex = iterationIndex
        self.metal1 = metal1
        self.metal2 = metal2
        self.gems = gems
        self.fingerSize = fingerSize
        self.quarterCaratRounding = quarterCaratRounding
        self.freehand = freehand
        self.highlightedGemSlots = highlightedGemSlots
    }

    // MARK: Derived

    public var centreGem: GemSelection? {
        gems.first { $0.role == .centre } ?? gems.first
    }

    public var centreCarat: Double? {
        centreGem?.carat
    }

    public var accentGems: [GemSelection] {
        let centreSlot = centreGem?.slotIndex
        return gems.filter { $0.slotIndex != centreSlot }
    }

    public var totalCaratWeight: Double {
        gems.reduce(0) { $0 + $1.carat }
    }

    public var isTwoTone: Bool { metal2 != nil }

    public var metals: [Metal] {
        metal2.map { [metal1, $0] } ?? [metal1]
    }

    public var accentGemCount: Int {
        gems.filter { $0.role != .centre }.count
    }

    // MARK: Mutation

    public mutating func clearHighlights() {
        highlightedGemSlots = []
    }

    /// Snaps the centre stone to quarter-carat steps when rounding is on.
    ///
    /// Only the centre stone: accents come from the design and a change there
    /// would change the design rather than the customer's choice.
    public mutating func applyCaratRounding() {
        guard quarterCaratRounding,
              let index = gems.firstIndex(where: { $0.role == .centre }) else { return }
        gems[index].carat = CaratRounding.rounded(gems[index].carat, enabled: true)
    }

    public mutating func setCarat(_ carat: Double, forSlotIndex slotIndex: Int, manual: Bool = true) {
        guard let index = gems.firstIndex(where: { $0.slotIndex == slotIndex }) else { return }
        gems[index].carat = Swift.max(0.001, carat)
        gems[index].manualSize = manual
    }

    /// Selects a different shape for the centre stone, keeping the weight.
    public mutating func setCentreShape(_ shape: GemShape) {
        guard let index = gems.firstIndex(where: { $0.role == .centre }) else { return }
        gems[index].shape = shape
    }

    // MARK: Validation

    /// Everything wrong with this configuration, in a stable order. An empty
    /// array means the engine will accept it.
    ///
    /// These are the invariants the recovered backend enforced through its own
    /// validation, restated so a bad configuration can never reach the geometry
    /// kernel: a ring with no centre stone, two centre stones, a negative
    /// weight, an unsolderable metal pair, or a ring size no mandrel makes.
    public var validationIssues: [String] {
        var issues: [String] = []

        if gems.isEmpty {
            issues.append("The configuration has no stones.")
        }

        if !gems.contains(where: { $0.role == .centre }) {
            issues.append("The configuration has no centre stone.")
        }

        let centreCount = gems.filter { $0.role == .centre }.count
        if centreCount > 1 {
            issues.append("The configuration has \(centreCount) centre stones; a ring has one.")
        }

        if Set(gems.map(\.slotIndex)).count != gems.count {
            issues.append("Two stones share the same slot.")
        }

        for stone in gems where !(stone.carat > 0) {
            issues.append("Stone at slot \(stone.slotIndex) has a non-positive weight.")
        }

        for stone in gems where stone.carat > 30 {
            issues.append("Stone at slot \(stone.slotIndex) exceeds the largest size offered.")
        }

        if let metal2, !metal1.canPair(with: metal2) {
            issues.append("\(metal1.displayName) cannot be paired with \(metal2.displayName).")
        }

        if !fingerSize.isWithinOfferedRange {
            issues.append("Ring size \(fingerSize.displayText) is outside the offered range.")
        }

        if !(fingerSize.innerDiameterMillimetres > 0) {
            issues.append("The ring size has a non-positive inside diameter.")
        }

        if !freehand.handleDrawScale.isFinite || freehand.handleDrawScale <= 0 {
            issues.append("The freehand handle scale must be positive.")
        }

        for part in freehand.parts where !part.controlPoints.allSatisfy(\.isFinite) {
            issues.append("Freehand component \(part.name) has a non-finite control point.")
        }

        return issues
    }

    public var isValid: Bool { validationIssues.isEmpty }
}
