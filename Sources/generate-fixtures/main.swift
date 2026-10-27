//
//  generate-fixtures
//
//  Writes the fixture documents that JewelcraftKit also builds in code.
//
//  This exists because the fixtures are data: they can be inspected, diffed and
//  regenerated. The tests compare the written documents with the code-built
//  ones, so the published JSON can never drift from what the app actually uses.
//
//  Usage: swift run generate-fixtures [output-directory]
//

import Foundation
import JewelcraftKit

let defaultDirectory = URL(fileURLWithPath: "Fixtures", isDirectory: true)
let argument = CommandLine.arguments.dropFirst().first
let directory = argument.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultDirectory

do {
    let written = try FixtureBundle.writeAllFixtures(to: directory)
    for url in written {
        print("wrote \(url.path)")
    }

    let hashes = try FixtureBundle.allHashes()
    for name in hashes.keys.sorted() {
        print("\(name) sha256 \(hashes[name] ?? "")")
    }
} catch {
    FileHandle.standardError.write(Data("fixture generation failed: \(error)\n".utf8))
    exit(1)
}
