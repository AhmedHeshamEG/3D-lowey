# CONTEXT — Hesham's 3D Video Creation Tool

> Name: **3D-lowey**. In code, identifiers use `Lowey` (Swift names can't start with a digit or contain a hyphen).
> This file holds the full context of the idea: what Hesham said, what he wants, what he rejected, what was decided, and every reference. Any agent or collaborator should read this first, fully, before touching code.

---

## 1. The Idea in One Paragraph

A native iPad app for making videos that **look like a game**: low-poly 3D worlds you build like Lego, animate fast, direct with camera moves, and sync to narration. It is inspired most of all by **Feather 3D** (the blueprint), mixed with the best parts of Blender, Procreate Dreams, Toonsquid, Adobe Character Animator, Unreal's virtual camera, Minecraft/Fortnite/Valorant-style worlds, and Townscaper/Tiny Glade-style "few decisions, big results" building. It becomes Hesham's video style (his "beta heshamvox") in place of filming his face, and it is meant to eventually replace his older tools Editoro and Retake. He sees it as the greatest thing he's built, his "early Manim moment" — like Grant Sanderson (3Blue1Brown) building Manim for his own videos, feature by feature, driven by real needs.

---

## 2. Who It's For and Why

- **User:** Hesham himself first. A maths/AI student and content creator. **Not an artist** — has taste and imagination, but not drawing or modeling technique.
- **Why:** to tell visual stories for YouTube at a level that competes with Zach D Films, TED-Ed, and the best explainer channels, while being **his own** style.
- **Replaces:** his current face-on-camera format for this kind of content, and the tools Editoro (template video editor) and Retake (transcript-based cutting). Those stay alive until this tool ships a real video.

---

## 3. The North Star (the benchmark)

**Minimize the time from "the idea pops into my head" to "it's on screen, moving and animated, without any problem."**

Every feature is judged against this. If a feature doesn't shorten idea-to-screen time, it waits.

Hesham's own words, paraphrased: the objective is minimizing the gap between the visual in mind and the visual on screen, however complicated it is. There must be a way to get what's in your head out, as if you plugged the computer into your brain and pulled everything out.

---

## 4. Core Principles (decided)

1. **Creative first, no limits.** There is **no house style**. Every project can look completely different (a low-poly village, a space scene, a WW2 trench, a neon city). The references below are examples of taste, not rules.
2. **Hesham is the director.** A director mixes things, has the vision, and **decides**. The tool and the AI produce and execute; he chooses.
3. **Decision is easier than creation, but too many decisions paralyze.** Recognition beats production (picking the right tree is easy; drawing one is hard). But a wall of 30 templates or a panel of sliders is paralysis. Lesson learned from Editoro: past ~25–30 templates the library became overwhelming and choosing became impossible.
   - **Rejected:** parametric assets controlled by many sliders. "An asset, yes. An asset with parameters, no."
   - **Rejected:** giant template walls.
   - **Wanted:** few decisions, each one producing a big result (Townscaper / Tiny Glade model: you express intent, the system fills details).
4. **AI assists, the creative tools stay central.** Procreate's team refuses AI entirely; Hesham partially agrees but would integrate AI as a helper while continuing to develop the creative tools. AI is never the main thing, and it must not produce "slop."
5. **Manim-style growth, structured from day one.** Build as you go, driven by real videos, but the core architecture must be **very well structured from the beginning** so every future feature has a place to attach.
6. **Everything the AI can do, the user can do by hand — and vice versa.** Both use the same command system.
7. **Build once, reuse forever.** Anything built (an asset, a character, a prop) is saved to a library once and reused across all projects.
8. **The non-artist gap is a feature to design around.** Turning a non-artist into a director / compositor / animator is the product. Everyone has taste and imagination; the tool bridges the missing technique.

---

## 5. Visual Direction

### 5.1 The core keyword: LOW-POLY
The single most important discovery of the brainstorm. Low-poly is what Hesham meant from the start. It works because:
- It's simple, consistent, efficient, and looks intentional ("rigorously simple").
- Like collage style, it's a recognizable style with its own identity, and the more great people use it, the more expressive it becomes.
- It's light on resources.
- It's easier to generate/vibe-code and to assemble from kits.

### 5.2 Shading preference
- **Preferred:** smooth-shaded / soft low-poly — low-poly silhouettes with soft surfaces (like the rigged animal pack with horse, tiger, penguin, cat, deer, husky, chicken). He said this looks better and closer to what he'd choose.
- Less preferred: flat/faceted shading (every facet visible). Still available per project.

### 5.3 What the references share (observed, not mandated)
- Game-like worlds seen from above, with the camera moving through them.
- Many mood references are **cool, dark night/dusk scenes lit by one warm source** (lamp, campfire, lighthouse, glowing window).
- Cute, simple, expressive characters (big shapes, tiny faces).
- These are observations. Hesham explicitly said they are **not yet "his"** — the app must support any look.

### 5.4 Animation feel
- Fast pacing, strong direction, camera punches.
- Must **not look like a cheap cartoon**.
- Recommended default (per project, switchable): snappy **pose-to-pose** with overshoot; option to animate characters **on twos** (12 fps) with a smooth full-rate camera (Spider-Verse technique).

---

## 6. Everything Hesham Wants (feature wishlist, in his terms)

### Building & assets
- Asset-based, "Lego-like" building (Lego = metaphor for buildable, snappable things).
- Use existing low-poly kits; if something doesn't exist, **invent/generate** it (vibe-codable assets, code-generated geometry).
- Feather-style drawing in 3D. His own idea of how drawing should work: fix an orthographic view, draw, switch point of view, draw again (Feather uses guide surfaces + strokes; he found Feather hard to draw with and wants this easier).
- An **asset library saved in one place**: build something once, reuse it everywhere.
- Text-to-3D model (later).
- Minecraft, Fortnite, Valorant as world/look references.

### Characters & rigging
- **His own character** — a big one for him. It performs instead of his face.
- Animals and characters that move naturally (a tiger that moves like an actual tiger).
- Rigging is his biggest technical fear: he tried vibe-coding rigs before and it didn't work in all cases. He wants rigging to be a non-problem for **any** scene he can imagine.
- Puppets (and Adobe Character Animator as a reference: face drives a puppet).
- Lip sync: in Toonsquid, you draw a mouth per sound and sync to speech; he wants that automated.

### Animation
- Keyframing of everything.
- **Motion capture by touch** = Procreate Dreams' **Performing**: press record, drag/scale/rotate content with finger or Pencil as the movie plays, and the motion is recorded as keyframes in real time. "So simple yet so effective."
- **Mass animation**: animate many things at once (e.g. a forest of trees), and simulations of many objects.
- A **programmatic** layer: the ability to drive things with code/scripts (simulations, generators, procedural motion).

### Camera
- "Packed with camera things" — camera moves are central to his fast-paced direction.
- Toonsquid-style camera movement is a good reference.
- Unreal Engine style: move the device itself to move the camera (virtual camera).
- Framing: **16:9 and 9:16** must both be well handled.

### Look & effects
- Lighting, environments, dynamic environments.
- **VFX** must be included.
- Modes like "attached environments" (environment presets).

### Narration & timing
- Narration synchronized with visuals; camera punches on words.
- **No Whisper** — Hesham said there's no room for it. Word timing comes from Apple's on-device speech framework instead (see Decisions).

### Workflow & organization
- Projects as folders with assets, scenes, exports — organizable, exportable, visual-first control (Feather-like).
- Export 3D objects, snapshots/screenshots, single frames, clips/parts of the video, full video.
- Director, timeline, organization all managed well.

### AI integration
- An **MCP layer** so Claude, GPT, or any other model can drive the tool.
- A **prompt/instruction layer** (skills + MCP prompts) that guarantees consistency and quality, and keeps token usage very efficient.
- AI can help with composition and placement — optional, per shot. Hesham doesn't mind AI handling composition in some cases, but he decides.
- Claude skills that pair with the MCP.
- Link the iPad with the laptop over local network (for AI, assets, and other heavy work).

### Platform & engineering
- **Native iPad** — he loves the feeling of touching the screen and using the Pencil.
- **Great CI/CD** that guarantees quality.
- Feather 3D is the blueprint to reimplement and stylize; he always saw things in Feather, Procreate, Procreate Dreams, and Toonsquid that he'd add or mix.

---

## 7. How Hesham Imagines Using It (worked examples)

### 7.1 The Enigma video (his real script)
While reading his script he visualized, shot by shot:
1. "This is a German army message from 1941" → a paper on screen with an army message written on it; the camera zooms/pinches in on it.
2. "Encrypted with Enigma" → emphasis on the encryption.
3. "People have been trying to read it since 2005" → many people at PCs trying to decode it; the paper grows bigger and bigger over the scene; everyone in the room is dwarfed by it.
4. "Nobody could" → a big **X** appears.
5. "Last week an AI did it" → a big hero robot, like a hero emerging from a cave.
6. "What's the big secret hidden for 85 years?" → a big **question mark** appears.
7. Later, "the AI wrote its own Enigma machine using Alan Turing's brain" → a robot that literally takes Alan Turing's brain from him (goofy on purpose — he loves turning ideas into visual stories this way).

This is the canonical test case. His process (reading the script and seeing images) is a **script breakdown**: script → shots → asset list → build → compose → animate → sync.

### 7.2 Other scenes he imagined
- Alan Turing on a computer by a river, a horse passing by, birds in the sky.
- The same Turing in a war, hiding in a trench, soldiers all around.
- A space scene (proving no fixed style).
- Map metaphors: "new areas on our mathematical map — instead of walking, now we ride horses" (from his first reference).

### 7.3 Effort split (his rough estimate)
Creation of everything ≈ 60–70% of the work; placement/composition is the next chunk; then narration, direction, synchronization. **Fast creation is the most important speed-up.**

---

## 8. References (complete list)

### 8.1 Images Hesham shared
1. **Low-poly tile world** (from a maths YouTube video): floating tiled island, river with wooden bridges, dirt path, horse riders, cabins, pine trees, rocks, snowy mountains, watchtower, bright blue sky. Subtitle: "new areas on our mathematical map. Instead of walking everywhere we can now ride horses." — one of the two images that fired the whole idea.
2. **Stylized car in a grid**: teal grainy car from above inside a wireframe box, pastel grid floor, starry purple-blue sky, collage/grain texture. Subtitle: "Familiar, reliable, built for roads we understand." — the other founding image.
3. **Feather 3D screenshot**: white 3D grid, a translucent guide surface with a black stroke; left vertical tool rail (brush, color, size 35, opacity 100%, undo/redo), top-left home/menu, top-right mode switcher, bottom-center control.
4. **Smooth low-poly animal pack** (horse, tiger, penguin, cat, deer, husky, chicken) — **preferred look**.
5. **Faceted low-poly animals** (bear, wolf, deer, boar, owl, fox, rabbit, squirrel, hedgehog) — flat-shaded comparison.
6. Blue low-poly forest with a glowing river path at night.
7. Moonlit snowy low-poly forest path.
8. Dusk campsite: glowing tent, campfire sparks, pine trees, soft depth of field.
9. Night lighthouse island: red cabin, dock, boat, string lights, campfire.
10. Cute white cat with headphones at a computer (retro/PS1-era 3D look).
11. Cute cat mascot at a payphone, purple/blue neon, low-res game look.
12. Low-poly bearded man portrait (character reference).
13. Voxel retro computer with a smiling face (isometric).
14. Hand-painted stylized barrel/box with triangle counts (178/130/42 tris) — wireframe vs painted.
15. Low-poly night mountains with a campfire and tent.
16. Grey A-frame witch house with glowing orange windows, pumpkins, stone path.

### 8.2 Tools and apps he named
Feather 3D (primary blueprint), Blender, Procreate, Procreate Dreams (Performing / motion capture, record button), Toonsquid (camera moves, mouth-per-sound lip sync), Adobe Character Animator (puppets driven by face), Unreal Engine (virtual camera by moving the device), Lego (metaphor), Manim/3Blue1Brown (build-as-you-go philosophy).

### 8.3 Games and creators he named
Minecraft, Fortnite, Valorant, Zach D Films, TED-Ed, 3Blue1Brown.

### 8.4 References suggested during the brainstorm (accepted as things to look at)
- **Townscaper, Tiny Glade** — one decision from you, many details from the system.
- **Primer** (YouTube) — Blender-based explainer creator who built his own animation library.
- **Imphenzia** (YouTube) — very fast low-poly modeling.
- **Kits:** Quaternius, Kenney (CC0), Synty POLYGON.
- **Mixamo** — auto-rigging and animation library for humanoids.
- **Monument Valley, Islanders, Crossy Road** — palette discipline, simple expressive characters.
- **Spider-Verse** — animating on twos.
- **Blender MCP** — proof that AI can drive a 3D tool through MCP.
- **Rhubarb Lip Sync** — reference for automatic mouth shapes (visemes).

### 8.5 About Feather 3D (researched)
Made by Sketchsoft (Korea). Native iPad app with its own rendering engine ("Airbreath"). Workflow: draw 3D guide surfaces, then draw strokes on them, rotating with touch. "Editing feels like gaming" — joystick for move/rotate/scale. 3D Liquify, pressure brushes, mirror, AR view, glTF/OBJ export, a Blender add-on. They also had a web version and discontinued it — same lesson Hesham learned.

---

## 9. Constraints (hard facts)

- **iPad:** iPad Air M3, 13-inch, iPadOS 27. Supports Apple Pencil Pro. **No TrueDepth/Face ID camera** → ARKit face tracking is not available on this iPad.
- **iPhone:** on iOS 26 (model unconfirmed — if it has Face ID, it can act as a face-capture companion).
- **Laptop:** NVIDIA RTX 2060 (6 GB VRAM), 16 GB RAM. Not a Mac.
- **No macOS machine** at all.
- **No paid Apple Developer account** (won't pay ~€99/yr). Installs his own apps by **sideloading unsigned .ipa files with Sideloadly** using a free Apple ID → apps expire after 7 days and must be re-signed.
- Prefers **local/on-device** processing, no dependence on subscriptions.
- A previous **three.js web attempt failed**. Native iPad chosen for the touch feel.
- Hesham is not a low-level coder; he vibe-codes. Code must be clean, documented, and buildable by CI without him touching Xcode.

---

## 10. Decisions Made

| Topic | Decision |
|---|---|
| Platform | Native iPadOS app, SwiftUI UI + RealityKit 3D. SceneKit is soft-deprecated since iOS 26 — not used. |
| Min OS | iPadOS 26 (needed for SpeechAnalyzer); develop against iPadOS 27 SDK. |
| Build without a Mac | GitHub Actions macOS runners build an unsigned, ad-hoc-signed .ipa → Hesham installs with Sideloadly. XcodeGen generates the Xcode project from `project.yml`. |
| Core architecture | Manim-like: Objects → Properties → Animations → Timeline → Scene. Scene saved as plain JSON. Every edit is a Command (undo/redo free; AI uses the same commands). |
| Core engine separation | Pure-Swift core package (no RealityKit) for the data model, commands, timeline math → fast unit tests. RealityKit only in the render layer. |
| Style | No house style. Look is per project (shading, palette, lighting, atmosphere, post). |
| Asset formats | USDZ native; glTF/GLB via GLTFKit2 (has a RealityKit converter). No Mac tools (Reality Converter is Mac-only). |
| Asset library | Global library outside projects; assets built once, referenced by ID, copied into a project on export. |
| Speech/word timing | **No Whisper.** Apple on-device **SpeechAnalyzer + SpeechTranscriber** with `audioTimeRange` for per-word timing. |
| Lip sync | Automatic visemes from word timings (+ audio amplitude fallback). |
| Face capture | iPad Air has no TrueDepth → use **Vision** face landmarks from the front camera; optional **iPhone companion** with ARKit face tracking over local network if the iPhone has Face ID. |
| Motion capture by touch | "Perform" mode, modeled on Procreate Dreams' Performing, with motion filtering (smoothing) control. |
| Mass animation | Multi-select + presets with stagger/offset/randomize; generators (scatter/array/along path); behaviors; scripting. |
| Programmatic layer | Scripting via JavaScriptCore mirroring the command API + native behaviors; simulations bake to keyframes. |
| AI | Level 1: AI writes Scene Scripts (JSON command lists) the app imports. Level 2: in-app local-network Bridge + a small MCP server on the laptop that proxies to it (tools/resources/prompts) + Claude skills. Model-agnostic. |
| Rendering/export | Real-time preview; export renders frame-by-frame at fixed timestep (quality independent of real-time speed) → AVAssetWriter video. 16:9 and 9:16. Rendering happens on the iPad (RealityKit doesn't run on the laptop). |
| Laptop role | AI agent host (Claude Code / MCP), Blender asset prep, text-to-3D, file transfer. Not a render farm. |
| Old tools | Editoro and Retake stay alive until this app ships one real video. |
| Build philosophy | Three phases to a complete, polished v1.0 (not an MVP). Each phase proven on the Enigma video. |

---

## 11. UI Shape (from Feather + Procreate Dreams + game HUDs)

- **Stage** fills the screen: the 3D viewport, game-like.
- **Left tool rail** (Feather-style vertical floating bar): current tool, color, size, opacity, undo/redo.
- **Top-left:** home (projects) and menu.
- **Top-right mode switcher:** Build · Animate · Camera · Look · Export.
- **Bottom timeline drawer** (Procreate Dreams-style), pull up/down to resize stage vs timeline; three timeline modes: **Compose** (arrange tracks), **Perform** (record motion), **Keyframe** (edit keys + easing).
- **On-screen joystick** for move/rotate/scale (Feather: "editing feels like gaming").
- **Asset library** as a slide-in panel with search and big thumbnails (search first, browse second — avoids template-wall paralysis).
- **Inspector** that appears only for the selection, showing few, meaningful controls.
- Dark, clean chrome that doesn't compete with the scene; game-HUD feel; large touch targets; Pencil for precision, fingers for navigation.
- Gestures: one finger orbit, two-finger pan/zoom, Pencil to draw/select, two-finger tap undo, three-finger tap redo.

---

## 12. Glossary

low-poly · flat vs smooth shading · blockout · kitbash · scene graph · entity-component-system (ECS) · command pattern · keyframe · easing · on twos · pose-to-pose · performing (motion capture by touch) · retargeting · skeleton · visemes · instancing · LOD (level of detail) · USDZ / glTF · emissive · post-processing · script breakdown · virtual camera · safe zones · stagger · MCP (tools / resources / prompts) · skills
