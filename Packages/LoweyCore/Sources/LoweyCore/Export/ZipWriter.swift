import Foundation

/// Minimal "stored" (uncompressed) zip writer — all USDZ needs.
public enum ZipWriter {
    public static func storedArchive(_ files: [(name: String, data: Data)], alignment: Int = 1) -> Data {
        var archive = Data()
        var central = Data()
        for file in files {
            let name = Data(file.name.utf8)
            let crc = CRC32.checksum(file.data)
            let offset = archive.count
            localHeader(name: name, crc: crc, size: file.data.count, alignment: alignment, into: &archive)
            archive.append(file.data)
            centralEntry(name: name, crc: crc, size: file.data.count, offset: offset, into: &central)
        }
        let centralOffset = archive.count
        archive.append(central)
        u32(0x0605_4B50, into: &archive)
        u16(0, into: &archive)
        u16(0, into: &archive)
        u16(files.count, into: &archive)
        u16(files.count, into: &archive)
        u32(UInt32(central.count), into: &archive)
        u32(UInt32(centralOffset), into: &archive)
        u16(0, into: &archive)
        return archive
    }

    /// The local file header, with padding in the extra field so the data begins on an aligned offset.
    private static func localHeader(name: Data, crc: UInt32, size: Int, alignment: Int, into archive: inout Data) {
        let headerSize = 30 + name.count
        var padding = 0
        if alignment > 1 {
            let extraHeader = 4
            padding = (alignment - (archive.count + headerSize + extraHeader) % alignment) % alignment
        }
        let extraLength = alignment > 1 ? 4 + padding : 0
        u32(0x0403_4B50, into: &archive)
        u16(20, into: &archive)
        u16(0, into: &archive)
        u16(0, into: &archive)
        u16(0, into: &archive)
        u16(0x21, into: &archive)
        u32(crc, into: &archive)
        u32(UInt32(size), into: &archive)
        u32(UInt32(size), into: &archive)
        u16(name.count, into: &archive)
        u16(extraLength, into: &archive)
        archive.append(name)
        if alignment > 1 {
            u16(0x1986, into: &archive)
            u16(padding, into: &archive)
            archive.append(Data(repeating: 0, count: padding))
        }
    }

    private static func centralEntry(name: Data, crc: UInt32, size: Int, offset: Int, into central: inout Data) {
        u32(0x0201_4B50, into: &central)
        u16(20, into: &central)
        u16(20, into: &central)
        u16(0, into: &central)
        u16(0, into: &central)
        u16(0, into: &central)
        u16(0x21, into: &central)
        u32(crc, into: &central)
        u32(UInt32(size), into: &central)
        u32(UInt32(size), into: &central)
        u16(name.count, into: &central)
        u16(0, into: &central)
        u16(0, into: &central)
        u16(0, into: &central)
        u16(0, into: &central)
        u32(0, into: &central)
        u32(UInt32(offset), into: &central)
        central.append(name)
    }

    private static func u16(_ value: Int, into data: inout Data) {
        withUnsafeBytes(of: UInt16(truncatingIfNeeded: value).littleEndian) { data.append(contentsOf: $0) }
    }

    private static func u32(_ value: UInt32, into data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
