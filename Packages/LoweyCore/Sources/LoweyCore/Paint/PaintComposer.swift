import Foundation

/// Paint layers as pictures: assembled from their tiles, composited with their blend modes and opacity (the W3C
/// formulas on the stored sRGB values, the same maths as the stage's GPU composite), split back into tiles.
public enum PaintComposer {
    /// A layer's whole picture; missing or unreadable tiles are transparent.
    public static func layerImage(_ layer: PaintLayer, surface: PaintSurface, tile: (String) -> RGBAImage?) -> RGBAImage {
        var image = RGBAImage.clear(width: surface.size, height: surface.size)
        let size = PaintSurface.tileSize
        for (key, file) in layer.tiles {
            guard let index = PaintTileIndex(key: key), index.column < surface.tilesPerSide, index.row < surface.tilesPerSide,
                  let picture = tile(file), picture.width == size, picture.height == size else { continue }
            image.place(picture, x: index.column * size, y: index.row * size)
        }
        return image
    }

    /// The picture's tiles that hold any paint (a transparent tile is left out: it's no file at all).
    public static func tiles(of image: RGBAImage, surface: PaintSurface) -> [PaintTileIndex: RGBAImage] {
        var result: [PaintTileIndex: RGBAImage] = [:]
        for index in surface.allTiles {
            let tile = image.tile(index, size: PaintSurface.tileSize)
            if !tile.isClear { result[index] = tile }
        }
        return result
    }

    /// Every visible layer, bottom first, into one straight-alpha picture (alpha 0 where nothing is painted: the
    /// object's own colour shows there).
    public static func composite(_ paint: ObjectPaint, layer image: (PaintLayer) -> RGBAImage) -> RGBAImage {
        let size = paint.surface.size
        var premultiplied = [Double](repeating: 0, count: size * size * 4)
        for layer in paint.layers where layer.visible && layer.opacity > 0 && !layer.isEmpty {
            let picture = image(layer)
            guard picture.width == size, picture.height == size else { continue }
            for index in 0 ..< size * size {
                let alpha = Double(picture.pixels[index * 4 + 3]) / 255 * layer.opacity
                guard alpha > 0 else { continue }
                let source = SIMD3<Double>(Double(picture.pixels[index * 4]), Double(picture.pixels[index * 4 + 1]),
                                           Double(picture.pixels[index * 4 + 2])) / 255
                let out = blend(source: source, alpha: alpha, mode: layer.blend,
                                backdrop: SIMD4<Double>(premultiplied[index * 4], premultiplied[index * 4 + 1], premultiplied[index * 4 + 2],
                                                        premultiplied[index * 4 + 3]))
                for channel in 0 ..< 4 {
                    premultiplied[index * 4 + channel] = out[channel]
                }
            }
        }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for index in 0 ..< size * size {
            let alpha = premultiplied[index * 4 + 3]
            guard alpha > 1e-6 else { continue }
            for channel in 0 ..< 3 {
                pixels[index * 4 + channel] = UInt8((min(max(premultiplied[index * 4 + channel] / alpha, 0), 1) * 255).rounded())
            }
            pixels[index * 4 + 3] = UInt8((min(alpha, 1) * 255).rounded())
        }
        return RGBAImage(width: size, height: size, pixels: pixels)
    }

    /// One source pixel over a premultiplied backdrop: Cs' = (1 − αb)·Cs + αb·B(Cb, Cs), then source-over.
    public static func blend(source: SIMD3<Double>, alpha: Double, mode: PaintBlend, backdrop: SIMD4<Double>) -> SIMD4<Double> {
        let backdropAlpha = backdrop.w
        let straight = backdropAlpha > 1e-6 ? SIMD3<Double>(backdrop.x, backdrop.y, backdrop.z) / backdropAlpha : .zero
        var mixed = source
        if mode != .normal, backdropAlpha > 0 {
            let blended = SIMD3<Double>(mode.mix(straight.x, source.x), mode.mix(straight.y, source.y), mode.mix(straight.z, source.z))
            mixed = source * (1 - backdropAlpha) + blended * backdropAlpha
        }
        let color = mixed * alpha + SIMD3<Double>(backdrop.x, backdrop.y, backdrop.z) * (1 - alpha)
        return SIMD4<Double>(color.x, color.y, color.z, alpha + backdropAlpha * (1 - alpha))
    }

    /// The paint's texture with the object's own colour under it (opaque): what a viewer without layers shows.
    public static func flattened(_ texture: RGBAImage, over base: RGBA) -> RGBAImage {
        var result = texture
        let (r, g, b, _) = RGBAImage.bytes(base)
        for index in 0 ..< texture.width * texture.height {
            let alpha = Int(texture.pixels[index * 4 + 3])
            for (channel, under) in [(0, Int(r)), (1, Int(g)), (2, Int(b))] {
                let over = Int(texture.pixels[index * 4 + channel])
                result.pixels[index * 4 + channel] = UInt8((over * alpha + under * (255 - alpha) + 127) / 255)
            }
            result.pixels[index * 4 + 3] = 255
        }
        return result
    }
}
