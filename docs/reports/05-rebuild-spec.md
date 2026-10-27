# 05 — Rebuild specification: what to reimplement, in which order

Purpose: give you a build-ready plan for an equivalent jewellery-ring configurator, derived from the recovered architecture (`reports/03`, `reports/04`) rather than from guesswork. It is scoped to **your own implementation** — no Stuller assets, catalog data, materials or services may be copied (see §7).

## 1. System decomposition (6 services + 1 desktop client)

| # | Module | Replacement for | Hard requirements |
|---|---|---|---|
| 1 | **Catalog & search service** | Stuller catalog + `SearchHelper` facets | design entities, collections, packages, SPIN-like IDs, keyword index, facet filters (shape, colour, metal, element, style), centre-gem-size re-filtering |
| 2 | **CAD/configurator engine** | Rhino + `CounterSketchServer` (383 ops) | persistent session per design, scene graph addressable by id/GUID, parametrics (ring rail, part groups), freehand curve editing, gem placement incl. manual-sized stones, undo, viewport control |
| 3 | **Renderer** | V-Ray (`.vismat`/`.visopt`/HDR) | PBR-ish metal shaders + **gem refraction** (diamond maps), fixed tile sizes (1240×600, 1240×1240) for catalog grid, headless render for order images |
| 4 | **Pricing service** | Stuller pricing WCF | metal rate lookup by alloy/weight, stone pricing by shape+quality+carat, labour/markup rules, per-customer price lists |
| 5 | **Order & export service** | `IStullerOrderService`, `IDesignExportService`, CAD/CAM export | order payload = configuration + rendered images + metadata; export formats for production (3D geometry + print/CAM) |
| 6 | **Identity & entitlement** | `ISecurityService`, `IKeyCodeService`, `IFeatureService` | accounts, activation keys, feature flags per customer (the app gates features remotely — reproduce that, don't hardcode) |
| 7 | **Desktop client** | `CounterSketch Studio.exe` | MVVM shell, search/browse UI with a "book"-style viewer, 3D viewport hosting the engine, order summary, library browser, updater |

## 2. Interfaces to define first (these are the seams that make the rest cheap)

```ts
// 1. Catalog
searchDesigns(filter: DesignFilter): DesignSummary[]        // facets + centre-gem size
getDesign(designId | spinNumber | packageName): DesignDetail

// 2. Configurator session (mirrors the recovered IRhinoServices semantics)
openSession(designId): SessionId
loadDesign(session, designId): SceneGraphId
setMetals(session, metal1, metal2)
setGems(session, gems: [{slot, shape, colour, quality, carat, manualSize?}])
setFingerSize(session, us | eu)
freehandBegin(session, mode) / freehandUpdate(session, curvePoints) / freehandEnd(session)
undo(session, depth) / highlight(session, itemIds | gemIndex)
setViewport(session, {target, camera, background, highlightColour})
renderPreview(session, {w, h}): ImageRef
exportForProduction(session, target: 'stl'|'3dm'|'cam'|'print'): ArtifactRef

// 3/4. Pricing & order
quote(configurationId): PriceBreakdown           // metal, stones, labour, total
submitOrder(quoteId): OrderRef
renderOrderImages(orderRef): ImageRef[]

// 5. Library
packLibrary(files): LibraryBlob                  // see §4
openLibrary(blob): LibraryIndex
```

Design rule recovered from the original and worth keeping: **the client never computes geometry or prices.** The original keeps all CAD in a separate long-lived process reached over a duplex channel, and all authoritative numbers server-side. That separation is what allows the same engine to serve the UI, order images and production export.

## 3. Data contracts (minimum fields)

* **Design**: `id, spinNumber, collectionIds[], packageNames[], baseRingType, gemSlots[], centreGemGraphIndex, metalOptions[], images{tile1240x600, tile1240x1240}, keywords[]`
* **Configuration / iteration**: `designId, iterationId, iterationIndex, metal1, metal2, gems[1..3]{shape,colour,quality,carat,manualSize}, fingerSizeUS, freehand{enabled,parts[]}`
* **Price**: `metalCost, stoneCost, labour, discount, total, currency, breakdown[]` (per line, with the source of each rate so it can be audited)
* **Order**: `orderRef, customer, shipTo, lines[config], images[], statusHistory[]`
* **Library entry**: `name, files[{path, sha256, bytes}], gemAttributes, freehandPartNames[], schemaVersion`

## 4. Formats you must define yourself

The original's formats are proprietary; define yours and version them from day one:

* **Library pack** — the original packs many geometry/gem files into one container with a manifest and migrates an older "ZipIt" layout (`DesignLibrary.{LibraryPacker, CSGLLibrary, Payload, OldLibraryConverter}`). Yours: a ZIP-with-manifest plus an explicit `schemaVersion` and a migration path; content-addressed entries (sha256) as in the evidence list above.
* **Component files** — the original stores parts as Rhino geometry (`.csg`/`.3dm`). Yours: pick an open format you can render and print (glTF/USD/STEP for interchange + a parametrics sidecar), and keep gem definitions separate from part geometry (the original separates `.gem` records from `.csg` geometry).
* **Facet manifests** — search facets are image-backed in the original (the shipped resource payload is largely facet thumbnails). Keep facet → image → query mapping in data, not code.

## 5. Build order (each stage independently demonstrable)

1. **Stage 0 — shell + catalog.** Desktop shell (MVVM), catalog service with facets, tile rendering placeholders, search UI. No CAD yet.
2. **Stage 1 — engine skeleton.** CAD session service with open/load/undo/viewport and a real renderer; load one parametric ring from data.
3. **Stage 2 — configuration depth.** Gems (shape/colour/quality/carat), metals, finger size, centre-gem-size-driven re-filtering, highlight/selection round-trips.
4. **Stage 3 — freehand + advanced parts.** Freehand curve editing, part groups, manual-sized stones, quarter-carat rounding rules (both are distinguishing product features).
5. **Stage 4 — pricing + order.** Quote service, order summary with line breakdown, order/export submission, headless order-image rendering.
6. **Stage 5 — production.** Print/CAM export path with a printer-parameter store (the original's `PrinterDB`), plus library packing/migration.
7. **Stage 6 — platform.** Feature entitlements, activation, updater, diagnostics/troubleshooter.

## 6. Non-obvious requirements recovered from the original (easy to miss)

* **Second-instance handoff**: the app accepts `designId, gem1..3, metal1..2, fingerSizeUS, iterationId/Index, filePath` and a `noServer` flag, and talks to the running instance over a **named pipe**. Any serious rebuild needs the same "drive the running app from outside" contract for CAD/CAM tooling integration.
* **Firmware/device awareness**: `UpdateFirmwareAndActivate` and a watcher (`WatcherSetEnabled`) show the product integrates with physical output devices.
* **Cost/quality vocabularies**: map UI-level gem quality to supplier-level vocabulary in one adapter layer (the original's `StullerProductAPIHelper` does exactly this, in both directions, including AGTA descriptions).
* **Enterprise plumbing**: large message limits and long timeouts for order/export calls; proxy-aware network defaults; per-customer theming (`ICounterSketchThemeService`).
* **Rendering as data**: materials and render options are external files, so artists can change the look without a rebuild. Keep that property.
* **Localisation**: the original ships 8+ languages; structure UI strings for satellite resources from the start.

## 7. Legal and ethical boundaries (non-negotiable for this rebuild)

* Do **not** ship or redistribute any CounterSketch/Stuller/GemVision asset: not the `.csg/.gem/.3dm` library, not the render materials, not the facet images, not the resources extracted from the executable. Use them only as *reference* for what capability to build.
* Do **not** call Stuller's live services with recovered contracts/keys, and do not implement licence circumvention. Pricing/order must be your own service stack.
* The recovered endpoint list (report 03 §3) documents *integration shape*, not permission to use those endpoints.
