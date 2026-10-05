import Foundation

/// Photoshop's `.abr`: the sampled tips (pictures) become brushes on the engine's defaults; computed (round) brushes
/// and Photoshop's dynamics don't come across (D-141). Versions 1 and 2 (old Photoshop) and 6 (Photoshop 7 to today)
/// are read; names and spacing come from version 6's descriptor section when it has them.
public enum ABRBrushImport {
    /// Tips are box-filtered to this many pixels on their long side.
    public static let maximumTipSize = 512

    public static func read(_ data: Data, fileName: String, newID: () -> String) throws -> BrushImportResult {
        let bytes = [UInt8](data)
        let baseName = (fileName as NSString).deletingPathExtension
        guard bytes.count > 4 else { throw BrushImportError.unreadable(fileName) }
        let reader = ABRReader(bytes: bytes)
        let version = reader.u16(0)
        let tips: [ABRTip]
        switch version {
        case 1, 2: tips = reader.legacyTips(version: version)
        case 6, 7, 10: tips = reader.sectionTips(subversion: reader.u16(2))
        default: throw BrushImportError.unreadable(fileName)
        }
        var result = BrushImportResult(setName: baseName)
        for (index, tip) in tips.enumerated() {
            guard let image = tip.image?.fitting(maximumTipSize), image.coverage > 0.001 else {
                result.notes.append("Skipped \(tip.name ?? "brush \(index + 1)"): it isn't a picture")
                continue
            }
            let png = GreyPNG.encode(image)
            let key = BrushKey.imageKey(for: png)
            result.images[key] = png
            let name = tip.name ?? "\(baseName) \(index + 1)"
            let shape = BrushShape(source: .image(key), followsStroke: false)
            let stroke = BrushStrokeSettings(spacing: tip.spacing ?? 0.25, streamline: 0.2)
            result.brushes.append(Brush(id: newID(), name: name, shape: shape, stroke: stroke,
                                        dynamics: BrushDynamics(pressureSize: 0.6, minimumSize: 0.2),
                                        about: BrushAbout(origin: .photoshop)).clamped)
        }
        guard !result.brushes.isEmpty else { throw BrushImportError.empty(fileName) }
        return result
    }
}

struct ABRTip {
    var image: GreyImage?
    var name: String?
    /// Fraction of the tip's diameter.
    var spacing: Double?
}

/// Big-endian reads over an ABR file; every read is bounds-checked (a damaged file reads as zeros and ends early).
struct ABRReader {
    let bytes: [UInt8]

    func u8(_ at: Int) -> Int { at >= 0 && at < bytes.count ? Int(bytes[at]) : 0 }
    func u16(_ at: Int) -> Int { u8(at) << 8 | u8(at + 1) }
    func u32(_ at: Int) -> Int { u16(at) << 16 | u16(at + 2) }

    /// Version 6+: `8BIM` sections; `samp` holds the pictures, `desc` their names.
    func sectionTips(subversion: Int) -> [ABRTip] {
        var offset = 4
        var samples: [(id: String, image: GreyImage?)] = []
        var descriptors: [String: (name: String, spacing: Double?)] = [:]
        while offset + 12 <= bytes.count {
            let key = String(decoding: bytes[offset + 4 ..< offset + 8], as: UTF8.self)
            let length = u32(offset + 8)
            let body = offset + 12
            guard length >= 0, body + length <= bytes.count else { break }
            if key == "samp" { samples = sampleSection(body, length: length, subversion: subversion) }
            if key == "desc" { descriptors = ABRDescriptors.read(Array(bytes[body ..< body + length])) }
            offset = body + length + (4 - length % 4) % 4
        }
        return samples.map { sample in
            let described = descriptors[sample.id]
            return ABRTip(image: sample.image, name: described?.name, spacing: described?.spacing)
        }
    }

    func sampleSection(_ start: Int, length: Int, subversion: Int) -> [(id: String, image: GreyImage?)] {
        var result: [(String, GreyImage?)] = []
        var offset = start
        while offset + 4 < start + length {
            let size = u32(offset)
            let begin = offset + 4
            guard size > 0, begin + size <= bytes.count else { break }
            let idLength = u8(begin)
            let id = String(decoding: bytes[min(begin + 1, bytes.count) ..< min(begin + 1 + idLength, bytes.count)], as: UTF8.self)
            // After the id: 10 bytes (6.1) or 264 bytes (6.2) of header before the picture's bounds.
            let picture = begin + 1 + idLength + (subversion == 1 ? 10 : 264)
            result.append((id.trimmingCharacters(in: CharacterSet(charactersIn: "$")), image(at: picture, end: begin + size)))
            offset = begin + size + (4 - size % 4) % 4
        }
        return result
    }

    /// Versions 1 and 2: a count, then brushes (1 computed, 2 sampled).
    func legacyTips(version: Int) -> [ABRTip] {
        let count = u16(2)
        var offset = 4
        var tips: [ABRTip] = []
        for _ in 0 ..< count {
            let type = u16(offset), size = u32(offset + 2)
            let body = offset + 6
            guard size > 0, body + size <= bytes.count else { break }
            if type == 2 {
                var cursor = body + 4
                let spacing = Double(u16(cursor)) / 100
                cursor += 2
                var name: String?
                if version == 2 {
                    let characters = u32(cursor)
                    let units = (0 ..< characters).map { UInt16(u16(cursor + 4 + $0 * 2)) }
                    name = String(decoding: units, as: UTF16.self).trimmingCharacters(in: .controlCharacters)
                    cursor += 4 + characters * 2
                }
                // Antialias flag and short bounds, then the picture.
                tips.append(ABRTip(image: image(at: cursor + 1 + 8, end: body + size), name: name, spacing: spacing > 0 ? spacing : nil))
            }
            offset = body + size
        }
        return tips
    }

    /// Bounds, depth, compression, then raw or PackBits rows.
    func image(at offset: Int, end: Int) -> GreyImage? {
        let top = u32(offset), left = u32(offset + 4), bottom = u32(offset + 8), right = u32(offset + 12)
        let depth = u16(offset + 16), compression = u8(offset + 18)
        let width = right - left, height = bottom - top
        guard width > 0, height > 0, width <= 8192, height <= 8192, depth == 8 || depth == 16 else { return nil }
        let start = offset + 19
        let bytesPerPixel = depth / 8
        let pixels = compression == 0
            ? raw(start, count: width * height * bytesPerPixel, end: end)
            : packBits(start, width: width * bytesPerPixel, height: height, end: end)
        guard pixels.count == width * height * bytesPerPixel else { return nil }
        let grey = bytesPerPixel == 1 ? pixels : stride(from: 0, to: pixels.count, by: 2).map { pixels[$0] }
        return GreyImage(width: width, height: height, pixels: grey)
    }

    func raw(_ start: Int, count: Int, end: Int) -> [UInt8] {
        guard start + count <= min(end, bytes.count) else { return [] }
        return Array(bytes[start ..< start + count])
    }

    /// PackBits rows after a table of each row's packed length.
    func packBits(_ start: Int, width: Int, height: Int, end: Int) -> [UInt8] {
        var offset = start + height * 2
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * height)
        for row in 0 ..< height {
            let rowEnd = offset + u16(start + row * 2)
            guard rowEnd <= min(end, bytes.count) else { return [] }
            var unpacked: [UInt8] = []
            while offset < rowEnd {
                let header = Int(Int8(bitPattern: bytes[offset]))
                offset += 1
                if header >= 0 {
                    let count = min(header + 1, rowEnd - offset)
                    unpacked += bytes[offset ..< offset + count]
                    offset += count
                } else if header != -128, offset < rowEnd {
                    unpacked += Array(repeating: bytes[offset], count: 1 - header)
                    offset += 1
                }
            }
            offset = rowEnd
            unpacked += Array(repeating: 0, count: max(width - unpacked.count, 0))
            pixels += unpacked.prefix(width)
        }
        return pixels
    }
}

/// Version 6's descriptor section, read only for what the import uses: each sampled tip's name and spacing. Each
/// brush's `Nm  TEXT` name is followed by its `sampledData` id and `Spcn` percentage before the next name.
enum ABRDescriptors {
    static func read(_ bytes: [UInt8]) -> [String: (name: String, spacing: Double?)] {
        let marks = occurrences(of: Array("Nm  TEXT".utf8), in: bytes)
        var result: [String: (String, Double?)] = [:]
        for (index, mark) in marks.enumerated() {
            let start = mark + 8
            let end = index + 1 < marks.count ? marks[index + 1] : bytes.count
            guard let name = unicode(bytes, at: start), let sample = find(Array("sampledDataTEXT".utf8), in: bytes, from: start, to: end),
                  let id = unicode(bytes, at: sample + 15), result[id] == nil else { continue }
            var spacing: Double?
            if let mark = find(Array("SpcnUntF#Prc".utf8), in: bytes, from: start, to: end), mark + 20 <= bytes.count {
                let raw = bytes[mark + 12 ..< mark + 20].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                spacing = Double(bitPattern: raw) / 100
            }
            result[id.trimmingCharacters(in: CharacterSet(charactersIn: "$"))] = (cleaned(name), spacing)
        }
        return result
    }

    /// "$$$/Presets/Brushes/HardRound=Hard Round" → "Hard Round".
    static func cleaned(_ name: String) -> String {
        let shown = name.split(separator: "=", maxSplits: 1).last.map(String.init) ?? name
        return shown.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }

    /// A UTF-16 string with a 4-byte length in characters.
    static func unicode(_ bytes: [UInt8], at offset: Int) -> String? {
        guard offset + 4 <= bytes.count else { return nil }
        let count = bytes[offset ..< offset + 4].reduce(0) { $0 << 8 | Int($1) }
        guard count > 0, count < 4096, offset + 4 + count * 2 <= bytes.count else { return nil }
        let units = (0 ..< count).map { UInt16(bytes[offset + 4 + $0 * 2]) << 8 | UInt16(bytes[offset + 5 + $0 * 2]) }
        return String(decoding: units, as: UTF16.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }

    static func occurrences(of needle: [UInt8], in bytes: [UInt8]) -> [Int] {
        var found: [Int] = []
        var from = 0
        while let index = find(needle, in: bytes, from: from, to: bytes.count) {
            found.append(index)
            from = index + needle.count
        }
        return found
    }

    static func find(_ needle: [UInt8], in bytes: [UInt8], from: Int, to: Int) -> Int? {
        guard let first = needle.first, to - from >= needle.count else { return nil }
        var index = from
        while index <= min(to, bytes.count) - needle.count {
            if bytes[index] == first, bytes[index ..< index + needle.count].elementsEqual(needle) { return index }
            index += 1
        }
        return nil
    }
}
