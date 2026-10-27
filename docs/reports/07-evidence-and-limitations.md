# 07 — Evidence index, verification, and what was *not* established

## 1. Evidence files (all under `evidence\`)

| File | Produced by | Proves |
|---|---|---|
| `baseline-hashes.json` | python sha256 | identity of the two source binaries before/after work |
| `installer-filelist.txt` | `innoextract --list --list-sizes` | the installer's complete file/dir/size manifest |
| `app-clr-header.json` | PE/CLI header parse | the 198.9 MiB managed-resource field and the file layout map |
| `app-resources.txt` | `ilspycmd --list-resources` | 855 embedded resource entries (BAML + images) |
| `app-types.txt` | `ilspycmd -l c` | 1,331 declared classes |
| `managed-artifact-app.json` | `rea inspect-managed-artifact` | REA's **fixed 128 MiB** managed-snapshot budget (the main exe cannot be fed to it) |
| `managed-artifact-designlibrary.json` | `rea inspect-managed-artifact` | full CLI metadata tables, identity, classification for an in-budget assembly |
| `managed-members-designlibrary.json` | `rea inspect-managed-members` | types/methods/fields/call edges/user strings; the library-codec type list |
| `desktop-application.json` | `rea inspect-desktop-application` | REA's directory-level Evidence: 2,065 entries examined, `dotnet` candidate, 149 next probes |
| `rea-doctor-initial.json`, `rea-doctor-ghidra.json` | `rea doctor` | tool readiness; Ghidra provider fully healthy on this host |
| `rea-setup-freebuff.json` | `rea setup --client freebuff` | MCP registration plan/applied actions for Freebuff |
| `mcp-registration.json` | copy of `~/.agents/mcp.json` | exact registered launcher (D-drive node + rea.mjs) |
| `native-dll-classification.txt` | PE parse | managed vs native map + sizes of the whole backend tree |
| `native-analyze-geobasicinterop.json` | `rea analyze --provider ghidra` | REA's correct refusal of a **managed** target (`managed_target_unsupported`) |
| `native-analyze-meshcmp.dll.json` | `rea analyze --provider ghidra` | a genuine Ghidra run: 9 segments, 32,433 procedures, 3,579 strings |

Extracted artefacts (not evidence, but reproducible outputs):

| Path | Content |
|---|---|
| `build/installer-extract\` | 4,177 files / 1.3 GiB — the installer payload, byte-for-byte as shipped |
| `build/app-decompiled\` | 1,229 C# files (5.83 MB source) + 113 XAML + 662 images extracted from the resource payload (238 MB) |
| `build/inputs/app\CounterSketchStudio.exe` | byte-identical working copy of the analysed binary (sha256 verified) |
| `cache/tmp/ilspy-full.log` | `exit=0` for the full decompile |

## 2. Verification actually performed

| Check | Result |
|---|---|
| Source binaries unchanged | **PASS** — re-hashed at the end; both SHA-256 values match `baseline-hashes.json` |
| Installer extraction completeness | **PASS** — 4,177 files vs a 4,179-entry manifest whose only duplicate is the "overwritten" app exe; sizes reconcile to ±1 MiB |
| Decompile ran to completion | **PASS** — `ilspycmd -p` exit 0; 1,229 `.cs` files produced and spot-read for this report set |
| Resource payload readable without decryption | **PASS** — `--list-resources` enumerated 855 entries; extraction produced images + XAML |
| REA managed provider | **PASS on in-budget targets** (DesignLibrary.dll fully inspected); **inapplicable** to the 214 MB main exe by design (128 MiB budget) |
| REA native provider | **PASS** — Ghidra 12.1.4 import + analysis of a native x64 module with an Evidence id |
| REA desktop-application inspection | **PASS** — Evidence id `ev_0f218b0a…` with coverage `complete-within-scan` |
| Claim cross-checks | Spot-checks of decompiled C# against binary strings and against config files (e.g. the WCF binding names in `CounterSketch Studio.exe.config` match the proxy namespaces) |
| REA MCP tools visible in this session | **NOT TESTED** — requires a Freebuff restart; all REA work here went through the CLI |

## 3. Limitations — stated plainly

1. **No runtime observation.** By your decision this was a static-only engagement: the product was never installed, launched or traced. Consequently:
   * the exact arithmetic behind a displayed price, the render settings actually used, and the runtime behaviour of the activation handshake are **not** established;
   * REA has no Windows process-capture path (its process capture is Linux/macOS only), and no Frida-based Windows workflow is documented by REA, so runtime tracing would need a separate plan with your approval.
2. **Installer script semantics not dumped.** innoextract does not reconstruct Inno's `[Registry]`/`[Run]`/`[UninstallRun]` actions, so the registry surface and any service/first-run actions of the installer are not enumerated (`innounp` or `innoextract --dump` is the follow-up).
3. **REA's 128 MiB managed snapshot budget** excludes the 214 MB main executable from `inspect-managed-*`. Workarounds used: ILSpy for decompilation, REA's managed provider for the in-budget assemblies.
4. **Native depth is inventory-level in this pass.** One module was fully auto-analysed (32,433 procedures) and the export/import surfaces of the kernel were parsed, but no module was decompiled to pseudocode wholesale — that is a multi-hour job and is queued as follow-up work (report 06 §5 has the exact commands).
5. **Obfuscated/encoded data left undecoded by choice.** `PrinterDB\paramsdb.db` and `stopp.db` are base64-encoded blobs; I did not guess their inner format. Decoding them is a bounded task once a decode hypothesis is available.
6. **Two builds exist** (user-supplied vs installer payload, 86,408 bytes apart). Only the user-supplied build was analysed in depth; a member-level diff is available via `compare-managed-members`.
7. **V-Ray internals** were treated as a third-party runtime (its 1,029 Python files are Chaos Group/ASGVIS code, not CounterSketch logic) and were not reversed.
8. **No licence circumvention.** The security/entitlement layer is documented as a mechanism; nothing was bypassed, patched or tested against a live service.

## 4. Reproduce anything in this report set

```bash
cd "/d/MAIN SOFTWARE/jewerly software/countersketch"
bash tools/rea-d.sh <rea-command> …          # everything D-pinned
cmd.exe //c "tools\rea-d.cmd <rea-command>"  # cmd/PowerShell equivalent
"tools/ilspycmd/ilspycmd.cmd" -p -o build/app-decompiled build/inputs/app/CounterSketchStudio.exe
tools/innoextract/innoextract.exe -d build/installer-extract "Main/CounterSketchInstaller_8.1.19323.1002.exe"
```
