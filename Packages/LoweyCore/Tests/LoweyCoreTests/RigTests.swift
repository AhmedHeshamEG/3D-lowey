import Foundation
@testable import LoweyCore
import XCTest

/// Builds small skinned glTF files in memory (skeleton + clips), like the ones kits ship.
struct TestRig {
    struct Bone {
        var name: String
        var parent: Int?
        var translation: Vec3
        var rotation: Quat = .identity
    }

    struct Channel {
        var bone: Int
        var path: String
        var times: [Float]
        var values: [Float]
        var interpolation = "LINEAR"
    }

    var bones: [Bone]
    var clips: [(String, [Channel])] = []
    /// Put the skeleton under an "Armature" node with this transform (Blender/Mixamo exports).
    var armature: Transform?
    /// Encode the first bone's rest pose as a matrix instead of TRS.
    var matrixRoot = false

    func glb() -> Data {
        var blob = Data()
        var views: [[String: Any]] = []
        var accessors: [[String: Any]] = []
        func add(_ floats: [Float], type: String, count: Int, minMax: Bool = false) -> Int {
            while blob.count % 4 != 0 {
                blob.append(0)
            }
            let offset = blob.count
            for value in floats {
                withUnsafeBytes(of: value.bitPattern.littleEndian) { blob.append(contentsOf: $0) }
            }
            views.append(["buffer": 0, "byteOffset": offset, "byteLength": floats.count * 4])
            var accessor: [String: Any] = ["bufferView": views.count - 1, "componentType": 5126, "count": count, "type": type]
            if minMax { accessor["min"] = [floats.min() ?? 0]; accessor["max"] = [floats.max() ?? 0] }
            accessors.append(accessor)
            return accessors.count - 1
        }
        // A one-triangle mesh so the file is a real model.
        let positions = add([0, 0, 0, 1, 0, 0, 0, 1, 0], type: "VEC3", count: 3)
        let offset = armature == nil ? 1 : 2
        var nodes: [[String: Any]] = [["name": "Body", "mesh": 0, "skin": 0]]
        if let armature {
            let a = armature
            nodes.append(["name": "Armature", "children": [], "translation": [a.position.x, a.position.y, a.position.z],
                          "rotation": [a.rotation.x, a.rotation.y, a.rotation.z, a.rotation.w], "scale": [a.scale.x, a.scale.y, a.scale.z]])
        }
        for (index, bone) in bones.enumerated() {
            var node: [String: Any] = ["name": bone.name, "children": [Int]()]
            if index == 0, matrixRoot {
                let t = Transform(position: bone.translation, rotation: bone.rotation)
                let x = t.rotation.act(.unitX), y = t.rotation.act(.unitY), z = t.rotation.act(.unitZ)
                node["matrix"] = [x.x, x.y, x.z, 0, y.x, y.y, y.z, 0, z.x, z.y, z.z, 0, t.position.x, t.position.y, t.position.z, 1]
            } else {
                node["translation"] = [bone.translation.x, bone.translation.y, bone.translation.z]
                node["rotation"] = [bone.rotation.x, bone.rotation.y, bone.rotation.z, bone.rotation.w]
            }
            nodes.append(node)
        }
        var roots: [Int] = [0]
        for (index, bone) in bones.enumerated() {
            if let parent = bone.parent {
                var children = nodes[offset + parent]["children"] as? [Int] ?? []
                children.append(offset + index)
                nodes[offset + parent]["children"] = children
            } else if armature != nil {
                var children = nodes[1]["children"] as? [Int] ?? []
                children.append(offset + index)
                nodes[1]["children"] = children
            } else {
                roots.append(offset + index)
            }
        }
        if armature != nil { roots.append(1) }
        var animations: [[String: Any]] = []
        for (name, channels) in clips {
            var samplers: [[String: Any]] = []
            var gltfChannels: [[String: Any]] = []
            for channel in channels {
                let input = add(channel.times, type: "SCALAR", count: channel.times.count, minMax: true)
                let components = channel.path == "rotation" ? 4 : 3
                let output = add(channel.values, type: components == 4 ? "VEC4" : "VEC3", count: channel.values.count / components)
                samplers.append(["input": input, "output": output, "interpolation": channel.interpolation])
                gltfChannels.append(["sampler": samplers.count - 1, "target": ["node": offset + channel.bone, "path": channel.path]])
            }
            animations.append(["name": name, "samplers": samplers, "channels": gltfChannels])
        }
        let json: [String: Any] = [
            "asset": ["version": "2.0"], "scene": 0, "scenes": [["nodes": roots]],
            "nodes": nodes, "meshes": [["primitives": [["attributes": ["POSITION": positions]]]]],
            "skins": [["joints": bones.indices.map { offset + $0 }]],
            "animations": animations, "accessors": accessors, "bufferViews": views, "buffers": [["byteLength": blob.count]]
        ]
        var jsonData = try! JSONSerialization.data(withJSONObject: json)
        while jsonData.count % 4 != 0 {
            jsonData.append(0x20)
        }
        while blob.count % 4 != 0 {
            blob.append(0)
        }
        var data = Data("glTF".utf8)
        func u32(_ value: Int) { withUnsafeBytes(of: UInt32(value).littleEndian) { data.append(contentsOf: $0) } }
        u32(2)
        u32(12 + 8 + jsonData.count + 8 + blob.count)
        u32(jsonData.count)
        data.append(Data("JSON".utf8))
        data.append(jsonData)
        u32(blob.count)
        data.append(contentsOf: [0x42, 0x49, 0x4E, 0])
        data.append(blob)
        return data
    }

    static func quatFloats(_ q: Quat) -> [Float] { [Float(q.x), Float(q.y), Float(q.z), Float(q.w)] }

    /// A humanoid in a T-pose. `names` picks the naming convention; `scale` its size.
    static func humanoid(mixamo: Bool, scale: Double = 1) -> TestRig {
        let n: [String] = mixamo
            ? ["mixamorig:Hips", "mixamorig:Spine", "mixamorig:Spine1", "mixamorig:Neck", "mixamorig:Head",
               "mixamorig:LeftArm", "mixamorig:LeftForeArm", "mixamorig:LeftHand",
               "mixamorig:RightArm", "mixamorig:RightForeArm", "mixamorig:RightHand",
               "mixamorig:LeftUpLeg", "mixamorig:LeftLeg", "mixamorig:LeftFoot",
               "mixamorig:RightUpLeg", "mixamorig:RightLeg", "mixamorig:RightFoot"]
            : ["Hips", "Abdomen", "Chest", "Neck", "Head",
               "UpperArm.L", "LowerArm.L", "Wrist.L", "UpperArm.R", "LowerArm.R", "Wrist.R",
               "UpperLeg.L", "LowerLeg.L", "Foot.L", "UpperLeg.R", "LowerLeg.R", "Foot.R"]
        let s = scale
        // Quaternius-style bones point along their own local Y with a different rest rotation on the legs,
        // Mixamo-style ones don't rotate at rest: retargeting must work in model space either way.
        let legRest = mixamo ? Quat.identity : Quat(angle: .pi, axis: .unitZ)
        let bones: [Bone] = [
            Bone(name: n[0], parent: nil, translation: Vec3(0, 1 * s, 0)),
            Bone(name: n[1], parent: 0, translation: Vec3(0, 0.15 * s, 0)),
            Bone(name: n[2], parent: 1, translation: Vec3(0, 0.2 * s, 0)),
            Bone(name: n[3], parent: 2, translation: Vec3(0, 0.25 * s, 0)),
            Bone(name: n[4], parent: 3, translation: Vec3(0, 0.1 * s, 0)),
            Bone(name: n[5], parent: 2, translation: Vec3(0.2 * s, 0.2 * s, 0)),
            Bone(name: n[6], parent: 5, translation: Vec3(0.3 * s, 0, 0)),
            Bone(name: n[7], parent: 6, translation: Vec3(0.25 * s, 0, 0)),
            Bone(name: n[8], parent: 2, translation: Vec3(-0.2 * s, 0.2 * s, 0)),
            Bone(name: n[9], parent: 8, translation: Vec3(-0.3 * s, 0, 0)),
            Bone(name: n[10], parent: 9, translation: Vec3(-0.25 * s, 0, 0)),
            Bone(name: n[11], parent: 0, translation: Vec3(0.1 * s, 0, 0), rotation: legRest),
            Bone(name: n[12], parent: 11, translation: mixamo ? Vec3(0, -0.45 * s, 0) : Vec3(0, 0.45 * s, 0)),
            Bone(name: n[13], parent: 12, translation: mixamo ? Vec3(0, -0.45 * s, 0) : Vec3(0, 0.45 * s, 0)),
            Bone(name: n[14], parent: 0, translation: Vec3(-0.1 * s, 0, 0), rotation: legRest),
            Bone(name: n[15], parent: 14, translation: mixamo ? Vec3(0, -0.45 * s, 0) : Vec3(0, 0.45 * s, 0)),
            Bone(name: n[16], parent: 15, translation: mixamo ? Vec3(0, -0.45 * s, 0) : Vec3(0, 0.45 * s, 0))
        ]
        return TestRig(bones: bones)
    }

    /// Kick: the left thigh swings forward 40° and back over 1 s; the hips move 1 m forward.
    static func kickClip(for rig: TestRig) -> [Channel] {
        let forward = Quat(angle: -40 * .pi / 180, axis: .unitX)
        let rest = rig.bones[11].rotation
        let values = [rest, (forward * rest).normalized, rest].flatMap(quatFloats)
        let hips = rig.bones[0].translation
        return [
            Channel(bone: 11, path: "rotation", times: [0, 0.5, 1], values: values),
            Channel(bone: 0, path: "translation", times: [0, 1],
                    values: [Float(hips.x), Float(hips.y), Float(hips.z), Float(hips.x), Float(hips.y), Float(hips.z) + 1])
        ]
    }

    static func quadruped(names: [String], length: Double) -> TestRig {
        // Root, Spine, Neck, Head, front L/R (upper, lower), back L/R (upper, lower), Tail
        let l = length
        var bones: [Bone] = [
            Bone(name: names[0], parent: nil, translation: Vec3(0, 0.6, -l / 2)),
            Bone(name: names[1], parent: 0, translation: Vec3(0, 0, l)),
            Bone(name: names[2], parent: 1, translation: Vec3(0, 0.2, 0.1)),
            Bone(name: names[3], parent: 2, translation: Vec3(0, 0.1, 0.1))
        ]
        let legs = [(4, 1, 0.15), (6, 1, -0.15), (8, 0, 0.15), (10, 0, -0.15)]
        for (start, parent, x) in legs {
            bones.append(Bone(name: names[start], parent: parent, translation: Vec3(x, 0, 0)))
            bones.append(Bone(name: names[start + 1], parent: bones.count - 1, translation: Vec3(0, -0.3, 0)))
        }
        bones.append(Bone(name: names[12], parent: 0, translation: Vec3(0, 0.1, -0.1)))
        return TestRig(bones: bones)
    }

    /// A walk: legs swing ±25° in pairs over a 1 s cycle.
    static func walkClip() -> [Channel] {
        func swing(_ bone: Int, _ phase: Double) -> Channel {
            let times: [Float] = [0, 0.25, 0.5, 0.75, 1]
            let values = times.flatMap { t -> [Float] in
                quatFloats(Quat(angle: sin(2 * .pi * Double(t) + phase) * 25 * .pi / 180, axis: .unitX))
            }
            return Channel(bone: bone, path: "rotation", times: times, values: values)
        }
        return [swing(4, 0), swing(6, .pi), swing(8, .pi), swing(10, 0)]
    }
}

final class RigTests: XCTestCase {
    func testReadsSkeletonAndClipsFromGLB() throws {
        var rig = TestRig.humanoid(mixamo: true)
        rig.clips = [("Kick", TestRig.kickClip(for: rig))]
        rig.matrixRoot = true
        rig.armature = Transform(position: Vec3(0, 0, 0), rotation: Quat(angle: .pi / 2, axis: .unitX), scale: Vec3(0.01, 0.01, 0.01))
        let asset = try XCTUnwrap(GLTFReader.rig(data: rig.glb()))
        XCTAssertEqual(asset.skeleton.joints.count, 17)
        XCTAssertEqual(asset.skeleton.joints[1].parent, 0)
        XCTAssertNil(asset.skeleton.joints[0].parent)
        XCTAssertTrue(asset.skeleton.joints[0].rest.position.isApproximately(Vec3(0, 1, 0), tolerance: 1e-6), "matrix decomposed")
        XCTAssertEqual(asset.standard, .humanoid)
        XCTAssertEqual(asset.boneMap["hips"], "mixamorig:Hips")
        XCTAssertEqual(asset.boneMap["chest"], "mixamorig:Spine1")
        XCTAssertEqual(asset.boneMap["leftUpperLeg"], "mixamorig:LeftUpLeg")
        XCTAssertEqual(asset.boneMap["leftFoot"], "mixamorig:LeftFoot")
        XCTAssertEqual(asset.boneMap["rightHand"], "mixamorig:RightHand")
        XCTAssertEqual(asset.clipNames, ["Kick"])
        let kick = try XCTUnwrap(asset.clips["Kick"])
        XCTAssertEqual(kick.duration, 1)
        let mid = kick.pose(at: 0.5, skeleton: asset.skeleton)
        XCTAssertTrue(mid[11].rotation.isApproximately(Quat(angle: -40 * .pi / 180, axis: .unitX), tolerance: 1e-5))
        XCTAssertEqual(kick.pose(at: 0.5, skeleton: asset.skeleton)[0].position.z, 0.5, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(asset.strideSpeed(of: kick)), 1, accuracy: 1e-5, "root motion: 1 m per second")
        XCTAssertNil(try GLTFReader.rig(data: TestRig(bones: []).glb()), "no joints → not rigged")
    }

    func testReaderHandlesEmbeddedAndExternalBuffersAndErrors() throws {
        var rig = TestRig.humanoid(mixamo: false)
        rig.clips = [("Kick", TestRig.kickClip(for: rig))]
        let glb = rig.glb()
        // Split the GLB into .gltf + .bin, then into a data: URI.
        let file = try GLTFReader.parse(glb, baseURL: nil)
        let folder = try temporaryDirectory()
        var json = file.json
        json["buffers"] = [["byteLength": file.buffers[0].count, "uri": "rig.bin"]]
        try file.buffers[0].write(to: folder.appendingPathComponent("rig.bin"))
        let gltfURL = folder.appendingPathComponent("rig.gltf")
        try JSONSerialization.data(withJSONObject: json).write(to: gltfURL)
        XCTAssertEqual(try GLTFReader.rig(contentsOf: gltfURL)?.clipNames, ["Kick"])
        json["buffers"] = [["byteLength": file.buffers[0].count, "uri": "data:application/octet-stream;base64," + file.buffers[0].base64EncodedString()]]
        XCTAssertEqual(try GLTFReader.rig(data: JSONSerialization.data(withJSONObject: json))?.skeleton.joints.count, 17)
        json["buffers"] = [["byteLength": 4, "uri": "missing.bin"]]
        XCTAssertThrowsError(try GLTFReader.rig(data: JSONSerialization.data(withJSONObject: json), baseURL: folder))
        XCTAssertThrowsError(try GLTFReader.rig(data: JSONSerialization.data(withJSONObject: json)))
        XCTAssertThrowsError(try GLTFReader.rig(data: Data("hello".utf8))) { error in
            XCTAssertEqual(error as? GLTFReadError, .notGLTF)
        }
        XCTAssertFalse(GLTFReadError.malformed("x").description.isEmpty)
        XCTAssertFalse(GLTFReadError.missingBuffer("x").description.isEmpty)
        // Quaternius-style names map too (legs found by chain).
        let asset = try XCTUnwrap(GLTFReader.rig(data: glb))
        XCTAssertEqual(asset.boneMap["spine"], "Abdomen")
        XCTAssertEqual(asset.boneMap["leftUpperArm"], "UpperArm.L")
        XCTAssertEqual(asset.boneMap["leftLowerLeg"], "LowerLeg.L")
        XCTAssertEqual(asset.boneMap["rightFoot"], "Foot.R")
    }

    func testCubicSplineAndStepChannels() throws {
        var rig = TestRig(bones: [TestRig.Bone(name: "Root", parent: nil, translation: .zero),
                                  TestRig.Bone(name: "Tail", parent: 0, translation: Vec3(0, 0, -1))])
        // Cubic: (in-tangent, value, out-tangent) per key.
        rig.clips = [("Wag", [
            TestRig.Channel(bone: 1, path: "translation", times: [0, 1], values: [0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, 0, 1, 0, -1, 0, 0, 0],
                            interpolation: "CUBICSPLINE"),
            TestRig.Channel(bone: 0, path: "scale", times: [0, 1], values: [1, 1, 1, 2, 2, 2], interpolation: "STEP")
        ])]
        let asset = try XCTUnwrap(GLTFReader.rig(data: rig.glb()))
        let wag = try XCTUnwrap(asset.clips["Wag"])
        XCTAssertEqual(wag.pose(at: 1, skeleton: asset.skeleton)[1].position, Vec3(1, 0, -1))
        XCTAssertEqual(wag.pose(at: 0.5, skeleton: asset.skeleton)[0].scale, .one, "step holds")
        XCTAssertEqual(asset.standard, .custom, "a tail alone isn't an animal")
        let decomposed = GLTFReader.decompose([-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
        XCTAssertEqual(decomposed.scale.x, -1, "mirrored matrices keep their handedness")
        for axis in [Vec3.unitX, .unitY, .unitZ] {
            let q = Quat(angle: 2.5, axis: axis)
            let x = q.act(.unitX), y = q.act(.unitY), z = q.act(.unitZ)
            let m = GLTFReader.decompose([x.x, x.y, x.z, 0, y.x, y.y, y.z, 0, z.x, z.y, z.z, 0, 1, 2, 3, 1])
            XCTAssertTrue(m.rotation.isApproximately(q, tolerance: 1e-9), "\(axis)")
        }
    }

    func testRetargetingAHumanoidClipOntoADifferentHuman() throws {
        var source = TestRig.humanoid(mixamo: true)
        source.clips = [("Kick", TestRig.kickClip(for: source))]
        let mixamo = try XCTUnwrap(GLTFReader.rig(data: source.glb()))
        let tall = try XCTUnwrap(GLTFReader.rig(data: TestRig.humanoid(mixamo: false, scale: 2).glb()))
        let small = try XCTUnwrap(GLTFReader.rig(data: TestRig.humanoid(mixamo: true, scale: 0.6).glb()))
        let clip = try XCTUnwrap(mixamo.clips["Kick"])
        let sourcePose = clip.pose(at: 0.5, skeleton: mixamo.skeleton)
        let sourceFoot = mixamo.skeleton.modelSpace(sourcePose)[13].position
        XCTAssertGreaterThan(sourceFoot.z, 0.5 + 0.3, "the source kicks forward")
        for target in [tall, small] {
            let pose = Retargeter.retarget(pose: sourcePose, from: mixamo, to: target)
            let model = target.skeleton.modelSpace(pose)
            let foot = try XCTUnwrap(target.joint("leftFoot"))
            let hips = try XCTUnwrap(target.joint("hips"))
            let restFoot = target.skeleton.modelRest[foot].position
            let legLength = try restFoot.distance(to: target.skeleton.modelRest[XCTUnwrap(target.joint("leftUpperLeg"))].position)
            // The thigh swung 40° forward: the foot moves forward by leg length × sin 40° (+ hips travel).
            let hipsTravel = model[hips].position.z - target.skeleton.modelRest[hips].position.z
            XCTAssertEqual(model[foot].position.z - hipsTravel - restFoot.z, legLength * sin(40 * .pi / 180), accuracy: 1e-3)
            XCTAssertEqual(hipsTravel, 0.5 * target.skeleton.restHeight(of: hips) / mixamo.skeleton.restHeight(of: 0), accuracy: 1e-6,
                           "hips travel scales with hip height")
            // The other leg doesn't move.
            let rightFoot = try XCTUnwrap(target.joint("rightFoot"))
            XCTAssertEqual(model[rightFoot].position.z - hipsTravel, target.skeleton.modelRest[rightFoot].position.z, accuracy: 1e-6)
        }
    }

    func testWalkClipPlaysOnTwoDifferentQuadrupeds() throws {
        var tiger = TestRig.quadruped(names: ["Root", "Spine", "Neck", "Head", "FrontLeg_L", "FrontLeg_L_Lower", "FrontLeg_R",
                                              "FrontLeg_R_Lower", "BackLeg_L", "BackLeg_L_Lower", "BackLeg_R", "BackLeg_R_Lower", "Tail"],
                                      length: 1.2)
        tiger.clips = [("Walk", TestRig.walkClip())]
        let tigerRig = try XCTUnwrap(GLTFReader.rig(data: tiger.glb()))
        let horse = try XCTUnwrap(GLTFReader.rig(data: TestRig.quadruped(
            names: ["hips", "spine", "neck", "head", "front_leg.l", "front_shin.l", "front_leg.r", "front_shin.r",
                    "hind_leg.l", "hind_shin.l", "hind_leg.r", "hind_shin.r", "tail"], length: 1.8
        ).glb()))
        XCTAssertEqual(tigerRig.standard, .quadruped)
        XCTAssertEqual(horse.standard, .quadruped)
        XCTAssertEqual(horse.boneMap["backLeftUpper"], "hind_leg.l")
        XCTAssertEqual(horse.boneMap["frontRightLower"], "front_shin.r")
        XCTAssertEqual(tigerRig.boneMap["frontLeftUpper"], "FrontLeg_L")
        let walk = try XCTUnwrap(tigerRig.clips["Walk"])
        XCTAssertGreaterThan(try XCTUnwrap(tigerRig.strideSpeed(of: walk)), 0.1, "estimated from the feet")
        for time in [0.25, 0.75] {
            let pose = Retargeter.retarget(pose: walk.pose(at: time, skeleton: tigerRig.skeleton), from: tigerRig, to: horse)
            let model = horse.skeleton.modelSpace(pose)
            let rest = horse.skeleton.modelRest
            let frontLeft = try XCTUnwrap(horse.joint("frontLeftLower"))
            let frontRight = try XCTUnwrap(horse.joint("frontRightLower"))
            let dl = model[frontLeft].position.z - rest[frontLeft].position.z
            let dr = model[frontRight].position.z - rest[frontRight].position.z
            XCTAssertGreaterThan(abs(dl), 0.05, "the horse's legs swing")
            XCTAssertLessThan(dl * dr, 0, "in opposite phase, like the tiger's")
        }
    }

    func testClipTrackCrossfadesLoopsAndHolds() {
        let a = ClipSegment(id: "a", clip: ClipRef(asset: "x", name: "Idle"), start: 0, duration: 2, loop: true, blend: 0)
        let b = ClipSegment(id: "b", clip: ClipRef(asset: "x", name: "Walk"), start: 2, duration: 3, offset: 0.25, speed: 2, blend: 0.5)
        let track = ClipTrack(id: "t", target: "hero", segments: [b, a])
        XCTAssertEqual(track.segments.map(\.id), ["a", "b"])
        XCTAssertEqual(track.weights(at: -1).map(\.segment.id), ["a"])
        XCTAssertEqual(track.weights(at: 1).map(\.weight), [1])
        let blend = track.weights(at: 2.25)
        XCTAssertEqual(blend.map(\.segment.id), ["a", "b"])
        XCTAssertEqual(blend[1].weight, 0.5, accuracy: 1e-9)
        XCTAssertEqual(track.weights(at: 3).map(\.segment.id), ["b"])
        XCTAssertEqual(track.weights(at: 9).map(\.segment.id), ["b"], "holds the last clip")
        XCTAssertEqual(b.clipTime(at: 2.5, clipDuration: 1), 0.25, accuracy: 1e-9, "offset + 0.5 s × speed 2, looped")
        XCTAssertEqual(ClipSegment(id: "c", clip: b.clip, start: 0, duration: 5, loop: false).clipTime(at: 4, clipDuration: 1), 1)
        XCTAssertEqual(a.clipTime(at: 3, clipDuration: 0.8, extendPastEnd: true), 3.0.truncatingRemainder(dividingBy: 0.8), accuracy: 1e-9)
        XCTAssertEqual(ClipTrack(id: "e", target: "x").weights(at: 0).count, 0)
    }

    func testAnimatorPosesCharactersWithRetargetingAndIK() throws {
        var source = TestRig.humanoid(mixamo: true)
        source.clips = [("Kick", TestRig.kickClip(for: source))]
        let mixamo = try XCTUnwrap(GLTFReader.rig(data: source.glb()))
        let target = try XCTUnwrap(GLTFReader.rig(data: TestRig.humanoid(mixamo: false, scale: 1.2).glb()))
        var document = makeDocument()
        document.scene.objects["hero"] = SceneObject(id: "hero", name: "Hero", kind: .asset("hero-asset"))
        document.scene.roots.append("hero")
        document.scene.timeline.clipTracks = [ClipTrack(id: "ct", target: "hero", segments: [
            ClipSegment(id: "s", clip: ClipRef(asset: "kick-asset", name: "Kick"), start: 0, duration: 4)
        ], ik: IKSettings(lookAt: "c"))]
        let rigs: [AssetID: RigAsset] = ["hero-asset": target, "kick-asset": mixamo]
        let animated = Animator.evaluate(document, at: 0.5, rigs: rigs)
        let pose = try XCTUnwrap(animated.poses["hero"])
        XCTAssertEqual(pose.count, target.skeleton.joints.count)
        XCTAssertTrue(animated.animated.contains("hero"))
        XCTAssertNil(Animator.evaluate(document, at: 0.5).poses["hero"], "no rig data, no pose")
        // Look-at: the head turns toward "c" at (-2, 0, 1).
        let head = try XCTUnwrap(target.joint("head"))
        let model = target.skeleton.modelSpace(pose)
        let forward = (model[head].rotation * target.skeleton.modelRest[head].rotation.inverse).act(.unitZ)
        XCTAssertLessThan(forward.x, -0.3, "turned toward -X")
    }

    func testTwoBoneIKReachesAndFeetStayAboveGround() throws {
        let asset = try XCTUnwrap(GLTFReader.rig(data: TestRig.humanoid(mixamo: true).glb()))
        var pose = asset.skeleton.restPose
        let upper = try XCTUnwrap(asset.joint("leftUpperArm"))
        let lower = try XCTUnwrap(asset.joint("leftLowerArm"))
        let hand = try XCTUnwrap(asset.joint("leftHand"))
        let target = Vec3(0.4, 1.2, 0.3)
        IKSolver.twoBone(&pose, skeleton: asset.skeleton, upper: upper, lower: lower, end: hand, target: target)
        XCTAssertLessThan(asset.skeleton.modelSpace(pose)[hand].position.distance(to: target), 1e-6, "reachable target is reached")
        let far = Vec3(5, 5, 5)
        IKSolver.twoBone(&pose, skeleton: asset.skeleton, upper: upper, lower: lower, end: hand, target: far)
        let model = asset.skeleton.modelSpace(pose)
        let direction = (model[hand].position - model[upper].position).normalized
        XCTAssertTrue(direction.isApproximately((far - model[upper].position).normalized, tolerance: 1e-3), "out of reach: points at it")
        XCTAssertEqual(model[lower].position.distance(to: model[upper].position), 0.3, accuracy: 1e-6, "bones keep their length")

        // Feet on the ground: sink the character; the IK lifts the feet back to ground height.
        var sunk = asset.skeleton.restPose
        let world = Transform(position: Vec3(0, -0.2, 0))
        ClipMixer.applyIK(IKSettings(feetOnGround: true), to: &sunk, character: asset, world: world, targetPosition: { _ in nil })
        let foot = try XCTUnwrap(asset.joint("leftFoot"))
        XCTAssertEqual(world.apply(to: asset.skeleton.modelSpace(sunk)[foot].position).y, 0, accuracy: 1e-4)
        // Reach with the right hand toward an object.
        var reaching = asset.skeleton.restPose
        ClipMixer.applyIK(IKSettings(reach: "cup"), to: &reaching, character: asset, world: .identity, targetPosition: { _ in Vec3(-0.5, 1.3, 0.3) })
        let rightHand = try XCTUnwrap(asset.joint("rightHand"))
        XCTAssertLessThan(asset.skeleton.modelSpace(reaching)[rightHand].position.distance(to: Vec3(-0.5, 1.3, 0.3)), 1e-4)
        // Walk in place: the kick's hips travel is removed, the height kept.
        var kick = TestRig.humanoid(mixamo: true)
        kick.clips = [("Kick", TestRig.kickClip(for: kick))]
        let kicker = try XCTUnwrap(GLTFReader.rig(data: kick.glb()))
        var moving = try XCTUnwrap(kicker.clips["Kick"]).pose(at: 0.5, skeleton: kicker.skeleton)
        XCTAssertEqual(moving[0].position.z, 0.5, accuracy: 1e-5)
        ClipMixer.applyIK(IKSettings(inPlace: true), to: &moving, character: kicker, world: .identity, targetPosition: { _ in nil })
        XCTAssertEqual(moving[0].position.z, 0, accuracy: 1e-9)
        XCTAssertEqual(moving[0].position.y, 1, accuracy: 1e-9)
        XCTAssertEqual(try LoweyJSON.decode(IKSettings.self, from: Data("{}".utf8)), IKSettings())
        XCTAssertNil(SkeletonStandard.quadruped.arm(left: true))
        XCTAssertEqual(SkeletonStandard.custom.bones.count, 0)
        XCTAssertEqual(SkeletonStandard(rig: .bird), .bird)
        XCTAssertEqual(SkeletonStandard(rig: .none), .custom)
    }

    func testBirdMappingAndBoneNameNormalisation() {
        let names = ["Body", "Neck", "Head", "Wing.L", "WingTip.L", "Wing.R", "WingTip.R", "Leg.L", "Foot.L", "Leg.R", "Foot.R", "Tail"]
        let parents: [Int?] = [nil, 0, 1, 0, 3, 0, 5, 0, 7, 0, 9, 0]
        let skeleton = Skeleton(joints: zip(names, parents).map { Joint(name: $0, parent: $1, rest: .identity) })
        let map = BoneMapper.map(skeleton, to: .bird)
        XCTAssertEqual(map["leftWing"], "Wing.L")
        XCTAssertEqual(map["leftWingTip"], "WingTip.L")
        XCTAssertEqual(map["rightFoot"], "Foot.R")
        XCTAssertEqual(map["tail"], "Tail")
        XCTAssertEqual(BoneMapper.normalize("mixamorig:LeftArm"), "leftarm")
        XCTAssertEqual(BoneMapper.normalize("Armature/Hips"), "hips")
        XCTAssertEqual(BoneMapper.side("thigh_l"), -1)
        XCTAssertEqual(BoneMapper.side("r_hand"), 1)
        XCTAssertEqual(BoneMapper.side("spine"), 0)
        XCTAssertTrue(BoneMapper.map(skeleton, to: .custom).isEmpty)
        XCTAssertEqual(skeleton.children(of: 0).count, 6)
        XCTAssertEqual(PoseMath.blend([.identity], [Transform(position: .unitX)], 0.5)[0].position, Vec3(0.5, 0, 0))
        XCTAssertEqual(PoseMath.blend([.identity], [Transform(position: .unitX)], 0)[0].position, .zero)
    }
}
