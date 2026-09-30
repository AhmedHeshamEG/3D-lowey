# Migration: 3D-lowey v1.4.3 → 2.0

Every feature of v1.4.3 (`legacy/v1`, tag `v1-final`) and what happened to it in 2.0: **kept** (same behaviour on the
new engine and layout), **changed** (still there, working differently, with the reason) or **dropped** (gone, with
the reason). Status is filled in as the port lands; nothing ships as "pending".

| Area | v1.4.3 feature | 2.0 | Where / why |
|---|---|---|---|
| Home | Projects grid, New project (name + mood), long-press menu (share .loweypack, archive, duplicate), import, tour, diagnostics | pending | |
| Samples | Welcome island (fly-through + tour) | pending | |
| Samples | Enigma sets (desk, room of 12 PCs, cave robot), "4 · Opening (animated)", "5 · The story (narrated)" | pending | |
| Modes | Build · Animate · Camera · Look · Export mode switcher | pending | |
| Tools | Select & move, Lasso select, Draw in 3D, Scatter | pending | |
| Add | Primitives (cube, sphere, cylinder, cone, plane, torus, ramp), light, camera, Character, Blob ("Me", "Blob"), Text, On the frame overlays, Effects, Photo or video | pending | |
| Draw | Guides (Facing me / Ground / Front / Side, Box, Cylinder, Sphere, On object), styles Tube / Ribbon / Extrude / Lathe, mirror, Pencil-only, QuickShape | pending | |
| Transform | Gizmo move / rotate / scale, two-finger twist & pinch on the selection, snapping | pending | |
| Transform | On-screen joystick (stick = X/Z, green slider = Y), joystick speed slider | pending | |
| Build ops | Array (row / grid / circle), Scatter, group / ungroup, align / distribute, Swap blockout → model, Save to library, Save & link (prefab) | pending | |
| Library | Search-first panel, filters All / Favorites / Recent / Models / Built / Looks, import USDZ / glTF / GLB / OBJ / folder, share sheet "Open in", drag onto stage, RIGGED badge | pending | |
| Look | 6 moods (Day, Golden hour, Dusk, Night, Space, Studio), palette with linked slots + eyedropper, fog, stars, ground, shading Smooth / Flat | pending | |
| Look | Finish presets (Clean, Cinematic, Dreamy, Retro, Comic, Collage, Old film) + sliders | pending | |
| Look | Depth-based ink outlines (Finish ▸ outline) | pending | |
| Animate | Auto-key, ◆ Key, 15 presets with order / delay / randomness | pending | |
| Animate | Behaviours (follow path, look at, orbit, wobble, wind sway, float, spin; bake) | pending | |
| Animate | Fall / Explode / Flock, Scripts panel (JavaScript) | pending | |
| Timeline | Compose / Perform / Keyframe, Select + Pick, easing curve editor, copy / paste / mirror / reverse / faster / slower, markers, loop, lanes (Camera, Voiceover, Words, Effects, Envelope), track groups | pending | |
| Perform | Record with 3-2-1, drag / pinch / twist / Pencil roll captured as keys, smoothing | pending | |
| Camera | Save camera from view, Cut here, Look through (pan / tilt, move, dolly, roll) | pending | |
| Camera | 11 moves, Length / Strength, focal length + focus pull, transitions (Cut, Fade, Dip to black, Wipe, Zoom through), Match cut | pending | |
| Camera | 9:16 framing (zoom / pan), iPad as camera (ARKit), camera Perform | pending | |
| Camera | Moving-around speed (orbit, pan, zoom) | pending | |
| Characters | Character builder (humanoid puppet) + 10 built-in clips | pending | |
| Characters | Imported rigs (Mixamo / Quaternius) with retargeting, IK, clip mixer | pending | |
| Characters | Blob builder (hat, hair, accessories, prop, mark, Likeness table), 12 expressions, springs, squash & stretch | pending | |
| Voice | Record voiceover, import audio, Transcribe (SpeechAnalyzer), Words lane, snapping, Transcript sheet (jump, phrase → animate / camera move / cut / marker / fix words), placeholder voice | pending | |
| Face | Lip sync (CMUdict + rules, Arabic, Italian), Face (front camera, Vision), Use my iPhone (ARKit companion), rest pose, hands via body tracking | pending | |
| Overlays | Titles, labels, big X, ?, !, ✓, ★, arrows; captions (Punchy, Subtitle, Pill, Outline) + .srt | pending | |
| VFX | 10 particle types; screen effects (flash, shake, speed lines, zoom blur, glitch) | pending | |
| Media | Photos / videos as cards in 3D, Manim renders (ProRes 4444 alpha via the laptop) | pending | |
| Export | PNG snapshot 16:9 / 9:16 / 1:1 HD / 4K | pending | |
| Export | Video 16:9 + 9:16, H.264 / HEVC .mp4, transparent HEVC-alpha .mov, PNG sequence, background export, Share / Save to Photos | pending | |
| Export | GLB / USDZ 3D export | pending | |
| AI | Scene Script v2 (paste or bridge), ScriptCompiler → one undo step, Proposal sheet Apply / Not now | pending | |
| Bridge | HTTP :7717 + WS :7718, Bonjour `_lowey._tcp`, on by default, permanent code 000000, background keep-alive | pending | |
| Laptop | lowey-mcp (17 tools), lowey-link (pair, push, audio, pull, media, manim, generate tree) | pending | |
| Laptop | `lowey-mcp --public` (internet exposure via UPnP + Let's Encrypt) | pending | |
| Rendering | RealityKit renderer, fog/glow surface shader, Core Image compositor, live light budget (8 lights / 2 shadows), preview resolution under load, per-pixel grid, ground melting into the sky | pending | |
| Misc | Focus mode, stats pill, gesture guide, tour, diagnostics, thermal handling, Pencil hover, Pencil Pro squeeze = play / pause | pending | |
| Misc | Keyboard shortcuts (⌘1–5 modes, Space, ⌘K, ⌘M, ⇧⌘T, ⇧⌘U, ⌥⌘R, ⇧⌘B, ⌥⌘V, ⇧⌘P, ⌥←/→, ⇧⌘R, ⌘Z / ⇧⌘Z, ⌃⌘F) | pending | |
| Misc | Localisation scaffold (Localizable.xcstrings) | pending | |
| Documents | `.lowey` folder (project.json, scenes/, assets/, audio/, renders/, thumbnail.png), .bak recovery, autosave, `.loweypack` | pending | |
