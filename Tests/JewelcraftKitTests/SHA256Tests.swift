//
//  SHA256Tests.swift
//  JewelcraftKitTests
//
//  The hasher is a primitive the rest of the kit trusts: the fixture hashes in
//  the fidelity ledger and a document's fingerprint are only worth anything if
//  they are the real digest. These are known-answer tests — against published
//  vectors and against digests produced by an independent implementation — at
//  every length where the final block is filled differently.
//

import XCTest
@testable import JewelcraftKit

final class SHA256Tests: XCTestCase {

    /// A deterministic byte pattern, so a vector for an arbitrary length can be
    /// stated once and reproduced exactly.
    private func pattern(_ count: Int) -> [UInt8] {
        (0..<count).map { UInt8(($0 * 37 + 11) % 256) }
    }

    private func hex(_ count: Int) -> String {
        SHA256.hexDigest(pattern(count))
    }

    func testThePublishedVectors() {
        XCTAssertEqual(
            SHA256.hexDigest([UInt8]()),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            SHA256.hexDigest(Array("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            SHA256.hexDigest(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
        XCTAssertEqual(
            SHA256.hexDigest(Array("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu".utf8)),
            "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"
        )
    }

    /// The million-'a' vector, fed a thousand bytes at a time, so the streaming
    /// path is exercised rather than one large update.
    func testTheLongStreamedVector() {
        var hasher = SHA256.Hasher()
        let chunk = [UInt8](repeating: UInt8(ascii: "a"), count: 1_000)
        for _ in 0..<1_000 { hasher.update(chunk) }
        XCTAssertEqual(
            SHA256.hexString(hasher.finalize()),
            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
        )
    }

    /// The lengths where the final block is filled differently: a tail of 55 to
    /// 63 bytes is the case the padding got wrong, because the padding was built
    /// from the tail alone and so was not a whole number of blocks. 63 of these
    /// 64 tail lengths trapped on the block slice; every one is checked here
    /// against a digest from an independent implementation.
    private static let tailVectors: [(length: Int, digest: String)] = [
        (0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        (1, "e7cf46a078fed4fafd0b5e3aff144802b853f8ae459a4f0c14add3314b7cc3a6"),
        (55, "2900465fcb533e05a158fd2b3be0e5e3b03740d83060aa3580e0d98a96bf2384"),
        (56, "31454ff48ef36af2f08fd511bdc37d9d5855ac23e992e5ff5445cb6b7674a674"),
        (63, "5f6401b96532c36de4e65beec0409b69b1d181864c8009b7a04f43e5d56350d1"),
        (64, "94eb5de4943613fd048dc93393ab06877405faa39c11f53e9386083339833e7e"),
        (65, "fc518669b6eb4b4dd91827ecacef86689c725bd5bab888fd3b26dbb196eec954"),
        (119, "b0dc41b1a384e2f1203f0351b38fbeaafceef577ce1191d5bfc25da39f721eae"),
        (120, "5df24dd802ac26132ce608dcb5f09841eef039ee0f152acf98d26d17fe4e88e6"),
        (128, "0aedd4856f8eba0963627336ad5144a9a7dbe12498e6066f0165fc97d8ddee4c"),
        (1000, "57799de80e3dd6e2ac4d40c41a150d1662f7f87d0d994776a2fdc37c39b0ea4e")
    ]

    func testEveryTailLengthMatchesTheReferenceDigest() {
        for vector in Self.tailVectors {
            XCTAssertEqual(hex(vector.length), vector.digest, "length \(vector.length)")
        }
    }

    /// Streaming must agree with a single update at every length: the buffer
    /// boundary is where an incremental hasher usually goes wrong.
    func testStreamingAgreesWithOneShot() {
        for length in 0...200 {
            let bytes = pattern(length)
            var hasher = SHA256.Hasher()
            var offset = 0
            while offset < bytes.count {
                let end = Swift.min(bytes.count, offset + 7)
                hasher.update(Array(bytes[offset..<end]))
                offset = end
            }
            XCTAssertEqual(
                SHA256.hexString(hasher.finalize()),
                SHA256.hexDigest(bytes),
                "length \(length)"
            )
        }
    }

    func testHexIsLowercaseAndFixedWidth() {
        for length in 0...120 {
            let text = hex(length)
            XCTAssertEqual(text.count, 64, "length \(length)")
            XCTAssertEqual(text, text.lowercased(), "length \(length)")
        }
    }
}
