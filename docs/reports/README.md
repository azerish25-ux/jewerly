# CounterSketch Studio 8.1 — reverse-engineering report set

Target (both files are byte-identical to how you supplied them — see §verification):

| File | Bytes | SHA-256 (short) |
|---|---|---|
| `Main\CounterSketch Studio.exe` | 214,248,448 | `228daa51…3430` |
| `Main\CounterSketchInstaller_8.1.19323.1002.exe` | 523,074,737 | `053eebec…d6dc` |

| Report | What it answers |
|---|---|
| [00 — Environment and toolchain](00-environment-and-toolchain.md) | what was installed, where, how it is pinned to D:, how REA is wired (MCP + CLI) |
| [01 — Installer analysis](01-installer-analysis.md) | what the 523 MB installer is (Inno Setup 5.5.6), how it was extracted, what it ships, where it writes |
| [02 — App binary and resources](02-app-binary-and-resources.md) | the `.exe`'s PE/CLR layout, the 198.9 MiB embedded payload explained, the decompiled corpus, REA's 128 MiB limit |
| [03 — Architecture](03-architecture.md) | the whole system: WPF/MVVM shell, Rhino CAD service (383 ops), V-Ray pipeline, native kernel, services, data, IPC |
| [04 — Business logic](04-business-logic.md) | catalog search, gems/metals, configurator semantics, pricing, orders, licensing, file formats, printers |
| [05 — Rebuild spec](05-rebuild-spec.md) | how to build an equivalent product: modules, interfaces, contracts, staged plan, legal boundaries |
| [06 — Native layer](06-native-layer.md) | the C++ geometry/print kernel: module map, OpenVDB/fitting/printer-driver findings, verified Ghidra run |
| [07 — Evidence and limitations](07-evidence-and-limitations.md) | every evidence artefact, what was verified, what was **not** established |

Key numbers: installer = 4,177 files / 1.3 GiB extracted; app = 1,229 C# files / 1,331 classes / 855 embedded resources; backend = ~150 MiB of x64 C++ across ~20 modules plus a 10.7 MiB managed Rhino plugin; one native module auto-analysed to 32,433 procedures.

Everything needed to re-run the work: `tools\rea-d.sh` (bash) or `tools\rea-d.cmd` (cmd) with the D-pinned environment, and the commands quoted inside each report.
