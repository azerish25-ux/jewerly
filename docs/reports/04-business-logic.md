# 04 — Business logic: catalog, configuration, rendering, pricing, orders, licensing, formats

Everything below is traced to a decompiled file, a shipped file or an REA Evidence record. Where a mechanism could only be seen at runtime it is flagged as **not provable statically**.

## 1. The product loop

CounterSketch Studio is a **custom-ring configurator and order pipeline** for a jewellery manufacturer/retailer (GemVision/Stuller):

1. **Search/browse** a design catalog (collections, packages, styles, SPIN numbers).
2. **Configure** the selected design: metal(s), gem(s), finger size, centre-gem size, free-hand edits.
3. **Render** the configuration with V-Ray into UI tiles and order images.
4. **Price** it from server-side data.
5. **Order/export** it to Stuller (order service, design export, CAD/CAM profile).

The decompiled shell contains the first three plus presentation of 4/5; the geometry happens in the Rhino backend next door, and the authoritative catalog/pricing/order state lives in Stuller services.

## 2. Catalog & search logic (`SearchHelper`, 27 methods)

The search API surface, verbatim from the decompiled helper:

```
GetAllBaseRingDesigns, Get3CDesigns, GetThreeStoneDesigns, GetEverAndEverDesigns, GetMensDesigns,
GetPendantDesigns, GetDesignsByCollectionId, GetDesignsForKeyword, GetDesignsForPackageName,
GetPackagedDesigns, GetPackagesForDesignSearch, GetDesignBySPINumber, GetDesignBySearchFilterItems,
GetSearchFilterItems, GetPackageAttributes, UpdateDesignKeywordsDictionary,
UpdateDesignResultsWithFilters, UpdateResultsUsingCenterGemSize, AddSearchFilterItem,
GetFilterItemDescription, GetSearchFilterItemImagePath, GetGemShapeFromGemTableShapeId,
GetCenterGemControlGraphIndex, GetCenterGemControlGuid
```

Reading it as a spec:

* Designs come from **collections** and **packages** as well as direct searches; "3C", "three stone", "ever and ever", "mens", "pendant" are curated entry points.
* Search results are **filterable by facet items** whose display images ship in the resource payload (`images/search/filteritems/{gemsettings,gemcolors,metals,designelements,…}` — the same facets visible in `evidence/app-resources.txt`).
* A design is addressed by an internal **design id**, a **SPIN number** and a **package name**; centre-gem size is used to re-filter results (`UpdateResultsUsingCenterGemSize`).
* Each design carries graph metadata for its **centre gem** (`GetCenterGemControlGuide/Guid`) — i.e. the CAD scene graph is addressable by the client.
* Keywords are cached client-side in a dictionary that the client updates.

The 1.6 MB `extractlibrary/SearchClass.cs` is the companion extraction/indexing class (a large generated-style class; it is the single biggest source file in the assembly).

## 3. Gems, metals and product mapping

* `GemHelper.GetGemMaterialOptionItems / GetGemShapeImage / GetGemShapeRotationAngle / GetImageForGems / UpdateMaterialImageCache` — gem shape and material option lists, with image caching and per-shape rotation for the UI.
* `StullerProductAPIHelper` (24 methods) is the **translation layer between GemVision's domain language and Stuller's product API**:

```
GetAdvancedProductFilters / GetAdvancedProductFilterFromString / CreateStoneSizeAdvancedProductFilter
GetStoneColorAdvancedProductFilters / GetStoneFamilyAdvancedProductFilters
GetStoneQualityAdvancedProductFilters / GetStoneUniquenessAdvancedProductFilters
GetQualitiesFromMaterialName / GetStullerGemQualityFromUIQuality / GetUIValidGemQualities /
GetUIValidDiamondQualities / GetStoneQualities / GetAGTADescriptionFromCode
ConvertGemvisionCounterSketchStoneShapeToStullerStoneShapeString
CheckMaterialSupportsImitation / CreateSizeString / InitializeGlobalFilterCollection
```

* Gems are modelled as **shape + colour + quality + size**; quality vocabularies are mapped in both directions (UI ↔ Stuller, e.g. "AGTA" descriptions for coloured stones); imitation/stone-substitute support is an explicit flag on materials.
* Metals are parameters of the configuration: the CLI contract takes `metal1`, `metal2`, `gem1..3`, `fingerSizeUS` (report 03 §8), and the UI ships metal filter thumbnails for pairs such as `palladiumwhite18k`.
* The renderer's materials are data, not code: 265 `.vismat` + 15 `.visopt` + 35 `.hdr` environments, including diamond-specific `*_TextureRefraction.png` maps (12.5 MB each) used for gemstone light behaviour.

## 4. Configuration & CAD semantics (backend contract)

The 383 `IRhinoServices` operations (report 03 §4) are the configurator's real API. Grouped, they define what a rebuilt configurator must support:

| Capability | Representative operations |
|---|---|
| Load/import a design | `ImportGroupAddToPartGroup`, `ImportGroupAddRingRailGuide`, `UpdateImportGroupSortOrder`, `UpdateImportGroupPartListGroupAssignment` |
| Hand/freehand modelling | `ToggleFreehand*`, `TurnHandOff`, `UpdateCurveObjectFromUI`, `UpdateValueChooserFromUI`, `UpdateViewPortHandleDrawScale` |
| Centre/melee gems | `GetManualSizedStones`, `ToggleQuarterCaratGemRounding`, `HighlightAccentGems`, `HighlightGemFromGemReportBy*` |
| Selection/highlight | `HighlightGraphItem`, `HighlightItemsByBlockInstanceGuid` |
| Undo/user data | `GraphUndoChange`, `GraphItemRemoveUserDataValue` |
| Viewport & materials | `ViewportSet*`, `UpdateRhinoAppearanceMaterials`, `UpdateRhinoHand` |
| Device/firmware & gating | `UpdateFirmwareAndActivate`, `WatcherSetEnabled` |
| UI callback plumbing | `UpdateStudioUICallbackChannel`, `UpdateUIControl`, `UpdateUIControlQuick` |
| Activation state | `GetActivationStateCompletedEventArgs` (service-side activation state reaching the UI) |

Two facts worth underlining for a rebuild: **(a)** "freehand" editing and **quarter-carat gem rounding** are first-class product features, and **(b)** the UI↔CAD channel is explicit (`UpdateStudioUICallbackChannel`), i.e. the CAD process pushes state back to the client.

## 5. Rendering pipeline

* V-Ray for Rhino (`VRay\dlls\vray.dll`, `VRayForMatrix.rhp`) with a **Python 2.6 + PyQt4** runtime under `commonappdata\ASGVIS\Common\x64\vc10\Python26` (1,029 `.py` files, 186 `.pyc` — that count is entirely the V-Ray runtime, not application logic).
* Materials: `.vismat` (XML) per material, `.visopt` render options, HDR environment maps, and dedicated refraction/reflection maps for diamond rendering.
* Render targets observed as assets: 1,240×600 and 1,240×1,240 tile composites (`images/tile/...` in the resource payload), i.e. the UI renders configuration previews at fixed sizes for the catalog grid.

## 6. Pricing and orders

* **Pricing model** lives in `Stuller.Web.Services.GV.Pricing` (30 files) with DTOs such as `CounterSketchCost`, `CustomerHead`, `CustomerStone`; the ordering UI is `OrderSummaryViewModel.cs` (128 KB, **222 price-related occurrences**, plus `Email` (17) and `ShipTo` (3) handling).
* **Order submission** goes through `IStullerOrderService` with deliberately large timeouts (open 1 min, receive 10 min, send 5 min) and 2 GiB message limits — order payloads include the configured design and its images.
* **Export** has its own contract (`IDesignExportService`) and the app's own "CAD/CAM profile" web page (`https://www.stuller.com/countersketchstudio/cadcamprofile`), which matches the string found inside the binary during reconnaissance.
* A `DebugOrderEmail` config switch and e-mail code paths exist for testing order e-mails without placing orders.

> **Not provable statically:** the actual price arithmetic. Rates, markups and stone prices are computed server-side; the client receives DTOs and adds presentation-level totals. Confirming which fields drive the displayed total requires either the server (out of scope) or a runtime trace.

## 7. Files, formats and printers

| Format | Signature / structure (observed) | Notes |
|---|---|---|
| `.3dm`, `.csg` | ASCII header `3D Geometry File Format ` | Rhino geometry; `.csg` is the app's component/part variant of the same container (120 + 3 shipped) |
| `.gem` | binary; `float 2.0` marker, then `uint32` size (≈ filesize−8), then counts (`03 00 00 00`, `04 00 00 00`, `09 00 00 00`), then **UTF-16 names** (`"Ca…"` for `Library\Gems\Cabochon\Bullet.gem`) | gem definition records; 57 shipped |
| `.geocomp` | binary, `uint32` size field (size−12) + version `1` | compiled geometry component (55 shipped) |
| `.vismat`, `.visopt` | XML (`<vismat>`, `<visopt>`) | V-Ray material/options |
| `Library\` pack | `DesignLibrary.dll`: `CSGLLibrary`, `LibraryPacker`, `LibraryDBBuilder`, `Payload`, `FileData`, `GemAttribFix`, `OldLibraryConverter.ZipIt`, `NameFreeHandParts` | the library codec: builds/packs libraries, migrates the old "ZipIt" format, fixes gem attributes, names freehand parts. Member-level evidence: `evidence/managed-members-designlibrary.json` |
| `PrinterDB\standard_params_db` | 7.17 MiB plain parameter database | printer/material parameters |
| `PrinterDB\paramsdb.db`, `stopp.db` | **not SQLite** — header bytes are base64 text (`QChFR2Y5P2hYYDh…`, `EVlvbj9If0RZQ0o…`) | printer parameter + "stop" (support) databases stored as base64 blobs (compressed/encoded). Decoding them is a bounded follow-up task, deliberately not guessed at here. |

Print/CAM export is implemented by the native `csharp.print.headless.dll` (33.2 MB) and `csharp.print.v2.dll` (30.7 MB), driven from the Rhino backend and parameterised by the `PrinterDB` data — i.e. **the app can hand a configured ring to a printer/CAM path without the UI.**

## 8. Licensing, activation and entitlements

* `CSSecurity.cs`, `SecurityHelper.cs`, `ISecurityService` + `SecurityServiceClient`, `CounterSketchSecurityService`, `IKeyCodeService`, `IFeatureService` + `FeatureServiceClient` + `FeatureDTO/Features/FeatureHelper`.
* Activation appears as a **separate thread started at app start** (`_activationThread`), plus the `UpdateFirmwareAndActivate` CAD operation and the `SecurityKeyword = "G3mv1s10nK3yPr0f1l3Upd4t3r!"` constant in `Program.cs`; a `KeyProfile` GUID is configured in `CounterSketch Studio.exe.config`.
* Feature gating is service-driven: `IFeatureService.GetFeature` (33 occurrences) with entitlement DTOs — the client asks what the customer is entitled to rather than embedding rules.
* A `Hasp` string appears once in the binary (dongle-family reference) — no dongle logic was identified in the decompiled shell; licensing is service-mediated.

> **Note on scope and ethics:** this report documents how the mechanisms work as shipped. It deliberately does **not** develop or test a licensing bypass.

## 9. Update, diagnostics and app management

* `CounterSketchUpdateInstaller\` (21.3 MiB) — the self-updater, staged through `commonappdata\Microsoft\Network\Downloader\`.
* `GemvisionApplicationManager\` — launcher/manager; `Troubleshooter\` — diagnostics.
* `FeatureService` and the "CadCam profile" web page suggest remote configuration of customer capability, not just code updates.
