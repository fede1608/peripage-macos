import Foundation

/// Seeded PRNG used by every generator: xoshiro256** seeded through SplitMix64.
/// All helpers (ranges, shuffles, picks) are implemented here instead of using the standard library's
/// `random(in:using:)` / `shuffled(using:)`, whose algorithms are not guaranteed to stay the same across
/// Swift releases; a printed puzzle id must keep reproducing the same puzzle.
struct PuzzleRNG {
    private var s0, s1, s2, s3: UInt64

    init(seed: UInt64, salt: UInt64 = 0) {
        var sm = seed ^ (salt &* 0x9E37_79B9_7F4A_7C15)
        func splitMix() -> UInt64 {
            sm &+= 0x9E37_79B9_7F4A_7C15
            var z = sm
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        s0 = splitMix(); s1 = splitMix(); s2 = splitMix(); s3 = splitMix()
    }

    @inline(__always) private static func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 { (x << k) | (x >> (64 - k)) }

    mutating func next() -> UInt64 {
        let result = Self.rotl(s1 &* 5, 7) &* 9
        let t = s1 << 17
        s2 ^= s0; s3 ^= s1; s1 ^= s2; s0 ^= s3
        s2 ^= t
        s3 = Self.rotl(s3, 45)
        return result
    }

    /// Uniform integer in 0..<n (Lemire's multiply-shift with rejection).
    mutating func int(_ n: Int) -> Int {
        precondition(n > 0)
        let bound = UInt64(n)
        var m = next().multipliedFullWidth(by: bound)
        if m.low < bound {
            let threshold = (0 &- bound) % bound
            while m.low < threshold { m = next().multipliedFullWidth(by: bound) }
        }
        return Int(m.high)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int { range.lowerBound + int(range.count) }

    /// Uniform double in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) * 0x1.0p-53 }

    mutating func chance(_ p: Double) -> Bool { unit() < p }

    mutating func shuffle<T>(_ a: inout [T]) {
        guard a.count > 1 else { return }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = int(i + 1)
            if i != j { a.swapAt(i, j) }
        }
    }

    mutating func shuffled<T>(_ a: [T]) -> [T] {
        var copy = a
        shuffle(&copy)
        return copy
    }

    mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
}
