//
//  CatalogTests.swift
//  JewelcraftKitTests
//
//  The search algebra and the catalogue's structural rules.
//
//  The recovered `SearchHelper` combined alternatives within a facet group with
//  OR and different groups with AND. That is the behaviour customers relied on
//  ("solitaire *or* three-stone, in *white gold*"), so it is tested directly
//  rather than inferred from a screen.
//

import XCTest
@testable import JewelcraftKit

final class CatalogTests: XCTestCase {

    private let catalog = CatalogService(index: CatalogFixtures.makeIndex())

    func testCatalogueHasNoStructuralProblems() {
        XCTAssertEqual(CatalogFixtures.integrityIssues(), [])
        XCTAssertEqual(GemFixtures.integrityIssues(), [])
        XCTAssertEqual(MaterialFixtures.integrityIssues(), [])
        XCTAssertEqual(RateTableFixtures.coverageIssues(), [])

        let issues = catalog.integrityIssues()
        XCTAssertEqual(issues, [], issues.joined(separator: "; "))
    }

    func testEveryDesignIsInternallyConsistent() {
        for design in catalog.allDesigns {
            XCTAssertEqual(design.integrityIssues, [], design.id.rawValue)
            XCTAssertGreaterThanOrEqual(design.gemSlots.count, 1)
            XCTAssertTrue(design.summary.centreGemCaratRange.contains(design.suggestedCentreCarat))
            XCTAssertTrue(design.summary.supportedCentreShapes.contains(design.centreSlot?.defaultShape ?? .roundBrilliant))
            XCTAssertFalse(design.longDescription.isEmpty)
        }
    }

    func testEmptyFilterReturnsTheWholeCatalogue() {
        XCTAssertEqual(catalog.search(.empty).count, catalog.allDesigns.count)
        XCTAssertEqual(catalog.allBaseRingDesigns().count, catalog.allDesigns.count)
    }

    func testAlternativesWithinAGroupAreOredAndGroupsAreAnded() {
        var filter = DesignFilter.empty
        filter.select(FacetItemID("rt.solitaire"), in: .ringType)
        let solitaires = catalog.search(filter)
        XCTAssertFalse(solitaires.isEmpty)
        XCTAssertTrue(solitaires.allSatisfy { $0.baseRingType == .solitaire })

        filter.select(FacetItemID("rt.halo"), in: .ringType)
        let solitairesOrHalos = catalog.search(filter)
        XCTAssertGreaterThan(solitairesOrHalos.count, solitaires.count)
        XCTAssertTrue(solitairesOrHalos.allSatisfy { $0.baseRingType == .solitaire || $0.baseRingType == .halo })

        // Adding a *different* group narrows rather than widens.
        filter.select(FacetItemID("mt.yellowGold"), in: .metal)
        let narrowed = catalog.search(filter)
        XCTAssertLessThanOrEqual(narrowed.count, solitairesOrHalos.count)
        XCTAssertTrue(narrowed.allSatisfy { $0.metalIDs.contains("gold-14k-yellow") || $0.metalIDs.contains("gold-18k-yellow") })
    }

    func testSelectingAndDeselectingIsSymmetric() {
        var filter = DesignFilter.empty
        XCTAssertTrue(filter.isEmpty)

        filter.select(FacetItemID("st.vintage"), in: .style)
        XCTAssertEqual(filter.selectedFacetCount, 1)
        XCTAssertFalse(catalog.search(filter).isEmpty)

        filter.deselect(FacetItemID("st.vintage"), in: .style)
        XCTAssertTrue(filter.isEmpty)
        XCTAssertEqual(catalog.search(filter).count, catalog.allDesigns.count)
    }

    func testFacetDescriptorsCountTheOtherGroupsAndIgnoreTheirOwn() {
        var filter = DesignFilter.empty
        filter.select(FacetItemID("rt.solitaire"), in: .ringType)

        let types = catalog.descriptors(for: .ringType, within: filter)
        XCTAssertEqual(types.count, 8)
        // The selected type is still reported as selected and still countable.
        let solitaire = try? XCTUnwrap(types.first { $0.id == FacetItemID("rt.solitaire") })
        XCTAssertEqual(solitaire?.isSelected, true)
        XCTAssertGreaterThan(solitaire?.resultCount ?? 0, 0)

        // A metal facet's count reflects the ring-type selection (AND across
        // groups) but ignores any metal selection of its own.
        let metals = catalog.descriptors(for: .metal, within: filter)
        XCTAssertEqual(metals.count, 6)
        XCTAssertTrue(metals.allSatisfy { $0.resultCount >= 0 && $0.isAvailable == ($0.resultCount > 0) })
    }

    func testKeywordSearchRequiresEveryToken() {
        let all = catalog.designs(keyword: "solitaire")
        XCTAssertFalse(all.isEmpty)
        XCTAssertTrue(all.allSatisfy { $0.baseRingType == .solitaire })

        let twoTokens = catalog.designs(keyword: "solitaire yellow")
        XCTAssertLessThan(twoTokens.count, all.count)
        XCTAssertTrue(twoTokens.allSatisfy { $0.keywords.contains("yellow gold") || $0.metalIDs.contains("gold-14k-yellow") })

        XCTAssertEqual(catalog.designs(keyword: "   ").count, catalog.allDesigns.count)
        XCTAssertTrue(catalog.designs(keyword: "no-such-design-anywhere").isEmpty)
    }

    func testCatalogueNumberLookupToleratesSpacingAndCase() {
        let design = catalog.design(id: DesignID("JWL-1007"))
        let spin = design?.summary.spinNumber.rawValue ?? ""
        XCTAssertNotNil(catalog.design(spinNumber: SpinNumber(spin)))
        XCTAssertEqual(catalog.design(matchingCatalogueNumber: spin.lowercased())?.id, DesignID("JWL-1007"))
        XCTAssertEqual(catalog.design(matchingCatalogueNumber: " jwl 1007 ")?.id, DesignID("JWL-1007"))
        XCTAssertNil(catalog.design(matchingCatalogueNumber: ""))
    }

    func testPackagesAndCollectionsResolveBothWays() {
        for package in catalog.packages {
            let members = catalog.designs(inPackage: package.name)
            XCTAssertEqual(members.count, package.designIDs.count)
            XCTAssertEqual(Set(members.map(\.id)), Set(package.designIDs))
            XCTAssertFalse(catalog.packageAttributes(forDesignID: members[0].id).isEmpty)
        }

        for collection in catalog.collections {
            let members = catalog.designs(inCollection: collection.id)
            XCTAssertFalse(members.isEmpty, collection.id.rawValue)
            XCTAssertTrue(members.allSatisfy { $0.collectionIDs.contains(collection.id) })
        }

        let packaged = catalog.packagedDesigns()
        XCTAssertEqual(packaged.count, catalog.allDesigns.count, "every design belongs to a package")
    }

    func testRefilterTrimsByCentreStoneSizeAndShape() {
        let all = catalog.allBaseRingDesigns()
        let twoCarat = catalog.refilter(all, usingCentreGemCarat: 2.0)
        XCTAssertLessThan(twoCarat.count, all.count)
        XCTAssertTrue(twoCarat.allSatisfy { $0.supportsCentreCarat(2.0) })

        let emerald = catalog.refilter(all, usingCentreGemCarat: 1.0, shape: .emerald)
        XCTAssertTrue(emerald.allSatisfy { $0.supportsCentreShape(.emerald) && $0.supportsCentreCarat(1.0) })
    }

    func testCentreGemHandleIsExposedBothWays() {
        for summary in catalog.allSummaries {
            let index = catalog.centreGemControlGraphIndex(for: summary)
            XCTAssertNotNil(index)
            XCTAssertEqual(catalog.centreGemGraphIndex(forDesignID: summary.id), index)
            XCTAssertNotNil(catalog.centreGemGUID(forDesignID: summary.id))
        }
    }

    func testEveryFacetGroupIsPresentAndPopulated() {
        for group in FacetGroup.allCases {
            XCTAssertFalse(catalog.facetItems(in: group).isEmpty, group.rawValue)
        }
        XCTAssertEqual(catalog.facetGroups.count, FacetGroup.allCases.count)
        XCTAssertFalse(catalog.allKeywordsAvailable.isEmpty)
        XCTAssertFalse(catalog.keywords(matching: "sol").isEmpty)
    }
}
