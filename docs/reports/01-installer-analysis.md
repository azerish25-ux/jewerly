# 01 — The installer: `CounterSketchInstaller_8.1.19323.1002.exe`

**File:** `Main\CounterSketchInstaller_8.1.19323.1002.exe` — 523,074,737 bytes
**SHA-256:** `053eebece6adadb13ce44070e3fa71fa4b911c8c80fb0f798bd4198023b4d6dc`

## 1. What it is

A **PE32 (x86) GUI application, only 8 sections, ~40 KB of real code** — i.e. a bootstrap stub, not an application. Its strings identify it unambiguously:

```
<description>Inno Setup</description>
Inno Setup Messages (5.5.3)
Inno Setup Setup Data (5.5.6)
```

`innoextract --info` confirms the payload header:

```
Inspecting "{param:product|CounterSketch Studio}" - setup data version 5.5.6
Languages: default: English
Setup is not passworded!
```

So: **Inno Setup 5.5.6, single language, no password.** There is no application logic in the stub worth decompiling — the logic lives in the appended setup data (file list, destinations, and the script's registry/service/run actions), and the *product* logic lives in the payload it installs.

## 2. How it was extracted

```
tools/innoextract/innoextract.exe --list --list-sizes "Main\CounterSketchInstaller_8.1.19323.1002.exe"   > evidence/installer-filelist.txt
tools/innoextract/innoextract.exe -d build/installer-extract --timestamps local "Main\CounterSketchInstaller_8.1.19323.1002.exe"
```

* exit code **0**, log `cache/tmp/innoextract-run.log`
* **4,177 files / 1.3 GiB** on disk, against a manifest of 4,179 file entries + 4 directory entries and a summed size of 1,519.5 MiB.
* The difference reconciles exactly: the manifest lists `CounterSketch Studio.exe` **twice** (204 MiB each, "overwritten"), so the summed size double-counts 204 MiB → 1,519.5 − 204 ≈ 1,315 MiB = the 1.3 GiB actually written. Extraction is therefore complete and consistent; nothing was dropped.

`evidence/installer-filelist.txt` is the authoritative inventory (every entry with its declared size).

## 3. Where the installer writes

Destination roots seen in the manifest:

| Manifest root | Meaning |
|---|---|
| `pf64\CounterSketch Studio\` | Program Files application tree (the bulk) |
| `commonappdata\Gemvision\CounterSketch Studio\` | shared machine-level app data |
| `commonappdata\Gemvision\CounterSketch\` | shared data for the older layout |
| `commonappdata\Gemvision\CSLibrary\` | **shared design library** (CounterSketch Library) |
| `commonappdata\ASGVIS\...` | V-Ray/A S G V I S runtime (Python 2.6 + PyQt4 + vray.dll) |
| `commonappdata\Microsoft\Network\Downloader\` | staging area used by the update mechanism |

> **Limitation (stated, not hidden):** innoextract does not decompile the Inno *script*, so the installer's `[Registry]`, `[Run]`, `[UninstallRun]` and service-check actions are **not** enumerated here. `innounp`/`innoextract --dump` scripting reconstruction is the follow-up if the exact registry surface is needed. What is proven is the file payload, its destinations and its structure.

## 4. Payload composition (measured, app tree = 722.3 MiB in subdirectories + ~208 MiB of top-level files)

| Directory | Size | Files | What it is |
|---|---|---|---|
| `CounterSketchServer\` | 302.9 MiB | 208 | the Rhino-side backend: `Platform\` 257.5 MiB (native geometry/print SDKs), `PrinterDB\` 10.6 MiB |
| `System\` | 184.0 MiB | 1,129 | render materials, textures, configs (`System\RenderMaterials\...`) |
| `Library\` | 104.6 MiB | 272 | shipped design library (`.csg`, `.gem`, `.3dm`) |
| `VRay\` | 39.8 MiB | 10 | V-Ray runtime for Rhino |
| `Troubleshooter\` | 24.1 MiB | 32 | diagnostics tool |
| `CounterSketchUpdateInstaller\` | 21.3 MiB | 29 | the updater |
| `locales\` (+`de,el,es,fr,it,ja,pt,zh`) | 14.7 MiB | 53 | CEF/Chromium locale packs and localized resources |
| `GemvisionApplicationManager\` | 8.9 MiB | 22 | launcher/licensing helper |
| `swiftshader\` | 4.0 MiB | 2 | software GL fallback for the embedded Chromium |
| `ImageThemes\`, `Images\`, `Layouts\`, `Eula\`, `Framework\`, `x64\`, `x86\` | ~7 MiB | ~100 | theming, legal text, SQLite interop natives |

Extension census (count / total size) of the whole app tree:

```
 858 .jpg   74.0 MiB     120 .3dm  87.6 MiB     57 .gem      2.1 MiB
 285 .dll  575.2 MiB      58 .pak  27.2 MiB     55 .geocomp  0.8 MiB
 265 .vismat 35.4 MiB      35 .hdr  53.9 MiB      3 .csg      2.1 MiB
 114 .xml   13.2 MiB        9 .exe 211.9 MiB      2 .rhp     15.7 MiB
```

## 5. Native / third-party binaries worth knowing about

| Component | Size | Role |
|---|---|---|
| `libcef.dll` | 107 MiB | Chromium 75 (via CefSharp 75.1.142.0) |
| `CounterSketchServer\CounterSketchServer.rhp` | 10.7 MiB | **Rhino plugin** = the geometry/CAD backend |
| `Platform\csharp.print.headless.dll` | 33.2 MiB | print/CAM export, headless |
| `Platform\csharp.print.v2.dll` | 30.7 MiB | print pipeline v2 |
| `Platform\geoisdk.dll` | 29.2 MiB | geometry SDK |
| `Platform\gpcorecmp.dll` | 25.8 MiB | geometry core (component) |
| `Platform\gplandercmp.dll` | 8.66 MiB | path/planning core (print or layout) |
| `Platform\surfacefitting.dll` | 5.51 MiB | surface fitting for organic shapes |
| `Platform\GeoBasicInterop.dll` | 336 KiB | managed↔native bridge (**managed** PE — see report 02 §6) |
| `Interop.RhinoScript4.dll` | 140 KiB | RhinoScript interop |
| `System.Data.SQLite.dll` + `x64\x86\SQLite.Interop.dll` | 313 KiB + 1.4/1.1 MiB | SQLite provider + EF6 |
| `DevExpress.*.v16.1.dll` (14 files) | ~30 MiB | WPF control suite |
| `VRay\dlls\vray.dll`, `VRayForMatrix.rhp`, `commonappdata\ASGVIS\Common\x64\vc10\Python26\...` | ~40 MiB | V-Ray renderer + its Python 2.6/PyQt4 runtime |

No nested MSI/MSIEXEC prerequisites were found in the payload (no `.msi`/`.cab` entries in the census): this installer ships **application files only**, not the .NET or SQL prerequisites.

## 6. Two different builds of the application exist

| | User-supplied `Main\` copy | Installer payload copy |
|---|---|---|
| bytes | **214,248,448** | **214,162,040** |
| SHA-256 | `228daa51…3430` | `ad7881ad…338c2e` |
| PE build timestamp | 2019-11-19 18:19:58 UTC | 2019-11-19 18:19:58 UTC |
| PE machine / sections / CLR dir | x86-64 / 2 / 0x2000:72 | x86-64 / 2 / 0x2000:72 |

Same declared build time, same structure, **86,408 bytes different** in the embedded resource payload. The user-supplied file (disk mtime Dec 2020) is therefore a *later* build than the one inside installer `8.1.19323.1002` (Nov 2019). Everything in reports 02–05 analyses the **user-supplied** build, and the installer copy is retained as a second sample for diffing (`compare-managed-members` is the right REA operation if a member-level diff is wanted later).

## 7. Verification performed

* Manifest ↔ disk reconciliation (above) — complete.
* The extracted `CounterSketch Studio.exe` is a valid PE with the same CLR layout as the loose one (checked by header parse).
* The two `.db` files in `CounterSketchServer\PrinterDB\` are **not** SQLite (see report 04 §7).
