# Vendored: xatlas

- Upstream: https://github.com/jpcy/xatlas, `master` at commit `f700c77` (2022-07-25; the project has no tags).
- Licence: MIT (`LICENSE-xatlas.txt`), credited in the app's LICENSES.md.
- Copied unchanged: `source/xatlas/xatlas.{cpp,h}` → `Sources/XAtlasCpp/xatlas-src/`.
- Built single-threaded (`XA_MULTITHREADED=0`) without its debug checks (`XA_DEBUG=0`, `XA_DEBUG_ASSERT` off: upstream's asserts name
  debug-only variables): the same mesh always unwraps
  the same way, which painted documents rely on (their unwrap is also stored, so an update can't move old paint).
- Ours: `Sources/XAtlasCpp/XAtlasBridge.cpp` and `include/XAtlasBridge.h`, a C face Swift imports without C++ interop.

To update: copy the two files from a newer commit, run this package's tests and LoweyCore's unwrap tests, change the
commit above.
