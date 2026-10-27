# 06 — The native layer: a custom geometry & 3D-print kernel behind a managed Rhino plugin

The backend is not "just Rhino". `CounterSketchServer\` contains a **managed Rhino plugin plus a large custom C++ kernel** (MSVC 2010 x64, `msvcp100/msvcr100`, Boost 1.54, OpenVDB 2.1.0, TBB). This report documents that layer, with the tools and commands used, so it can be extended on demand.

Evidence: `evidence/native-dll-classification.txt`, `evidence/native-analyze-meshcmp.dll.json`, plus export/import tables parsed with `pefile` (commands reproduced at the end).

## 1. Managed vs native map (measured, `CounterSketchServer\` and below)

| Module | Size | Kind | Notes |
|---|---|---|---|
| `CounterSketchServer.rhp` | 10.65 MiB | **MANAGED** (PE32) | the .NET Rhino plugin = the `IRhinoServices` host |
| `SharedTypes.dll` | 6.23 MiB | MANAGED (PE32) | shared types between plugin and kernel |
| `Platform\csharp.print.headless.dll` | 33.23 MiB | NATIVE x64 | print/CAM pipeline, headless |
| `Platform\csharp.print.v2.dll` | 30.66 MiB | NATIVE x64 | print pipeline v2 |
| `Platform\geoisdk.dll` | 29.19 MiB | NATIVE x64 | geometry SDK core (single `EntryPoint` export → **component plugin**) |
| `Platform\gpcorecmp.dll` | 25.81 MiB | NATIVE x64 | **1,652 exports**, printer/driver core (see §3) |
| `Platform\gplandercmp.dll` | 8.66 MiB | NATIVE x64 | path/planning component (uses `ws2_32`, `crypt32`) |
| `Platform\meshcmp.dll` | 6.15 MiB | NATIVE x64 | mesh component — **32,433 procedures / 3,579 strings** (Ghidra) |
| `Platform\voxelsvdb.dll` | 6.13 MiB | NATIVE x64 | **OpenVDB 2.1.0** voxel grids + TBB (836 exports) |
| `Platform\FFF.dll` | 5.69 MiB | NATIVE x64 | **curve/surface fitting engine** (317 exports) |
| `Platform\surfacefitting.dll` | 5.51 MiB | NATIVE x64 | surface fitting, imports `fff.dll` |
| `Platform\curvenet.dll` | 5.18 MiB | NATIVE x64 | curve networks, imports `fff.dll` |
| `core_utils.dll` | 4.76 MiB | NATIVE x64 | shared utilities |
| `Platform\watsoncmp.dll`, `geofeature.dll`, `featurescmp.dll`, `pointsmod.dll`, `curvesetcmp.dll`, `gpslacmp.dll`, `aligncmp.dll`, `geosurfacing.dll`, `canvas_utils.dll`, `imageio.dll`, `geofeature_app.dll`, `geoselection.dll` | 3–4.6 MiB each | NATIVE x64 | feature modelling, points, curve sets, surface analysis, alignment, canvas/image IO, selection |
| `GeoBasicInterop.dll` | 336 KiB | **MANAGED** | the managed↔native bridge; REA correctly refused it for the Ghidra lane (`managed_target_unsupported`) — see `evidence/native-analyze-geobasicinterop.json` |

## 2. Component-plugin architecture

Most kernel modules export **exactly one symbol — `EntryPoint`** (`geoisdk`, `gplandercmp`, `meshcmp`, `curvenet`, `aligncmp`, `imageio`, `surfacefitting`, `geosurfacing`, …). They are therefore **plugins loaded by a host** (the SDK/plugin host inside the Rhino process) rather than link-time libraries — a deliberate modular CAD architecture. Consequence for analysis: the useful API surface is not in the export table; it is reached through the host's internal object model, which is why REA's Ghidra analysis (function inventory + decompilation) is the right tool rather than export parsing.

## 3. What the exported APIs reveal

* **`gpcorecmp.dll` — printing/driver core.** 1,652 exports around `ZPrinterSrv::CZPrinterInfo` / `CZDriverOL`: `FindPrinter`, `DestroyDriver`, `DropPistonToPos`, `AutoAlignSupport`, `DefaultAlignmentSupport`, `ExportTableSupport`, `GetBitsPerPixel`, `GetClassNameA`, `DesktopCanLog`, `CancelReservation`. "ZPrinter" is the ZCorp-style powder 3D-printer family, so this module is the **machine driver layer**; it imports `crypt32`, `ws2_32`, `iphlpapi` (licensing/network) and Boost 1.54 (regex, threads, date-time).
* **`voxelsvdb.dll` — solid/voxel geometry.** 836 exported symbols from OpenVDB 2.1.0 (`openvdb::math::AffineMap`, `openvdb::io::Archive/File`, `openvdb::GridBase`, exceptions), plus TBB — i.e. volumetric (watertight solid) modelling for additive manufacturing.
* **`FFF.dll` — curve & surface fitting.** 317 exports: `CurveFairer`, `CurveLifter`, `GeneralCurveFitter`, `PlanarCurveFitter`, `SpatialCurveFitter`, `SurfaceFitter` with `AddPointGroup` / `AddNormalGroup`. This is the maths behind converting user-drawn curves into smooth jewellery surfaces — the technical core of "freehand" modelling.
* **`geofeature.dll` — interactive feature targeting.** 64 exports: `GeoTargetLineParametricUtil`, `GeoTargetPointParametricUtil`, with direction constants `AHEAD/BEHIND/LEFT/RIGHT/TOP/BOTTOM/INSIDE` and `computeOutCode_`, `computeDefaultSelectionOnModel_`, operating on an `IGeoMesh` interface — the machinery for "select this face/edge and edit it".
* **`imageio.dll`, `canvas_utils.dll`** — image/canvas I/O used by the print/document path.

## 4. Verified REA + Ghidra run

```
bash tools/rea-d.sh analyze "<...>/CounterSketchServer/Platform/meshcmp.dll" --provider ghidra --json
```

Result (`evidence/native-analyze-meshcmp.dll.json`, exit 0):

```json
{ "operation": "binary_overview",
  "evidence_id": "ev_66457abc6c870f47e3ac8…",
  "document": "target-cbd9344626b6.dll",
  "image_base": "0x180000000",
  "segments": 9, "segment_count": 9,
  "procedure_count": 32433, "string_count": 3579 }
```

So a real Ghidra import + auto-analysis completed under REA's Windows P0 boundary on a 6.15 MiB x64 native DLL. The same command shape works for every native module in the table above; the two rejected/limited cases were reported by REA itself and are documented, not hidden:

* managed targets (`GeoBasicInterop.dll`, and every `.rhp`/`.dll` classified MANAGED) → `managed_target_unsupported` (correct behaviour; managed work goes through the managed provider or ILSpy),
* Hopper/IDA/Kuna → not configured on this host by design (Ghidra was the requested engine).

## 5. Going deeper (ready-to-run, not run here)

| Task | Command |
|---|---|
| Full pseudocode of a module | `bash tools/rea-d.sh decompile-all "<module>.dll" --output build/native-decompiled/<module>` |
| One interesting function | `bash tools/rea-d.sh function "<module>.dll" <name\|address> --provider ghidra --json` |
| Symbol/string search | `bash tools/rea-d.sh search "<module>.dll" entry --kind procedures --provider ghidra --json` |
| Cross-references | `bash tools/rea-d.sh xrefs "<module>.dll" 0x<addr> --provider ghidra --json` |
| Value tracing | `bash tools/rea-d.sh trace "<module>.dll" <pattern> --provider ghidra --json` |

**Scale expectation (stated honestly):** `meshcmp.dll` alone auto-analysed to **32,433 procedures**; the kernel as a whole is ~150 MiB of x64 C++ across ~20 modules. Full pseudocode export is a multi-hour, multi-gigabyte job — a targeted question (e.g. "how is a ring rail fitted to a user curve?" → `FFF.dll`/`surfacefitting.dll`/`curvenet.dll`) is the efficient entry point.

## 6. Reproduction commands for this report

```bash
# managed/native classification of the backend tree
python - <<'PY'   # (see evidence/native-dll-classification.txt for the exact output)
...   # parses each PE's machine + CLI data directory
PY

# export/import tables of the kernel modules
cache/venv/Scripts/python.exe - <<'PY'
import pefile
pe = pefile.PE(".../Platform/geoisdk.dll", fast_load=True)
pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXPORT'],
                                       pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_IMPORT']])
print([e.name for e in pe.DIRECTORY_ENTRY_EXPORT.symbols if e.name])
print([imp.dll for imp in pe.DIRECTORY_ENTRY_IMPORT])
PY
```
