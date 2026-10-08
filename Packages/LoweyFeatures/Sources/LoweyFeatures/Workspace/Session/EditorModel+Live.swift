import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine
import Observation
import QuartzCore

/// Live performance beyond the face (CONTEXT §10.6): the voice driving the mouth, hands dragged while a take records,
/// loose bones, a character's own breathing and blinking, and the parts that ride its bones.
@Observable
@MainActor
final class LiveState {
    var voiceOn = false
    /// The joint last touched on the stage: the one Rig ▸ Pose loosens.
    var joint: (character: ObjectID, name: String)?
    /// Triggers that are on while a take records.
    var held: Set<String> = []
    var selectedTake: String?
    /// What the microphone hears (0…1): its own observable, so the sound redraws only the meter.
    let meter = VoiceMeter()

    @ObservationIgnored var voice: VoiceCapture?
    /// What each held trigger returns to when it's let go.
    @ObservationIgnored var restores: [String: [PropertyChange]] = [:]
    /// The live values of the last second and a bit, newest last, for bones that follow through.
    @ObservationIgnored var moments: [(at: CFTimeInterval, overrides: [ObjectID: [PropertyKey: PropertyValue]])] = []
}

@Observable
@MainActor
final class VoiceMeter {
    var level = 0.0
}

extension EditorModel {
    // MARK: Voice

    /// The microphone drives the character's mouth: on or off.
    func toggleVoice() {
        if live.voiceOn {
            stopVoice()
            return
        }
        guard faceTarget != nil else {
            app.show("Select your character first")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            guard await VoiceCapture.requestPermission() else {
                app.show("Allow the microphone in Settings to perform with your voice", kind: .error)
                return
            }
            let capture = VoiceCapture()
            capture.onMouth = { [weak self] mouth in self?.performVoice(mouth) }
            do {
                try capture.start()
                live.voice = capture
                live.voiceOn = true
                startLiveClock()
                updateStageClock()
            } catch {
                app.show("The microphone didn't start: \(String(describing: error))", kind: .error)
            }
        }
    }

    func stopVoice() {
        live.voice?.stop()
        live.voice = nil
        guard live.voiceOn else { return }
        live.voiceOn = false
        live.meter.level = 0
        if let target = faceTarget {
            for key in [PropertyKey.mouth, .jawOpen, .mouthWide] where !faceActive || key == .mouth {
                propertyOverride[target]?[key] = nil
            }
        }
        if !faceActive { faceClock.stop() }
        refreshDisplay()
        updateStageClock()
    }

    private func performVoice(_ mouth: VoiceSolver.Mouth) {
        live.meter.level = mouth.level
        guard live.voiceOn, let target = faceTarget else { return }
        for (key, value) in VoiceSolver.channels(mouth) {
            performLive(value, key, on: target)
        }
        faceDirty = true
    }

    /// The clock that redraws the stage when a live value arrived and nothing else is drawing.
    func startLiveClock() {
        faceClock.onTick = { [weak self] _ in
            guard let self, faceDirty else { return }
            faceDirty = false
            if !isPlaying { refreshDisplay() }
        }
        faceClock.start()
    }

    /// One live value: shown at once, and part of the take while one records.
    func performLive(_ value: PropertyValue, _ key: PropertyKey, on object: ObjectID, stepped: Bool = false) {
        propertyOverride[object, default: [:]][key] = value
        guard performPhase == .recording else { return }
        let channel = PerformChannel(object: object, property: key)
        if takes[channel] == nil {
            var take = PerformTake(object: object, property: key, stepped: stepped)
            take.begin()
            takes[channel] = take
        }
        takes[channel]?.add(.init(time: time, value: value))
    }

    // MARK: The live past

    /// What was live over the last moments, for bones that follow through; nil when nothing is live.
    func livePast() -> LivePast? {
        let active = faceActive || live.voiceOn || performPhase == .recording
        guard active else {
            if !live.moments.isEmpty { live.moments = [] }
            return nil
        }
        let now = CACurrentMediaTime()
        live.moments.append((now, propertyOverride))
        live.moments.removeAll { now - $0.at > Dangle.longestWindow + 0.2 }
        return LivePast(moments: live.moments.map { LivePast.Moment(ago: now - $0.at, overrides: $0.overrides) }, playing: isPlaying)
    }

    // MARK: Draggers

    /// A joint dragged while a take records: it follows the finger live and the take keeps it.
    func performIK(_ changes: [PropertyChange]) {
        for change in changes {
            guard let value = change.value else { continue }
            let channel = PerformChannel(object: change.object, property: change.key)
            if takes[channel] == nil || !performTouching { takes[channel, default: PerformTake(object: change.object, property: change.key)].begin() }
            performChannels.insert(channel)
            propertyOverride[change.object, default: [:]][change.key] = value
        }
        performTouching = true
        recordPerformSample()
        refreshDisplay()
    }

    /// The joint a handle ends at becomes the one Rig ▸ Pose talks about.
    func chooseJoint(of handle: IKHandle) {
        guard case let .chain(joints) = handle.kind, let last = joints.last,
              let rig = CharacterRig.of(handle.character, in: displayed.scene, rigs: libraryRigs()), rig.skeleton.joints.indices.contains(last) else {
            live.joint = nil
            return
        }
        live.joint = (handle.character, rig.skeleton.joints[last].name)
    }

    // MARK: Dangle

    /// How loosely the chosen joint dangles (0 = it doesn't).
    func dangle(of joint: String, on character: ObjectID) -> Double {
        baseScene.objects[character]?[.dangle(joint)]?.floatValue ?? 0
    }

    /// Loosens a joint and everything below it (a tail dangles as a whole).
    func setDangle(_ amount: Double, joint: String, on character: ObjectID) {
        guard let rig = CharacterRig.of(character, in: baseScene, rigs: libraryRigs()), let index = rig.skeleton.index(of: joint) else { return }
        var joints = [index]
        var next = 0
        while next < joints.count {
            joints += rig.skeleton.children(of: joints[next])
            next += 1
        }
        let value: PropertyValue? = amount > 0.005 ? .float(min(amount, 1)) : nil
        let changes = joints.map { PropertyChange(object: character, key: .dangle(rig.skeleton.joints[$0].name), value: value) }
        perform(.batch("Dangle", [.setProperties(changes)]), coalesceKey: "dangle-\(character.raw)-\(joint)")
    }

    // MARK: Life

    func breathing(of character: ObjectID) -> Double {
        baseScene.objects[character]?[.breathe]?.floatValue ?? 0
    }

    func setBreathing(_ depth: Double, on character: ObjectID) {
        perform(.batch("Breathe", [.setProperties([PropertyChange(object: character, key: .breathe, value: depth > 0.005 ? .float(depth) : nil)])]),
                coalesceKey: "breathe-\(character.raw)")
    }

    /// A Blob blinks unless told not to; anything else blinks once it's asked.
    func blinksOnItsOwn(_ character: ObjectID) -> Bool {
        baseScene.objects[character]?[.autoBlink]?.boolValue ?? isBlob(character)
    }

    func setBlinksOnItsOwn(_ on: Bool, for character: ObjectID) {
        perform(.batch("Blink", [.setProperties([PropertyChange(object: character, key: .autoBlink, value: .bool(on))])]))
    }

    /// The joints of a character whose skeleton isn't a person's: any of them can be its head.
    func headChoices(of character: ObjectID) -> [String] {
        guard let object = baseScene.objects[character], let rig = CharacterRig.of(character, in: baseScene, rigs: libraryRigs()),
              rig.body == .bones, rig.standard != .humanoid, object.rig != nil || object.kind.assetID != nil else { return [] }
        return rig.skeleton.names
    }

    func setHead(_ joint: String?, on character: ObjectID) {
        perform(.batch("Head", [.setProperties([PropertyChange(object: character, key: .liveHead, value: joint.map(PropertyValue.string))])]))
    }

    // MARK: Parts

    /// Drawn rigs a loose object could become a part of.
    func partHosts(for object: SceneObject) -> [SceneObject] {
        guard castType(of: object.id) == nil, object.rig == nil, object[.attachBone] == nil else { return [] }
        return baseScene.orderedIDs().compactMap { baseScene.objects[$0] }.filter { host in
            host.rig != nil && host.id != object.id && !baseScene.isAncestor(object.id, of: host.id)
        }
    }

    /// Makes an object a part of a rigged character: it goes inside it, stays where it is, and rides the nearest bone.
    func attachPart(_ id: ObjectID, to character: ObjectID) {
        guard let host = baseScene.objects[character], let rig = host.rig, baseScene.objects[id] != nil else { return }
        let local = CoreTransform.relative(world: baseScene.worldTransform(of: id), toParent: baseScene.worldTransform(of: character))
        let inRig = RigSpace.frame(of: character, in: baseScene).inverseApply(to: baseScene.worldTransform(of: id).position)
        guard let joint = LiveRig.nearestJoint(to: inRig, of: rig) else { return }
        perform(.batch("Make a part", [
            .reparent([ReparentEntry(object: id, parent: character, transform: local)]),
            .setProperties([PropertyChange(object: id, key: .attachBone, value: .string(joint))])
        ]))
        app.show("It's part of \(host.name) now and moves with its bones")
    }

    func detachPart(_ id: ObjectID) {
        guard baseScene.objects[id] != nil else { return }
        let world = baseScene.worldTransform(of: id)
        perform(.batch("Take the part off", [
            .setProperties([PropertyChange(object: id, key: .attachBone, value: nil), PropertyChange(object: id, key: .faceRole, value: nil)]),
            .reparent([ReparentEntry(object: id, parent: nil, transform: world)])
        ]))
    }

    func setPartBone(_ joint: String, of id: ObjectID) {
        perform(.batch("Bone", [.setProperties([PropertyChange(object: id, key: .attachBone, value: .string(joint))])]))
    }

    func setPartRole(_ role: PartRole?, of id: ObjectID) {
        perform(.batch("Part", [.setProperties([PropertyChange(object: id, key: .faceRole, value: role.map { .string($0.rawValue) })])]))
    }
}

/// What a part of a face does when the face is performed (`FaceRig`'s roles).
enum PartRole: String, CaseIterable, Identifiable {
    case eyeLeft = "eye.L", eyeRight = "eye.R", pupilLeft = "pupil.L", pupilRight = "pupil.R", browLeft = "brow.L", browRight = "brow.R"
    case mouth, jaw
    case mouthRest = "mouth.X", mouthA = "mouth.A", mouthB = "mouth.B", mouthC = "mouth.C", mouthD = "mouth.D", mouthE = "mouth.E"
    case mouthF = "mouth.F", mouthG = "mouth.G", mouthH = "mouth.H"

    var id: String { rawValue }

    /// The mouth shapes a set of drawn mouths takes turns through.
    static let shapes: [PartRole] = [.mouthRest, .mouthA, .mouthB, .mouthC, .mouthD, .mouthE, .mouthF, .mouthG, .mouthH]
    static let features: [PartRole] = [.eyeLeft, .eyeRight, .pupilLeft, .pupilRight, .browLeft, .browRight, .mouth, .jaw]

    var title: String {
        switch self {
        case .eyeLeft: "Left eye"
        case .eyeRight: "Right eye"
        case .pupilLeft: "Left pupil"
        case .pupilRight: "Right pupil"
        case .browLeft: "Left brow"
        case .browRight: "Right brow"
        case .mouth: "Mouth"
        case .jaw: "Jaw"
        case .mouthRest: "Mouth at rest"
        case .mouthA: "Closed (M, B, P)"
        case .mouthB: "Teeth (EE, S)"
        case .mouthC: "Open (EH)"
        case .mouthD: "Wide open (AH)"
        case .mouthE: "Round (OH)"
        case .mouthF: "Puckered (OO)"
        case .mouthG: "Lip bite (F, V)"
        case .mouthH: "Tongue up (L)"
        }
    }
}
