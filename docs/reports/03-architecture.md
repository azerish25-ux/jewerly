# 03 — System architecture of CounterSketch Studio 8.1

Derived from: decompiled corpus (`build/app-decompiled/`, 1,229 C# files), `CounterSketch Studio.exe.config`, the extracted application tree, REA Evidence for the desktop application (`evidence/desktop-application.json`, 2,065 files examined, candidate family `dotnet`, 149 `next_probes`) and the installer manifest.

## 1. Big picture

```
                     Stuller cloud                                  Stuller cloud
        ┌────────────────────────────────────────┐   ┌───────────────────────────────────────┐
        │ services.stuller.com (v1/v3/GemVision) │   │ api.stuller.com/v2/  (product API)    │
        │  ISecurityService  IPartsLibraryService│   │  advanced product filters, stones,    │
        │  ILibraryService   IStullerOrderService│   │  metals, qualities, SPIN lookups      │
        │  IDesignExportService IKeyCodeService  │   └───────────────────────────────────────┘
        │  IFeatureService   ICounterSketchTheme │
        └───────────────┬────────────────────────┘
                        │ basicHttp / basicHttps (WCF)
    ┌───────────────────▼───────────────────────────────────────────────────────────────────┐
    │  CounterSketch Studio.exe  —  WPF / MVVM (MVVM Light) desktop shell                    │
    │   • DevExpress 16.1 XPF + Telerik + WPFMitsuControls("book") + FontAwesome.WPF         │
    │   • CefSharp.Wpf 75.1.142.0 (Chromium 75 + SwiftShader fallback) for embedded web      │
    │   • ViewModels: MainViewModel, OrderSummaryViewModel, TileSearchResult… (56 VM files)   │
    │   • Search/domain helpers: SearchHelper, GemHelper, StullerProductAPIHelper            │
    │   • Local data: file libraries (.csg/.gem) + SQL via System.Data.SqlClient             │
    └───────┬────────────────────────────────────────────┬──────────────────────────────────┘
            │ netTcp WCF (reliable session, 7-day idle)  │ named pipes + process launch
            │ localhost:8556/RhinoServices (mex at …)    │ (CLI args, registry, updater)
    ┌───────▼──────────────────────────────┐   ┌─────────▼──────────────────────────────────┐
    │ CounterSketchServer  (Rhino plugin)  │   │ CounterSketchUpdateInstaller /             │
    │  • CounterSketchServer.rhp  (10.7 MB)│   │ GemvisionApplicationManager /              │
    │  • IRhinoServices: 383 operations    │   │ Troubleshooter                             │
    │  • Platform\ native SDKs:            │   └────────────────────────────────────────────┘
    │      geoisdk, gpcorecmp,             │
    │      gplandercmp, surfacefitting,    │
    │      csharp.print.headless/v2,       │
    │      GeoBasicInterop (managed)       │
    │  • PrinterDB\ paramsdb/stopp db      │
    └───────┬──────────────────────────────┘
            │ in-process
    ┌───────▼──────────────────────────────┐
    │ V-Ray render pipeline (ASGVIS)       │
    │  vray.dll, VRayForMatrix.rhp,        │
    │  Python 2.6 + PyQt4 runtime,         │
    │  System\RenderMaterials\*.vismat,    │
    │  HDR environments, diamond maps      │
    └──────────────────────────────────────┘
```

## 2. Processes and their boundaries

| Process | Evidence | Responsibility |
|---|---|---|
| `CounterSketch Studio.exe` | main assembly | UI, search/browse, pricing display, order submission, library management, launching the backend |
| Rhino-hosted `CounterSketchServer` | `CounterSketchServer.rhp`, `IRhinoServices` (383 ops), `netTcpBinding_IRhinoServices_IRhinoServices` + `http://localhost:8556/RhinoServices/mex` | all 3D/CAD work: loading designs, gems, metals, viewport, freehand modelling, print/CAM export |
| V-Ray render host | `VRay\dlls`, `commonappdata\ASGVIS\...\Python26`, `VRayForMatrix.rhp` | photorealistic rendering of designs into the UI tiles and order images |
| `CefSharp.BrowserSubprocess.exe` | shipped | Chromium render/GPU subprocess for the embedded browser |
| `CounterSketchUpdateInstaller` | shipped folder (21.3 MiB) | self-update |
| `GemvisionApplicationManager` | shipped folder (8.9 MiB) | launcher / application management |
| `Troubleshooter` | shipped folder (24.1 MiB) | diagnostics collection |

## 3. Service contracts (from `CounterSketch Studio.exe.config` + generated proxies)

Configured WCF bindings — each name is a contract the app actually consumes:

```
basicHttp/basicHttps : ISecurityService            (activation/licensing)
                       IPartsLibraryService        (component/parts library)
                       ILibraryService             (design library service)
                       IStullerOrderService        (order submission; 1-min open,
                                                    10-min receive, 5-min send timeouts)
                       IDesignExportService        (export of designs upstream)
                       IKeyCodeService             (key codes / activation keys)
                       IFeatureService             (feature entitlements)
netTcp               : IRhinoServices (reliable session, no TLS, local)
mex                  : http://localhost:8556/RhinoServices/mex
```

Endpoints referenced from code (occurrence counts from the decompiled corpus):

```
369  http://CounterSketch.biz/                     (XML/data namespace for local documents)
 21  http://services.stuller.com
 14  https://api.stuller.com/v2/
 13  http://services.stuller.com/v3/GemVision      (GemVision-specific service version)
  2  http://localhost:8556/RhinoServices/mex
```

`GV.CounterSketchServices.WebServices\CounterSketchService.cs` (1,002 methods) and `…RhinoServicesReference\RhinoServicesClient.cs` (1,538 methods) are the generated clients for the two big contracts.

## 4. The CAD backbone: `IRhinoServices` — 383 operations

Every operation is exposed **twice** (sync + `Begin*` async), which is the signature of a generated duplex/async WCF contract. The operation names map the domain precisely:

* **Freehand modelling**: `ToggleFreehandCommonCenterMode`, `ToggleFreehandVisibility`, `GetFreehandComponentVisibility`, `TurnHandOff`, `UpdateCurveObjectFromUI`, `UpdateValueChooserFromUI`, `UpdateViewPortHandleDrawScale`
* **Gems**: `GetManualSizedStones`, `ToggleQuarterCaratGemRounding`, `HighlightAccentGems`, `HighlightGemFromGemReportByGemNumber|ByIndex`
* **Viewport/camera**: `ViewportSetBackgroundAndColor`, `ViewportSetHighlightColor`, `ViewportSetTargetAndCameraLocation`, `ToggleViewportControls`
* **Assembly/graph**: `GraphItemRemoveUserDataValue`, `GraphUndoChange`, `HighlightGraphItem`, `HighlightItemsByBlockInstanceGuid`
* **Import/parts**: `ImportGroupAddRingRailGuide`, `ImportGroupAddToPartGroup`, `UpdateImportGroupPartListGroupAssignment`, `UpdateImportGroupSortOrder`
* **Materials/environment**: `UpdateRhinoAppearanceMaterials`, `UpdateRhinoHand`
* **Firmware/device**: `UpdateFirmwareAndActivate`, `WatcherSetEnabled`
* **UI bridging**: `UpdateStudioUICallbackChannel`, `UpdateUIControl`, `UpdateUIControlQuick`

This is the single most important interface to reimplement: **the UI is a thin client over a persistent CAD service.**

## 5. Client architecture (WPF shell)

* **Pattern**: MVVM with MVVM Light (`GalaSoft.MvvmLight`, `Messenger`), 56 files under `…Studio.ViewModel`, 51 under `…Studio.View`, 47 `…Studio.Controls`, 53 `…Studio.Utilities.Helpers`.
* **Notable helpers**: `SearchHelper` (27 methods — design search/filters), `GemHelper` (5), `StullerProductAPIHelper` (24 — mapping GemVision domain terms to Stuller product filters), `StullerProductAPIHelper.GetAGTADescriptionFromCode`, `ConvertGemvisionCounterSketchStoneShapeToStullerStoneShapeString`, `HtmlToXamlConverter`, `SecurityHelper`.
* **Third-party UI**: DevExpress XPF v16.1 (grid, layout, printing, themes — "Office2016White"), Telerik, `WPFMitsuControls` (the flip-book control used in the design browser), `FontAwesome.WPF`, `EmbeddedFonts.dll` (18.2 MB).
* **Embedded browser**: `CefSharp.Wpf` 75.1.142.0 + `chrome_elf.dll` + `cef*.pak` + `swiftshader`. There are **no local HTML/JS assets** in the shipped tree (the 251 `.html` files it contains belong to the V-Ray/PyQt runtime), so CEF is used for *remote/web-hosted content* (help, dashboards, Stuller web pages) rather than a local SPA.
* **Realtime**: `EngineIoClientDotNet.dll` ships with the app → a socket.io/Engine.IO client for live updates alongside the WCF calls.
* **Localization**: `locales\`, `de el es fr it ja pt zh` satellite resource files, `Localization` namespace in `Program.cs` usings.

## 6. Data and persistence

| Store | Evidence | Notes |
|---|---|---|
| Remote catalog & pricing | `Stuller.Web.Services.GV.Pricing` (30 files), `CounterSketchService`, `api.stuller.com/v2/` | authoritative product/price data lives server-side |
| Design libraries | `Library\` (104.6 MiB, 272 files) | `.csg` (Rhino geometry), `.gem`, `.geocomp`; packed/versioned by `DesignLibrary.dll` |
| Local SQL | `System.Data.SQLite` + `x64\x86\SQLite.Interop.dll`, `EntityFramework` + `EntityFramework.SqlServer`, `SqlConnection` usages in `GV.CounterSketch.Shared.DataAccess` | EF6/SQLite are shipped; the app's own data-access layer opens ADO.NET connections |
| Printer parameters | `CounterSketchServer\PrinterDB\{paramsdb.db, stopp.db, standard_params_db}` | `standard_params_db` is 7.17 MiB of plain parameters; the two `.db` files are **not SQLite** (see report 04 §7) |
| Design/render assets | `System\RenderMaterials\*` (`265 .vismat`, `15 .visopt`, `35 .hdr`, diamond refraction maps) | V-Ray materials and environments; `.vismat`/`.visopt` are XML |
| Update staging | `commonappdata\Microsoft\Network\Downloader\` | payload download area |

## 7. Interop and native boundary

Managed→native transitions documented in the tree: `GeoBasicInterop.dll` (managed bridge), `Interop.RhinoScript4.dll`, `Microsoft.Surface.NativeWrappers.dll`, and the `CounterSketchServer\Platform\*` native SDKs, all of which plug into a Rhino process. REA classified a native-vs-managed map of the backend directory → `evidence/native-dll-classification.txt`; the corresponding native analysis is described in report 06.

## 8. Startup and command-line contract (`Program.cs`)

The entry class carries CLI state that reveals how the app is driven *by its own launcher and by other GemVision components*:

```
designId, designVersion, filePath, fingerSizeUS, gem1, gem2, gem3, metal1, metal2,
iterationId, iterationIndex, rhinoInstallPath, rhinoPluginPath, noServer (flag)
```

plus: a **named-pipe** channel (`System.IO.Pipes`) for cross-process signalling, a splash thread, an **activation thread**, registry access (`Microsoft.Win32`), `Process.Start` for child processes, and the constant
`SecurityKeyword = "G3mv1s10nK3yPr0f1l3Upd4t3r!"` (a security/key-profile updater token). Config keys observed: `DisableRhinoPlugins` (three plugin GUIDs), `EventLoggingVerbosity`, `DebugOrderEmail`, `KeyProfile` GUID.

A second instance launched with a design id + gem/metal/iteration arguments and `--no-server` hands work to the running instance through the pipe channel — i.e. **the app is both an interactive tool and a render/export engine for callers.**
