# Migration: 3D-lowey v1.4.3 → 2.0

Every feature of v1.4.3 (branch `legacy/v1`, tag `v1-final`) and what happened to it in 2.0: **kept** (same
behaviour on the new engine and layout), **changed** (still there, working differently, with the reason) or
**dropped** (gone, with the reason). Projects made with 1.x open in 2.0 unchanged; they render in the Clay Look
(Low-poly when the project used flat shading), which is the closest to the 1.x RealityKit picture.

| Area | v1.4.3 feature | 2.0 | Where / why |
|---|---|---|---|
| Home | Projects grid, New project (name + mood), long-press menu (share .loweypack, archive, duplicate), import, tour, diagnostics | changed | The **Theater**: project cards play a looping preview; New project asks for a name, a mood and a Look; the card menu shares a .loweypack, archives, duplicates. Diagnostics moved to Settings. |
| Samples | Welcome island (fly-through + tour) | kept | Theater ▸ Samples; the tour starts from Settings or the first launch. |
| Samples | Enigma sets (desk, room of 12 PCs, cave robot), "4 · Opening (animated)", "5 · The story (narrated)" | kept | Theater ▸ Samples. The Engine tests render every set and export the opening and the story end to end. |
| Modes | Build · Animate · Camera · Look · Export mode switcher | changed | One editor instead of five modes: tool panels in the sidebar (Select, Build, Draw, Transform, Look, Cast, Inspector, Library, Actions), the stage in the middle, the timeline below. Nothing hides behind a mode any more. |
| Tools | Select & move, Lasso select, Draw in 3D, Scatter | kept | Select (with lasso and Select similar), Draw, Build ▸ Scatter. |
| Add | Primitives (cube, sphere, cylinder, cone, plane, torus, ramp), light, camera, Character, Blob, Text, overlays, Effects, Photo or video | kept | Build panel. Primitives get a small bevel by default (Bevel in the inspector). |
| Draw | Guides (Facing me / Ground / Front / Side, Box, Cylinder, Sphere, On object), Tube / Ribbon / Extrude / Lathe, mirror, Pencil-only, QuickShape | kept | Draw panel and its options bar. New beside it: the **Shadow Brush** paints shadow shapes onto surfaces. |
| Transform | Gizmo move / rotate / scale, two-finger twist & pinch on the selection, snapping | kept | Transform panel; snapping in its options. |
| Transform | On-screen joystick (stick = X/Z, slider = Y), joystick speed | changed | Optional and off by default (Transform ▸ Joystick). Direct touch does the same job in most cases. |
| Build ops | Array, Scatter, group / ungroup, align / distribute, Swap blockout → model, Save to library, Save & link (prefab) | kept | Build and Actions panels. |
| Library | Search-first panel, filters, import USDZ / glTF / GLB / OBJ / folder, share sheet "Open in", drag onto stage, RIGGED badge | kept | Library panel. glTF now loads through a pure-Swift reader in LoweyCore (no GLTFKit2). |
| Look | 6 moods, palette with linked slots + eyedropper, fog, stars, ground, shading Smooth / Flat | changed | Moods and the palette stay; on top of them a **Look** decides how everything is drawn: Ink, Comic, Sketch, Clay, Low-poly, or your own (duplicate one, change it, save it). A Look can be overridden per scene. |
| Look | Finish presets (Clean, Cinematic, Dreamy, Retro, Comic, Collage, Old film) + sliders | kept | Look ▸ Finish. |
| Look | Depth-based ink outlines | changed | Lines are drawn by the renderer's line pass (the Ink and Comic Looks), and Finish ▸ Outline adds lines over any Look. |
| Animate | Auto-key, ◆ Key, 15 presets with order / delay / randomness | changed | Presets and stagger are in Inspector ▸ Motion. Auto-key belongs to the timeline's **Keyframe** mode; Compose (the default) never creates keys by accident. |
| Animate | Behaviours (follow path, look at, orbit, wobble, wind sway, float, spin; bake) | kept | Inspector ▸ Motion. |
| Animate | Fall / Explode / Flock, Scripts panel (JavaScript) | kept | Inspector ▸ Motion; Actions ▸ Scripts. |
| Timeline | Compose / Perform / Keyframe, Select + Pick, easing curve editor, copy / paste / mirror / reverse / faster / slower, markers, loop, lanes, track groups | kept | The timeline under the stage (collapsible). |
| Perform | Record with 3-2-1, drag / pinch / twist / Pencil roll captured as keys, smoothing | kept | Timeline ▸ Perform. |
| Camera | Save camera from view, Cut here | kept | Cast and timeline; **Frame shot** (new) places a camera on the selection with a shot size and composition. |
| Camera | Look through (pan / tilt, move, dolly, roll) | changed | **Director view** (⌥⌘D): see through the shot camera with the delivery frame marked; drag aims, two fingers move, pinch dollies, twist rolls, all keyed. |
| Camera | 11 moves, length / strength, focal length + focus pull, transitions, Match cut | kept | Inspector ▸ Camera. |
| Camera | 9:16 framing, iPad as camera (ARKit), camera Perform | kept | |
| Camera | Moving-around speed (orbit, pan, zoom) | kept | Settings ▸ Navigation speed. |
| Characters | Character builder (humanoid puppet) + 10 built-in clips | kept | Cast panel. |
| Characters | Imported rigs (Mixamo / Quaternius) with retargeting, IK, clip mixer | kept | Cast ▸ Clips. Skinning now runs on the GPU. |
| Characters | Blob builder (hat, hair, accessories, prop, mark, Likeness table), 12 expressions, springs, squash & stretch | kept | Cast panel. |
| Voice | Record voiceover, import audio, Transcribe (SpeechAnalyzer), Words lane, snapping, Transcript sheet, placeholder voice | kept | Audio & Words (⇧⌘U), Transcript (⇧⌘T), Record voiceover (⌥⌘R). Transcription goes through hmm-kit's engine selector. |
| Face | Lip sync (CMUdict + rules, Arabic, Italian), Face (front camera, Vision), Use my iPhone (ARKit companion), rest pose, hands via body tracking | kept | Cast panel and the face preview. |
| Overlays | Titles, labels, big X, ?, !, ✓, ★, arrows; captions (Punchy, Subtitle, Pill, Outline) + .srt | kept | Same drawing code on the stage and in the export. |
| VFX | 10 particle types; screen effects (flash, shake, speed lines, zoom blur, glitch) | kept | Screen effects and transitions are now one Metal composite pass. |
| Media | Photos / videos as cards in 3D, Manim renders (ProRes 4444 alpha via the laptop) | kept | |
| Export | PNG snapshot 16:9 / 9:16 / 1:1 HD / 4K | kept | Export sheet. |
| Export | Video 16:9 + 9:16, H.264 / HEVC .mp4, HEVC-alpha .mov, PNG sequence, background export, Share / Save to Photos | changed | **Presets**: YouTube 4K, 1080p, Shorts / Reels 9:16, Square, Transparent (HEVC alpha), PNG still HD / 4K, GIF loop, 3D (GLB / USDZ), Captions (.srt). Exports are verified (frames, size, length, audio, alpha) before they're handed over. In the background the export keeps going as an iPadOS continued-processing task with a Live Activity, and a notification when it's done. |
| Export | GIF | new | GIF loop preset. |
| Export | GLB / USDZ 3D export | kept | Export sheet ▸ 3D model. |
| AI | Scene Script v2 (paste or bridge), ScriptCompiler → one undo step, proposal Apply / Not now | kept | Proposals appear as a banner over the stage. Paste a Scene Script: ⌥⌘V. |
| Bridge | HTTP :7717 + WS :7718, Bonjour `_lowey._tcp`, on by default, permanent code 000000, background keep-alive | changed | hmm-kit's bridge: **off until you turn it on**, Bonjour `_hmm._tcp`, pairing with a **one-time code** traded for a token kept in the Keychain; paired laptops are listed and can be revoked; unpaired requests are refused. The background keep-alive stays for sideloaded builds and is switched off in the App Store configuration. |
| Laptop | lowey-mcp (17 tools), lowey-link (pair, push, audio, pull, media, manim, generate tree) | changed | Same tools; `lowey-link pair <code>` needs the code the iPad shows. The MCP surface becomes 16 intent tools in phase 2. |
| Laptop | `lowey-mcp --public`, `--tunnel`, `--own-tunnel` | dropped | No internet mode. A creative tool shouldn't be an open door; `lowey-mcp --http` serves on 127.0.0.1 only. |
| Rendering | RealityKit renderer, fog/glow surface shader, Core Image compositor, light budget (8 lights / 2 shadows), preview resolution under load, per-pixel grid, ground melting into the sky | changed | **LoweyRender 2** on Metal: one renderer for the stage, thumbnails and export (the preview is the export, tested). Reverse-Z, MSAA, sun shadow cascades, ID-buffer picking, a line pass, GPU skinning, instanced repeats, up to 16 point and spot lights (only the sun casts shadows), dynamic resolution with MetalFX upscaling on device. Zero RealityKit. |
| Misc | Focus mode | changed | Hide interface (⌃⌘F). |
| Misc | Stats pill | changed | Settings ▸ Diagnostics: a performance HUD over the stage (fps, frame-time p50 / p95 / p99, dropped frames, thermal state, memory), the Night Market benchmark (writes a JSON report) and log export. |
| Misc | Gesture guide, tour, diagnostics, thermal handling, Pencil hover, Pencil Pro squeeze = play / pause | kept | Settings ▸ Gestures; dynamic resolution steps down when the device is hot. |
| Misc | Keyboard shortcuts | changed | ⌘1–5 open the Select, Build, Draw, Transform and Look panels (there are no modes); the rest are kept, plus ⌥⌘D Director view and ⌘L Library. |
| Misc | Localisation scaffold (Localizable.xcstrings) | kept | `App/Resources/Localizable.xcstrings`. |
| Documents | `.lowey` folder, .bak recovery, autosave, `.loweypack` | kept | iCloud Drive in the App Store build; on a sideloaded build (which can't carry the iCloud entitlement) projects stay on the device. |
| Identity | Bundle id `com.hesham.lowey` | changed | `studio.hmm.lowey`. A 2.0 install sits next to a 1.x install; open 1.x projects through Files or the share sheet. |
