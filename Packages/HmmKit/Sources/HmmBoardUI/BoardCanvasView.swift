#if canImport(UIKit) && canImport(Metal) && !os(watchOS) && !os(tvOS)
    import HmmBoard
    import HmmBrush
    import HmmDesign
    import Metal
    import Observation
    import QuartzCore
    import UIKit

    /// The board on screen: a Metal layer that draws only when something changed, the making touch (the Pencil, or
    /// a finger when fingers make), and the fingers that move the view. Pencil or hand is automatic (`HmmPencilOrHand`).
    @MainActor
    public final class BoardCanvasView: UIView, UIGestureRecognizerDelegate {
        let model: BoardModel
        /// The Pencil's point while it hovers (the app's hover setting).
        var showsHover = true {
            didSet { setNeedsFrame() }
        }

        private var displayLink: CADisplayLink?
        private var needsFrame = true
        private var makingTouch: UITouch?
        private let pan = UIPanGestureRecognizer()
        private let pinch = UIPinchGestureRecognizer()
        private let doubleTap = UITapGestureRecognizer()
        private let hoverRecognizer = UIHoverGestureRecognizer()
        private var holdMenu: HmmHoldMenuInteraction?
        private var glide: Glide?

        /// The view easing from one place to another (double-tap to frame).
        private struct Glide {
            var from: BoardViewport
            var to: BoardViewport
            var start: CFTimeInterval
            static let duration = 0.3
        }

        override public static var layerClass: AnyClass { CAMetalLayer.self }

        public init(model: BoardModel) {
            self.model = model
            super.init(frame: .zero)
            isMultipleTouchEnabled = true
            isOpaque = true
            accessibilityIdentifier = "board-canvas"
            isAccessibilityElement = true
            accessibilityLabel = NSLocalizedString("Board", comment: "")
            accessibilityTraits = .allowsDirectInteraction
            if let metal = layer as? CAMetalLayer {
                metal.device = model.renderer?.device
                metal.pixelFormat = BoardRenderer.format
                metal.framebufferOnly = true
                metal.isOpaque = true
            }
            installGestures()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("BoardCanvasView is made in code")
        }

        // MARK: Drawing on demand

        override public func didMoveToWindow() {
            super.didMoveToWindow()
            displayLink?.invalidate()
            displayLink = nil
            guard window != nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
            setNeedsFrame()
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            let scale = traitCollection.displayScale
            contentScaleFactor = scale
            (layer as? CAMetalLayer)?.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            model.sized(viewSize)
            setNeedsFrame()
        }

        func setNeedsFrame() {
            needsFrame = true
            displayLink?.isPaused = false
        }

        private var viewSize: Vec2 { Vec2(bounds.width, bounds.height) }

        @objc private func tick(_ link: CADisplayLink) {
            if let glide {
                let t = min((link.timestamp - glide.start) / Glide.duration, 1)
                // Ease out: fast away, soft landing.
                let eased = 1 - pow(1 - t, 3)
                let center = glide.from.center + (glide.to.center - glide.from.center) * eased
                let scale = glide.from.scale * pow(glide.to.scale / glide.from.scale, eased)
                model.mutate { $0.viewport = BoardViewport(center: center, scale: scale) }
                if t >= 1 {
                    self.glide = nil
                    model.interacting = false
                }
                needsFrame = true
            }
            guard needsFrame else {
                // Nothing moved: the screen keeps the last frame and the link rests until something does.
                link.isPaused = true
                return
            }
            needsFrame = false
            drawFrame()
        }

        private func drawFrame() {
            guard bounds.width > 0, bounds.height > 0, let renderer = model.renderer, let metal = layer as? CAMetalLayer,
                  let drawable = metal.nextDrawable(), let commandBuffer = renderer.queue.makeCommandBuffer() else { return }
            let size = viewSize
            let scale = Double(contentScaleFactor)
            let hover = showsHover
            // Whatever the frame read from the model, a change to it asks for the next frame.
            let scene = withObservationTracking {
                model.scene(size: size, contentScale: scale, showsHover: hover)
            } onChange: { [weak self] in
                Task { @MainActor in self?.setNeedsFrame() }
            }
            renderer.draw(scene, to: drawable.texture, commandBuffer: commandBuffer)
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        // MARK: The making touch

        /// A touch's place on the board, with what the Pencil says about it.
        private func sample(_ touch: UITouch, precise: Bool = true) -> BrushInput<Vec2> {
            let location = precise ? touch.preciseLocation(in: self) : touch.location(in: self)
            let point = model.session.viewport.toBoard(Vec2(location.x, location.y), size: viewSize)
            if touch.type == .pencil {
                let pressure = touch.maximumPossibleForce > 0 ? Double(touch.force / touch.maximumPossibleForce) : 0.6
                return BrushInput(point: point, pressure: pressure, altitude: Double(touch.altitudeAngle), time: touch.timestamp)
            }
            return BrushInput(point: point, pressure: 0.6, altitude: nil, time: touch.timestamp)
        }

        /// How far off a tap may land, in board units: a finger is blunter than a Pencil.
        private func slack(_ touch: UITouch) -> Double {
            (touch.type == .pencil ? 6 : 14) / model.session.viewport.scale
        }

        /// Whether a touch makes: the Pencil always; a finger while fingers make, or when it lands on something with
        /// the Select tool (so a thing can always be dragged with the hand).
        private func makes(_ touch: UITouch) -> Bool {
            guard model.isLoaded, glide == nil else { return false }
            if touch.type == .pencil { return true }
            guard touch.type == .direct || touch.type == .indirectPointer else { return false }
            if model.pencilOrHand.fingerMakes { return true }
            return fingerGrabs(at: touch.location(in: self), slack: slack(touch))
        }

        private func fingerGrabs(at location: CGPoint, slack: Double) -> Bool {
            let session = model.session
            guard session.tool == .select else { return false }
            let point = session.viewport.toBoard(Vec2(location.x, location.y), size: viewSize)
            if session.handle(at: point, slack: slack) != nil { return true }
            if let bounds = session.selectionBounds, bounds.contains(point) { return true }
            return session.board.item(at: point, tolerance: slack) != nil
        }

        override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard makingTouch == nil, let touch = touches.first(where: makes) else {
                super.touchesBegan(touches, with: event)
                return
            }
            if touch.type == .pencil {
                model.pencilTouched()
                applyPencilOrHand()
            }
            makingTouch = touch
            let first = sample(touch), reach = slack(touch)
            model.hover = nil
            model.predicted = []
            model.mutate { $0.begin(first, slack: reach) }
            if model.session.tool == .erase { model.eraserAt = first.point }
        }

        override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = makingTouch, touches.contains(touch) else {
                super.touchesMoved(touches, with: event)
                return
            }
            let samples = (event?.coalescedTouches(for: touch) ?? [touch]).map { sample($0) }
            model.predicted = (event?.predictedTouches(for: touch) ?? []).map { sample($0) }
            model.mutate { session in
                for sample in samples {
                    session.move(sample)
                }
            }
            if model.session.tool == .erase { model.eraserAt = samples.last?.point }
        }

        override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = makingTouch, touches.contains(touch) else {
                super.touchesEnded(touches, with: event)
                return
            }
            let last = sample(touch), reach = slack(touch)
            makingTouch = nil
            model.predicted = []
            model.eraserAt = nil
            let before = model.session.revision
            model.mutate { $0.end(last, slack: reach) }
            // Placing a note, an arrow or a frame, or dropping what was dragged, is felt; a stroke isn't.
            let tool = model.session.tool
            if model.session.revision != before, tool != .draw, tool != .erase { HmmHaptics.play(.commit) }
        }

        override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = makingTouch, touches.contains(touch) else {
                super.touchesCancelled(touches, with: event)
                return
            }
            makingTouch = nil
            model.predicted = []
            model.eraserAt = nil
            model.mutate { $0.cancel() }
        }
    }

    extension BoardCanvasView {
        // MARK: Moving the view

        fileprivate func installGestures() {
            pan.addTarget(self, action: #selector(panned))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            pan.allowedScrollTypesMask = .all
            pan.maximumNumberOfTouches = 2
            pan.delegate = self
            addGestureRecognizer(pan)
            pinch.addTarget(self, action: #selector(pinched))
            pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            pinch.delegate = self
            addGestureRecognizer(pinch)
            doubleTap.addTarget(self, action: #selector(doubleTapped))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            doubleTap.delegate = self
            addGestureRecognizer(doubleTap)
            hoverRecognizer.addTarget(self, action: #selector(hovered))
            addGestureRecognizer(hoverRecognizer)
            let menu = HmmHoldMenuInteraction { [weak self] location in self?.menu(at: location) }
            menu.install(on: self)
            holdMenu = menu
            addInteraction(UIDropInteraction(delegate: self))
            applyPencilOrHand()
        }

        /// One finger draws until a Pencil has touched; from then on one finger moves the view.
        func applyPencilOrHand() {
            pan.minimumNumberOfTouches = model.pencilOrHand.fingerMakes ? 2 : 1
        }

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                let moved = recognizer.translation(in: self)
                recognizer.setTranslation(.zero, in: self)
                glide = nil
                model.interacting = true
                model.mutate { $0.viewport = $0.viewport.panned(byScreen: Vec2(moved.x, moved.y)) }
            default:
                model.interacting = pinch.state == .began || pinch.state == .changed
            }
        }

        @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                let factor = Double(recognizer.scale), middle = recognizer.location(in: self), size = viewSize
                recognizer.scale = 1
                glide = nil
                model.interacting = true
                model.mutate { $0.viewport = $0.viewport.zoomed(by: factor, around: Vec2(middle.x, middle.y), size: size) }
            default:
                model.interacting = pan.state == .began || pan.state == .changed
            }
        }

        /// Double-tap: the frame under the finger (or everything) glides to fill the view.
        @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            let location = recognizer.location(in: self), size = viewSize
            var target = model.session
            target.frame(at: target.viewport.toBoard(Vec2(location.x, location.y), size: size), size: size)
            ease(to: target.viewport)
        }

        /// Eases the view to another place.
        func ease(to viewport: BoardViewport) {
            guard viewport != model.session.viewport else { return }
            glide = Glide(from: model.session.viewport, to: viewport, start: CACurrentMediaTime())
            model.interacting = true
            setNeedsFrame()
        }

        @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                let location = recognizer.location(in: self)
                let point = model.session.viewport.toBoard(Vec2(location.x, location.y), size: viewSize)
                // A hovering Pencil is a Pencil: fingers stop drawing as soon as one is near.
                if recognizer.zOffset > 0 {
                    model.pencilTouched()
                    applyPencilOrHand()
                }
                if model.session.tool == .erase { model.eraserAt = point } else { model.hover = point }
            default:
                model.hover = nil
                if makingTouch == nil { model.eraserAt = nil }
            }
        }

        private func menu(at location: CGPoint) -> HmmHoldMenu? {
            let session = model.session
            let point = session.viewport.toBoard(Vec2(location.x, location.y), size: viewSize)
            return model.holdMenu(at: point, slack: 14 / session.viewport.scale)
        }

        // MARK: Which recognizer gets a touch

        public func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if recognizer === doubleTap {
                // Where one finger draws, two quick taps are two dots, not a zoom (except with the Select tool).
                return !model.pencilOrHand.fingerMakes || model.session.tool == .select
            }
            if recognizer === pan, !model.pencilOrHand.fingerMakes {
                // A finger on a thing (Select tool) drags the thing, not the view.
                return !fingerGrabs(at: touch.location(in: self), slack: slack(touch))
            }
            return true
        }

        public func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (recognizer === pan && other === pinch) || (recognizer === pinch && other === pan)
        }
    }

    extension BoardCanvasView: UIDropInteractionDelegate {
        public func dropInteraction(_: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
            model.store != nil && session.canLoadObjects(ofClass: UIImage.self)
        }

        public func dropInteraction(_: UIDropInteraction, sessionDidUpdate _: any UIDropSession) -> UIDropProposal {
            UIDropProposal(operation: .copy)
        }

        public func dropInteraction(_: UIDropInteraction, performDrop session: any UIDropSession) {
            let location = session.location(in: self)
            let point = model.session.viewport.toBoard(Vec2(location.x, location.y), size: Vec2(bounds.width, bounds.height))
            let model = model
            session.loadObjects(ofClass: UIImage.self) { objects in
                // Several pictures land side by side, a little apart.
                let pictures = objects.compactMap { ($0 as? UIImage)?.pngData() }
                Task { @MainActor in
                    for (index, data) in pictures.enumerated() {
                        model.addPicture(data, at: point + Vec2(Double(index) * 40, Double(index) * 40))
                    }
                }
            }
        }
    }
#endif
