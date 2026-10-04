import CoreGraphics
import HmmPerception
import LoweyCore
import Metal
import simd

/// What `observe` returns: the report and the pictures asked for (the camera view always).
public struct ShotObservation: @unchecked Sendable {
    // @unchecked: CGImage is immutable and thread-safe; it just isn't annotated Sendable.
    public var report: ShotReport
    public var images: [ObserveView: CGImage]
}

/// What `contact_sheet` returns: the numbers and the sheet.
public struct ContactSheetObservation: @unchecked Sendable {
    public var report: ContactSheetReport
    public var image: CGImage?
}

public extension ExportSession {
    /// Looks at the shot at `time`: renders it like the export, measures it (geometry from what was drawn, colour from
    /// the pixels) and draws the views asked for, each with the same set-of-marks numbers.
    func observe(at time: Double, framing: Framing = .landscape, longSide: Int = 1280, views: Set<ObserveView> = [.camera],
                 subject: String? = nil, library: LibraryManifest) async throws -> ShotObservation {
        await loadModels()
        let size = framing.pixelSize(longSide: longSide)
        let cgSize = CGSize(width: size.width, height: size.height)
        await prepareMedia(at: time, size: cgSize, framing: framing)
        let request = builder.request(at: time, framing: framing, size: cgSize, frameIndex: builder.timeline.frame(for: time))
        let bytes = try await frames.bytes(request, width: size.width, height: size.height)
        let renderer = frames.renderer
        let observer = ShotObserver(document: builder.document, library: library, rigs: builder.rigs()) { renderer.worldMesh(of: $0, staticOnly: true) }
        var pixels = ObservePixels(width: size.width, height: size.height, bytes: bytes, bgra: true)
        pixels.objects = objectBuffer(width: size.width, height: size.height)
        let report = observer.observe(at: time, aspect: framing.aspect, subject: subject, pixels: pixels)
        let image = try FrameRenderer.image(bgra: bytes, width: size.width, height: size.height, transparent: false)
        var images: [ObserveView: CGImage] = [:]
        images[.camera] = PerceptionDrawing.marked(image, marks: report.marks) ?? image
        if views.contains(.value) {
            let value = ValueImage(pixels: bytes, width: size.width, height: size.height, redIndex: 2, greenIndex: 1, blueIndex: 0)
            images[.value] = PerceptionDrawing.valueImage(value.blurred(radius: max(size.width / 320, 2)))
        }
        if views.contains(.silhouette), let subjectName = report.frame.subject, let subjectObject = report.object(named: subjectName) {
            images[.silhouette] = silhouette(of: ObjectID(raw: subjectObject.id))
        }
        for view in views where view.isDiagram {
            let diagram = observer.diagram(view, at: time, aspect: framing.aspect, report: report)
            images[view] = try await render(diagram, request: request, size: size)
        }
        return ShotObservation(report: report, images: images)
    }

    /// `frames` frames of `start…end` with their notes, and how things move between them.
    func contactSheet(from start: Double, to end: Double, frames count: Int = 6, framing: Framing = .landscape, subject: String? = nil,
                      library: LibraryManifest) async throws -> ContactSheetObservation {
        await loadModels()
        let observer = ShotObserver(document: builder.document, library: library, rigs: builder.rigs())
        let report = observer.contactSheet(from: start, to: end, frames: count, aspect: framing.aspect, subject: subject)
        var cells: [ContactSheetFrame] = []
        for frame in report.frames {
            let image = try await image(at: frame.time, framing: framing, longSide: 640)
            cells.append(ContactSheetFrame(image: image, timecode: frame.timecode, note: frame.note))
        }
        return ContactSheetObservation(report: report, image: PerceptionDrawing.contactSheet(cells))
    }
}

extension ExportSession {
    /// Which object the last frame drew at each pixel (the ID buffer, resampled to `width` × `height`).
    func objectBuffer(width: Int, height: Int) -> [String?]? {
        let renderer = frames.renderer
        guard let (ids, idWidth, idHeight) = renderer.idBuffer(), let scene = renderer.lastScene, idWidth > 0, idHeight > 0 else { return nil }
        var names: [UInt32: String?] = [:]
        var result = [String?](repeating: nil, count: width * height)
        for row in 0 ..< height {
            let sourceRow = min(row * idHeight / height, idHeight - 1)
            for column in 0 ..< width {
                let packed = PackedID.object(ids[sourceRow * idWidth + min(column * idWidth / width, idWidth - 1)])
                if let known = names[packed] {
                    result[row * width + column] = known
                } else {
                    let name = scene.objectID(forPacked: packed)?.raw
                    names[packed] = name
                    result[row * width + column] = name
                }
            }
        }
        return result
    }

    /// The subject black on white, from the ID buffer of the frame just drawn (exactly what was drawn).
    func silhouette(of subject: ObjectID) -> CGImage? {
        let renderer = frames.renderer
        guard let (ids, width, height) = renderer.idBuffer(), let scene = renderer.lastScene,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let data = context.data else { return nil }
        let document = builder.document.scene
        var isSubject: [UInt32: Bool] = [:]
        let rowBytes = context.bytesPerRow
        let bytes = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let packed = PackedID.object(ids[row * width + column])
                let inside: Bool
                if let known = isSubject[packed] {
                    inside = known
                } else {
                    let id = scene.objectID(forPacked: packed)
                    inside = id.map { $0 == subject || document.isAncestor(subject, of: $0) } ?? false
                    isSubject[packed] = inside
                }
                bytes[row * rowBytes + column] = inside ? 0 : 255
            }
        }
        return context.makeImage()
    }

    /// A layout diagram: the same moment from an orthographic camera, no overlays, the marks and the shot camera drawn on.
    func render(_ diagram: ObserveDiagram, request: FrameRequest, size: (width: Int, height: Int)) async throws -> CGImage? {
        var plan = request
        let height = diagram.camera.orthographicHeight ?? 10
        let fieldOfView = RenderCamera.orthographicFieldOfView
        // An extreme telephoto from far away reads as orthographic (D19), framed to the diagram's height near the set.
        let distance = height / 2 / tan(fieldOfView * .pi / 360)
        let position = diagram.camera.position + diagram.camera.forward * (10 - distance)
        plan.camera = RenderCamera(position: position.float3, orientation: diagram.camera.rotation.simd, fieldOfView: Float(fieldOfView), near: 1,
                                   far: Float(distance + 1000))
        plan.lens = nil
        plan.transition = nil
        plan.overlay = nil
        plan.flipbookLayers = [:]
        plan.screen = ScreenState()
        let bytes = try await frames.bytes(plan, width: size.width, height: size.height)
        let image = try FrameRenderer.image(bgra: bytes, width: size.width, height: size.height, transparent: false)
        let withCamera = diagram.shotCamera.flatMap { ObserveSketch.camera($0, on: image) } ?? image
        return PerceptionDrawing.marked(withCamera, marks: diagram.marks)
    }
}

/// Lines drawn on diagrams.
enum ObserveSketch {
    /// The shot camera: a wedge from its position along the edges of its view, and a dot where it stands.
    static func camera(_ glyph: CameraGlyph, on image: CGImage) -> CGImage? {
        let width = Double(image.width)
        let height = Double(image.height)
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let point = { (p: FramePoint) in CGPoint(x: p.x * width, y: height - p.y * height) }
        let eye = point(glyph.eye)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 0.27, blue: 0.2, alpha: 0.95))
        context.setFillColor(CGColor(srgbRed: 1, green: 0.27, blue: 0.2, alpha: 0.18))
        context.setLineWidth(max(height * 0.004, 2))
        context.move(to: eye)
        context.addLine(to: point(glyph.left))
        context.addLine(to: point(glyph.right))
        context.closePath()
        context.drawPath(using: .fillStroke)
        let radius = max(height * 0.012, 5)
        context.setFillColor(CGColor(srgbRed: 1, green: 0.27, blue: 0.2, alpha: 1))
        context.fillEllipse(in: CGRect(x: eye.x - radius, y: eye.y - radius, width: radius * 2, height: radius * 2))
        return context.makeImage()
    }
}
