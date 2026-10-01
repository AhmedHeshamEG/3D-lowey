import CoreGraphics
import Foundation
import LoweyCore
import Metal
import MetalKit

/// GPU textures for model materials and card pictures / video frames, made once per image. Bounded: the least
/// recently used go first when the budget is full (a long video on a card makes a new frame most of the time).
final class TextureStore {
    private let loader: MTKTextureLoader
    private var entries: [String: (texture: MTLTexture, lastUse: UInt64, bytes: Int)] = [:]
    private var imageIdentity: [String: ObjectIdentifier] = [:]
    private var clock: UInt64 = 0
    private var bytes = 0
    var budget = 256 * 1024 * 1024

    init(device: MTLDevice) {
        loader = MTKTextureLoader(device: device)
    }

    private var options: [MTKTextureLoader.Option: Any] {
        [.SRGB: true, .generateMipmaps: true, .textureUsage: MTLTextureUsage.shaderRead.rawValue, .textureStorageMode: MTLStorageMode.private.rawValue]
    }

    /// A model texture (encoded PNG / JPEG in the file).
    func texture(model: AssetID, index: Int, texture: ImportedTexture) -> MTLTexture? {
        let key = "model:\(model.raw)#\(index)"
        if let hit = lookup(key) { return hit }
        guard !texture.data.isEmpty, let made = try? loader.newTexture(data: texture.data, options: options) else { return nil }
        return insert(made, key: key)
    }

    /// A picture or video frame. `key` names the frame; the texture is replaced when the image object changes.
    func texture(for image: CGImage, key: String, maxSide: Int) -> MTLTexture? {
        let identity = ObjectIdentifier(image)
        if imageIdentity[key] == identity, let hit = lookup(key) { return hit }
        let fitted = Self.fitted(image, maxSide: maxSide)
        guard let made = try? loader.newTexture(cgImage: fitted, options: options) else { return nil }
        imageIdentity[key] = identity
        entries[key].map { bytes -= $0.bytes }
        return insert(made, key: key)
    }

    private func lookup(_ key: String) -> MTLTexture? {
        guard let entry = entries[key] else { return nil }
        clock &+= 1
        entries[key] = (entry.texture, clock, entry.bytes)
        return entry.texture
    }

    private func insert(_ texture: MTLTexture, key: String) -> MTLTexture {
        clock &+= 1
        let size = texture.width * texture.height * 4 * 4 / 3
        entries[key] = (texture, clock, size)
        bytes += size
        if bytes > budget {
            for (old, entry) in entries.sorted(by: { $0.value.lastUse < $1.value.lastUse }) where old != key {
                entries[old] = nil
                imageIdentity[old] = nil
                bytes -= entry.bytes
                if bytes <= budget * 3 / 4 { break }
            }
        }
        return texture
    }

    func removeAll() {
        entries.removeAll()
        imageIdentity.removeAll()
        bytes = 0
    }

    /// Big photos are drawn down to `maxSide` pixels (a 12 MP photo as a texture is 48 MB for nothing).
    static func fitted(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let scale = Double(maxSide) / Double(longest)
        let width = max(Int(Double(image.width) * scale), 1)
        let height = max(Int(Double(image.height) * scale), 1)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
