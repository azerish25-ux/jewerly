//
//  CatalogService.swift
//  JewelcraftKit
//
//  The catalogue, its curated entry points and its facet algebra.
//
//  The recovered search helper exposed 27 operations by name. Reading them as a
//  specification rather than as a list of methods gives this file its shape:
//  designs come from collections and packages as well as direct searches;
//  results are narrowed by facet items; a centre-gem size re-filters what is
//  left; and a design is reachable by internal id, catalogue number and package
//  name. Every one of those is implemented here and covered by a test that names
//  the recovered operation it stands in for.
//
//  The facet algebra is the part worth getting exactly right. Selecting two
//  metals means "either", selecting a metal and a style means "both". That is
//  OR within a group and AND across groups, and it is why selections are stored
//  grouped rather than as one flat set.
//

import Foundation

/// A loaded catalogue.
public struct CatalogIndex: Codable, Sendable {
    public var schemaVersion: Int
    public var designs: [DesignDetail]
    public var collections: [Collection]
    public var packages: [DesignPackage]
    public var facets: [FacetItem]

    public init(
        schemaVersion: Int,
        designs: [DesignDetail],
        collections: [Collection],
        packages: [DesignPackage],
        facets: [FacetItem]
    ) {
        self.schemaVersion = schemaVersion
        self.designs = designs
        self.collections = collections
        self.packages = packages
        self.facets = facets
    }
}

public final class CatalogService {

    public let index: CatalogIndex

    private let designsByID: [DesignID: DesignDetail]
    private let designsBySpin: [SpinNumber: DesignDetail]
    private let facetsByID: [FacetItemID: FacetItem]
    private let facetsByGroup: [FacetGroup: [FacetItem]]
    private let facetsByDesign: [DesignID: [FacetGroup: Set<FacetItemID>]]
    private let collectionsByID: [CollectionID: Collection]
    private let packagesByName: [String: DesignPackage]
    private let allKeywords: [String]

    public init(index: CatalogIndex) {
        self.index = index

        var byID: [DesignID: DesignDetail] = [:]
        var bySpin: [SpinNumber: DesignDetail] = [:]
        var designFacets: [DesignID: [FacetGroup: Set<FacetItemID>]] = [:]
        let facetLookup = Dictionary(
            index.facets.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for design in index.designs {
            byID[design.id] = design
            bySpin[design.summary.spinNumber] = design

            var grouped: [FacetGroup: Set<FacetItemID>] = [:]
            for itemID in design.summary.facetItemIDs {
                guard let item = facetLookup[itemID] else { continue }
                grouped[item.group, default: []].insert(itemID)
            }
            designFacets[design.id] = grouped
        }

        self.designsByID = byID
        self.designsBySpin = bySpin
        self.facetsByID = facetLookup
        self.facetsByDesign = designFacets

        var byGroup: [FacetGroup: [FacetItem]] = [:]
        for group in FacetGroup.allCases {
            byGroup[group] = index.facets.filter { $0.group == group }
        }
        self.facetsByGroup = byGroup

        self.collectionsByID = Dictionary(
            index.collections.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.packagesByName = Dictionary(
            index.packages.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var keywordSet = Set<String>()
        for design in index.designs {
            keywordSet.insert(design.summary.name.lowercased())
            for keyword in design.summary.keywords {
                keywordSet.insert(keyword.lowercased())
            }
        }
        self.allKeywords = keywordSet.sorted()
    }

    /// Loads the catalogue that ships with the package.
    public static func loadFromBundle(_ bundle: Bundle? = nil) throws -> CatalogService {
        let index: CatalogIndex = try FixtureBundle.decode("catalog", from: bundle)
        return CatalogService(index: index)
    }

    // MARK: - Lookup

    public var allDesigns: [DesignDetail] { index.designs }

    public var allSummaries: [DesignSummary] { index.designs.map(\.summary) }

    public var collections: [Collection] { index.collections }

    public var packages: [DesignPackage] { index.packages }

    public var allFacetItems: [FacetItem] { index.facets }

    public var facetGroups: [FacetGroup] {
        FacetGroup.allCases.filter { !(facetsByGroup[$0] ?? []).isEmpty }
    }

    public func facetItems(in group: FacetGroup) -> [FacetItem] {
        facetsByGroup[group] ?? []
    }

    public func facetItem(id: FacetItemID) -> FacetItem? {
        facetsByID[id]
    }

    public func design(id: DesignID) -> DesignDetail? {
        designsByID[id]
    }

    public func design(spinNumber: SpinNumber) -> DesignDetail? {
        designsBySpin[spinNumber]
    }

    /// Finds a design by a catalogue number the customer typed, tolerating
    /// spacing and case.
    public func design(matchingCatalogueNumber text: String) -> DesignDetail? {
        let normalised = Self.normaliseCatalogueNumber(text)
        guard !normalised.isEmpty else { return nil }
        if let exact = designsBySpin[SpinNumber(normalised)] {
            return exact
        }
        return index.designs.first {
            Self.normaliseCatalogueNumber($0.summary.spinNumber.rawValue) == normalised
        }
    }

    public func collection(id: CollectionID) -> Collection? {
        collectionsByID[id]
    }

    public func package(named name: String) -> DesignPackage? {
        packagesByName[name]
    }

    // MARK: - Curated entry points

    /// Every design in the catalogue, which is what the "all base rings" entry
    /// point returned.
    public func allBaseRingDesigns() -> [DesignSummary] {
        sorted(index.designs.map(\.summary))
    }

    public func designs(ofType type: BaseRingType) -> [DesignSummary] {
        sorted(index.designs.map(\.summary).filter { $0.baseRingType == type })
    }

    public func designs3C() -> [DesignSummary] { designs(ofType: .threeC) }
    public func threeStoneDesigns() -> [DesignSummary] { designs(ofType: .threeStone) }
    public func everAndEverDesigns() -> [DesignSummary] { designs(ofType: .everAndEver) }
    public func mensDesigns() -> [DesignSummary] { designs(ofType: .mens) }
    public func pendantDesigns() -> [DesignSummary] { designs(ofType: .pendant) }

    public func designs(inCollection collectionID: CollectionID) -> [DesignSummary] {
        sorted(index.designs.map(\.summary).filter { $0.collectionIDs.contains(collectionID) })
    }

    /// Designs in a named package. The recovered API also had a "packaged
    /// designs" list, which is every design that is in any package.
    public func designs(inPackage name: String) -> [DesignSummary] {
        if let package = packagesByName[name] {
            let members = Set(package.designIDs)
            let byPackageMembership = sorted(index.designs.map(\.summary).filter { members.contains($0.id) })
            if !byPackageMembership.isEmpty {
                return byPackageMembership
            }
        }
        return sorted(index.designs.map(\.summary).filter { $0.packageNames.contains(name) })
    }

    public func packagedDesigns() -> [DesignSummary] {
        sorted(index.designs.map(\.summary).filter { !$0.packageNames.isEmpty })
    }

    public func designs(keyword text: String) -> [DesignSummary] {
        let query = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allBaseRingDesigns() }
        let tokens = query.split(separator: " ").map(String.init)
        return sorted(index.designs.map(\.summary).filter { design in
            let haystack = Self.searchableText(for: design)
            return tokens.allSatisfy { haystack.contains($0) }
        })
    }

    public func keywords(matching prefix: String) -> [String] {
        let query = prefix.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allKeywords }
        return allKeywords.filter { $0.contains(query) }
    }

    public var allKeywordsAvailable: [String] { allKeywords }

    /// The package attributes a design carries, which the recovered API
    /// surfaced alongside package search results.
    public func packageAttributes(forDesignID id: DesignID) -> [String: String] {
        guard let design = designsByID[id] else { return [:] }
        var attributes: [String: String] = [:]
        for name in design.summary.packageNames {
            guard let package = packagesByName[name] else { continue }
            for (key, value) in package.attributes {
                attributes[key] = value
            }
        }
        return attributes
    }

    // MARK: - Search

    /// Narrow the catalogue by a filter.
    public func search(_ filter: DesignFilter) -> [DesignSummary] {
        guard !filter.isEmpty else { return allBaseRingDesigns() }
        return sorted(index.designs.map(\.summary).filter { matches($0, filter: filter) })
    }

    /// Whether one design satisfies a filter.
    public func matches(_ summary: DesignSummary, filter: DesignFilter) -> Bool {
        // Facet groups: alternatives within a group are OR-ed, groups are AND-ed.
        let designFacets = facetsByDesign[summary.id] ?? [:]
        for (group, selected) in filter.selections where !selected.isEmpty {
            let designInGroup = designFacets[group] ?? []
            if designInGroup.isDisjoint(with: selected) {
                return false
            }
        }

        if let collectionID = filter.collectionID, !summary.collectionIDs.contains(collectionID) {
            return false
        }
        if let packageName = filter.packageName, !summary.packageNames.contains(packageName) {
            return false
        }
        if !filter.baseRingTypes.isEmpty, !filter.baseRingTypes.contains(summary.baseRingType) {
            return false
        }
        if !filter.metalIDs.isEmpty, Set(summary.metalIDs).isDisjoint(with: filter.metalIDs) {
            return false
        }
        if let carat = filter.centreGemCarat, !summary.supportsCentreCarat(carat) {
            return false
        }
        if let shape = filter.centreShape, !summary.supportsCentreShape(shape) {
            return false
        }
        if let keyword = filter.keyword {
            let query = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let tokens = query.split(separator: " ").map(String.init)
                let haystack = Self.searchableText(for: summary)
                if !tokens.allSatisfy({ haystack.contains($0) }) {
                    return false
                }
            }
        }

        return true
    }

    /// Facets for a group, with the result count each would give.
    ///
    /// The count for a facet is computed with the *other* groups' selections
    /// applied and its own group's selection ignored, which is what lets a
    /// facet list show "Yellow gold (12)" while yellow gold is already selected
    /// and "White gold (9)" as a real alternative rather than as an empty set.
    public func descriptors(for group: FacetGroup, within filter: DesignFilter) -> [FacetDescriptor] {
        let base = filter.removingSelection(in: group)
        let selectedInGroup = filter.selected(in: group)

        return facetItems(in: group).map { item in
            var candidate = base
            candidate.select(item.id, in: group)
            let count = search(candidate).count
            return FacetDescriptor(
                id: item.id,
                item: item,
                isSelected: selectedInGroup.contains(item.id),
                resultCount: count,
                isAvailable: count > 0
            )
        }
    }

    /// Re-filters an existing result set by centre gem size, the recovered
    /// `UpdateResultsUsingCenterGemSize` operation.
    ///
    /// Kept separate from `search` because it operates on a result set that is
    /// already on screen: the original used it to trim visible results as the
    /// customer moved the centre-stone size, without rebuilding the whole query.
    public func refilter(
        _ results: [DesignSummary],
        usingCentreGemCarat carat: Double,
        shape: GemShape? = nil
    ) -> [DesignSummary] {
        results.filter { summary in
            guard summary.supportsCentreCarat(carat) else { return false }
            if let shape {
                return summary.supportsCentreShape(shape)
            }
            return true
        }
    }

    /// The centre-gem graph index for a design, the handle the original exposed
    /// so the client could address the centre stone's control directly.
    public func centreGemGraphIndex(forDesignID id: DesignID) -> Int? {
        designsByID[id]?.centreGemGraphIndex
    }

    public func centreGemGUID(forDesignID id: DesignID) -> String? {
        designsByID[id]?.centreGemGUID
    }

    /// The centre gem's control graph index, resolved from a summary, as the
    /// recovered helper did.
    public func centreGemControlGraphIndex(for summary: DesignSummary) -> Int? {
        designsByID[summary.id]?.centreGemGraphIndex
    }

    // MARK: - Integrity

    /// Problems with the catalogue as a whole. Run against the shipped fixtures
    /// by the test suite so a malformed design cannot reach a customer.
    public func integrityIssues() -> [String] {
        var issues: [String] = []

        let metalCatalog = StandardMetals.catalog

        for design in index.designs {
            issues.append(contentsOf: design.integrityIssues)
            for itemID in design.summary.facetItemIDs where facetsByID[itemID] == nil {
                issues.append("design \(design.id.rawValue) references unknown facet \(itemID.rawValue)")
            }
            for metalID in design.summary.metalIDs where metalCatalog.metal(id: metalID) == nil {
                issues.append("design \(design.id.rawValue) offers unknown metal \(metalID)")
            }
            for collectionID in design.summary.collectionIDs where collectionsByID[collectionID] == nil {
                issues.append("design \(design.id.rawValue) references unknown collection \(collectionID.rawValue)")
            }
            for packageName in design.summary.packageNames where packagesByName[packageName] == nil {
                issues.append("design \(design.id.rawValue) references unknown package \(packageName)")
            }
        }

        if Set(index.designs.map(\.id)).count != index.designs.count {
            issues.append("catalogue contains duplicate design ids")
        }
        if Set(index.designs.map(\.summary.spinNumber)).count != index.designs.count {
            issues.append("catalogue contains duplicate catalogue numbers")
        }
        if Set(index.facets.map(\.id)).count != index.facets.count {
            issues.append("catalogue contains duplicate facet ids")
        }

        for package in index.packages {
            for designID in package.designIDs where designsByID[designID] == nil {
                issues.append("package \(package.name) references unknown design \(designID.rawValue)")
            }
        }

        // Every facet should be reachable, or the UI offers a dead end.
        let usedFacets = Set(index.designs.flatMap(\.summary.facetItemIDs))
        for facet in index.facets where !usedFacets.contains(facet.id) {
            issues.append("facet \(facet.id.rawValue) is not used by any design")
        }

        return issues
    }

    // MARK: - Helpers

    private func sorted(_ summaries: [DesignSummary]) -> [DesignSummary] {
        summaries.sorted { lhs, rhs in
            if lhs.spinNumber.rawValue == rhs.spinNumber.rawValue {
                return lhs.id.rawValue < rhs.id.rawValue
            }
            return lhs.spinNumber.rawValue < rhs.spinNumber.rawValue
        }
    }

    private static func searchableText(for summary: DesignSummary) -> String {
        var parts = [summary.name, summary.spinNumber.rawValue, summary.baseRingType.rawValue]
        parts.append(contentsOf: summary.keywords)
        parts.append(contentsOf: summary.packageNames)
        return parts.joined(separator: " ").lowercased()
    }

    private static func normaliseCatalogueNumber(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
