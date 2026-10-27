// swift-tools-version: 5.10
//
//  JewelcraftKit — the platform-agnostic core of the Jewelcraft iPadOS rebuild.
//
//  Everything in this target is pure Swift with no UIKit/SwiftUI/RealityKit
//  dependency, which is deliberate: it is what lets CI verify the geometry
//  kernel, catalog algebra, pricing arithmetic and document formats with
//  `swift test` in seconds — no simulator, no code signing, no GPU.
//
//  Swift 5 language mode is intentional. The core is a large deterministic
//  numeric codebase; opting into Swift 6 strict concurrency here would add
//  isolation annotations without buying correctness, and the concurrency story
//  for the render layer lives in the app target, where the actors actually are.
//

import PackageDescription

let package = Package(
    name: "JewelcraftKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(name: "JewelcraftKit", targets: ["JewelcraftKit"])
    ],
    targets: [
        .target(
            name: "JewelcraftKit",
            // The fixture documents ship as JSON so they can be inspected,
            // diffed and regenerated without recompiling. Every one of them has
            // a code-built equivalent, and the tests assert the two agree: the
            // JSON is the published form, the Swift is the checked one.
            resources: [.copy("Resources")]
        ),
        // `swift run generate-fixtures` writes the fixture documents.
        .executableTarget(
            name: "generate-fixtures",
            dependencies: ["JewelcraftKit"]
        ),
        .testTarget(
            name: "JewelcraftKitTests",
            dependencies: ["JewelcraftKit"]
        )
    ]
)
