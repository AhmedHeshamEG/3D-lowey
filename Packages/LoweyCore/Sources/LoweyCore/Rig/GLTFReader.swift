import Foundation

public enum GLTFReadError: Error, Equatable, CustomStringConvertible {
    case notGLTF
    case malformed(String)
    case missingBuffer(String)

    public var description: String {
        switch self {
        case .notGLTF: "Not a glTF / GLB file"
        case let .malformed(reason): "Damaged glTF: \(reason)"
        case let .missingBuffer(name): "Missing glTF buffer \(name)"
        }
    }
}

/// Reads skeletons and animation clips straight from glTF / GLB files, in pure Swift.
///
/// The renderer shows the model (GLTFKit2); this reader gives the *animator* the bones and
/// keyframes, so clip playback, crossfades, retargeting and IK happen in LoweyCore —
/// deterministic, testable on Linux, identical in preview and export.
public enum GLTFReader {
    /// The rig of a glTF file (`nil` if the file has no skin).
    public static func rig(contentsOf url: URL) throws -> RigAsset? {
        let data = try Data(contentsOf: url)
        return try rig(data: data, baseURL: url.deletingLastPathComponent())
    }

    public static func rig(data: Data, baseURL: URL? = nil) throws -> RigAsset? {
        let file = try parse(data, baseURL: baseURL)
        guard let skeleton = try skeleton(file) else { return nil }
        let clips = try animations(file, skeleton: skeleton)
        return RigAsset(skeleton: skeleton, clips: clips)
    }

    // MARK: Container

    struct File {
        var json: [String: Any]
        var buffers: [Data]

        func array(_ key: String) -> [[String: Any]] { json[key] as? [[String: Any]] ?? [] }
    }

    static func parse(_ data: Data, baseURL: URL?) throws -> File {
        var jsonData = data
        var binary: Data?
        if data.count >= 12, data.prefix(4) == Data("glTF".utf8) {
            var offset = 12
            jsonData = Data()
            while offset + 8 <= data.count {
                let length = Int(readUInt32(data, offset))
                let type = readUInt32(data, offset + 4)
                let start = offset + 8
                guard start + length <= data.count else { throw GLTFReadError.malformed("chunk overruns the file") }
                let chunk = data.subdata(in: start ..< start + length)
                if type == 0x4E4F_534A { jsonData = chunk } else if type == 0x004E_4942 { binary = chunk }
                offset = start + length
            }
        }
        guard let object = try? JSONSerialization.jsonObject(with: jsonData), let json = object as? [String: Any],
              json["asset"] != nil else { throw GLTFReadError.notGLTF }
        var buffers: [Data] = []
        for (index, buffer) in (json["buffers"] as? [[String: Any]] ?? []).enumerated() {
            if let uri = buffer["uri"] as? String {
                if uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ",") {
                    guard let decoded = Data(base64Encoded: String(uri[uri.index(after: comma)...])) else {
                        throw GLTFReadError.malformed("bad data URI")
                    }
                    buffers.append(decoded)
                } else if let baseURL {
                    let path = uri.removingPercentEncoding ?? uri
                    guard let loaded = try? Data(contentsOf: baseURL.appendingPathComponent(path)) else {
                        throw GLTFReadError.missingBuffer(uri)
                    }
                    buffers.append(loaded)
                } else {
                    throw GLTFReadError.missingBuffer(uri)
                }
            } else if index == 0, let binary {
                buffers.append(binary)
            } else {
                throw GLTFReadError.missingBuffer("#\(index)")
            }
        }
        return File(json: json, buffers: buffers)
    }

    static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }.littleEndian
    }

    // MARK: Accessors

    /// Accessor values as doubles, `components` per element (normalised integers mapped to 0…1 / -1…1).
    static func accessor(_ file: File, _ index: Int) throws -> (values: [Double], components: Int, count: Int) {
        let accessors = file.array("accessors")
        guard index >= 0, index < accessors.count else { throw GLTFReadError.malformed("accessor \(index)") }
        let accessor = accessors[index]
        let count = accessor["count"] as? Int ?? 0
        let components: Int = switch accessor["type"] as? String ?? "SCALAR" {
        case "VEC2": 2
        case "VEC3": 3
        case "VEC4": 4
        case "MAT4": 16
        case "MAT3": 9
        default: 1
        }
        guard let viewIndex = accessor["bufferView"] as? Int else {
            return (Array(repeating: 0, count: count * components), components, count)
        }
        let views = file.array("bufferViews")
        guard viewIndex < views.count else { throw GLTFReadError.malformed("bufferView \(viewIndex)") }
        let view = views[viewIndex]
        let bufferIndex = view["buffer"] as? Int ?? 0
        guard bufferIndex < file.buffers.count else { throw GLTFReadError.missingBuffer("#\(bufferIndex)") }
        let buffer = file.buffers[bufferIndex]
        let componentType = accessor["componentType"] as? Int ?? 5126
        let normalized = accessor["normalized"] as? Bool ?? false
        let componentSize: Int = switch componentType {
        case 5120, 5121: 1
        case 5122, 5123: 2
        default: 4
        }
        let elementSize = componentSize * components
        let stride = (view["byteStride"] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? elementSize
        let base = (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
        guard count == 0 || base + stride * (count - 1) + elementSize <= buffer.count else {
            throw GLTFReadError.malformed("accessor \(index) overruns its buffer")
        }
        var values: [Double] = []
        values.reserveCapacity(count * components)
        buffer.withUnsafeBytes { raw in
            for element in 0 ..< count {
                for component in 0 ..< components {
                    let offset = base + element * stride + component * componentSize
                    let value: Double = switch componentType {
                    case 5120:
                        normalized ? max(Double(raw.loadUnaligned(fromByteOffset: offset, as: Int8.self)) / 127, -1)
                            : Double(raw.loadUnaligned(fromByteOffset: offset, as: Int8.self))
                    case 5121:
                        normalized ? Double(raw.loadUnaligned(fromByteOffset: offset, as: UInt8.self)) / 255
                            : Double(raw.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                    case 5122:
                        normalized ? max(Double(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: Int16.self))) / 32767, -1)
                            : Double(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: Int16.self)))
                    case 5123:
                        normalized ? Double(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))) / 65535
                            : Double(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
                    case 5125:
                        Double(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
                    default:
                        Double(Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))))
                    }
                    values.append(value)
                }
            }
        }
        return (values, components, count)
    }

    // MARK: Nodes

    static func localTransform(_ node: [String: Any]) -> Transform {
        if let matrix = (node["matrix"] as? [Any])?.compactMap({ ($0 as? NSNumber)?.doubleValue }), matrix.count == 16 {
            return decompose(matrix)
        }
        let t = numbers(node["translation"]) ?? [0, 0, 0]
        let r = numbers(node["rotation"]) ?? [0, 0, 0, 1]
        let s = numbers(node["scale"]) ?? [1, 1, 1]
        guard t.count == 3, r.count == 4, s.count == 3 else { return .identity }
        return Transform(position: Vec3(t[0], t[1], t[2]), rotation: Quat(x: r[0], y: r[1], z: r[2], w: r[3]).normalized,
                         scale: Vec3(s[0], s[1], s[2]))
    }

    static func numbers(_ value: Any?) -> [Double]? {
        (value as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue }
    }

    /// Column-major 4×4 → TRS.
    static func decompose(_ m: [Double]) -> Transform {
        let position = Vec3(m[12], m[13], m[14])
        let cx = Vec3(m[0], m[1], m[2])
        let cy = Vec3(m[4], m[5], m[6])
        let cz = Vec3(m[8], m[9], m[10])
        var scale = Vec3(cx.length, cy.length, cz.length)
        if cx.cross(cy).dot(cz) < 0 { scale.x = -scale.x }
        let r0 = scale.x != 0 ? cx / scale.x : .unitX
        let r1 = scale.y != 0 ? cy / scale.y : .unitY
        let r2 = scale.z != 0 ? cz / scale.z : .unitZ
        // Rotation matrix (columns r0, r1, r2) → quaternion.
        let m00 = r0.x, m10 = r0.y, m20 = r0.z
        let m01 = r1.x, m11 = r1.y, m21 = r1.z
        let m02 = r2.x, m12 = r2.y, m22 = r2.z
        let trace = m00 + m11 + m22
        let q: Quat
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            q = Quat(x: (m21 - m12) / s, y: (m02 - m20) / s, z: (m10 - m01) / s, w: 0.25 * s)
        } else if m00 > m11, m00 > m22 {
            let s = (1 + m00 - m11 - m22).squareRoot() * 2
            q = Quat(x: 0.25 * s, y: (m01 + m10) / s, z: (m02 + m20) / s, w: (m21 - m12) / s)
        } else if m11 > m22 {
            let s = (1 + m11 - m00 - m22).squareRoot() * 2
            q = Quat(x: (m01 + m10) / s, y: 0.25 * s, z: (m12 + m21) / s, w: (m02 - m20) / s)
        } else {
            let s = (1 + m22 - m00 - m11).squareRoot() * 2
            q = Quat(x: (m02 + m20) / s, y: (m12 + m21) / s, z: 0.25 * s, w: (m10 - m01) / s)
        }
        return Transform(position: position, rotation: q.normalized, scale: scale)
    }

    static func nodeName(_ node: [String: Any], index: Int) -> String {
        (node["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "joint_\(index)"
    }

    // MARK: Skeleton

    static func skeleton(_ file: File) throws -> Skeleton? {
        let nodes = file.array("nodes")
        guard let skin = file.array("skins").first, let jointNodes = skin["joints"] as? [Int], !jointNodes.isEmpty else { return nil }
        var parentOf: [Int: Int] = [:]
        for (index, node) in nodes.enumerated() {
            for child in node["children"] as? [Int] ?? [] {
                parentOf[child] = index
            }
        }
        let jointSet = Set(jointNodes)
        // Order parents before children (skins usually are, but not always).
        var ordered: [Int] = []
        var placed = Set<Int>()
        func place(_ node: Int, depth: Int) {
            guard !placed.contains(node), depth < 512 else { return }
            var ancestor = parentOf[node]
            while let current = ancestor, !jointSet.contains(current) {
                ancestor = parentOf[current]
            }
            if let ancestor { place(ancestor, depth: depth + 1) }
            placed.insert(node)
            ordered.append(node)
        }
        for node in jointNodes {
            place(node, depth: 0)
        }
        var indexOfNode: [Int: Int] = [:]
        var joints: [Joint] = []
        for node in ordered {
            guard node < nodes.count else { throw GLTFReadError.malformed("joint node \(node)") }
            // Non-joint nodes between this joint and its joint parent are folded into the rest pose.
            // Above a root joint (the armature) they're left out: clips key joints in their own
            // local space, and the renderer applies poses relative to the model's own rest pose.
            var rest = localTransform(nodes[node])
            var ancestor = parentOf[node]
            var parentJoint: Int?
            var between: [Int] = []
            while let current = ancestor {
                if jointSet.contains(current) {
                    parentJoint = indexOfNode[current]
                    break
                }
                between.append(current)
                ancestor = parentOf[current]
            }
            if parentJoint != nil {
                for current in between {
                    rest = localTransform(nodes[current]) * rest
                }
            }
            indexOfNode[node] = joints.count
            joints.append(Joint(name: nodeName(nodes[node], index: node), parent: parentJoint, rest: rest))
        }
        return Skeleton(joints: joints)
    }

    // MARK: Animations

    static func animations(_ file: File, skeleton: Skeleton) throws -> [MotionClip] {
        let nodes = file.array("nodes")
        let jointNames = Set(skeleton.names)
        var clips: [MotionClip] = []
        for (clipIndex, animation) in file.array("animations").enumerated() {
            let samplers = animation["samplers"] as? [[String: Any]] ?? []
            var channels: [JointChannel] = []
            var duration = 0.0
            for channel in animation["channels"] as? [[String: Any]] ?? [] {
                guard let target = channel["target"] as? [String: Any], let node = target["node"] as? Int, node < nodes.count,
                      let pathName = target["path"] as? String, let path = ChannelPath(rawValue: pathName),
                      let samplerIndex = channel["sampler"] as? Int, samplerIndex < samplers.count else { continue }
                let name = nodeName(nodes[node], index: node)
                guard jointNames.contains(name) else { continue }
                let sampler = samplers[samplerIndex]
                guard let input = sampler["input"] as? Int, let output = sampler["output"] as? Int else { continue }
                let times = try accessor(file, input).values
                let (values, components, count) = try accessor(file, output)
                let interpolation = sampler["interpolation"] as? String ?? "LINEAR"
                let cubic = interpolation == "CUBICSPLINE"
                // Cubic splines store (in-tangent, value, out-tangent) triplets: keep the values.
                let stride = cubic ? 3 : 1
                guard !times.isEmpty, count >= times.count * stride else { continue }
                duration = max(duration, times.last ?? 0)
                var result = JointChannel(joint: name, path: path, times: times, step: interpolation == "STEP")
                for key in times.indices {
                    let element = key * stride + (cubic ? 1 : 0)
                    let base = element * components
                    switch path {
                    case .rotation where components == 4:
                        result.rotations.append(Quat(x: values[base], y: values[base + 1], z: values[base + 2], w: values[base + 3]).normalized)
                    case .translation where components == 3, .scale where components == 3:
                        result.vectors.append(Vec3(values[base], values[base + 1], values[base + 2]))
                    default:
                        break
                    }
                }
                if !result.rotations.isEmpty || !result.vectors.isEmpty { channels.append(result) }
            }
            guard !channels.isEmpty else { continue }
            let name = (animation["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Clip \(clipIndex + 1)"
            clips.append(MotionClip(name: name, duration: duration, channels: channels))
        }
        return clips
    }
}
