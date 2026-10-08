# Changelog

All notable changes. 1.x grew in four phases (v0.1 → v1.4); 2.0 is the remaster, released as betas first. Maquette
continues from 2.0 and numbers its phases again from 0.1 (each phase bumps the minor version until 1.0).

## [0.10] — Maquette — live performance (phase M10)

- **Your face drives any character.** Front camera or iPhone: drawn rigs, person rigs, 2D drawn puppets and rigged
  models turn their head with yours now, not only Blobs and Puppets. A skeleton that isn't a person's can name the
  bone that is its head (Cast ▸ Life).
- **Your hands move its hands**: on every humanoid, by IK.
- **Your voice shapes its mouth**, live (Cast ▸ Mouth from the microphone). Nothing is recorded or sent.
- **Parts**: make a loose object part of a drawn rig and it rides the nearest bone; give it a face role and it
  blinks, looks and talks with the face. A drawn puppet gets its face this way; a prop sits in a hand.
- **Life**: characters breathe (a slider) and blink on their own.
- **Triggers**: one tap or the keys 1…0 for an expression, a saved pose or a swap of what it holds. While a take
  records they're performed, held or switched; the deck sits under the stage in Perform.
- **Draggers**: while a take records, drag a hand and it follows; the take keeps it.
- **Dangle** (Cast ▸ Rig ▸ Pose): touch a joint, slide Dangle. Hair, ears and tails trail and swing, and settle as
  drawn. The same on the stage and in every export.
- **Takes**: every recording is kept. They're listed above the lanes in Perform; drag across one to use it from there
  to there.
- The iPhone companion also sends eyes-wide and the brows' angle. Project files are schema 11.

## [0.9] — Maquette — the Schizzo board (phase M9)

- **A board in every project** (Actions ▸ Board): an endless 2D sheet for planning before you build. Sketch on it with
  the whole brush engine (every brush, pressure, tilt), drop pictures on it, write notes, draw arrows between them,
  and put frames around what belongs together.
- **Pin anything to the project.** Pick a frame, a note or a sketch and pin it: it floats over the stage as a
  reference card you can move and size. From the card's menu, **Stand it in the scene** makes it a plane in the 3D
  scene, an object like any other.
- The board works like the stage: Select top left; Draw, Erase, Note, Arrow, Frame top right; size, opacity, the
  colour and undo on the sidebar; touch and hold a thing for the same menu as everywhere. Two fingers move the view
  (one, once a Pencil has touched), pinch zooms, double-tap fills the view with a frame.
- The eraser cuts strokes where it touches. Arrows follow the notes and pictures they point at. Moving a frame moves
  what's in it.
- Nothing on the board is ever lost: every stroke is written as it's drawn, and undo is still there after closing the
  app.
- **Sketch** is a starter template in New project: it opens on the board.
- The paper is dark or light, with dots, a grid or nothing. Share a picture of a frame, a pick or the whole board.
- Don't want it? Settings ▸ Board switches it off (nothing is deleted).
- Under the hood the brush engine moved into hmm-kit, so Cutaway will draw with the same brushes on the same board.

## [0.8] — Maquette — fixes and touch (phase M8)

- **Nothing is said on the stage under load.** The "close to what this iPad keeps smooth" chip and its setting are
  gone; the preview lightens by itself and comes back when there's room. The numbers are in Diagnostics ▸ Smoothness.
- **One hold menu everywhere.** Touch and hold an object on the stage (a still finger; a moving one drags), a key, a
  clip, a flipbook drawing, a layer, a brush, a Look, a card: Duplicate · Rename · Copy · Paste, then what fits the
  thing, then Delete. Clips gained **Split at the playhead**. Adding to the selection is the menu's *Add to the
  selection*.
- **Pencil or hand, automatic.** With no Apple Pencil, a finger draws, paints and rigs; once a Pencil has touched,
  it makes and fingers move the view. One switch in Settings ▸ Pencil or hand.
- **Move it.** Six looping motions at the top of the inspector: Spin, Float, Bounce, Wiggle, Swing, Follow a path. One
  tap and it moves, one Speed slider, **Make keyframes** when you want keys. Bounce and Swing are new.
- **A colour well on the sidebar** while you draw or paint.
- **Rigging in three steps**: Bones → Skin → Pose, each with only its own tools. A drawn bone runs through the middle
  of the part it's drawn on (also where an arm lies in front of the body, or a tail goes into it), bends where the
  stroke bends, shows as you draw it, and replaces a bone you draw again.
- Fixed: an object that already had drawn bones refused more of them, and its Rig tools were replaced by a sentence.
- The sphere is findable: Model's second page is called **Edit**, and the sphere's tile looks like a ball.
- Panels opened from the corners sit above the sidebar.
- The inspector can be docked at the side (Settings ▸ Stage).
- Projects are schema 10 (two new motion kinds); 0.7 projects open unchanged.

## [0.7] — Maquette — rigging (phase M7)

- **Cast ▸ Rig ▸ Draw a bone**: draw through a limb, a tail or a rope with the Pencil and it bends there. Works on
  shapes, modelled parts, drawings and placed models; more strokes add more bones.
- The weights are worked out for you (bone heat): smooth bends at every joint, and parts that only touch don't drag
  each other. Prefer to paint them? **Paint weights** shows a bone's weight in colour and paints it with the brush.
- **Rig as a person**: tap eight dots on the model's front (the other side is mirrored), drag any of them, Rig. Every
  built-in clip (Idle, Walk, Run, Talk, Wave, Point, Type, Nod, Shrug, Celebrate) plays on it.
- **2D drawn puppets**: draw bones on a drawing's plane and its strokes bend with them.
- **Pose by dragging**: select any character (Blob, Puppet, Rigged or one you rigged) and drag its joints; the limb or
  chain follows. Keys land at the playhead in Keyframe mode; Reset the pose puts it back. The pose library works on every
  kind of character.
- **One skeleton system** underneath: Blobs, Puppets, imported Rigged models and drawn rigs pose, key and play clips the
  same way.
- Rigged objects can be painted (they stand as they were made while you paint them).
- **Exports carry the pose**: glTF and the Blender package as you posed it, USDZ, OBJ, STL and 3MF as posed at the
  playhead, so a posed character can be printed.

## [0.6] — Maquette — painting on models (phase M6)

- **Paint ▸ Colour**: paint colour straight onto shapes, modelled parts, solid drawings and placed models with any brush
  in the library, in the current colour, at the sidebar's size and opacity. Paint, erase, fill a layer, take a colour
  with the eyedropper. Fingers move around; the Pencil paints.
- A stroke lands exactly where the camera sees the model, in the frame that shows it: never behind something, never
  round the back.
- **Layers** on every painted object: show and hide, opacity, blend modes (Normal, Multiply, Screen, Overlay, Add),
  add, duplicate, merge down, move, clear, rename, delete.
- **Project a picture** from Photos or Files onto a model: place it over the stage, then Project.
- Models are laid flat for painting by xatlas the first time; placed models keep their own colours as a first layer.
- Every stroke, fill and layer change is one undo step and survives closing the app; modelling a painted object
  carries its paint onto the new shape.
- **Exports** carry the paint: glTF and the Blender package, USDZ (Quick Look) and OBJ with its texture.
- Diagnostics: the painting benchmark (a scripted Pencil paints a 50k-triangle model for 20 seconds).
- Settings ▸ Licences credits xatlas and Manifold.
- **Smoothness warnings are off by default.** The chip that says a scene is close to what the iPad keeps smooth only
  shows when Settings ▸ Stage ▸ Smoothness warnings is on. The stage still adapts its resolution to stay smooth.

## [0.5] — Maquette — brushes & drawing guides (phase M5)

- **One brush engine** for ink and flipbooks: a tip and a grain stamped along the stroke, with StreamLine, spacing,
  jitter, fall-off, tapers, pressure, tilt and speed, flow and wet edges. The stroke under the Pencil is drawn by the
  same engine as the one that's kept, with the Pencil's predicted path drawn ahead.
- **Ten brushes** in three sets (Inking, Sketching, Painting). Draw ▸ Ink and Draw ▸ Flipbook each hold a brush: tap it
  for the **brush library**.
- **Brush Studio**: every setting on seven pages, your own picture as a tip or a grain, a pad to try the brush on.
  Duplicate, reset, rename, move between sets, delete; make, rename and delete sets.
- **Import Procreate brushes** (`.brushset`, `.brush`) and **Photoshop brushes** (`.abr`) from the library or with
  Open in from Files and AirDrop. **Share a set** as a `.maquettebrushes` file.
- Strokes keep the brush they were drawn with: editing a brush never redraws finished work, and a project carries its
  brushes to another iPad.
- **Drawing guides**: for flipbooks a 2D grid, isometric, 1-, 2- and 3-point perspective and symmetry (vertical,
  horizontal, quadrant, radial); for ink a grid, isometric or symmetry on the guide plane. Drawing Assist straightens
  strokes along the guide; symmetry mirrors them as you draw.
- **Diagnostics ▸ Apple Pencil**: how long the Pencil takes to show on screen (median and 95th percentile).
- Projects are schema 7 (brushes); Maquette 0.4 asks for a newer version instead of opening them.

## [0.4] — Maquette — modelling II & interop (phase M4)

- **Bevel, round, inset, shell** from the Model tool's bar: pick edges and bevel or round them, pick faces and inset
  them or hollow the solid leaving them open. Each runs at once at a size that suits the units; tap the size that
  floats beside it to type an exact one.
- **Mirror** across the picked face or the middle, and **live symmetry** (left and right, front and back, top and
  bottom): change one side and the other follows (Model ▸ Shape).
- **Array along a sketch** from the inspector's Array, optionally turning with the curve.
- **Model ▸ Precision** (was Snapping): snap to corners, edge middles, edges and faces as well as the grid (grid sizes
  follow the units); the stage marks what a point snapped to.
- **Measure** between two points, with how far apart along x, y and z; **keep** it on the stage as a dimension that
  moves with what it measures.
- **Section view**: cut the stage open across x, y or z, or along a face; slide the cut, keep the other side. Exports
  are never cut.
- **3D printing** (Model ▸ Shape ▸ 3D print): the printer's build volume on the stage, **Check for printing** (holes,
  inside-out faces, walls too thin for the printer, fitting the bed) and **Repair**.
- **Building** (Model ▸ Add): walls along tapped corners (height and thickness typed beside them), floors, doors and
  windows cut into walls, stairs.
- **Export a 3D model** as **glTF** (the scene with its hierarchy, materials, cameras, lights and animation), **USDZ**,
  **OBJ**, **STL** or **3MF** (millimetres, standing on the bed), or a **Blender package** that builds a
  ready-to-render .blend with the Look, lights and cameras.
- **Import STL and 3MF**; **Make editable** takes a placed model apart, keeping a glTF's hierarchy and animation.
- Booleans are exact to the nanometre where shapes cross, and keep their faces whole.
- Projects are schema 6 (kept dimensions, symmetry); Maquette 0.3 asks for a newer version instead of opening them.

## [0.3] — Maquette — modelling I (phase M3)

- **Model ▸ Shape**: sketch, push/pull and booleans, Shapr3D's core loop. Choose a shape or a mode and the stage is
  yours, with the Model tool's bar at the bottom.
- **Sketch on any surface**: line, rectangle, circle, arc, spline and offset, by tapping, on the face you tap or the
  ground. Closed shapes fill; a shape inside another makes a hole.
- **Pull a region into a solid or cut it into the face below**, by dragging or by typing the distance.
- **Pick faces, edges and corners**: tap, touch and hold to add, a Pencil loop for many; grow, shrink, select similar.
- **Push/pull faces** with the distance floating beside them, snapping to other corners and to the unit. Tap any
  number on the stage and type an exact length: `25`, `25mm`, `2*12`, `1ft 6in`.
- **Union, subtract, intersect** two or more shapes; results are clean solids (flat faces merged, no seams), ready to
  keep modelling. Any shape becomes an editable mesh on the way.
- **Units**: millimetres, centimetres, metres, inches, feet (Model ▸ Snapping). Model to print starts in millimetres,
  Room or building in metres.
- The inspector shows the selection's size, and what's picked.
- The camera comes in to 3 cm, so double-tap frames a small printed part.
- Projects are schema 5 (meshes and sketches); Maquette 0.2 and 3D-lowey ask for a newer version instead of opening
  them.
- Booleans by Manifold (Apache-2.0), vendored.

## [0.2] — Maquette — the canvas owns the screen (phase M2)

- **The stage owns the screen.** At rest it holds at least 85% of it: two corner clusters, a thin sidebar, and
  everything else when called. The layout that freezes at 1.0, every control mapped to one home in
  [docs/LAYOUT.md](docs/LAYOUT.md).
- **Model, Draw, Paint, Animate, Cast** top right. Model gathers what you put into the world (shapes, lights,
  cameras, words, photos and videos, effects), the Kit and your models, and snapping. Paint has the Shadow Brush and
  Scatter. Animate opens the timeline. Top left is now **Home** · Actions · Look · Select.
- **Time on call.** New projects start without a timeline. The control at the bottom right calls the slim
  transport; Animate opens the whole timeline; each project remembers how it left it, and how tall.
- **The inspector floats beside what's selected**, on whichever side has room, and glides over when the view
  settles. Move, turn and size are at its top; align and distribute when several things are selected.
- **Every panel resizes** from the grip in its corner and remembers its size (double-tap the grip to reset).
- **The joystick is on by default**, with its own × to hide it (Settings ▸ Stage brings it back).
- **Home, the living gallery.** Each card is the model slowly turning in its own Look; tap it and it grows into the
  stage. Stacks (drag a card onto another), search, sort, and Select for several at once. Closing a project no
  longer waits for its card to be drawn.
- **Starter templates** in New project: Model to print, Room or building, Character, Animation, Blank.
- Nothing appears in two places any more: sound and the timeline's settings live in the timeline, photos and videos
  are added from Model, Pick is the sidebar's.
- **Diagnostics ▸ Run the Home benchmark**: a hundred projects turning while the gallery scrolls for 20 seconds.
- Section titles in panels are translated into Italian and Arabic too; Settings ▸ About says studio h.
- hmm-kit 0.3.0: resizable panels (`hmmResizable`), `HmmFloatingPlacement`, `GalleryArrangement`.

## [0.1] — Maquette — foundation & feel (phase M1)

- **3D-lowey is now Maquette**, by studio h.: its own name, icon (temporary, until the identity phase), bundle id and
  `.maquette` projects. It installs next to 3D-lowey; 3D-lowey's projects and `.loweypack` files open in it.
- **Nothing is ever lost.** Every change is written to the scene's history the moment it happens (the 1.2-second
  autosave delay that could drop your last edit is gone). Force-quit mid-edit, reopen: the edit is there and undo
  takes it back. Undo keeps 500 steps across relaunches.
- **History** (Actions ▸ History): drag back through every step and see the stage as it was; *Go back here* (the
  state you leave is kept as a version), name a version, restore any version as one undo step. Versions are kept
  automatically each time a scene opens and after each hour of work.
- **The Pencil feels right.** With hover preview on, a small point sits exactly under the tip, for every tool, drawn
  in the stage's own frame; with it off, nothing shows. The brush outline appears only while you resize the brush.
- **Every iPad, tuned.** Maquette reads the iPad's GPU and memory and picks a preview tier: full on M-chip iPads,
  lighter render scale and shadows on A-chip ones. Exports are always full quality. The stage holds the screen's
  own refresh (60 Hz iPads are no longer pushed to 120).
- **A load meter that speaks up before lag.** Invisible until a scene nears what the iPad keeps smooth; then a calm
  chip offers a lighter preview.
- **Diagnostics**: shows the tier; the benchmark's pass rule follows the screen, and M iPads can run it as Tier B.
- **Faster frames**: smears no longer rescan the scene every frame, the stroke preview uploads once, frame timing
  allocates nothing.
- **CI**: one run per change, routed by what it touches, the app build beside the render tests; one required check.
- [docs/PROJECT_FORMAT.md](docs/PROJECT_FORMAT.md) documents the package, `project.json` and the journal.
- hmm-kit 0.2.0: `HistoryJournal`, `HistoryVersions`, journaling on `CommandStack`, `DeviceTier`, `LoadMeter`.

## [2.0.0] — 2026-10-04 — Tools, the Kit, and a director that can see

The remaster's second half. Everything in 2.0.0-beta.1, plus:

- **Ink strokes.** Draw pressure ribbons with the Pencil on the guides, next to the solid shapes. Select strokes
  (tap or loop), move, erase, smooth and change their width; strokes are objects, so they animate like anything else
  and can write themselves on.
- **Flipbooks.** Draw frame-by-frame over the shot, anchored to the camera or to an object, with onion skin, holds,
  multiply / screen / add blending and several tracks. Five drawn effects ready to drop on a word: speed lines,
  impact burst, sweat drop, sparkle, smear.
- **Animation tools.** Per-object frame rate (ones to fours, keyable) — a character on twos, the camera on ones;
  motion paths with dots you drag; 3D onion skin; a graph editor; smears on fast moves; a pose library with mirror; IK
  handles; pick several clips with the Pencil lasso.
- **One Cast.** Blobs, Puppets and Rigged characters in one panel under the same verbs. Blobs get a steady thick
  outline, face decals that stay flat, Shadow Brush presets for designed shadow shapes, and ten built-in clips.
- **Fly the camera** with on-screen sticks or a game controller, eased like a real operator, and record the flight in
  Perform. Frame shot knows every shot type and composition, from either side of the subject.
- **The Kit.** About 350 CC0 models from Kenney and Quaternius in nine Sets — Room & Desk, Office & Computers, Nature,
  City & Street, Kitchen & Food, Lab & Science, Space, Props & Signs, Characters — at real size, knowing their surfaces
  and which way they face. The Library opens on them; thumbnails are drawn in the Ink Look.
- **Sound effects.** A track for them and a small synthesised foley set (whoosh, pop, impact, click, swell) whose hit
  lands on the word you pick.
- **New samples.** The Welcome island and the Enigma story rebuilt from the Kit: a desk at night in Ink, a room of
  computers in Comic on twos, a cave robot in Sketch with one accent, and the narrated three-shot story. A new tour.
- **Claude can see what it builds.** `observe` shows Claude the shot with numbered marks, top / front / side diagrams
  with the camera drawn in, a squint (value) view and the subject's silhouette, and measures it: what's visible and how
  much, what floats or intersects, where the subject sits, contrast, palette, light — graded against a critique rubric
  with a fix for each failure. `contact_sheet` adds how things move. Running it on our own samples found a glTF bug
  that drew whole Kit packs at a third of their size, a chair blocking a shot and a lamp that made a desk glow; all
  fixed.
- **MCP v2 and Scene Script v3.** The laptop tool is now `hmm-bridge`, and its `lowey` MCP server has sixteen intent
  tools. Scripts speak relations instead of coordinates ("the lamp on the desk, the books beside it"), frame shots,
  light them with six recipes and animate by intent (enter, react, walk to, look at, talk…); the solver grounds
  everything and keeps things apart. Proposals on the iPad show a preview picture. v2 scripts still work.
- **A new Claude skill** built around a director's loop — plan, build, look, critique, fix — with modules on sets,
  camera, light, animation, characters and style, a tool reference generated from the server, and twelve eval briefs
  with a harness that scores Claude's work from the app's own measurements.
- **Italian and Arabic.** The whole interface in English, Italian and Arabic, right to left in Arabic.
- **Accessibility.** VoiceOver reaches every control, the chrome follows Dynamic Type, and Reduce Motion, Reduce
  Transparency and Increase Contrast are respected.
- **Windows.** A Monitor window shows the shot live, as it will export — beside the editor in Stage Manager or on an
  external display (Actions ▸ Monitor, ⌥⌘N). The app reopens where you left off.
- **App Store ready.** A new icon, privacy manifests, App Store screenshots made by the UI tests, and a TestFlight
  upload in the release workflow. The App Store build ships without the laptop bridge until 2.1.

## [2.0.0-beta.1] — 2026-10-03 — A new engine, Looks, and a layout without modes

The remaster's first half: everything 1.4.3 did, on a new renderer, in a new layout. Projects from 1.x open as they
are. Every 1.x feature and what happened to it is in [docs/MIGRATION.md](docs/MIGRATION.md).

- **Looks.** Five ways to draw the same world: **Ink** (the new default: cel shading with soft-edged bands, shadows
  that shift toward the sky's colour, bounce light, contact shading, a rim light and ink lines), **Comic** (halftone
  shadows, colour misregistration, heavier lines, on twos), **Sketch** (pencil lines, paper, and one **Accent** that
  keeps its colour), **Clay** (the soft 1.x look, with soft shadows) and **Low-poly** (faceted). Duplicate any Look
  into your own; a scene or a single object can use a different one. Moods and the palette work with all of them.
  1.x projects open in Clay, so nothing looks different until you choose.
- **LoweyRender 2.** A Metal renderer of our own replaces RealityKit. The stage, thumbnails and exports are drawn by
  the same code, so what you see is what you export. Tapping picks exactly the object under your finger (even thin
  ones), the selection is outlined, rigged characters are skinned on the GPU, repeated objects are drawn in one go,
  and the picture drops to a lower resolution and upscales (MetalFX) when the iPad is busy or hot. Shadows come from
  the sun; up to 16 lamps light a shot.
- **One editor, no modes.** The stage sits over the timeline. Top left: Theater, Actions, Look, Select. Top right:
  Build, Draw, Transform, Cast, Library. A sidebar holds two sliders for whatever you're doing, Pick, undo and redo.
  The inspector slides in when something is selected. Four fingers hide everything but the stage. ⌘1–5 open Select,
  Build, Draw, Transform and Look.
- **The Theater.** Projects play a short loop of their first seconds; New project asks for a name, a mood and a Look.
- **Bevels** on primitives (on by default, small), so edges catch the light and the lines.
- **Shadow Brush.** Paint where shadows fall on any surface with the Pencil.
- **Director view** (⌥⌘D): look through the shot camera with the delivery frame, thirds and safe areas marked;
  drag, pinch and twist to aim, move, dolly and roll it, keyed. **Frame shot** places a camera on the selection with
  a shot size and a composition.
- **Auto-key lives in Keyframe mode.** Compose, the default, never makes keys by accident.
- **Export presets**: YouTube 4K, 1080p, Shorts / Reels, Square, Transparent, PNG stills, **GIF loop** (new), 3D, and
  captions. Every export is checked (frames, size, length, sound, transparency) before it's handed to you. Exports keep
  going in the background, with a Live Activity where the system shows one and a notification when they're done.
- **Diagnostics**: a performance HUD over the stage and the **Night Market** benchmark (a busy street with walkers and
  blobs under lamps) that writes a JSON report; log export.
- **The bridge is off until you turn it on.** Pairing uses a one-time code shown on the iPad, laptops get their own
  token (kept in the Keychain, listed, revocable), and nothing answers from outside the local network. `lowey-link pair
  <code>` takes the code; `lowey-mcp --public` and the tunnel modes are gone.
- **New identity**: bundle id `studio.hmm.lowey`; 2.0 installs next to 1.x.
- Under the hood: the code is now LoweyCore → LoweyEngine → LoweyFeatures → App, with shared parts in hmm-kit; Swift 6
  with no warnings; no file over 500 lines; golden-image tests for every Look; releases only from commits CI passed.

## [1.4.3] — Moving-around speed, a smoother stage, a real ground, a nicer joystick

- **Moving-around speed.** Scene menu → *Speed…* now has two sliders: *Moving around* (orbit, pan and pinch zoom with
  your fingers, and a camera's moves in Camera mode) and *Joystick*. Normal is the feel it always had.
- **Smoother in big scenes.** The live view now lights what you're looking at: the 8 nearest point / spot lights shine
  and only the 2 nearest cast shadows (a set with twenty lamps across five rooms used to light and shadow-map every
  room, every frame). Lens blur and ink outlines are worked out at a fraction of the size in the live view (the blur
  was the heaviest thing on screen). When the stage still drops below about 40 frames a second it draws a step fewer
  pixels until it's smooth, then climbs back. Exports are unchanged: full quality, every light.
- **The ground.** It no longer ends in a hard line against the sky: towards its edge it melts into the exact colour of
  the sky behind it, and a faint large-scale shading keeps a big floor from looking like one flat sheet. The building
  grid is drawn per pixel: crisp, anti-aliased lines at any distance, no shimmer far away, and it fades out instead of
  stopping at 20 m.
- **Joystick, redesigned.** A shaded well with tick marks, X and Z labels on a compass that turns with the view as you
  orbit (it used to update three times a second), the rim lighting up where and how hard you push, a glossy knob that
  springs back, a green height slider that fills from its centre notch, the mode (MOVE / TURN / SIZE) and speed on top,
  and a light tap when you grab it or hit full speed.

## [1.4.2] — Joystick speed, a calmer cartoon face

- **Joystick speed back to how it was**, and now yours to set: scene menu → *Joystick speed…* (a slider, tortoise to
  hare, with *Back to normal*). v1.4.1 made the pad count real time instead of frames; when the stage runs below 60
  frames a second that made it about twice as fast as before (turns up to three times). Normal is the old feel.
- **Squash & stretch that doesn't wreck the face.** The head used to squash by how far the face *lagged behind* a new
  expression, so the instant you keyed one the whole head, eyes and mouth included, was crushed to about half its
  height and then shot up to 1.6×. Now it's a quick take: the head stretches a little (at most 10%) in the direction
  the face is moving and is round again once it settles; a held expression keeps only a hint (2–3%). The hat follows
  the same take.
- **About half the bounce.** Expressions overshoot about 14% and settle (it was about 30%, a wobble). The *Cartoon*
  slider still goes from none to rubbery.

## [1.4.1] — Joystick, bridge that stays up, clean shots

- **Joystick, one layout in every mode.** The stick works on the ground (red X and blue Z, drawn inside the pad the way
  they lie from where you look), the green slider on the vertical (Y): Move slides / lifts, Rotate tips the object
  (stick) and spins it (slider). Analog: gentle near the middle, full speed at the rim, and speeds are per second (the
  pad assumed 60 frames a second, so on a 120 Hz screen or when frames dropped it jumped). No snap jump when you let go
  of a joystick turn. Stick and slider together are one undo step.
- **Cameras, light bulbs and particle emitters no longer show in the shot**: hidden while looking through a camera and
  in Export (exports never had them).
- **The bridge stays up.** It starts with the app (unless you switch it off) and keeps answering when 3D-lowey is in the
  background or the screen is locked (it plays silence, mixed with your music, which is how iOS lets an app keep
  running). A "Bridge on" notification shows while the app is away, and one tells you when Claude proposes a change.
  Snapshots need the app on screen (iOS doesn't let a background app draw). It restarts its listeners when the app
  returns to the front and saves a laptop's pairing at once (it was saved on the next status call, so a pairing could
  be lost).
- **The iPad no longer auto-locks while 3D-lowey is on screen.**
- **Pairing code**: permanent by default (000000 until you change it, *Change* in the bridge panel), or *New code after
  every pairing*. `lowey-link pair` with no code uses 000000. Ten wrong codes pause pairing for a minute.
- **lowey-mcp / lowey-link answer fast or fail fast**: 2.5 s to connect (a sleeping iPad used to hang a call for up to
  200 s), no proxy lookups, and if the iPad's address changed they find it again by Bonjour and remember it.

## [1.4.0] — Polish: feel, face, media

### Feel
- **Rotation that behaves.** Objects turn around their own pivot (several: the middle of their pivots) and never drift
  while turning (the pivot used to be re-measured from the bounding box every frame). Rotate rings are thin and picked
  by their drawn line, the ring facing you winning where they cross (overlapping hit boxes grabbed the wrong axis).
  Face-on rings turn by circling, edge-on rings by sliding along them. Snapping happens in steps during the turn, with a
  tick, instead of jumping at the end. The inspector keeps the angles you typed (X 100° stays 100°, not 80°/180°/180°).
- **Two fingers on the selected object** hold it: twist turns it, pinch sizes it (Reality Composer). Elsewhere two
  fingers still move the camera.
- **Squeeze the Apple Pencil Pro** to play or pause, in any mode, with the interface hidden too (unless Squeeze is set
  to Ignore in Settings).
- **The timeline scrolls up and down again** with many rows (the lanes' drag swallowed the list's scrolling), flicks
  glide, a thin bar shows where you are. To start and Add marker are back on the header.

### Simpler, lighter chrome
- Buttons on a panel draw no glass of their own (glass on glass); the top bar's glass is one group. Undo and redo sit in
  the top bar; move / turn / size only show with something selected; the inspector keeps the numbers folded and has
  three actions (duplicate, hide, delete) plus one menu for the rest.

### Faster stage
- The selection box is rebuilt only when the selection's size changes (it was rebuilt, and the selection re-measured,
  on every camera move and every frame of playback). The drawing guide likewise.
- Live bloom at quarter size (exports keep the full filter); video frames for the stage decode at 1280 px.
- The stage renders at 1.75× (about a quarter fewer pixels); *Full-resolution stage* in the scene menu brings back
  full density. Rigs are only looked up for clip tracks.

### Face, hands and the phone
- **Set rest pose** (Character Animator): sit relaxed and tap; head angles, gaze and dials are measured from there, so
  looking at the iPad from below no longer leaves the character nodding.
- **Hands**: body tracking (Vision) moves the blob's hands and the rubber-hose arms follow; recorded with the face.
- **A camera preview** floats over the stage while you perform: the picture, green dots on the face, lines on the arms,
  Set rest pose and stop. The iPhone companion shows its own preview and streams a small one to the iPad.
- Sides are consistent: every source reports the mirror's sides (the iPhone used to mix mirrored blinks with unmirrored
  turns); head turn, nod and tilt from the iPad camera come from the face's own geometry. The iPhone measures the head
  against the phone, not against where tracking started. Live values draw once per screen frame.

### Characters
- **The neutral face is neutral**: a short level mouth, level brows, upright eyes. The smirk lives on as *Smug*.

### Media
- **Pictures and videos stand in the world as thin cards** (Add → Photo or video): a framed slab facing you, moved,
  turned, sized and keyed like any object; videos play on them frame-exact in exports. Transparent Manim renders still
  go over the frame. The bridge takes `?as=card|overlay`; `add_media(..., overlay=False)`, `lowey-link media --overlay`.

### Laptop tools
- `lowey-link pair 123456` finds the iPad by itself (Bonjour); `python -m lowey_tools` works when `Scripts` isn't on PATH.

## [1.3.1] — Smooth stage

- The live stage works out the glow halo at quarter size (it blurred the whole screen at full size every frame whenever
  anything glowed, including the blob's hover glow). Looks the same; exports keep the full-size halo.
- Blob faces stop making a new mesh every frame: springs settle to the exact pose and step in steps too small to see, so
  shapes are reused; the mouth works out each moment once instead of eight times.
- The renderer's mesh cache is bounded (it grew for as long as a face animated, so the app got slower the longer it ran).

## [1.3.0] — Phase 4: Characters, stability, feel

### Characters: the blob house style
- Hesham's own drawing turned into the house character (`assets/avatar`: traced from the drawing, built in Blender, GLB
  + .blend). In the app: **Add → Me**, or **Add → Blob** with a builder (who, hat and the name on it, hair, accessories,
  what they hold, colours).
- Famous people as blobs by their clues (Newton's wig and apple, Einstein's white hair and mustache, Turing, Curie,
  Darwin, Tesla, Lovelace, Edison, Sherlock…), in the app and in scripts (`{"do": "blob", "likeness": "Isaac Newton"}`).
- A real cartoon face: eyes, brows and one morphing mouth redrawn from dials every frame (happy crescents, wide eyes,
  curved closed lids, angry and worried brows, his smirk at rest). Springs make every pose **overshoot and settle**;
  the head squashes and stretches on the hits; the hat follows through; eyes blink on their own.
- **Expressions** (12) in one tap at the playhead, Character Animator-style, and `{"do": "expression"}` for Claude.
- Rubber-hose arms that follow the hands; no legs, a soft hover glow that stays on the ground.

### Stability
- First-launch crash fixed (the tour opened a scene with post-processing into a stage that hadn't rendered yet).
- Exports never hang: the screen stays awake, the export waits while the app is in the background and resumes, a
  stalled frame is retried and reported. The full narrated story exports start to end in CI.
- Playback no longer redraws the whole timeline every frame (lag while playing).
- Glow works (it did nothing: the surface shader multiplied it by an empty emission map); glow casts a halo; imported
  models glow in their own colours. Image overlays now reach exported videos.

### Timeline, camera, drawing
- Track groups: folders you fold; a folded group shows and moves everything inside. Drags lock to their direction,
  only selected keys and bars move, flicks glide, pinch zooms under the fingers, a quieter header with one menu.
- Camera Perform records the path you fly with your usual gestures. **Snap zoom** move.
- **QuickShape**: draw, then hold, and the stroke becomes a line, arc, circle, ellipse, triangle or rectangle.

### Media and Manim
- **Add → Photo or video**; videos play from a time and export frame-exact. `lowey-link media`, `lowey-link manim`
  (renders a Manim scene with a transparent background, ProRes 4444) and the MCP tools `add_media`, `render_manim`.

### Interface
- Liquid Glass chrome, focus mode (button, four-finger tap, ⌃⌘F), a small stats pill, Pencil hover preview off by
  default, remove colours from the palette, a gestures & shortcuts page.

### Claude
- One skill, `skills/lowey`: an orchestrator that routes to modules (breakdown, shots, sets, camera, characters,
  cartoon animation, Manim & media, style, troubleshooting). End-to-end test: pair over HTTP, send a script, approve
  on the iPad, find the result.

## [1.0.0] — Phase 3: Story, voice, VFX, AI, polish

### Timeline — keyframe multi-select (Procreate Dreams-style)
- Box-select keys across rows and time: long-press and drag, or switch on **Select** and drag. Taps add/remove in Select mode.
- **Pick** menu: all keys, everything after / before the playhead, keys at the playhead, keys in the loop, invert, none
  (scoped to the selected objects when something is selected).
- A band over the selected keys on the ruler: drag either end to **stretch or squash** their timing (proportions kept).
- Move many keys together (the earliest stops at 0), nudge by a frame (menu, ⌥⇧← / ⌥⇧→), ⌘⌥A selects all keys.
- Compose mode: pick several bars and slide them together.

### Audio & narration
- Voiceover, sound-effect and music clips: waveforms in the timeline, drag to move, volume, fade in/out, mute, trim to
  the playhead, split, delete; "duck music under the voice" from the transcript. Import from Files or record a voiceover
  while the animation plays.
- Playback follows the sound's clock (no drift). Exports carry the mixed soundtrack (AAC in .mp4/.mov; soundtrack.wav next
  to PNG sequences) — mixed exactly as previewed.
- Word timing with Apple's on-device SpeechAnalyzer (no Whisper): the model downloads once; English, Arabic, Italian first.
- Words lane in the timeline, transcript panel (tap a word to jump; long-press + tap to pick a phrase; fix words and keep
  their timing), snapping of keys, the playhead, sounds and effects to words, phrase actions (animate here, camera move,
  cut, marker, loop).

### Lip sync, face, your character
- Lip sync from the voiceover's words (CMU Pronouncing Dictionary + rules; Arabic and Italian), with the voice's loudness as
  fallback: stepped mouth shapes plus jaw and width keys — editable like any animation.
- Face performance from the iPad's front camera (Vision landmarks): blinks, brows, mouth, smile, eyes, head turn — live on
  the character, recorded with Perform. Optional iPhone companion (Face ID / ARKit) streaming over the local network.
- Character builder: head, hair, eyes, body, top, bottom, extras, colours → a low-poly character on the Humanoid standard
  with swappable mouth shapes; edit it later; save it to the library.
- Built-in humanoid clips (Idle, Walk, Run, Talk, Wave, Point, Type, Nod, Shrug, Celebrate) that play on built characters
  and imported humanoids; imported humanoid clips play on built characters too.

### Text, overlays, captions
- 2D overlays in frame space: titles, labels, arrows (draw themselves), highlights, the big X, question / exclamation
  marks, ticks, shapes, images; drag / pinch / twist on the stage; presets animate them (typewriter types, arrows draw);
  labels can follow a 3D object.
- 3D text: Blocky (built-in low-poly font) plus Rounded, Bold, Serif, Mono (any script).
- Captions from the transcript: Punchy (karaoke highlight), Subtitle, Pill, Outline; top / middle / bottom; burn-in on
  export; .srt and .vtt export. Portrait frames get shorter lines.

### VFX & post
- Particles: fire, sparks, smoke, dust, magic, rain, snow, confetti, embers, explosion — amount, size, speed, spread,
  colour; animate emission; bursts at a time. Deterministic (scrub and export exactly).
- Post (in the Look): glow, vignette, grain, exposure, contrast, colour, warmth, ink outlines, colour fringe, retro/PS1,
  paper / collage / old-film textures, depth of field from the camera (now rendered). One-tap finishes: Clean, Cinematic,
  Dreamy, Retro, Ink outlines, Collage, Old film. Identical in the live view and in exports.
- Screen effects on the timeline: flash, shake, speed lines, zoom blur, glitch. Transitions on cuts: fade, dip to black,
  wipe, zoom-through. Match-cut helper.

### AI layer & laptop link
- Scene Script v2: friendly actions (names, spoken-word times, presets, cameras, characters, look…) → preview → apply as
  one undo step. Paste from the clipboard, open a file, or send from the laptop. JSON Schema updated.
- LAN Bridge (off by default, pairing code, local network only): scene / assets / transcript / look queries, scripts
  (with approval on the iPad), snapshots, renders, file and audio import, undo, WebSocket events.
- `tools/lowey`: **lowey-mcp** (MCP server: 16 tools, 4 resources, 5 prompts) and **lowey-link** (pair, push, pull renders,
  watch a folder, Blender / text-to-3D generators, send scripts). Claude skills in `/skills`: script-breakdown,
  shot-planner, scene-builder, camera-director.

### Projects & polish
- Share a project as one `.loweypack` file and import it; archive / restore; copy a scene to another project.
- Welcome island sample (golden-hour fly-through) and a 60-second tour; the Enigma sample gains "5 · The story (narrated)"
  with a placeholder voice.
- Menu-bar commands with shortcuts (modes ⌘1–5, transcript ⇧⌘T, audio ⇧⌘U, record ⌥⌘R, bridge ⇧⌘B, markers ⌘M…),
  Apple Pencil hover preview, localisation scaffold (Arabic, Italian), thermal-aware preview, local diagnostics log and
  "Export diagnostics".

### Engineering
- Schema v3 (additive). New Core areas: `Audio/`, `Text/`, `VFX/`, `Face/`, `Character/`, `AI/`, `Project/ProjectPackage`.
- LoweyRender: `FrameCompositor`, `OverlayRenderer`, `StagePost`, depth world + `loweyDepth` / `loweyInverseDepth` shaders,
  particle meshes, text meshes; exporter composites, renders transitions and writes audio.
- Tests: Core (~180, Linux), render and speech tests on the simulator (`Phase3Tests`), laptop tools (pytest) in CI.

## [0.8.0] — Phase 2: Motion, camera, characters, export

### Timeline
- Bottom timeline drawer in Animate and Camera modes: transport, frame stepping, scrubbing ruler, markers (tap to jump,
  long-press to rename/delete), loop region, zoom (pinch) and pan, one row per animated object (expand into property
  rows), behaviour spans, clip segments, camera-cut row.
- Modes: **Compose** (slide whole animations in time), **Perform** (record by touch), **Keyframe** (select, drag,
  retime keys). Frame rate 24/25/30/60, length, "fit to animation".
- Timeline evaluation, per-object and per-project stepping (cameras stay smooth) — all in LoweyCore, unit-tested.

### Keyframes & easing
- Keyframe any animatable property: auto-key (edits in Animate/Camera mode become keys at the playhead), animated
  properties always key, "Key" button (⌘K).
- Easing presets (linear, in, out, in-out, overshoot, bounce, elastic, step) + a curve editor with draggable handles.
- Copy/paste (also onto another object), mirror (there and back), reverse, twice as fast/slow, delete.

### Perform mode
- Record → "Ready 3-2-1" → the timeline plays; drag to move, pinch to scale, twist (or Apple Pencil Pro barrel roll)
  to turn. Lift = pause, touch again = resume. Smoothing 0–100 %. Sliders perform any number (glow, light, opacity,
  zoom, focus). Re-performing replaces only the performed range. One undo step per take.

### Presets & mass animation
- 15 one-tap presets: pop in/out, grow, shrink, bounce, wiggle, float, spin, shake, pulse, fade in/out, slide in,
  drop in, typewriter — real, editable keys.
- Many objects at once: delay, order (selection, left→right, right→left, front→back, wave), random timing and strength.
- Behaviours: follow a drawn path, look at, follow (with lag), orbit, wobble, wind sway, bob on water, spin —
  deterministic, bake to keys. Animated generators (arrays/scatters grow in one by one).
- Simulations baked to keys: fall, explode, flock of birds, crowd walks in.
- Scripting (JavaScriptCore): script panel with inline errors and a log; scripts saved in the library; examples:
  forest grows in, flock of birds, crowd walks in. Every run is one undo step.

### Characters
- Skeletons and clips read from glTF/GLB in LoweyCore; clips play on skinned models (poses → joint transforms).
- Standards Humanoid / Quadruped / Bird / Custom with auto bone mapping (Mixamo, Quaternius-style, Blender, generic).
- Retargeting: a clip for a standard plays on any character of that standard (tested on 2 humans, 2 quadrupeds).
- Clip track: play from the playhead, loop, speed, crossfade; walk speed matched to a path (no sliding); feet on the
  ground, head look-at, hand reach (IK). Crowd tool: N copies with offset, varied clips.
- Puppet joints: wrap parts in a joint that pivots at the top/middle/bottom (shoulders, hips, hinges).

### Camera
- Look through the shot camera; drag to aim, two fingers to move, pinch to dolly, twist to roll — keyed.
- Cameras + camera-cut track ("Cut here"). 10 one-tap moves: push in, pull out, punch in, orbit, dolly, truck, crane,
  whip pan, shake, reveal; follow the selection.
- Lens: focal length, focus distance, aperture, focus on selection, animated focus pull (rendered blur arrives with
  Phase 3's post-processing — see DECISIONS D50).
- Framing guides 16:9 / 9:16 / 1:1 with safe zones and thirds; per-camera 9:16 zoom and pan, so one camera exports both.
- The iPad as a virtual camera (ARKit world tracking, scale factor), recorded through Perform.

### Export
- Video rendered frame by frame at a fixed timestep: 16:9 + 9:16 (+ 1:1) in one job, HD/4K, H.264/HEVC, PNG sequences,
  transparent background (HEVC with alpha / PNG), whole timeline or the loop region; progress and cancel; saved in the
  project's renders folder; share or save to Photos. Single frames through the camera.
- 3D export of the selection or the scene: glTF (.glb) and USDZ.

### Engineering
- Schema v2 (Phase 1 files open unchanged). New commands: `setTracks`. Deleting/duplicating objects carries their animation.
- New package `LoweyScript`. New Core modules: Motion, Rig, Export. Sample project gains "4 · Opening (animated)".
- CI: `[build-only]` in a commit message runs a compile-only app job (saves macOS minutes).
- Fixed: Mixamo "Fo**rear**m" was read as a quadruped's rear leg by the rig classifier.

## [0.4.0] — Phase 1: Foundation & Build

### Engineering
- XcodeGen project (`project.yml`), Swift 6 strict concurrency, packages `LoweyCore` + `LoweyRender`, app `LoweyApp`.
- CI: SwiftFormat + SwiftLint → LoweyCore tests on Linux with ≥ 80 % coverage gate → iPad simulator build,
  render tests and UI smoke test (screenshots exported as artifacts).
- Release: unsigned device build → ad-hoc codesign → `Lowey.ipa` on every `main` push; GitHub Release on `v*` tags.
- Docs: README (Sideloadly install), ARCHITECTURE, DECISIONS, THIRD_PARTY.

### Core model
- Objects with typed, animatable properties; groups/hierarchy; lights; cameras; drawn objects (recipes); prefab instances.
- Command system with exact inverses, batches, JSON encoding (Scene Script vocabulary); undo/redo with gesture coalescing.
- Timeline, keyframes, easing (linear, in, out, in-out, back, bounce, elastic, step, bezier), on-twos stepping.
- Project folders (`.lowey`), schema versioning + migrations (v0 → v1), atomic writes with backup recovery, autosave.

### Render
- RealityKit bridge with diff-based sync, shared meshes/materials (instancing), fog + glow surface shader.
- Looks: smooth/flat shading, linked palette, 6 mood presets, sun with shadows, sky gradient + stars, fog, ground,
  sky-driven ambient light, custom point/spot/directional lights with shadows, emissive glow.
- Offscreen renderer (RealityRenderer) for snapshots and thumbnails — the Phase 2 export path.

### Building
- Blockout primitives (cube, sphere, cylinder, cone, plane, torus, ramp); swap blockout → library model (fit to size).
- Gizmos (move/rotate/scale), on-screen joystick, direct drag, numeric inspector.
- Snapping: grid, ground, flush to other objects, rotation steps.
- Duplicate, copy/paste, array (row, grid, circle), scatter an area in one gesture (seeded), group/ungroup,
  outliner with lock/hide/reparent, align/distribute.

### Drawing in 3D
- Pencil pressure strokes with smoothing → tube or ribbon; extrude a drawn outline; lathe a drawn profile; mirror.
- Guides: plane locked to the view (or ground/front/side) with offset, box, cylinder, sphere, or any existing object.
- Save anything to the library.

### Library
- Global library (USDZ, glTF/GLB with dependencies, OBJ; files, folders, drag & drop, share sheet).
- Auto thumbnails, search-first panel, tags, favorites, recents, RIGGED badge (skeleton + clips kept), prefabs that
  update everywhere, saved looks. Projects reference assets by id; "Export" copies them in.

### UI
- Home with project thumbnails; stage with left tool rail, top-right mode switcher (Build · Animate · Camera · Look ·
  Export), inspector, library, outliner, look panel; snapshot export as PNG in 16:9, 9:16 and 1:1 (HD / 4K).
- Keyboard shortcuts (⌘Z, ⇧⌘Z, ⌘D, ⌘C, ⌘V, ⌘G, ⌘A, ⌘⌫ delete, ⌘F frame, ⌘L library), haptics, Stage Manager friendly.
- Sample project: the Enigma sets.
