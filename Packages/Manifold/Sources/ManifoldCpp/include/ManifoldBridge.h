// A small C face over Manifold (Apache-2.0, vendored in manifold-src/ and manifold-include/).
// Swift imports this header as plain C, so nothing above this package needs C++ interop.
#ifndef MANIFOLD_BRIDGE_H
#define MANIFOLD_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// A triangle mesh: xyz positions, counter-clockwise triangles, and one face tag per triangle
/// (the caller's polygon it came from; tags survive the boolean so faces can be rebuilt).
typedef struct {
    float *positions;      // 3 floats per vertex
    size_t vertexCount;
    uint32_t *triangles;   // 3 indices per triangle
    uint32_t *faceTags;    // 1 per triangle
    size_t triangleCount;
} MBMesh;

typedef enum { MBUnion = 0, MBSubtract = 1, MBIntersect = 2 } MBOperation;

typedef enum {
    MBOk = 0,
    MBNotManifold = 1,     // an input isn't a closed, consistently wound solid
    MBInvalidInput = 2,    // non-finite or out-of-range data
    MBFailed = 3           // anything else Manifold reported
} MBStatus;

/// Combines `a` and `b`. On MBOk, `result` owns new buffers the caller frees with MBMeshFree.
/// Face tags in the result are `a`'s tags for triangles from `a`, and `b`'s tags + `tagOffsetB` from `b`.
MBStatus MBBoolean(const MBMesh *a, const MBMesh *b, MBOperation op, uint32_t tagOffsetB, MBMesh *result);

/// Checks that a mesh is a closed manifold solid as Manifold sees it (after merging coincident vertices).
MBStatus MBValidate(const MBMesh *mesh);

void MBMeshFree(MBMesh *mesh);

#ifdef __cplusplus
}
#endif

#endif
