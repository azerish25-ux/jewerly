//
//  CatalogFixtures.swift
//  JewelcraftKit
//
//  The synthetic catalogue: facets, collections, packages and designs.
//
//  This is the fixture that carries the most recovered *structure*, so it is
//  worth being explicit about what is reproduced and what is invented.
//
//  Reproduced from the reverse engineering:
//    * A design is addressed three ways — an id, a spin (catalogue) number, and
//      a package membership — exactly as the recovered search exposed them.
//    * Facets are grouped, alternatives within a group are OR-ed and groups are
//      AND-ed, which is the search algebra the original's `SearchHelper`
//      implemented. The fixture is shaped so that algebra is observable.
//    * Design types (solitaire, three-stone, three-C, ever-and-ever, men's,
//      pendant, band, halo) exist as first-class categories.
//    * A design owns its gem *slots*, its accent pattern, its shank profile and
//      its head, and the centre stone has both a graph index and a GUID.
//
//  Invented: every design, name, measurement and keyword. No catalogue entry,
//  photograph or model from any commercial product is reproduced.
//

import Foundation

public enum CatalogFixtures {

    public static let fixtureName = "catalog"

    // MARK: - Collections

    public static let collections: [Collection] = [
        Collection(id: CollectionID("col.classic"), name: "Classic",
                   summary: "Proportions that have not needed changing."),
        Collection(id: CollectionID("col.modern"), name: "Modern",
                   summary: "Straight lines, thin rails, and settings that sit low."),
        Collection(id: CollectionID("col.heirloom"), name: "Heirloom",
                   summary: "Milgrain, engraving and heavier shoulders.")
    ]

    // MARK: - Facets

    /// One facet row: group, id, label, artwork key, query key.
    private typealias FacetRow = (FacetGroup, String, String, String)

    private static let ringTypeFacets: [FacetRow] = [
        (.ringType, "rt.solitaire", "Solitaire", "solitaire"),
        (.ringType, "rt.threeStone", "Three stone", "three-stone"),
        (.ringType, "rt.threeC", "Three C", "three-c"),
        (.ringType, "rt.everAndEver", "Ever and ever", "ever-and-ever"),
        (.ringType, "rt.halo", "Halo", "halo"),
        (.ringType, "rt.mens", "Men's", "mens"),
        (.ringType, "rt.pendant", "Pendant", "pendant"),
        (.ringType, "rt.band", "Band", "band")
    ]

    private static let settingFacets: [FacetRow] = [
        (.gemSetting, "gs.prong", "Prong", "prong"),
        (.gemSetting, "gs.bezel", "Bezel", "bezel"),
        (.gemSetting, "gs.halo", "Halo", "halo"),
        (.gemSetting, "gs.tension", "Tension", "tension"),
        (.gemSetting, "gs.channel", "Channel", "channel"),
        (.gemSetting, "gs.pave", "Pave", "pave")
    ]

    private static let colourFacets: [FacetRow] = [
        (.gemColor, "gc.white", "White", "white"),
        (.gemColor, "gc.fancyYellow", "Fancy yellow", "fancy-yellow"),
        (.gemColor, "gc.pink", "Pink", "pink"),
        (.gemColor, "gc.blue", "Blue", "blue"),
        (.gemColor, "gc.champagne", "Champagne", "champagne")
    ]

    private static let metalFacets: [FacetRow] = [
        (.metal, "mt.whiteGold", "White gold", "white-gold"),
        (.metal, "mt.yellowGold", "Yellow gold", "yellow-gold"),
        (.metal, "mt.roseGold", "Rose gold", "rose-gold"),
        (.metal, "mt.platinum", "Platinum", "platinum"),
        (.metal, "mt.palladium", "Palladium", "palladium"),
        (.metal, "mt.silver", "Sterling silver", "silver")
    ]

    private static let styleFacets: [FacetRow] = [
        (.style, "st.classic", "Classic", "classic"),
        (.style, "st.vintage", "Vintage", "vintage"),
        (.style, "st.modern", "Modern", "modern"),
        (.style, "st.cathedral", "Cathedral", "cathedral"),
        (.style, "st.twist", "Twist", "twist"),
        (.style, "st.split", "Split shank", "split-shank")
    ]

    private static let elementFacets: [FacetRow] = [
        (.designElement, "de.plain", "Plain", "plain"),
        (.designElement, "de.milgrain", "Milgrain", "milgrain"),
        (.designElement, "de.engraved", "Engraved", "engraved"),
        (.designElement, "de.diamondShoulders", "Diamond shoulders", "diamond-shoulders"),
        (.designElement, "de.tapered", "Tapered", "tapered")
    ]

    private static let rows: [FacetRow] =
        ringTypeFacets + settingFacets + colourFacets + metalFacets + styleFacets + elementFacets

    /// Every facet, in the order the UI presents its groups.
    public static let facets: [FacetItem] = rows.map { row in
        let (group, id, name, key) = row
        return FacetItem(
            id: FacetItemID(id),
            group: group,
            name: name,
            artworkPath: "images/search/filteritems/\(group.rawValue)/\(key)",
            queryKey: key
        )
    }

    // MARK: - Designs

    /// One design in compact form. Everything derivable from the type and the
    /// setting is derived, so this table stays readable and a design cannot
    /// carry a measurement that contradicts its category.
    struct Seed {
        var id: String
        var name: String
        var type: BaseRingType
        var setting: String
        var colour: String
        var metal: String
        var style: String
        var element: String
        var carats: ClosedRange<Double>
        var suggested: Double
        var shapes: [GemShape]
        var accents: Int
        var pattern: AccentPatternKind
    }

    private static func s(
        _ id: String, _ name: String, _ type: BaseRingType,
        _ setting: String, _ colour: String, _ metal: String,
        _ style: String, _ element: String,
        _ carats: ClosedRange<Double>, _ suggested: Double,
        _ shapes: [GemShape], _ accents: Int, _ pattern: AccentPatternKind
    ) -> Seed {
        Seed(id: id, name: name, type: type, setting: setting, colour: colour, metal: metal,
             style: style, element: element, carats: carats, suggested: suggested,
             shapes: shapes, accents: accents, pattern: pattern)
    }

    static let seeds: [Seed] = [
        s("JWL-1001", "Aria Solitaire", .solitaire, "gs.prong", "gc.white", "mt.whiteGold",
          "st.classic", "de.plain", 0.5...3.0, 1.0, [.roundBrilliant, .oval], 0, .none),
        s("JWL-1002", "Aria Bezel", .solitaire, "gs.bezel", "gc.white", "mt.platinum",
          "st.modern", "de.tapered", 0.5...2.5, 0.75, [.roundBrilliant], 0, .none),
        s("JWL-1003", "Aurora Halo", .halo, "gs.halo", "gc.pink", "mt.roseGold",
          "st.vintage", "de.milgrain", 0.5...2.0, 1.0, [.roundBrilliant, .cushion], 16, .pave),
        s("JWL-1004", "Tension Line", .solitaire, "gs.tension", "gc.white", "mt.palladium",
          "st.modern", "de.plain", 1.0...2.5, 1.25, [.princess], 0, .none),
        s("JWL-1005", "Trilogy Plain", .threeStone, "gs.prong", "gc.white", "mt.whiteGold",
          "st.classic", "de.diamondShoulders", 0.5...2.0, 1.0, [.roundBrilliant], 2, .beadSet),
        s("JWL-1006", "Trilogy Channel", .threeStone, "gs.channel", "gc.blue", "mt.platinum",
          "st.cathedral", "de.tapered", 0.75...2.5, 1.0, [.oval, .emerald], 2, .channel),
        s("JWL-1007", "Three C Duet", .threeC, "gs.prong", "gc.fancyYellow", "mt.yellowGold",
          "st.vintage", "de.engraved", 0.5...3.0, 1.5, [.radiant, .oval], 4, .beadSet),
        s("JWL-1008", "Three C Halo", .threeC, "gs.halo", "gc.white", "mt.whiteGold",
          "st.split", "de.diamondShoulders", 0.5...2.0, 1.0, [.cushion, .roundBrilliant], 24, .pave),
        s("JWL-1009", "Ever and Ever Rail", .everAndEver, "gs.pave", "gc.white", "mt.whiteGold",
          "st.modern", "de.plain", 1.0...3.0, 1.5, [.oval], 8, .pave),
        s("JWL-1010", "Ever and Ever Twist", .everAndEver, "gs.bezel", "gc.champagne", "mt.yellowGold",
          "st.twist", "de.milgrain", 0.5...2.0, 1.0, [.roundBrilliant], 10, .beadSet),
        s("JWL-1011", "Meridian", .mens, "gs.channel", "gc.white", "mt.palladium",
          "st.modern", "de.plain", 0.5...1.5, 0.75, [.roundBrilliant], 0, .none),
        s("JWL-1012", "Bedrock", .mens, "gs.bezel", "gc.white", "mt.platinum",
          "st.classic", "de.tapered", 0.5...1.5, 0.5, [.princess], 0, .none),
        s("JWL-1013", "Solis Pendant", .pendant, "gs.prong", "gc.fancyYellow", "mt.yellowGold",
          "st.classic", "de.plain", 0.5...2.0, 1.0, [.pear, .oval], 0, .none),
        s("JWL-1014", "Milgrain Band", .band, "gs.channel", "gc.white", "mt.roseGold",
          "st.vintage", "de.milgrain", 0.25...0.5, 0.25, [.baguette], 12, .channel),
        s("JWL-1015", "Pave Edge Band", .band, "gs.pave", "gc.white", "mt.silver",
          "st.modern", "de.engraved", 0.25...0.5, 0.25, [.roundBrilliant], 14, .pave),
        s("JWL-1016", "Cathedral Grace", .solitaire, "gs.prong", "gc.blue", "mt.yellowGold",
          "st.cathedral", "de.engraved", 1.0...3.0, 1.5, [.emerald, .oval], 0, .none)
    ]

    // MARK: - Packages

    public static func packageName(for type: BaseRingType) -> String {
        switch type {
        case .mens, .band: return "Men's Collection"
        case .pendant: return "Modern Minimal"
        default: return "Bridal Essentials"
        }
    }

    public static var packages: [DesignPackage] {
        let names = ["Bridal Essentials", "Modern Minimal", "Men's Collection"]
        return names.map { name in
            DesignPackage(
                id: "pkg.\(name.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "'", with: ""))",
                name: name,
                designIDs: seeds.filter { packageName(for: $0.type) == name }.map { DesignID($0.id) },
                attributes: [
                    "priceTier": name == "Bridal Essentials" ? "premium" : "standard",
                    "leadTimeDays": name == "Bridal Essentials" ? "14" : "10",
                    "channel": "studio"
                ]
            )
        }
    }

    // MARK: - Derivation

    static func ringTypeFacetID(for type: BaseRingType) -> String {
        switch type {
        case .solitaire: return "rt.solitaire"
        case .threeStone: return "rt.threeStone"
        case .threeC: return "rt.threeC"
        case .everAndEver: return "rt.everAndEver"
        case .halo: return "rt.halo"
        case .mens: return "rt.mens"
        case .pendant: return "rt.pendant"
        case .band: return "rt.band"
        }
    }

    /// The studio's gem colour a catalogue colour facet means.
    static func gemColourID(forFacet facetID: String) -> String {
        switch facetID {
        case "gc.fancyYellow": return "c.fancyYellow"
        case "gc.pink": return "c.pink"
        case "gc.blue": return "c.blue"
        case "gc.champagne": return "c.champagne"
        default: return "c.white"
        }
    }

    /// A blue centre stone is a sapphire; everything else opens as a diamond.
    /// The catalogue facet says the colour, and the colour says the material,
    /// so the two can never contradict each other.
    static func centreMaterial(forColourFacet facetID: String) -> GemMaterial {
        facetID == "gc.blue" ? .sapphire : .diamond
    }

    static func defaultQualityID(for material: GemMaterial) -> String {
        material == .sapphire ? "q.colour.fine" : "q.diamond.premier"
    }

    static func shankProfile(for type: BaseRingType) -> ShankProfileShape {
        switch type {
        case .solitaire, .halo, .pendant: return .domed
        case .threeStone, .mens: return .flat
        case .threeC, .band: return .euroComfort
        case .everAndEver: return .knifeEdge
        }
    }

    static func headStyle(forSetting facetID: String) -> HeadStyle {
        switch facetID {
        case "gs.bezel": return .bezel
        case "gs.halo": return .halo
        case "gs.tension": return .tension
        default: return .prongBasket
        }
    }

    /// Width, thickness, shoulder taper and base taper, by category. A men's
    /// band is wider and heavier than a solitaire; a pendant is lighter than
    /// either. Values are millimetres and fractions.
    static func measurements(for type: BaseRingType) -> (width: Double, thickness: Double, shoulderTaper: Double, baseTaper: Double) {
        switch type {
        case .solitaire: return (2.2, 1.7, 0.20, 0.18)
        case .threeStone: return (2.6, 1.8, 0.15, 0.12)
        case .threeC: return (2.4, 1.8, 0.25, 0.10)
        case .everAndEver: return (2.0, 1.6, 0.10, 0.08)
        case .halo: return (2.3, 1.7, 0.22, 0.15)
        case .mens: return (5.0, 2.2, 0.05, 0.04)
        case .pendant: return (1.6, 1.4, 0.12, 0.10)
        case .band: return (3.6, 1.9, 0.00, 0.00)
        }
    }

    static func labourTier(for type: BaseRingType) -> LabourTier {
        switch type {
        case .threeC, .everAndEver: return .master
        case .threeStone, .halo, .pendant: return .premium
        case .solitaire, .mens, .band: return .standard
        }
    }

    /// The metals a design offers, most likely first. The first entry is what a
    /// new configuration opens in.
    static func metalIDs(forFacet facetID: String) -> [String] {
        switch facetID {
        case "mt.whiteGold":
            return ["gold-14k-white", "gold-18k-white", "gold-14k-yellow", "platinum-950"]
        case "mt.yellowGold":
            return ["gold-14k-yellow", "gold-18k-yellow", "gold-14k-rose", "platinum-950"]
        case "mt.roseGold":
            return ["gold-14k-rose", "gold-18k-rose", "gold-14k-white", "palladium-950"]
        case "mt.platinum":
            return ["platinum-950", "gold-14k-white", "palladium-950", "gold-18k-white"]
        case "mt.palladium":
            return ["palladium-950", "platinum-950", "gold-14k-white", "titanium-6al4v"]
        default:
            return ["silver-sterling", "gold-14k-white", "palladium-950", "gold-14k-yellow"]
        }
    }

    static func collectionIDs(for seed: Seed) -> [CollectionID] {
        var ids: [CollectionID] = []
        switch seed.type {
        case .mens, .band, .pendant: ids.append(CollectionID("col.modern"))
        case .threeC, .everAndEver: ids.append(CollectionID("col.heirloom"))
        default: ids.append(CollectionID("col.classic"))
        }
        if seed.style == "st.vintage" && !ids.contains(CollectionID("col.heirloom")) {
            ids.append(CollectionID("col.heirloom"))
        }
        if seed.style == "st.modern" && !ids.contains(CollectionID("col.modern")) {
            ids.append(CollectionID("col.modern"))
        }
        return ids
    }

    // MARK: - Index

    public static func makeIndex() -> CatalogIndex {
        CatalogIndex(
            schemaVersion: 1,
            designs: seeds.enumerated().map { design($0.element, index: $0.offset) },
            collections: collections,
            packages: packages,
            facets: facets
        )
    }

    static func design(_ seed: Seed, index: Int) -> DesignDetail {
        let material = centreMaterial(forColourFacet: seed.colour)
        let qualityID = defaultQualityID(for: material)
        let colourID = gemColourID(forFacet: seed.colour)
        let sizes = measurements(for: seed.type)
        let centreShape = seed.shapes.first ?? .roundBrilliant

        var slots: [GemSlot] = [
            GemSlot(
                id: 0,
                role: .centre,
                graphIndex: 100 + index,
                defaultMaterial: material,
                defaultShape: centreShape,
                defaultColourID: colourID,
                defaultQualityID: qualityID,
                defaultCarat: seed.suggested,
                supportsManualSize: true
            )
        ]

        for accent in 0..<seed.accents {
            slots.append(GemSlot(
                id: accent + 1,
                role: .accent,
                graphIndex: 200 + index * 100 + accent,
                defaultMaterial: .diamond,
                defaultShape: .roundBrilliant,
                defaultColourID: "c.white",
                defaultQualityID: "q.diamond.premier",
                defaultCarat: 0.02,
                supportsManualSize: false
            ))
        }

        let facetIDs = [
            ringTypeFacetID(for: seed.type), seed.setting, seed.colour,
            seed.metal, seed.style, seed.element
        ].map { FacetItemID($0) }

        let summary = DesignSummary(
            id: DesignID(seed.id),
            spinNumber: SpinNumber("SPIN-\(seed.id.dropFirst(4))"),
            name: seed.name,
            collectionIDs: collectionIDs(for: seed),
            packageNames: [packageName(for: seed.type)],
            baseRingType: seed.type,
            metalIDs: metalIDs(forFacet: seed.metal),
            facetItemIDs: facetIDs,
            keywords: keywords(for: seed),
            centreGemCaratMin: seed.carats.lowerBound,
            centreGemCaratMax: seed.carats.upperBound,
            supportedCentreShapes: seed.shapes,
            accentGemCount: seed.accents,
            labourTier: labourTier(for: seed.type)
        )

        return DesignDetail(
            summary: summary,
            gemSlots: slots,
            centreGemGraphIndex: 100 + index,
            centreGemGUID: "gem-guid-\(seed.id.lowercased())",
            accentPattern: AccentPattern(
                kind: seed.pattern,
                count: seed.accents,
                coverageDegrees: seed.accents == 0 ? 0 : 70
            ),
            shankProfile: shankProfile(for: seed.type),
            shankWidthMillimetres: sizes.width,
            shankThicknessMillimetres: sizes.thickness,
            shoulderTaperMillimetres: sizes.shoulderTaper,
            baseWidthTaperFraction: sizes.baseTaper,
            head: HeadSpec(style: headStyle(forSetting: seed.setting)),
            accentMetalWidthMillimetres: 1.1,
            suggestedCentreCarat: seed.suggested,
            longDescription: description(for: seed)
        )
    }

    static func keywords(for seed: Seed) -> [String] {
        let ids = [
            ringTypeFacetID(for: seed.type), seed.setting, seed.colour,
            seed.metal, seed.style, seed.element
        ]
        let labels = ids.compactMap { id in facets.first { $0.id.rawValue == id }?.name.lowercased() }
        let nameWords = seed.name.lowercased().split(separator: " ").map(String.init)
        return Array(Set(labels + nameWords + [seed.type.rawValue])).sorted()
    }

    static func description(for seed: Seed) -> String {
        let accents: String
        switch seed.pattern {
        case .none: accents = "no accent stones"
        case .beadSet: accents = "\(seed.accents) bead-set accent stones"
        case .pave: accents = "\(seed.accents) pave-set accent stones"
        case .channel: accents = "\(seed.accents) channel-set accent stones"
        }
        return "\(seed.name) is a \(seed.type.displayName.lowercased()) with a "
            + "\(headStyle(forSetting: seed.setting).displayName.lowercased()) setting, "
            + "a \(shankProfile(for: seed.type).displayName.lowercased()) shank and \(accents). "
            + "It is cut for a centre stone between "
            + "\(String(format: "%.2f", seed.carats.lowerBound)) and "
            + "\(String(format: "%.2f", seed.carats.upperBound)) carats."
    }

    /// The catalogue's own integrity check, run by the tests. Kept next to the
    /// fixture so a new design cannot be added without the rules applying to it.
    public static func integrityIssues() -> [String] {
        var issues: [String] = []
        let index = makeIndex()
        let facetIDs = Set(index.facets.map { $0.id.rawValue })

        for design in index.designs {
            for facetID in design.summary.facetItemIDs.map({ $0.rawValue }) where !facetIDs.contains(facetID) {
                issues.append("design \(design.id.rawValue) references unknown facet \(facetID)")
            }
        }

        let used = Set(index.designs.flatMap { $0.summary.facetItemIDs.map { $0.rawValue } })
        for facet in index.facets where !used.contains(facet.id.rawValue) {
            issues.append("facet \(facet.id.rawValue) is used by no design")
        }

        return issues
    }
}

// MARK: - Fixture conformance

extension CatalogIndex: CodeFixture {
    public static var fixtureName: String { CatalogFixtures.fixtureName }
    public static func make() -> CatalogIndex { CatalogFixtures.makeIndex() }
}
