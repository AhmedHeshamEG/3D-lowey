import Foundation

/// A property list value, as read from a binary (`bplist00`) file. Keyed archives' object references (`uid`) are
/// kept, which Foundation's reader hides on Apple platforms and can't give on Linux.
public indirect enum PlistValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case real(Double)
    case date(Double)
    case data(Data)
    case string(String)
    case uid(Int)
    case array([PlistValue])
    case dict([String: PlistValue])

    public subscript(key: String) -> PlistValue? {
        if case let .dict(dictionary) = self { return dictionary[key] }
        return nil
    }

    public var double: Double? {
        switch self {
        case let .real(value): value
        case let .int(value): Double(value)
        case let .bool(value): value ? 1 : 0
        default: nil
        }
    }

    public var bool: Bool? {
        switch self {
        case let .bool(value): value
        case let .int(value): value != 0
        default: nil
        }
    }

    public var string: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var array: [PlistValue]? {
        if case let .array(value) = self { return value }
        return nil
    }
}

/// Reads binary property lists (the format of Procreate's `Brush.archive` and `brushset.plist`).
public enum BinaryPlist {
    public enum Failure: Error, Equatable {
        case notBinary, damaged
    }

    /// Nested containers deeper than this are refused (a malformed file can't recurse forever).
    static let maximumDepth = 64

    public static func isBinary(_ data: Data) -> Bool {
        data.count >= 40 && data.prefix(8) == Data("bplist00".utf8)
    }

    public static func read(_ data: Data) throws(Failure) -> PlistValue {
        guard isBinary(data) else { throw .notBinary }
        let reader = Reader(bytes: [UInt8](data))
        return try reader.root()
    }

    struct Reader {
        let bytes: [UInt8]

        func root() throws(Failure) -> PlistValue {
            let trailer = bytes.count - 32
            let offsetSize = Int(bytes[trailer + 6]), refSize = Int(bytes[trailer + 7])
            let count = try integer(at: trailer + 8, size: 8)
            let top = try integer(at: trailer + 16, size: 8)
            let table = try integer(at: trailer + 24, size: 8)
            guard (1 ... 8).contains(offsetSize), (1 ... 8).contains(refSize), count > 0, top < count,
                  table + count * offsetSize <= trailer else { throw .damaged }
            let tables = Tables(offsetSize: offsetSize, refSize: refSize, count: count, table: table)
            return try object(top, tables: tables, depth: 0)
        }

        struct Tables {
            var offsetSize: Int
            var refSize: Int
            var count: Int
            var table: Int
        }

        func integer(at offset: Int, size: Int) throws(Failure) -> Int {
            guard offset >= 0, size > 0, offset + size <= bytes.count else { throw .damaged }
            var value = 0
            for index in 0 ..< size {
                value = value << 8 | Int(bytes[offset + index])
            }
            return value
        }

        func object(_ ref: Int, tables: Tables, depth: Int) throws(Failure) -> PlistValue {
            guard depth < BinaryPlist.maximumDepth, ref >= 0, ref < tables.count else { throw .damaged }
            let offset = try integer(at: tables.table + ref * tables.offsetSize, size: tables.offsetSize)
            guard offset < bytes.count else { throw .damaged }
            let marker = bytes[offset]
            let high = marker >> 4, low = Int(marker & 0x0F)
            switch high {
            case 0x0:
                return marker == 0x08 ? .bool(false) : marker == 0x09 ? .bool(true) : .null
            case 0x1:
                return try .int(signedInteger(at: offset + 1, size: 1 << low))
            case 0x2:
                return try .real(real(at: offset + 1, size: 1 << low))
            case 0x3:
                return try .date(real(at: offset + 1, size: 8))
            case 0x8:
                return try .uid(integer(at: offset + 1, size: low + 1))
            case 0xA, 0xC, 0xD:
                return try container(high: high, low: low, at: offset, tables: tables, depth: depth)
            default:
                return try bytesObject(high: high, low: low, at: offset)
            }
        }

        func bytesObject(high: UInt8, low: Int, at offset: Int) throws(Failure) -> PlistValue {
            let (length, start) = try lengthAndStart(low, at: offset)
            switch high {
            case 0x4:
                guard start + length <= bytes.count else { throw .damaged }
                return .data(Data(bytes[start ..< start + length]))
            case 0x5:
                guard start + length <= bytes.count else { throw .damaged }
                return .string(String(decoding: bytes[start ..< start + length], as: UTF8.self))
            case 0x6:
                guard start + length * 2 <= bytes.count else { throw .damaged }
                let units = (0 ..< length).map { UInt16(bytes[start + $0 * 2]) << 8 | UInt16(bytes[start + $0 * 2 + 1]) }
                return .string(String(decoding: units, as: UTF16.self))
            default:
                throw .damaged
            }
        }

        func container(high: UInt8, low: Int, at offset: Int, tables: Tables, depth: Int) throws(Failure) -> PlistValue {
            let (count, start) = try lengthAndStart(low, at: offset)
            let entries = high == 0xD ? count * 2 : count
            guard start + entries * tables.refSize <= bytes.count else { throw .damaged }
            var refs: [Int] = []
            refs.reserveCapacity(entries)
            for index in 0 ..< entries {
                try refs.append(integer(at: start + index * tables.refSize, size: tables.refSize))
            }
            if high != 0xD {
                var items: [PlistValue] = []
                for ref in refs {
                    try items.append(object(ref, tables: tables, depth: depth + 1))
                }
                return .array(items)
            }
            var dictionary: [String: PlistValue] = [:]
            for index in 0 ..< count {
                guard case let .string(key) = try object(refs[index], tables: tables, depth: depth + 1) else { throw .damaged }
                dictionary[key] = try object(refs[count + index], tables: tables, depth: depth + 1)
            }
            return .dict(dictionary)
        }

        /// The length in the marker's low nibble, or the integer object after it when the nibble is 0xF.
        func lengthAndStart(_ low: Int, at offset: Int) throws(Failure) -> (Int, Int) {
            guard low == 0xF else { return (low, offset + 1) }
            guard offset + 1 < bytes.count, bytes[offset + 1] >> 4 == 0x1 else { throw .damaged }
            let size = 1 << Int(bytes[offset + 1] & 0x0F)
            let length = try integer(at: offset + 2, size: size)
            guard length >= 0 else { throw .damaged }
            return (length, offset + 2 + size)
        }

        func signedInteger(at offset: Int, size: Int) throws(Failure) -> Int64 {
            guard size <= 8 else { return try Int64(integer(at: offset + size - 8, size: 8)) }
            let raw = try UInt64(truncatingIfNeeded: integer(at: offset, size: size))
            return size == 8 ? Int64(bitPattern: raw) : Int64(raw)
        }

        func real(at offset: Int, size: Int) throws(Failure) -> Double {
            let raw = try UInt64(truncatingIfNeeded: integer(at: offset, size: size))
            return size == 4 ? Double(Float(bitPattern: UInt32(truncatingIfNeeded: raw))) : Double(bitPattern: raw)
        }
    }
}

/// An `NSKeyedArchiver` archive read without Foundation's unarchiver (whose classes, like Procreate's `SilicaBrush`,
/// don't exist here): objects are dictionaries whose values point into `$objects` by uid.
public struct KeyedArchive {
    public let objects: [PlistValue]
    public let root: PlistValue

    public init(_ plist: PlistValue) throws(BinaryPlist.Failure) {
        guard let objects = plist["$objects"]?.array, case let .uid(top)? = plist["$top"]?["root"], objects.indices.contains(top) else {
            throw .damaged
        }
        self.objects = objects
        root = objects[top]
    }

    /// Follows a uid to its object (other values pass through); `$null` becomes `.null`.
    public func resolve(_ value: PlistValue?) -> PlistValue? {
        guard let value else { return nil }
        if case let .uid(index) = value {
            guard objects.indices.contains(index) else { return nil }
            let object = objects[index]
            return object == .string("$null") ? .null : object
        }
        return value
    }

    public func value(_ key: String, in object: PlistValue? = nil) -> PlistValue? {
        resolve((object ?? root)[key])
    }

    public func double(_ key: String) -> Double? { value(key)?.double }
    public func bool(_ key: String) -> Bool? { value(key)?.bool }
    public func string(_ key: String) -> String? { value(key)?.string }

    /// An `NSArray`'s items, resolved.
    public func items(of object: PlistValue?) -> [PlistValue] {
        guard let array = resolve(object?["NS.objects"])?.array ?? object?["NS.objects"]?.array else { return [] }
        return array.compactMap { resolve($0) }
    }
}
