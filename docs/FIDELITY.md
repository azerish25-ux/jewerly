# Fidelity ledger — recovered behaviour vs. this rebuild

This is the honest account of what the iPadOS rebuild reproduces, what it
replaces with an equivalent, and what it deliberately does not build.

The reference product is **CounterSketch Studio 8.1** (Stuller/GemVision), a
Windows WPF application served by a long-lived Rhino CAD process and a V-Ray
render pipeline. Its anatomy is documented in [the report set](reports/README.md),
principally [03 — Architecture](reports/03-architecture.md) and
[04 — Business logic](reports/04-business-logic.md).

Three verdicts are used:

| Verdict | Meaning |
|---|---|
| **1:1** | Same contract and same semantics; only the platform and the data source changed. |
| **Adapted** | Same seam and same product behaviour, with a different mechanism, because the original's mechanism cannot exist on an iPad (a Rhino service, an offline V-Ray farm). |
| **Absent** | Not built, with the reason stated. |

---

## 1. Catalogue and search

| Recovered behaviour | Rebuild | Verdict |
|---|---|---|
| Designs addressed by SPIN-like number, package name and surrogate id | `DesignID`, `SpinNumber`, `CatalogService.design(id:)`, `.design(spinNumber:)`, `.design(matchingCatalogueNumber:)` | **1:1** |
| Facet search: design element, gem setting, gem colour, metal, style, ring type | `FacetGroup`, `FacetItem`, `FacetDescriptor`, `CatalogService.descriptors(for:within:)` | **1:1** |
| Facets that would dead-end are shown disabled, with a live result count | `FacetDescriptor.isAvailable` / `.resultCount`, surfaced by the facet rail | **1:1** |
| Re-filtering by centre-stone size, driven from the configurator | `DesignFilter.centreGemCarat`, `DesignSummary.supportsCentreCarat(_:)` | **1:1** |
| Collections and packages as first-class groupings | `Collection`, `DesignPackage`, `designs(inCollection:)`, `designs(inPackage:)` | **1:1** |
| Typed convenience queries (`threeStoneDesigns()`, `everAndEverDesigns()`, `mensDesigns()`, …) | Same names on `CatalogService` | **1:1** |
| Facet artwork shipped as bitmaps | Facet items carry an `artworkPath`; the UI draws its own chips | **Adapted** |
| The published catalogue itself | Synthetic fixtures — a few collections' worth of designs generated from the recovered *shape* of the data | **Adapted** |

The catalogue content is original: no Stuller design record, name, image or
keyword was copied. What is reproduced is the *schema* and the *search algebra*.

## 2. The CAD engine seam

The single most important property of the original is that **the client never
computes geometry**. All CAD lives in a separate long-lived process
(`CounterSketchServer`, 383 recovered operations) reached over a duplex channel,
with a callback channel (`UpdateStudioUICallbackChannel`) pushing state back to
the UI.

| Recovered behaviour | Rebuild | Verdict |
|---|---|---|
| A long-lived session per design, opened once and mutated | `CADEngineSession` protocol; `InProcessCADEngine` implements it | **Adapted** — in-process, because an iPad cannot host Rhino and a local product should not need a network round trip to redraw a ring |
| Every call asynchronous, because the original's were | All `CADEngineSession` methods are `async`, including the in-process ones, so a remote implementation is a drop-in replacement | **1:1** |
| State pushed to the UI, not polled | `EngineEvent`, `EngineEventListener`, `EngineEventStream`; the app subscribes | **1:1** |
| One mutation path that validates, records undo, rebuilds and notifies | `InProcessCADEngine.mutate(_:)` | **1:1** |
| A scene graph addressable by id, by GUID, and by CAD graph index | `SceneGraph`, `GraphItem`, `GraphItemID`, `centreGemGraphIndex`, `centreGemGUID`, `centreGemControlGraphIndex` | **1:1** |
| Undo with a bounded history and a discardable redo branch | `UndoStack<State>` (limit 64), `undo()`, `redo()`, `undoStateChanged` events | **1:1** |
| Operations: open, load design, set metals, set gems, set finger size, manual-size a stone, quarter-carat rounding, highlight, viewport, render request, export | All present on the protocol; export is represented by `requestRender(target:)` | **1:1** except export (below) |
| Freehand curve editing with named part groups and a common-centre mode | `FreehandState`, `FreehandPart`, `setFreehand`, `updateCurve(partID:controlPoints:)`, `toggleFreehandCommonCentreMode`, `toggleFreehandVisibility` | **Adapted** — the data model and the engine operations exist; the app exposes the toggles but not a curve-drawing gesture surface |
| Highlight by item list, by gem slot, by accent group | `highlight(items:)`, `highlightGem(slotIndex:)`, `highlightAccentGems(_:)`, `clearHighlights()` | **1:1** |
| Viewport: target, camera location, background, highlight colour, handle draw scale | `ViewportState`, `setViewport`, `setViewportHandleDrawScale` | **Adapted** — the app's orbit and pinch drive the RealityKit camera rather than the engine's camera operations |

## 3. Geometry and gemetrics

| Recovered behaviour | Rebuild | Verdict |
|---|---|---|
| A parametric ring: rail, shank profile, shoulder taper, width taper, head | `RingParameters`, `RingBuilder`, `ShankProfileShape`, `HeadSpec` | **1:1** in parameters |
| Head styles: prong basket, bezel, halo, tension, with sensible prong counts | `HeadStyle`, `HeadSpec.prongCount` | **1:1** |
| Gem placements with orientation and a world-space mesh | `GemPlacement`, `GemPlacement.mesh()` | **1:1** |
| Faceted stones: brilliant-style layouts per shape, girdle-relative proportions | `GemFacetLayout`, `GemMeshBuilder` | **1:1** in construction; the proportions are published jewellery conventions rather than GemVision's constants |
| Carat ↔ millimetre conversion, per material and per cut | `GemSizer.girdleWidthMillimetres(for:carat:material:)` and its inverse | **1:1** in method, using published specific gravities and cut geometry |
| Manual-sized stones flagged separately in the gem report | `GemSelection.manualSize`, `GemReportLine.isManualSize`, `setManualSize(slotIndex:carat:)` | **1:1** |
| Quarter-carat rounding for centre stones | `CaratRounding`, `Configuration.applyCaratRounding()`, `toggleQuarterCaratRounding()` | **1:1** |
| Watertightness and degeneracy checks before production | `Mesh.validate()`, `MeshDefect`, `BuiltRing.isWatertight` | **1:1** in intent |
| Two-tone rings limited to metals that can be soldered together | `Metal.canPair(with:)`, `EngineError.metalPairUnsupported` | **1:1** |
| Ring-size range and quarter-step quantisation | `FingerSize.offeredRange`, `.quantised()`, `.allOfferedSizes` | **1:1** |

The geometry is generated from parameters, not imported: no `.3dm`, `.csg` or
`.gem` file from the reference product is used or shipped.

## 4. Rendering

| Recovered behaviour | Rebuild | Verdict |
|---|---|---|
| Fixed tile sizes for the catalogue and for order imagery (1240×600, 1240×1240) | `RenderTarget.pixelSize` | **1:1** |
| Render settings and materials live in data, so artists can retune them without a rebuild | `MaterialLibrary`, `MaterialDefinition`, `RenderOptions`, `MaterialFixtures` | **1:1** |
| Rendering requested by the engine, fulfilled by the client | `requestRender(target:)` → `RenderRequest` → `renderRequested` event | **1:1** |
| Offline V-Ray: physically-based metal shaders, gem refraction with diamond maps, HDR environments | RealityKit `PhysicallyBasedMaterial` with three analytic lights; gems are opaque with a very low roughness | **Adapted** — no offline render farm on an iPad, no refraction maps |
| Pre-rendered catalogue tiles shipped as 662 bitmaps | Tiles draw a vector **glyph** from the design's own parameters | **Adapted** — an honest diagram instead of a copy of the original's imagery |
| Headless order-image rendering | `OrderImage` records reference the tile keys the renderer would produce; no bitmaps are written | **Absent** — it would need the offline renderer this rebuild replaces |

## 5. Pricing

| Recovered behaviour | Rebuild | Verdict |
|---|---|---|
| Metal priced by alloy rate × measured weight, not by a flat allowance | `MetalRate`, `Metal.grams(forCubicMillimetres:)`, `PricingEngine` fed from the actual `BuiltRing` | **1:1** |
| Stones priced by material + shape + quality + carat band, per carat, or per stone for melee | `StoneRateBand`, `RateTable.stoneRate(material:shape:qualityID:carat:)` with narrowest-band-wins resolution | **1:1** |
| Labour by complexity tier with a margin multiplier | `LabourTier`, `LabourRule` | **1:1** |
| Setting charges per stone, by setting role | `SettingCharge` | **1:1** |
| Markups per category, tax, and a billing rounding increment | `PricingPolicy` | **1:1** |
| Every line carries the rate it came from, so a quote can be audited | `QuoteLine.sourceRateID`, `Quote.categoryTotals`, `Quote.isSelfConsistent` | **1:1** |
| Per-customer price lists resolved server-side | `PricingPolicy.priceListID` is carried on the quote; resolution is local | **Adapted** |
| Live supplier pricing (Stuller WCF) | A local, versioned rate table with synthetic rates | **Absent** — and deliberately so: the report set documents the integration shape, not permission to call those services |

## 6. Orders

| Recovered behaviour | Rebuild | Verdict |
|---|---|---|
| Order payload = configuration + audited quote + image references | `Order`, `OrderLine`, `OrderImage` | **1:1** |
| A versioned document, so an old stored order is recognisable | `Order.schemaVersion`, `Order.currentSchemaVersion` | **1:1** |
| Reference numbers of the form `PREFIX-YYYYMMDD-TOKEN`, unambiguous when read aloud | `OrderReferenceGenerator` (no O/0 or I/1 in the alphabet) | **1:1** |
| A status machine with guarded transitions and a full history | `OrderStatus.allowedTransitions`, `OrderStatusEvent`, `transitioning(to:at:note:)` | **1:1** |
| One-minute open / ten-minute receive / five-minute send timeouts, 2 GiB messages | Not applicable: orders are local documents, so there is no transport to time out | **Absent**, by design |
| Order submission to a supplier service | `OrderService.submit(_:)` validates and advances a stored order | **Adapted** — local submit, no supplier |
| Storage | `FileOrderRepository` (one JSON document per order) with `InMemoryOrderRepository` for tests | **Adapted** |

## 7. Platform, entitlement and the surrounding application

| Recovered behaviour | Rebuild | Verdict |
|---|---|---|
| Activation keys, feature flags, per-customer entitlements, licence enforcement | Not implemented | **Absent** — this is a single-tenant studio build; the recovered mechanism is documented in [04 — Business logic](reports/04-business-logic.md) §6 |
| Second-instance handoff over a named pipe, with `designId`, gems, metals, size, iteration and `noServer` | Not implemented | **Absent** — iPadOS has no named pipes; the equivalent would be a URL scheme or an App Intent, which is future work |
| Printer firmware activation, the `PrinterDB` parameter store, CAM and print export | Not implemented; the kernel's `Mesh.validate()` provides the print-readiness check the original's native kernel performed | **Absent** |
| Library packing (`LibraryPacker`, `CSGLLibrary`, payload + manifest, sha256 content addressing, migration from the older ZipIt layout) | `FixtureBundle` manifest with per-document SHA-256 hashes and a declared source; no ZIP container, no migration path | **Adapted** |
| Book-style viewer, floating CAD palettes, library browser | A single three-column SwiftUI studio: library, catalogue, bench | **Adapted** to iPadOS |
| Eight-plus localisations | English | **Absent** |
| Installer, updater, troubleshooter | Replaced by XcodeGen + CI and the normal TestFlight path | **Absent**, by design |
| Enterprise plumbing: proxy-aware defaults, long timeouts, per-customer theming | Not applicable without a server | **Absent**, by design |

## 8. What was verified, and what was not

Verified by the kernel test suite (`swift test`), which runs on every push:

- catalogue search algebra: facets, keyword, collection and package scoping, carat re-filtering, disabled-facet guidance;
- every fixture design and every fixture document passes its own integrity checks;
- gem sizing round-trips (carat → girdle → carat) within tolerance, for every shape and material;
- ring geometry is watertight and consistently wound, and its measured volume agrees with its mass;
- metal weights follow density; two-tone weights split by measured part volumes;
- pricing arithmetic reconciles: lines sum to the subtotal, discount and tax apply to the rounded subtotal, and every line names its rate;
- orders transition only along allowed edges, references are reproducible, and a stored order round-trips;
- the engine pushes the same state it would report if asked, and undo/redo restores exactly.

Verified by CI once a macOS runner picks it up:

- the app target builds for the iPadOS simulator;
- the UI test walks catalogue → configure → gem report → quote → order register, checks that filters narrow and clear, and checks that plates expose accessible labels.

**Not verified, and not claimed:** that the app renders correctly on a device.
The RealityKit viewport, the gesture handling and the visual design have not been
seen running. The app target has not been compiled by the author of this commit:
the development host has no Swift toolchain, so compilation is CI's job. A
failure in `.github/workflows/ci.yml` is a real defect to fix, not a formality.

## 9. Legal boundary

No CounterSketch, Stuller or GemVision asset, catalogue record, image, material
file, geometry file or service endpoint is shipped or called. The reference
binaries, the extracted installer tree, the decompiled corpus and the RE
toolchain are excluded from this repository by `.gitignore` and refused by
[the guards workflow](../.github/workflows/guards.yml). What the reports and this
rebuild carry forward is *behaviour and contract*, which is what a clean-room
reimplementation of a product may reproduce.
