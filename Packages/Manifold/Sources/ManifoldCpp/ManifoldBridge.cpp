// The C face over Manifold. See include/ManifoldBridge.h.

#include "ManifoldBridge.h"

#include <cstdlib>
#include <cstring>
#include <exception>

#include "manifold/manifold.h"

namespace {

manifold::MeshGL toMeshGL(const MBMesh *mesh, uint32_t tagOffset) {
    manifold::MeshGL gl;
    gl.numProp = 3;
    gl.vertProperties.assign(mesh->positions, mesh->positions + mesh->vertexCount * 3);
    gl.triVerts.assign(mesh->triangles, mesh->triangles + mesh->triangleCount * 3);
    gl.faceID.resize(mesh->triangleCount);
    for (size_t i = 0; i < mesh->triangleCount; ++i) {
        gl.faceID[i] = (mesh->faceTags ? mesh->faceTags[i] : 0) + tagOffset;
    }
    gl.Merge();
    return gl;
}

MBStatus statusOf(manifold::Manifold::Error error) {
    using Error = manifold::Manifold::Error;
    switch (error) {
    case Error::NoError: return MBOk;
    case Error::NotManifold: return MBNotManifold;
    case Error::NonFiniteVertex:
    case Error::VertexOutOfBounds:
    case Error::PropertiesWrongLength:
    case Error::MissingPositionProperties:
    case Error::MergeVectorsDifferentLengths:
    case Error::MergeIndexOutOfBounds:
    case Error::FaceIDWrongLength:
        return MBInvalidInput;
    default: return MBFailed;
    }
}

template <typename T> T *copyOut(const std::vector<T> &values) {
    if (values.empty()) return nullptr;
    T *out = static_cast<T *>(std::malloc(values.size() * sizeof(T)));
    if (out) std::memcpy(out, values.data(), values.size() * sizeof(T));
    return out;
}

}  // namespace

extern "C" MBStatus MBValidate(const MBMesh *mesh) {
    try {
        manifold::Manifold solid(toMeshGL(mesh, 0));
        return statusOf(solid.Status());
    } catch (const std::exception &) {
        return MBFailed;
    }
}

extern "C" MBStatus MBBoolean(const MBMesh *a, const MBMesh *b, MBOperation op, uint32_t tagOffsetB, MBMesh *result) {
    std::memset(result, 0, sizeof(MBMesh));
    try {
        manifold::Manifold left(toMeshGL(a, 0));
        if (left.Status() != manifold::Manifold::Error::NoError) return statusOf(left.Status());
        manifold::Manifold right(toMeshGL(b, tagOffsetB));
        if (right.Status() != manifold::Manifold::Error::NoError) return statusOf(right.Status());

        manifold::OpType type = op == MBUnion ? manifold::OpType::Add
            : op == MBSubtract ? manifold::OpType::Subtract : manifold::OpType::Intersect;
        manifold::Manifold combined = left.Boolean(right, type);
        if (combined.Status() != manifold::Manifold::Error::NoError) return statusOf(combined.Status());

        manifold::MeshGL out = combined.GetMeshGL();
        std::vector<float> positions;
        positions.reserve(out.NumVert() * 3);
        for (size_t v = 0; v < out.NumVert(); ++v) {
            for (int k = 0; k < 3; ++k) positions.push_back(out.vertProperties[v * out.numProp + k]);
        }
        result->positions = copyOut(positions);
        result->vertexCount = out.NumVert();
        result->triangles = copyOut(out.triVerts);
        result->faceTags = copyOut(out.faceID);
        result->triangleCount = out.NumTri();
        return MBOk;
    } catch (const std::exception &) {
        MBMeshFree(result);
        return MBFailed;
    }
}

extern "C" void MBMeshFree(MBMesh *mesh) {
    std::free(mesh->positions);
    std::free(mesh->triangles);
    std::free(mesh->faceTags);
    std::memset(mesh, 0, sizeof(MBMesh));
}
