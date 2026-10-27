//
//  SHA256.swift
//  JewelcraftKit
//
//  SHA-256 (FIPS 180-4).
//
//  Why hand-rolled rather than CryptoKit: the library package is deliberately
//  platform-agnostic so `swift test` can verify it on the macOS runner, and
//  content addressing is part of the document formats. A small, fully
//  specified implementation with published test vectors is both easier to
//  audit than a wrapper and keeps the package dependency-free.
//
//  It is *not* used for anything security-sensitive in this rebuild: there is
//  no authentication, no key derivation and no licensing logic anywhere in the
//  product. It exists to content-address geometry and gem records so library
//  documents can be verified and migrated.
//

import Foundation

public enum SHA256 {

    // MARK: - Public API

    /// The 32-byte digest of `data`.
    public static func digest(_ data: Data) -> [UInt8] {
        digest([UInt8](data))
    }

    /// The 32-byte digest of `bytes`.
    public static func digest(_ bytes: [UInt8]) -> [UInt8] {
        var hasher = Hasher()
        hasher.update(bytes)
        return hasher.finalize()
    }

    /// Lower-case hexadecimal digest, the form used in manifests and evidence.
    public static func hexDigest(_ data: Data) -> String {
        hexDigest(digest(data))
    }

    /// Lower-case hexadecimal digest, the form used in manifests and evidence.
    public static func hexDigest(_ bytes: [UInt8]) -> String {
        hexString(digest(bytes))
    }

    /// Lower-case hexadecimal encoding.
    public static func hexString(_ bytes: [UInt8]) -> String {
        var output = String()
        output.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            output.append(Character(UnicodeScalar(hexDigits[Int(byte >> 4)])))
            output.append(Character(UnicodeScalar(hexDigits[Int(byte & 0x0F)])))
        }
        return output
    }

    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

    // MARK: - Streaming implementation

    /// Incremental hasher, so a large document can be hashed without being held
    /// in memory twice.
    public struct Hasher {
        private var state: [UInt32] = Self.initialState
        private var buffer: [UInt8] = []
        private var totalByteCount: UInt64 = 0

        private static let initialState: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ]

        private static let roundConstants: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        ]

        public init() {}

        public mutating func update(_ bytes: [UInt8]) {
            totalByteCount &+= UInt64(bytes.count)
            buffer.append(contentsOf: bytes)
            var offset = 0
            while buffer.count - offset >= 64 {
                compress(block: Array(buffer[offset..<(offset + 64)]))
                offset += 64
            }
            if offset > 0 {
                buffer.removeFirst(offset)
            }
        }

        public mutating func finalize() -> [UInt8] {
            let bitCount = totalByteCount &* 8

            // Padding: a single 1 bit, then zeros up to the 56th byte of the
            // final block, then the 64-bit length. The buffered tail is the
            // beginning of that block, so the padding is counted from the tail:
            // padding the tail on its own leaves a buffer that is not a whole
            // number of blocks, and the block slices below then trap.
            var tail = buffer
            buffer.removeAll(keepingCapacity: false)

            tail.append(0x80)
            while tail.count % 64 != 56 {
                tail.append(0x00)
            }
            for shift in stride(from: 56, through: 0, by: -8) {
                tail.append(UInt8((bitCount >> UInt64(shift)) & 0xFF))
            }
            // Compressed here rather than through `update`, so the recorded byte
            // count stays the message's own.
            var offset = 0
            while offset < tail.count {
                compress(block: Array(tail[offset..<(offset + 64)]))
                offset += 64
            }

            var output: [UInt8] = []
            output.reserveCapacity(32)
            for word in state {
                output.append(UInt8((word >> 24) & 0xFF))
                output.append(UInt8((word >> 16) & 0xFF))
                output.append(UInt8((word >> 8) & 0xFF))
                output.append(UInt8(word & 0xFF))
            }
            return output
        }

        private mutating func compress(block: [UInt8]) {
            precondition(block.count == 64, "SHA-256 block must be 64 bytes")

            var schedule = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let base = index * 4
                schedule[index] = (UInt32(block[base]) << 24)
                    | (UInt32(block[base + 1]) << 16)
                    | (UInt32(block[base + 2]) << 8)
                    | UInt32(block[base + 3])
            }
            for index in 16..<64 {
                let s0 = Self.rotateRight(schedule[index - 15], by: 7)
                    ^ Self.rotateRight(schedule[index - 15], by: 18)
                    ^ (schedule[index - 15] >> 3)
                let s1 = Self.rotateRight(schedule[index - 2], by: 17)
                    ^ Self.rotateRight(schedule[index - 2], by: 19)
                    ^ (schedule[index - 2] >> 10)
                schedule[index] = schedule[index - 16] &+ s0 &+ schedule[index - 7] &+ s1
            }

            var a = state[0], b = state[1], c = state[2], d = state[3]
            var e = state[4], f = state[5], g = state[6], h = state[7]

            for index in 0..<64 {
                let s1 = Self.rotateRight(e, by: 6) ^ Self.rotateRight(e, by: 11) ^ Self.rotateRight(e, by: 25)
                let choice = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ choice &+ Self.roundConstants[index] &+ schedule[index]
                let s0 = Self.rotateRight(a, by: 2) ^ Self.rotateRight(a, by: 13) ^ Self.rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ majority

                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            state[0] = state[0] &+ a
            state[1] = state[1] &+ b
            state[2] = state[2] &+ c
            state[3] = state[3] &+ d
            state[4] = state[4] &+ e
            state[5] = state[5] &+ f
            state[6] = state[6] &+ g
            state[7] = state[7] &+ h
        }

        private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
            (value >> amount) | (value << (32 - amount))
        }
    }
}
