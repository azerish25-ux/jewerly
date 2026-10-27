# 02 — `CounterSketch Studio.exe`: binary layout, the 199 MiB payload, and the decompiled corpus

**File:** `Main\CounterSketch Studio.exe` — 214,248,448 bytes
**SHA-256:** `228daa515e2e0a95d554bd45f484521689791aef8d84f7dd093ed3bc88fd3430`
**Evidence:** `evidence/app-clr-header.json`, `evidence/app-resources.txt`, `evidence/app-types.txt`, `evidence/managed-artifact-*.json`

## 1. PE and CLR identity

| Field | Value |
|---|---|
| Machine | `0x8664` (x86-64), `PE32+`, GUI subsystem |
| Sections | 2 — `.text` (214,225,920 B), `.rsrc` (21,843 B) |
| Build timestamp in PE header | 2019-11-19 18:19:58 UTC |
| CLR header | at file offset `0x200`, `cb`=72, runtime metadata version `v4.0.30319` (.NET Framework 4.x) |
| CLR flags | `0x00000001` = **ILONLY** |
| Entry-point token | `0x06000bf8` |
| Metadata | RVA `0xc804428`, size **4,501,380 B** (~4.3 MiB) at file offset `0xc802628` |
| **Managed resources** | RVA `0x116000`, size **208,593,960 B (198.9 MiB)** at file offset `0x114200` |
| Strong-name signature | RVA 0, size 0 → **unsigned** |
| Target framework | v4.6.2 (from `CounterSketch Studio.exe.config`) |

### Layout map

```
0x000000  MZ / PE headers, .rsrc ……………………… small
0x000200  CLI header (72 B) + ~1.1 MiB of IL method bodies
0x114200  198.9 MiB  .g.resources   <-- the "mystery" high-entropy region
0xc802628 4.5 MiB    .NET metadata (#~ tables, #Strings, #US, #Blob)
0xcc4d600 .rsrc (VERSIONINFO / manifest)
0xcc52c00 end of file
```

## 2. How the "mysterious 190 MB" was resolved

Initial static probes (entropy per 1 MB, IL-opcode density, archive-signature counts) showed the file was **not** a normal assembly and **not** a plain archive:

* entropy ≈ 7.99 from ~1 MB to ~200 MB; only the first ~1–2 MB contains real IL (29,108 `ldstr` + 24,226 `call` tokens in the first MB, dropping to chance level afterwards);
* no `PK`/7z/RAR/gzip/zlib streams; scattered readable strings (`StullerImage`, `Uniform=`, `Edit CAD/CAM Profile`, `https://www.stuller.com/countersketchstudio/cadcamprofile?`) that look like markup, not code.

Two hypotheses were live: (a) a self-extracting/encrypted container appended by a packer, (b) an ordinary embedded resource payload. The deciding datum is the **CLI header's own `Resources` field** — which is *not* the PE data-directory 15 (that slot is reserved in the PE optional header, which is why the first, naive scan showed "0"):

```
Resources RVA = 0x116000   size = 208,593,960
```

That is precisely the high-entropy region. **Conclusion: the payload is the assembly's managed-resource blob (`.g.resources`), i.e. WPF compiled XAML + images — not an encrypted container and not a self-extracting bundle.** The readable strings are BAML markup leaking plaintext, exactly as expected.

Corroboration: `ilspycmd --list-resources` lists **855 entries** inside `CounterSketch Studio.g.resources` (BAML views, resource dictionaries, UI images, render prop materials, filter icons, gem-colour thumbnails …) and ILSpy extracted them without any decryption step.

## 3. Resource payload inventory

* 855 entries inside the single `.g.resources` container (list: `evidence/app-resources.txt`).
* Extracted by `ilspycmd -p` into `build/app-decompiled/`:
  **475 PNG, 112 JPG, 71 BMP, 4 ICO and 113 XAML** files (BAML → XAML), e.g. `resourcedictionaries\{brushes,colors,controls,datatemplates,gemshapeicons,…}.xaml`.
* Content types observed: UI chrome and icons, search-filter facet images (gem shapes, gem colours, metals, design elements), design "tile" composites for the browsing UI, render prop materials (`images/render/propmat/*.bmp`), and stored view markup (`views/*.baml`).

## 4. The managed code

* `ilspycmd -p` completed with **exit 0** (`cache/tmp/ilspy-full.log`), producing **1,229 C# files / 5,827,717 bytes** of source, 1,331 classes (`evidence/app-types.txt`), plus the extracted resources — **238 MB** total in `build/app-decompiled/`.
* Structure of the assembly (see report 03): MVVM WPF shell (`GV.CounterSketch.Studio.*`), shared domain model (`GV.CounterSketch.Shared.{CAD,Model,DataAccess,Pricing}`), generated service proxies (`GV.CounterSketchServices.WebServices`, 323 files; `GV.CounterSketch.Studio.RhinoServicesReference`, 100 files), and the design-library codec (`DesignLibrary.*`).
* Heaviest members measured: `RhinoServicesClient.cs` **1,538 methods**, `CounterSketchService.cs` **1,002 methods**, `SearchClass.cs` 1.6 MB, `OrderSummaryViewModel.cs` 128 KB, `MainViewModel.cs` 94 methods.
* A `SmartAssembly.Attributes.PoweredByAttribute` type is present (Red Gate SmartAssembly was part of the build pipeline), but **no encryption, packing or name obfuscation is in effect**: IL decompiled cleanly, names are fully readable, resources parse. No deobfuscation step was required.

## 5. Integrity of the analysis (no modification of the original)

The decompile ran against a byte-identical copy (`build/inputs/app/CounterSketchStudio.exe`, SHA-256 verified equal). REA operates on immutable snapshots of its own. The originals in `Main\` were re-hashed after all work (§ report 06).

## 6. REA's managed provider — what it gave us, and its one hard limit

REA's execution-free managed provider **rejected the main executable**:

```json
{"code":"resource_constraint",
 "message":"Managed static inspection requires an eagerly retained PE snapshot within its input byte budget.",
 "details":{"reported_limits":{"max_snapshot_bytes":134217728}}}
```
(evidence: `evidence/managed-artifact-app.json`)

The budget is a **fixed 128 MiB**, and the file is 214 MB, so this target can never be inspected by that provider — a limitation of the tool, not of the file. Routing used instead:

1. **ILSpy** for the whole-assembly decompile (no size limit), which is also the only path that produces readable C#.
2. **REA's managed provider on the in-budget assemblies**, which works excellently. Verified on `DesignLibrary.dll` (2.9 MB):
   * `inspect-managed-artifact` → classification `managed`, `dotnet-framework`, CIL, anycpu; metadata `v4.0.30319` complete; full table row counts (TypeDef 32, MethodDef 166, MemberRef 182, AssemblyRef 8, …); assembly identity `DesignLibrary 1.0.18015.10002`; `evidence_id ev_e7d35366…`
   * `inspect-managed-members` → types, methods, call edges, field accesses, user strings; `evidence_id ev_439fd783…`
   * Notably its type list *is* the library-format codec: `DesignLibrary.{CSGLLibrary, LibraryPacker, LibraryDBBuilder, Payload, FileData, OldLibraryConverter.ZipIt.LocalFile, GemAttribFix, NameFreeHandParts, SlackClient}` and `extractlibrary.SearchClass`.
   * Evidence: `evidence/managed-artifact-designlibrary.json`, `evidence/managed-members-designlibrary.json`.

## 7. Two builds

The installer carries a second, smaller build (214,162,040 B) of the same assembly with an identical PE timestamp — see report 01 §6. Diffing them member-by-member is a one-command follow-up (`compare-managed-members`), outside the scope requested here.
