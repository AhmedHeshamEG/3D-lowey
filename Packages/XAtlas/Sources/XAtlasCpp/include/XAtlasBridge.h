// A small C face over xatlas (MIT, vendored in xatlas-src/). Swift imports this header as plain C, so nothing above
// this package needs C++ interop.
#ifndef XATLAS_BRIDGE_H
#define XATLAS_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// An unwrapped mesh: xatlas splits vertices along chart seams, so it has its own vertices, each pointing back at the
/// input vertex it came from, with a uv in 0…1 (square: the longer side of the atlas is 1).
typedef struct {
    uint32_t *xref;        // 1 per output vertex: the input vertex
    float *uvs;            // 2 floats per output vertex
    size_t vertexCount;
    uint32_t *indices;     // 3 per triangle, the input's triangles in the input's order
    size_t indexCount;
    uint32_t chartCount;
} XAUnwrap;

typedef enum {
    XAOk = 0,
    XAInvalidInput = 1,    // no triangles, an index out of range, non-finite positions
    XAFailed = 2           // xatlas made no atlas (or more than one)
} XAStatus;

/// Charts and packs `indexCount / 3` triangles into one square atlas. `padding` is in texels of a `resolution`-sized
/// texture. Single-threaded and seeded, so the same mesh always unwraps the same way. On XAOk, `result` owns new
/// buffers the caller frees with XAUnwrapFree.
XAStatus XAUnwrapMesh(const float *positions, const float *normals, size_t vertexCount, const uint32_t *indices, size_t indexCount,
                      uint32_t resolution, uint32_t padding, XAUnwrap *result);

void XAUnwrapFree(XAUnwrap *unwrap);

#ifdef __cplusplus
}
#endif

#endif
