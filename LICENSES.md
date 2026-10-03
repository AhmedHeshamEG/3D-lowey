# Third-party software

Only permissively licensed dependencies are allowed.

| Dependency | Version | License | Used for |
|---|---|---|---|
| [CMU Pronouncing Dictionary](https://github.com/cmusphinx/cmudict) | cmudict.dict (2026 master) | BSD 2-clause | Word → mouth shapes for lip sync (converted by `Tools/make_visemes.py` into `LoweyCore/Resources/visemes.txt`) |
| [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk) (laptop tool only) | ≥ 2 | MIT | `lowey-mcp`, the MCP server on the laptop (not shipped in the app) |

## The Kit (shipped in the app, `App/Resources/Kit`)

Every Kit asset is CC0 1.0 Universal (public domain). `Tools/fetch-kit.py` downloads each pack from its official page
and refuses a pack whose own licence file doesn't say CC0; each asset's `asset.json` records its pack page and licence.

| Pack | Author | Source | License |
|---|---|---|---|
| Furniture Kit | Kenney | https://kenney.nl/assets/furniture-kit | CC0 1.0 |
| Food Kit | Kenney | https://kenney.nl/assets/food-kit | CC0 1.0 |
| Nature Kit | Kenney | https://kenney.nl/assets/nature-kit | CC0 1.0 |
| City Kit (Commercial) | Kenney | https://kenney.nl/assets/city-kit-commercial | CC0 1.0 |
| City Kit (Suburban) | Kenney | https://kenney.nl/assets/city-kit-suburban | CC0 1.0 |
| City Kit (Roads) | Kenney | https://kenney.nl/assets/city-kit-roads | CC0 1.0 |
| Car Kit | Kenney | https://kenney.nl/assets/car-kit | CC0 1.0 |
| Space Kit | Kenney | https://kenney.nl/assets/space-kit | CC0 1.0 |
| Survival Kit | Kenney | https://kenney.nl/assets/survival-kit | CC0 1.0 |
| Mini Market | Kenney | https://kenney.nl/assets/mini-market | CC0 1.0 |
| Sci-Fi Essentials Kit | Quaternius | https://quaternius.itch.io/sci-fi-essentials-kit | CC0 1.0 |
| Universal Base Characters | Quaternius | https://quaternius.itch.io/universal-base-characters | CC0 1.0 |
| Universal Animation Library | Quaternius | https://quaternius.itch.io/universal-animation-library | CC0 1.0 |

CC0 asks for nothing; Kenney and Quaternius are credited in the app (Settings ▸ About ▸ Licences) all the same.

Build/CI tools (not shipped in the app): XcodeGen (MIT), SwiftLint (MIT), SwiftFormat (MIT), pytest (MIT).

[hmm-kit](https://github.com/AhmedHeshamEG/hmm-kit) (in `Packages/HmmKit`) is the same author's shared package, not a
third-party dependency. Everything else is Apple system frameworks (SwiftUI, UIKit, Metal, MetalFX, AVFoundation, Vision, ARKit, Speech,
JavaScriptCore, ActivityKit). glTF is read by LoweyCore's own reader.

### CMU Pronouncing Dictionary license (BSD 2-clause)

Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
   The contents of this file are deemed to be source code.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in
   the documentation and/or other materials provided with the
   distribution.

This work was supported in part by funding from the Defense Advanced
Research Projects Agency, the Office of Naval Research and the National
Science Foundation of the United States of America, and by member
companies of the Carnegie Mellon Sphinx Speech Consortium. We acknowledge
the contributions of many volunteers to the expansion and improvement of
this dictionary.

THIS SOFTWARE IS PROVIDED BY CARNEGIE MELLON UNIVERSITY ``AS IS'' AND
ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL CARNEGIE MELLON UNIVERSITY
NOR ITS EMPLOYEES BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
