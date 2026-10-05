import Foundation

/// Raw DEFLATE (RFC 1951) decompression in pure Swift, for compressed zip entries: 3MF files from slicers and other
/// apps are zips with deflated parts. Stored, fixed-Huffman and dynamic-Huffman blocks.
public enum Inflate {
    public enum Failure: Error, Equatable {
        case damaged
    }

    public static func decompress(_ data: Data, expectedSize: Int? = nil) throws(Failure) -> Data {
        var reader = BitReader(bytes: [UInt8](data))
        var output: [UInt8] = []
        if let expectedSize { output.reserveCapacity(expectedSize) }
        var last = false
        while !last {
            last = try reader.bits(1) == 1
            switch try reader.bits(2) {
            case 0: try stored(&reader, into: &output)
            case 1: try huffman(&reader, literals: fixedLiterals, distances: fixedDistances, into: &output)
            case 2:
                let (literals, distances) = try dynamicTables(&reader)
                try huffman(&reader, literals: literals, distances: distances, into: &output)
            default: throw .damaged
            }
        }
        return Data(output)
    }

    // MARK: Blocks

    private static func stored(_ reader: inout BitReader, into output: inout [UInt8]) throws(Failure) {
        reader.alignToByte()
        let length = try reader.bits(16)
        let complement = try reader.bits(16)
        guard length == ~complement & 0xFFFF else { throw .damaged }
        for _ in 0 ..< length {
            try output.append(UInt8(reader.bits(8)))
        }
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                                       4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    private static func huffman(_ reader: inout BitReader, literals: Huffman, distances: Huffman, into output: inout [UInt8]) throws(Failure) {
        while true {
            let symbol = try literals.decode(&reader)
            if symbol < 256 {
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let index = symbol - 257
                guard index < lengthBase.count else { throw .damaged }
                let length = try lengthBase[index] + reader.bits(lengthExtra[index])
                let code = try distances.decode(&reader)
                guard code < distanceBase.count else { throw .damaged }
                let distance = try distanceBase[code] + reader.bits(distanceExtra[code])
                guard distance <= output.count else { throw .damaged }
                let start = output.count - distance
                for offset in 0 ..< length {
                    output.append(output[start + offset])
                }
            }
        }
    }

    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private static func dynamicTables(_ reader: inout BitReader) throws(Failure) -> (Huffman, Huffman) {
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let codeCount = try reader.bits(4) + 4
        var codeLengths = [Int](repeating: 0, count: 19)
        for index in 0 ..< codeCount {
            codeLengths[codeLengthOrder[index]] = try reader.bits(3)
        }
        let codes = try Huffman(lengths: codeLengths)
        var lengths: [Int] = []
        while lengths.count < literalCount + distanceCount {
            let symbol = try codes.decode(&reader)
            switch symbol {
            case 0 ... 15:
                lengths.append(symbol)
            case 16:
                guard let previous = lengths.last else { throw .damaged }
                try lengths += Array(repeating: previous, count: 3 + reader.bits(2))
            case 17:
                try lengths += Array(repeating: 0, count: 3 + reader.bits(3))
            case 18:
                try lengths += Array(repeating: 0, count: 11 + reader.bits(7))
            default:
                throw .damaged
            }
        }
        guard lengths.count == literalCount + distanceCount else { throw .damaged }
        return try (Huffman(lengths: Array(lengths[..<literalCount])), Huffman(lengths: Array(lengths[literalCount...])))
    }

    private static let fixedLiterals: Huffman = {
        let lengths = (0 ..< 288).map { symbol in symbol < 144 ? 8 : symbol < 256 ? 9 : symbol < 280 ? 7 : 8 }
        return (try? Huffman(lengths: lengths)) ?? Huffman.empty
    }()

    private static let fixedDistances: Huffman = (try? Huffman(lengths: Array(repeating: 5, count: 30))) ?? Huffman.empty

    // MARK: Pieces

    /// Canonical Huffman decoding by code length (counts per length, symbols in code order).
    struct Huffman {
        var counts: [Int]
        var symbols: [Int]

        static let empty = Huffman(counts: Array(repeating: 0, count: 16), symbols: [])

        private init(counts: [Int], symbols: [Int]) {
            self.counts = counts
            self.symbols = symbols
        }

        init(lengths: [Int]) throws(Failure) {
            var counts = [Int](repeating: 0, count: 16)
            for length in lengths {
                guard (0 ... 15).contains(length) else { throw .damaged }
                counts[length] += 1
            }
            counts[0] = 0
            var offsets = [Int](repeating: 0, count: 16)
            for length in 1 ..< 16 {
                offsets[length] = offsets[length - 1] + counts[length - 1]
            }
            var symbols = [Int](repeating: 0, count: lengths.count)
            for (symbol, length) in lengths.enumerated() where length > 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
            self.counts = counts
            self.symbols = symbols
        }

        func decode(_ reader: inout BitReader) throws(Failure) -> Int {
            var code = 0, first = 0, index = 0
            for length in 1 ..< 16 {
                code |= try reader.bits(1)
                let count = counts[length]
                if code - first < count { return symbols[index + code - first] }
                index += count
                first = (first + count) << 1
                code <<= 1
            }
            throw .damaged
        }
    }

    /// Least significant bit first, as DEFLATE packs them.
    struct BitReader {
        let bytes: [UInt8]
        var position = 0
        var bitBuffer = 0
        var bitCount = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func bits(_ count: Int) throws(Failure) -> Int {
            while bitCount < count {
                guard position < bytes.count else { throw .damaged }
                bitBuffer |= Int(bytes[position]) << bitCount
                position += 1
                bitCount += 8
            }
            let value = bitBuffer & ((1 << count) - 1)
            bitBuffer >>= count
            bitCount -= count
            return value
        }

        mutating func alignToByte() {
            bitBuffer = 0
            bitCount = 0
        }
    }
}
