# Vendored: Manifold

- Upstream: https://github.com/elalish/manifold, tag `v3.5.4` (commit `ce50d78`).
- Licence: Apache-2.0 (`LICENSE-manifold.txt`), credited in the app's LICENSES.md.
- Copied unchanged: `src/*.{cpp,h}` → `Sources/ManifoldCpp/manifold-src/`, `include/manifold/*.h` →
  `Sources/ManifoldCpp/manifold-include/manifold/` (minus `cross_section.h`; no 2D cross sections, so no Clipper2).
- Built single-threaded (`MANIFOLD_PAR=-1`, no TBB) without iostream (`MANIFOLD_NO_IOSTREAM`).
- Ours: `Sources/ManifoldCpp/ManifoldBridge.cpp` and `include/ManifoldBridge.h`, a C face Swift imports without
  C++ interop.

To update: copy the same folders from a newer tag, delete `cross_section.h`, run the package's tests and
LoweyCore's boolean tests, change the tag above.
