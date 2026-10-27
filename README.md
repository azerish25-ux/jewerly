# Jewelcraft — an iPadOS ring studio

A ground-up iPadOS rebuild of **CounterSketch Studio 8.1** (Stuller/GemVision): a
jewellery CAD configurator where you choose a design, put a stone in it, size it,
price it and place it on order.

The original is a Windows WPF application driving a long-lived Rhino CAD process
and an offline V-Ray render farm. Neither of those can exist on an iPad, so the
rebuild keeps the *contract* and replaces the *machinery*:

```
CatalogService ──► CADEngineSession ──► RingBuilder ──► PricingEngine ──► OrderService
   (facets)          (async seam)        (geometry)       (rate table)      (documents)
                          │                                      ▲
                          └────── EngineEvent ───────────────────┘
```

Nothing in the UI computes geometry, a weight, a price or a total. Those come
back from the kernel, which is what the test suite exercises.

## Status

| Layer | State |
|---|---|
| Kernel (`Sources/JewelcraftKit`) | Complete: catalogue algebra, parametric ring geometry, gem sizing, pricing, orders, fixtures. 87 unit tests. |
| App (`App/`) | Complete in source: three-column studio, RealityKit viewport, configurator, gem report, quote, order register. |
| CI | Configured: kernel tests on every push, then a simulator build and a UI walk-through. |
| Visual polish / device tuning | **Not yet verified** — see [What has and has not been verified](#what-has-and-has-not-been-verified). |

## Layout

```
Package.swift                  SwiftPM manifest: kernel library, fixture generator, tests
Sources/JewelcraftKit/
  Core/                        vectors, colours, SHA-256
  Catalog/                     designs, gem slots, facets, the search service
  Configuration/               metals, gems, ring sizes, carat rounding, freehand state
  Geometry/                    meshes, primitives, gem facet layouts, the ring builder
  Engine/                      the CAD session protocol, scene graph, undo, in-process engine
  Pricing/                     rate table, quote
  Order/                       order document, state machine, repositories
  Render/                      render targets, material library
  Fixtures/                    JSON documents with code-built equivalents
Sources/generate-fixtures/     writes the fixture documents
Tests/JewelcraftKitTests/      87 tests over the kernel
App/                           SwiftUI + RealityKit iPadOS app
UITests/                       end-to-end walk through the studio
docs/FIDELITY.md               recovered behaviour vs. this rebuild, item by item
docs/reports/                  the reverse-engineering reports this was built from
project.yml                    XcodeGen manifest (the .xcodeproj is generated)
.github/workflows/ci.yml       kernel tests + simulator build + UI tests
.github/workflows/guards.yml   refuses reference material, binaries and oversized files
```

## Quick start

Kernel — no Xcode project, no simulator, no signing:

```bash
swift test                     # 87 tests, seconds
swift run generate-fixtures    # rewrite the JSON fixture documents
```

App — needs macOS with Xcode 16 or later:

```bash
brew install xcodegen
xcodegen generate              # writes Jewelcraft.xcodeproj from project.yml
open Jewelcraft.xcodeproj      # run on an iPad simulator (iPadOS 17+)
```

The project file is generated on purpose: CI checks out a clean tree, runs
`xcodegen generate` and builds, so the layout in `project.yml` is the single
source of truth and there is no `.pbxproj` to drift or conflict.

## How the studio works

**Library → catalogue → bench.** The left column scopes the catalogue by
collection or package; the middle column is search, facets and the results grid;
the right column is the open ring: viewport, metals, centre stone, finger size,
structure, gem report and quote.

**One engine session per design.** Opening a design builds a starting
configuration from the design's own suggested centre stone, metal and slot list,
opens a session and subscribes to its event stream. Every control calls an intent
(`setMetal`, `setCentreCarat`, `setFingerSize`, `undo`, …); the engine validates,
rebuilds the geometry, records undo and pushes a new snapshot. The UI re-reads the
engine rather than assuming the result, so a rejected change leaves the screen
honest.

**Pricing follows geometry.** Metal cost is the built mesh's measured volume
multiplied by the alloy's density and rate — so changing the shank profile or the
finger size moves the price. Stones are priced from shape, quality and carat
bands; labour from a tier; settings per stone by role; every line carries the id
of the rate it came from.

**Orders are documents.** A submitted order holds the configuration, the audited
quote and the image references the renderer will need, under a versioned schema
and a reference like `JWL-20261027-4F2A`. The state machine only permits
transitions it defines, and a shipped order cannot be cancelled.

## What has and has not been verified

Verified by `swift test` (run it before trusting anything else):

- search algebra: facets, keyword, scope, carat re-filtering, disabled-facet guidance;
- every fixture document and design passes its own integrity checks;
- carat ↔ girdle-width round trips per shape and material;
- meshes are watertight, consistently wound, and their measured volume agrees with their mass;
- pricing reconciles line by line, and every quote recomputes from its own lines;
- orders round-trip, references are reproducible, transitions are guarded;
- the engine's pushed state matches its queried state, and undo/redo restores exactly.

**Not verified by the author of this commit:** the app has not been compiled or
run on this machine — the development host has no Swift toolchain or Xcode. The
first real compile is the CI job in `.github/workflows/ci.yml`; anything it
reports is a genuine defect rather than a formality. The RealityKit viewport and
the visual design have not been seen running.

## Fidelity and legal boundary

[docs/FIDELITY.md](docs/FIDELITY.md) is the ledger: every recovered capability,
what it became here, and whether it is a faithful reproduction, an adaptation to
iPadOS, or deliberately absent (supplier pricing, entitlement, named-pipe
handoff, printers, localisation).

No Stuller or GemVision asset, catalogue record, image, material, geometry file
or service endpoint is used. The reference binaries, the extracted installer, the
decompiled corpus and the reverse-engineering toolchain are excluded from this
repository by `.gitignore` and refused by the guards workflow. What is carried
forward is behaviour and contract.

The background analysis is in [docs/reports](docs/reports/README.md): installer,
binary, architecture, business logic, native layer, rebuild specification, and an
explicit list of what the analysis did *not* establish.
