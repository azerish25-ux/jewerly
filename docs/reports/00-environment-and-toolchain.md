# 00 — Environment, toolchain and evidence policy

Everything for this project lives on **D:** in
`D:\MAIN SOFTWARE\jewerly software\countersketch\`.

```
countersketch\
  Main\                 the two user-supplied binaries (never modified)
  tools\                node\ rea\ jdk-21\ ghidra_12.1.4_PUBLIC\ innoextract\ 7zip\ dnspy\ dotnet\ ilspycmd\ venv\
                        rea-d.cmd  rea-d-home.cmd  rea-d.sh        <- pinned launchers
  cache\                npm\ nuget\ pip\ dotnet-cli\ tmp\ venv\
  build\                inputs\ installer-extract\ app-decompiled\
  evidence\             raw REA Evidence JSON, listings, hashes
  reports\              this documentation set
```

## Toolchain actually installed (verified, not assumed)

| Tool | Version | Location | Purpose |
|---|---|---|---|
| Node.js | **v24.22.1** (npm 11.19.1) | `tools/node` | REA runtime (system Node v24.18.0 was **too old**: REA requires `^22.23.4 \|\| ^24.22.1 \|\| >=26.12.1`) |
| rea-agents | **6.8.0** | `tools/rea` (npm global prefix on D) | MCP + CLI reverse-engineering toolchain |
| Ghidra | **12.1.4 PUBLIC** | `tools/ghidra_12.1.4_PUBLIC` | native PE analysis engine for REA |
| Temurin JDK | **21.0.12.1** (64-bit full JDK) | `tools/jdk-21` | required by Ghidra 12.1.x |
| innoextract | **1.9** (supports Inno Setup 1.2.10–6.0.5) | `tools/innoextract` | installer payload extraction |
| 7-Zip | **26.05** (`7za.exe`) | `tools/7zip` | nested archives |
| dnSpy | **6.1.8** (`dnSpy.exe`, `dnSpy.Console.exe`) | `tools/dnspy` | interactive .NET inspection |
| .NET SDK | **10.0.403** | `tools/dotnet` | ILSpy runtime |
| ilspycmd | **11.2.0.10050** | `tools/ilspycmd` | automated C# / metadata / resource extraction |
| Python | 3.15 + venv with `pefile dnfile capstone lief zstandard lz4 brotli pycryptodome` | `cache/venv` | binary/format analysis |

## REA configuration

* Provider: `REA_ANALYSIS_PROVIDER=ghidra`, `GHIDRA_INSTALL_DIR`, `JAVA_HOME` pinned in the launchers.
* `rea doctor --provider ghidra --json` → **healthy**, every check `ok`: node, ghidra, ghidra-platform (win32), ghidra-architecture (x64), ghidra-version (12.1.4), ghidra-headless, ghidra-native_decompiler, ghidra-java (21.0.12.1, 64-bit JDK accepted), ghidra-native_authority (Windows Job Object + private DACL verified). Evidence: `evidence/rea-doctor-ghidra.json`.
* MCP registration for **Freebuff** applied: `rea setup --client freebuff --yes --json` → status `ready`, actions `configured_freebuff` + `installed_skill` (evidence: `evidence/rea-setup-freebuff.json`).
  * Written to `C:\Users\shahr\.agents\mcp.json` (mirrored at `evidence/mcp-registration.json`); it launches `tools\node\node.exe` + `tools\rea\node_modules\rea-agents\scripts\rea.mjs mcp`, i.e. a **D-drive** toolchain.
  * Skill installed at `C:\Users\shahr\.agents\skills\reverse-engineer-anything`.
  * Freebuff must be restarted for the `mcp__rea__*` tools to appear. REA's own docs mark Freebuff MCP loading as *not yet verified against a native Freebuff client*, so every REA result in this project was additionally produced through the **CLI**, which needs no restart.

### The one exception to "everything on D"

Freebuff reads its MCP server list from the user-scope shared agent file `~/.agents/mcp.json`, so that one small file (and the optional skill copy) must live in the Windows profile. All binaries, caches, extracted data and outputs stay on D.

### Pinned launchers (reproduce any command in this report set)

* `tools/rea-d.sh` — bash/Git-Bash friendly (used by every command in these reports)
* `tools/rea-d.cmd` — cmd/PowerShell equivalent
* `tools/rea-d-home.cmd` — additionally redirects `HOME`/`USERPROFILE` into `cache\home` so REA's home-relative state also lands on D (not used for `setup`/`doctor`, which must see the real profile)

All three pin: `PATH` (local node → JDK → dotnet), `NPM_CONFIG_CACHE`, `NUGET_PACKAGES`, `DOTNET_CLI_HOME`, `PIP_CACHE_DIR`, `TEMP`/`TMP`, `REA_ANALYSIS_PROVIDER`, `GHIDRA_INSTALL_DIR`, `JAVA_HOME`.

## Baseline integrity (hard gate)

`evidence/baseline-hashes.json` — re-verified unchanged at the end of the work:

| File | Bytes | SHA-256 |
|---|---|---|
| `Main\CounterSketch Studio.exe` | 214,248,448 | `228daa515e2e0a95d554bd45f484521689791aef8d84f7dd093ed3bc88fd3430` |
| `Main\CounterSketchInstaller_8.1.19323.1002.exe` | 523,074,737 | `053eebece6adadb13ce44070e3fa71fa4b911c8c80fb0f798bd4198023b4d6dc` |

## Evidence policy used throughout

1. Every claim in these reports traces to a file under `evidence\` or to a reproducible command.
2. REA Evidence records keep the provider's own `evidence_id`, coverage/limitation fields; nothing is upgraded from "derived" to "observed".
3. Checks that could not be run are reported as limitations, never as passes.
