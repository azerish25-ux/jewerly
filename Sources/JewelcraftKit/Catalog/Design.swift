//
//  Design.swift
//  JewelcraftKit
//
//  Catalogue domain: designs, collections, packages, facets and the search
//  filter.
//
//  A design is addressable three ways here, exactly as it was in the original:
//  by an internal id, by a SPIN-style catalogue number, and by the package it
//  belongs to. The recovered search surface exposed all three, and a rebuild
//  that only supports one of them cannot answer the questions the original
//  answered — "what is in this package", "find SPIN 12345", "show me the
//  three-stone designs" are three different entry points into one catalogue.
//
//  The facet model is the other half. In the original, search results were
//  narrowed by facet items whose thumbnails shipped as resources, and the
//  centre-gem size re-filtered the result set. Facet selections are kept
//  *grouped* here, because the filter's algebra depends on it: alternatives
//  within a group are OR-ed, and separate groups are AND-ed. Getting that
//  grouping wrong is the difference between "yellow or white gold" and "yellow
//  gold and white gold at once", which is no ring at all.
//

import Foundation

// MARK: - Identifiers

/// A type whose identity is a stable string, encoded as a bare JSON string so
/// fixtures stay readable and diffs stay reviewable.
public protocol StringIdentifiable: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible
where RawValue == String {
    init(rawValue: String)
}

extension StringIdentifiable {
    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

public struct DesignID: StringIdentifiable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// The catalogue number a customer would quote over the phone.
public struct SpinNumber: StringIdentifiable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct CollectionID: StringIdentifiable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct FacetItemID: StringIdentifiable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - Classification

/// The broad families the catalogue is navigated by. These are the curated entry
/// points the recovered search exposed by name.
public enum BaseRingType: String, Codable, CaseIterable, Sendable {
    case solitaire
    case threeStone
    case threeC
    case everAndEver
    case mens
    case pendant
    case band
    case halo

    public var displayName: String {
        switch self {
        case .solitaire: return "Solitaire"
        case .threeStone: return "Three stone"
        case .threeC: return "Three-stone 3C"
        case .everAndEver: return "Ever and ever"
        case .mens: return "Men's"
        case .pendant: return "Pendant"
        case .band: return "Band"
        case .halo: return "Halo"
        }
    }
}

/// The groups facets are offered in.
public enum FacetGroup: String, Codable, CaseIterable, Hashable, Sendable {
    case designElement
    case gemSetting
    case gemColor
    case metal
    case style
    case ringType

    public var displayName: String {
        switch self {
        case .designElement: return "Design element"
        case .gemSetting: return "Gem setting"
        case .gemColor: return "Gem colour"
        case .metal: return "Metal"
        case .style: return "Style"
        case .ringType: return "Ring type"
        }
    }

    /// The order facets are presented in.
    public var presentationOrder: Int {
        FacetGroup.allCases.firstIndex(of: self) ?? 0
    }
}

public struct Collection: Codable, Hashable, Identifiable, Sendable {
    public var id: CollectionID
    public var name: String
    public var summary: String

    public init(id: CollectionID, name: String, summary: String) {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

/// A curated bundle of designs sold together, addressed by name.
public struct DesignPackage: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var designIDs: [DesignID]
    public var attributes: [String: String]

    public init(id: String, name: String, designIDs: [DesignID], attributes: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.designIDs = designIDs
        self.attributes = attributes
    }
}

// MARK: - Facets

/// One selectable facet, with the artwork reference the UI uses for its chip.
public struct FacetItem: Codable, Hashable, Identifiable, Sendable {
    public var id: FacetItemID
    public var group: FacetGroup
    public var name: String
    /// Logical artwork path, mirroring the recovered layout
    /// (`images/search/filteritems/...`). The app draws its own original chip
    /// artwork; this path is the key that artwork is looked up by, so the
    /// mapping lives in data rather than in a view.
    public var artworkPath: String
    /// Value this facet matches on when a query is forwarded to a catalogue
    /// service, so a future remote catalogue gets a stable key rather than a
    /// display label.
    public var queryKey: String

    public init(id: FacetItemID, group: FacetGroup, name: String, artworkPath: String, queryKey: String) {
        self.id = id
        self.group = group
        self.name = name
        self.artworkPath = artworkPath
        self.queryKey = queryKey
    }
}

/// A facet as the UI needs to render it: how many results it would give, and
/// whether it is currently reachable.
public struct FacetDescriptor: Identifiable, Equatable, Sendable {
    public var id: FacetItemID
    public var item: FacetItem
    public var isSelected: Bool
    /// Results if this facet were added to the current filter, ignoring the
    /// selection in its own group.
    public var resultCount: Int
    /// False when selecting this facet would produce no results, which is how a
    /// facet list guides rather than dead-ends.
    public var isAvailable: Bool
}

// MARK: - Design

/// The summary form: what a result tile needs.
public struct DesignSummary: Codable, Hashable, Identifiable, Sendable {
    public var id: DesignID
    public var spinNumber: SpinNumber
    public var name: String
    public var collectionIDs: [CollectionID]
    public var packageNames: [String]
    public var baseRingType: BaseRingType
    /// Metal ids this design may be made in.
    public var metalIDs: [String]
    /// Every facet this design satisfies.
    public var facetItemIDs: [FacetItemID]
    public var keywords: [String]
    public var centreGemCaratMin: Double
    public var centreGemCaratMax: Double
    /// Centre-stone shapes this design is cut for.
    public var supportedCentreShapes: [GemShape]
    public var accentGemCount: Int
    public var labourTier: LabourTier

    public init(
        id: DesignID,
        spinNumber: SpinNumber,
        name: String,
        collectionIDs: [CollectionID],
        packageNames: [String],
        baseRingType: BaseRingType,
        metalIDs: [String],
        facetItemIDs: [FacetItemID],
        keywords: [String],
        centreGemCaratMin: Double,
        centreGemCaratMax: Double,
        supportedCentreShapes: [GemShape],
        accentGemCount: Int,
        labourTier: LabourTier
    ) {
        self.id = id
        self.spinNumber = spinNumber
        self.name = name
        self.collectionIDs = collectionIDs
        self.packageNames = packageNames
        self.baseRingType = baseRingType
        self.metalIDs = metalIDs
        self.facetItemIDs = facetItemIDs
        self.keywords = keywords
        self.centreGemCaratMin = centreGemCaratMin
        self.centreGemCaratMax = centreGemCaratMax
        self.supportedCentreShapes = supportedCentreShapes
        self.accentGemCount = accentGemCount
        self.labourTier = labourTier
    }

    public var centreGemCaratRange: ClosedRange<Double> {
        Swift.min(centreGemCaratMin, centreGemCaratMax)...Swift.max(centreGemCaratMin, centreGemCaratMax)
    }

    /// Whether this design can be built around a centre stone of this size.
    public func supportsCentreCarat(_ carat: Double) -> Bool {
        centreGemCaratRange.contains(carat)
    }

    public func supportsCentreShape(_ shape: GemShape) -> Bool {
        supportedCentreShapes.contains(shape)
    }

    /// Tile keys, at the sizes the original renderer produced.
    public var tileKeys: [String] {
        [RenderTarget.catalogTileWide.key(for: id), RenderTarget.catalogTileSquare.key(for: id)]
    }
}

/// One stone position a design defines.
public struct GemSlot: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var role: GemRole
    public var graphIndex: Int
    /// The material this slot is designed around. A blue centre suggests a
    /// sapphire, not a dyed diamond, so the catalogue decides it rather than
    /// the configurator guessing.
    public var defaultMaterial: GemMaterial
    public var defaultShape: GemShape
    public var defaultColourID: String
    public var defaultQualityID: String
    public var defaultCarat: Double
    public var supportsManualSize: Bool

    public init(
        id: Int,
        role: GemRole,
        graphIndex: Int,
        defaultMaterial: GemMaterial = .diamond,
        defaultShape: GemShape,
        defaultColourID: String,
        defaultQualityID: String,
        defaultCarat: Double,
        supportsManualSize: Bool
    ) {
        self.id = id
        self.role = role
        self.graphIndex = graphIndex
        self.defaultMaterial = defaultMaterial
        self.defaultShape = defaultShape
        self.defaultColourID = defaultColourID
        self.defaultQualityID = defaultQualityID
        self.defaultCarat = defaultCarat
        self.supportsManualSize = supportsManualSize
    }

    public var supportsQuarterCaratSteps: Bool {
        role == .centre && supportsManualSize
    }
}

/// The full form: what the configurator and the geometry kernel need.
public struct DesignDetail: Codable, Hashable, Identifiable, Sendable {
    public var summary: DesignSummary
    public var gemSlots: [GemSlot]
    /// The graph index of the centre stone's control, which the recovered
    /// search exposed so the client could address it directly.
    public var centreGemGraphIndex: Int
    /// The GUID of the centre stone's control, the original's other handle on it.
    public var centreGemGUID: String
    public var accentPattern: AccentPattern
    public var shankProfile: ShankProfileShape
    public var shankWidthMillimetres: Double
    public var shankThicknessMillimetres: Double
    public var shoulderTaperMillimetres: Double
    public var baseWidthTaperFraction: Double
    public var head: HeadSpec
    public var accentMetalWidthMillimetres: Double
    public var suggestedCentreCarat: Double
    public var longDescription: String

    public init(
        summary: DesignSummary,
        gemSlots: [GemSlot],
        centreGemGraphIndex: Int,
        centreGemGUID: String,
        accentPattern: AccentPattern,
        shankProfile: ShankProfileShape,
        shankWidthMillimetres: Double,
        shankThicknessMillimetres: Double,
        shoulderTaperMillimetres: Double,
        baseWidthTaperFraction: Double,
        head: HeadSpec,
        accentMetalWidthMillimetres: Double,
        suggestedCentreCarat: Double,
        longDescription: String
    ) {
        self.summary = summary
        self.gemSlots = gemSlots
        self.centreGemGraphIndex = centreGemGraphIndex
        self.centreGemGUID = centreGemGUID
        self.accentPattern = accentPattern
        self.shankProfile = shankProfile
        self.shankWidthMillimetres = shankWidthMillimetres
        self.shankThicknessMillimetres = shankThicknessMillimetres
        self.shoulderTaperMillimetres = shoulderTaperMillimetres
        self.baseWidthTaperFraction = baseWidthTaperFraction
        self.head = head
        self.accentMetalWidthMillimetres = accentMetalWidthMillimetres
        self.suggestedCentreCarat = suggestedCentreCarat
        self.longDescription = longDescription
    }

    public var id: DesignID { summary.id }

    public var centreSlot: GemSlot? {
        gemSlots.first { $0.role == .centre } ?? gemSlots.first
    }

    public var accentSlots: [GemSlot] {
        let centreID = centreSlot?.id
        return gemSlots.filter { $0.id != centreID }
    }

    /// Consistency problems that would make this record unusable. Checked for
    /// every fixture design by the test suite, because a catalogue with a slot
    /// that points at nothing is a crash waiting for a customer.
    public var integrityIssues: [String] {
        var issues: [String] = []
        if gemSlots.isEmpty {
            issues.append("design \(summary.id.rawValue) defines no gem slots")
        }
        if !gemSlots.contains(where: { $0.role == .centre }) {
            issues.append("design \(summary.id.rawValue) has no centre slot")
        }
        if Set(gemSlots.map(\.id)).count != gemSlots.count {
            issues.append("design \(summary.id.rawValue) has duplicate slot ids")
        }
        if centreGemCaratOutOfRange {
            issues.append("design \(summary.id.rawValue) has a suggested centre weight outside its own range")
        }
        if summary.accentGemCount != accentSlots.count {
            issues.append("design \(summary.id.rawValue) advertises \(summary.accentGemCount) accents but defines \(accentSlots.count) slots")
        }
        if accentPattern.count != summary.accentGemCount {
            issues.append("design \(summary.id.rawValue) accent pattern count disagrees with its summary")
        }
        return issues
    }

    private var centreGemCaratOutOfRange: Bool {
        guard let centre = centreSlot else { return true }
        let range = summary.centreGemCaratRange
        return !range.contains(suggestedCentreCarat) || !range.contains(centre.defaultCarat)
    }
}

// MARK: - Filter

/// A search query.
public struct DesignFilter: Equatable, Codable, Sendable {
    /// Selections grouped by facet group. Within a group the alternatives are
    /// OR-ed; separate groups are AND-ed.
    public var selections: [FacetGroup: Set<FacetItemID>]
    public var collectionID: CollectionID?
    public var packageName: String?
    public var keyword: String?
    public var centreGemCarat: Double?
    public var centreShape: GemShape?
    public var baseRingTypes: Set<BaseRingType>
    public var metalIDs: Set<String>

    public init(
        selections: [FacetGroup: Set<FacetItemID>] = [:],
        collectionID: CollectionID? = nil,
        packageName: String? = nil,
        keyword: String? = nil,
        centreGemCarat: Double? = nil,
        centreShape: GemShape? = nil,
        baseRingTypes: Set<BaseRingType> = [],
        metalIDs: Set<String> = []
    ) {
        self.selections = selections
        self.collectionID = collectionID
        self.packageName = packageName
        self.keyword = keyword
        self.centreGemCarat = centreGemCarat
        self.centreShape = centreShape
        self.baseRingTypes = baseRingTypes
        self.metalIDs = metalIDs
    }

    public static let empty = DesignFilter()

    // MARK: Facet selection

    public func selected(in group: FacetGroup) -> Set<FacetItemID> {
        selections[group] ?? []
    }

    public mutating func select(_ id: FacetItemID, in group: FacetGroup) {
        var set = selections[group] ?? []
        set.insert(id)
        selections[group] = set
    }

    public mutating func deselect(_ id: FacetItemID, in group: FacetGroup) {
        guard var set = selections[group] else { return }
        set.remove(id)
        if set.isEmpty {
            selections.removeValue(forKey: group)
        } else {
            selections[group] = set
        }
    }

    public mutating func toggle(_ id: FacetItemID, in group: FacetGroup) {
        if selected(in: group).contains(id) {
            deselect(id, in: group)
        } else {
            select(id, in: group)
        }
    }

    public var selectedFacetCount: Int {
        selections.values.reduce(0) { $0 + $1.count }
    }

    /// Whether any narrowing is applied at all.
    public var isEmpty: Bool {
        selectedFacetCount == 0
            && collectionID == nil
            && packageName == nil
            && (keyword ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && centreGemCarat == nil
            && centreShape == nil
            && baseRingTypes.isEmpty
            && metalIDs.isEmpty
    }

    /// How many facets of each group are selected, for a summary chip.
    public var selectedCountsByGroup: [FacetGroup: Int] {
        var counts: [FacetGroup: Int] = [:]
        for (group, set) in selections where !set.isEmpty {
            counts[group] = set.count
        }
        return counts
    }

    /// A copy with one group's selection replaced, used when computing facet
    /// counts without the group's own selection interfering.
    public func removingSelection(in group: FacetGroup) -> DesignFilter {
        var copy = self
        copy.selections.removeValue(forKey: group)
        return copy
    }
}
