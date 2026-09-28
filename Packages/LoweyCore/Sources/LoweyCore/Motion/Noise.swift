import Foundation

/// Smooth, deterministic 1D value noise (no state, no platform randomness), so procedural
/// motion evaluates identically at any time, in any order, on any device — export is exact.
public enum Noise {
    /// Hash of an integer lattice point and a seed to [-1, 1].
    static func lattice(_ index: Int64, seed: UInt64) -> Double {
        var z = UInt64(bitPattern: index) &+ seed &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) * (2.0 / 9_007_199_254_740_992.0) - 1
    }

    /// Value noise in [-1, 1] with smoothstep interpolation between lattice points (period 1).
    public static func value(_ x: Double, seed: UInt64) -> Double {
        let floorX = x.rounded(.down)
        let i = Int64(floorX)
        let f = x - floorX
        let u = f * f * (3 - 2 * f)
        let a = lattice(i, seed: seed)
        let b = lattice(i + 1, seed: seed)
        return a + (b - a) * u
    }

    /// Two octaves: organic wobble without looking random-jittery.
    public static func fractal(_ x: Double, seed: UInt64) -> Double {
        value(x, seed: seed) * 0.7 + value(x * 2.13 + 17.3, seed: seed &+ 101) * 0.3
    }

    /// Stable seed derived from a string (object ids, behaviour ids).
    public static func seed(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
