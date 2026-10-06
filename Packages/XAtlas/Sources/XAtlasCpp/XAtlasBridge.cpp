// The C face over xatlas. Ours (not vendored): see VENDORED.md.
#include "XAtlasBridge.h"
#include "xatlas.h"

#include <cmath>
#include <cstdlib>
#include <cstring>

extern "C" XAStatus XAUnwrapMesh(const float *positions, const float *normals, size_t vertexCount, const uint32_t *indices,
                                 size_t indexCount, uint32_t resolution, uint32_t padding, XAUnwrap *result) {
    if (result == nullptr || positions == nullptr || indices == nullptr || vertexCount == 0 || indexCount < 3 || indexCount % 3 != 0) {
        return XAInvalidInput;
    }
    std::memset(result, 0, sizeof(XAUnwrap));
    for (size_t i = 0; i < vertexCount * 3; i++) {
        if (!std::isfinite(positions[i])) { return XAInvalidInput; }
    }
    for (size_t i = 0; i < indexCount; i++) {
        if (indices[i] >= vertexCount) { return XAInvalidInput; }
    }
    xatlas::Atlas *atlas = xatlas::Create();
    xatlas::MeshDecl mesh;
    mesh.vertexPositionData = positions;
    mesh.vertexPositionStride = sizeof(float) * 3;
    if (normals != nullptr) {
        mesh.vertexNormalData = normals;
        mesh.vertexNormalStride = sizeof(float) * 3;
    }
    mesh.vertexCount = (uint32_t)vertexCount;
    mesh.indexData = indices;
    mesh.indexCount = (uint32_t)indexCount;
    mesh.indexFormat = xatlas::IndexFormat::UInt32;
    if (xatlas::AddMesh(atlas, mesh) != xatlas::AddMeshError::Success) {
        xatlas::Destroy(atlas);
        return XAInvalidInput;
    }
    xatlas::ChartOptions charts;
    charts.fixWinding = true;
    xatlas::PackOptions pack;
    // One atlas whose texel density is estimated for a square of `resolution`; padding in its texels.
    pack.resolution = 0;
    pack.texelsPerUnit = 0;
    pack.padding = padding;
    pack.bilinear = true;
    pack.blockAlign = false;
    xatlas::Generate(atlas, charts, pack);
    if (atlas->meshCount != 1 || atlas->width == 0 || atlas->height == 0 || atlas->atlasCount > 1) {
        xatlas::Destroy(atlas);
        return XAFailed;
    }
    const xatlas::Mesh &out = atlas->meshes[0];
    // The estimate targets 1024 texels; scale the padding to the texture the caller paints.
    const float side = (float)(atlas->width > atlas->height ? atlas->width : atlas->height);
    (void)resolution;
    result->vertexCount = out.vertexCount;
    result->indexCount = out.indexCount;
    result->chartCount = out.chartCount;
    result->xref = (uint32_t *)std::malloc(sizeof(uint32_t) * out.vertexCount);
    result->uvs = (float *)std::malloc(sizeof(float) * 2 * out.vertexCount);
    result->indices = (uint32_t *)std::malloc(sizeof(uint32_t) * out.indexCount);
    if (result->xref == nullptr || result->uvs == nullptr || result->indices == nullptr) {
        XAUnwrapFree(result);
        xatlas::Destroy(atlas);
        return XAFailed;
    }
    for (uint32_t i = 0; i < out.vertexCount; i++) {
        result->xref[i] = out.vertexArray[i].xref;
        result->uvs[i * 2] = out.vertexArray[i].uv[0] / side;
        result->uvs[i * 2 + 1] = out.vertexArray[i].uv[1] / side;
    }
    std::memcpy(result->indices, out.indexArray, sizeof(uint32_t) * out.indexCount);
    xatlas::Destroy(atlas);
    return XAOk;
}

extern "C" void XAUnwrapFree(XAUnwrap *unwrap) {
    if (unwrap == nullptr) { return; }
    std::free(unwrap->xref);
    std::free(unwrap->uvs);
    std::free(unwrap->indices);
    std::memset(unwrap, 0, sizeof(XAUnwrap));
}
