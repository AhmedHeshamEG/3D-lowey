import Foundation
import LoweyCore
import os

/// Skeletons and clips of rigged library models, read once from their glTF files (LoweyCore's
/// `GLTFReader`) and shared by the live stage and the exporter.
@MainActor
public final class RigCache {
    private var rigs: [AssetID: RigAsset] = [:]
    private var missing = Set<AssetID>()
    private let logger = Logger(subsystem: "com.hesham.lowey", category: "rigs")

    public init() {}

    /// The rig of a library model (`nil` for static models and formats without Core rig data).
    public func rig(for asset: LibraryAsset, url: URL) -> RigAsset? {
        if let cached = rigs[asset.id] { return cached }
        guard !missing.contains(asset.id) else { return nil }
        guard asset.format == .glb || asset.format == .gltf else {
            missing.insert(asset.id)
            return nil
        }
        do {
            if let rig = try GLTFReader.rig(contentsOf: url) {
                rigs[asset.id] = rig
                return rig
            }
        } catch {
            logger.error("Couldn't read the rig of \(asset.name): \(String(describing: error))")
        }
        missing.insert(asset.id)
        return nil
    }

    /// Rigs needed to evaluate a document: every character with a clip track and every clip source.
    public func rigs(for document: Document, library: LibraryProviding?) -> [AssetID: RigAsset] {
        guard let library, !document.scene.timeline.clipTracks.isEmpty else { return [:] }
        var needed = Set<AssetID>()
        for track in document.scene.timeline.clipTracks {
            if let asset = document.scene.objects[track.target]?.kind.assetID { needed.insert(asset) }
            for segment in track.segments {
                needed.insert(segment.clip.asset)
            }
        }
        var result: [AssetID: RigAsset] = [:]
        for id in needed {
            guard let asset = library.manifest.asset(id), let rig = rig(for: asset, url: library.fileURL(for: asset)) else { continue }
            result[id] = rig
        }
        return result
    }

    /// Clip names a character can play: its own, plus every clip of the same skeleton standard
    /// in the library (retargeting).
    public func availableClips(for asset: LibraryAsset, library: LibraryProviding) -> [ClipRef] {
        guard let own = rig(for: asset, url: library.fileURL(for: asset)) else {
            return asset.clips.map { ClipRef(asset: asset.id, name: $0) }
        }
        var result = own.clipNames.map { ClipRef(asset: asset.id, name: $0) }
        guard own.standard != .custom else { return result }
        for other in library.manifest.assets where other.id != asset.id && other.rig.isRigged {
            guard let rig = rig(for: other, url: library.fileURL(for: other)), rig.standard == own.standard else { continue }
            result += rig.clipNames.map { ClipRef(asset: other.id, name: $0) }
        }
        return result
    }

    public func forget(_ id: AssetID) {
        rigs[id] = nil
        missing.remove(id)
    }
}
