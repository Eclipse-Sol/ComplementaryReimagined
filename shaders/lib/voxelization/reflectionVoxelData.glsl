#extension GL_ARB_gpu_shader5 : enable
#extension GL_ARB_shading_language_packing : enable

#include "/lib/voxelization/reflectionTextureMapping.glsl"
#include "/lib/voxelization/reflectionFaceGeometry.glsl"

struct faceData {
    vec3 glColor;
    vec2 lightmap;
    vec3 textureBounds;

};

#if defined SHADOW && defined VERTEX_SHADER || defined SHAPE_BUILD
    #define SSBO_QUALIFIER
#else
    #define SSBO_QUALIFIER readonly
#endif

#if WORLD_SPACE_PLAYER_REF == 1
    #include "/lib/voxelization/SSBOs/playerVerticesBuffer.glsl"
#endif

#include "/lib/voxelization/SSBOs/blockDataBuffer.glsl"
#if WORLD_SPACE_SHAPES > 0
    #include "/lib/voxelization/SSBOs/shapeDataBuffer.glsl"
#endif

uint GetReflectionCellGeneration(ivec3 cell, int packedRegionOrigin) {
    #if WORLD_SPACE_SHAPES > 0
        return shapeDataSSBO.regionGenerations[GetReflectionCellRegion(cell, packedRegionOrigin)];
    #else
        return blockDataSSBO.faceGeneration;
    #endif
}

reflectionCellHandle GetReflectionCellHandle(ivec3 cell, ivec3 storageOrigin, int packedRegionOrigin) {
    ivec3 p = WrapReflectionStoragePosition(cell, storageOrigin, sceneVoxelVolumeSize);
    return reflectionCellHandle(GetSceneVoxelIndexFromStorage(p),
                              GetReflectionCellGeneration(cell, packedRegionOrigin));
}

reflectionCellHandle GetReflectionCellHandle(ivec3 cell) {
    #if WORLD_SPACE_SHAPES > 0
        return GetReflectionCellHandle(cell, PositiveModulo(GetReflectionVolumeOrigin(), sceneVoxelVolumeSize), GetPackedRegionTileOffset());
    #else
        return GetReflectionCellHandle(cell, ivec3(0), 0);
    #endif
}

// Opposite sides of a boundary belong to different blocks
 int GetFaceRecordSlot(ivec3 voxelPos, vec3 normal) {
    return 6 * GetSceneVoxelIndex(voxelPos) + GetReflectionFaceIndex(normal);
}

uvec3 PackFaceData(faceData data) {
    uvec3 uv = uvec3(clamp(round(data.textureBounds * 65536.0), 0.0, 65535.0));
    uvec2 lightmap = uvec2(clamp(data.lightmap * 4096.0, 0.0, 4095.0));
    return uvec3((uv.x << 16u) | uv.y,
                 uv.z | (lightmap.x << 16u) | ((lightmap.y & 15u) << 28u),
                 packUnorm4x8(vec4(data.glColor, 0.0)) | ((lightmap.y >> 4u) << 24u));
}

vec2 UnpackFaceLightmap(uvec3 data) {
    return vec2((data.y >> 16u) & 4095u, (data.y >> 28u) | ((data.z >> 24u) << 4u)) / 4096.0;
}

uvec3 PackReflectionFaceData(faceData face, uint orientation) {
    uvec3 data = PackFaceData(face);
    data.y = (data.y & 0xf000ffffu) | (((data.y >> 19u) & 511u) << 16u) | (orientation << 25u);
    return data;
}

faceData UnpackReflectionFaceData(uvec3 data, out uint orientation) {
    orientation = (data.y >> 25u) & 7u;
    vec2 lightmap = vec2((data.y >> 16u) & 511u, (data.y >> 28u) | ((data.z >> 24u) << 4u)) / vec2(512.0, 4096.0);
    return faceData(unpackUnorm4x8(data.z).xyz, lightmap,
                    vec3(data.x >> 16u, data.x & 65535u, data.y & 65535u) / 65536.0);
}

uvec3 ReadReflectionFace(reflectionCellHandle cell, vec3 normal) {
    if (!ReflectionStorageAvailable()) return uvec3(0u);
    int face = 6 * cell.storageIndex + GetReflectionFaceIndex(normal);
    #if defined SHADOW && defined VERTEX_SHADER
        uint reference = atomicAdd(blockDataSSBO.faceRefs[face], 0u);
    #else
        uint reference = blockDataSSBO.faceRefs[face];
    #endif
    uint pointer = reference & reflectionFacePointerMask;
    #if WORLD_SPACE_SHAPES > 0
        if (pointer == 0u || pointer > 2u * reflectionFaceCapacity) return uvec3(0u);
    #else
        if (pointer == 0u || pointer > reflectionFaceCapacity) return uvec3(0u);
    #endif
    uint regionGeneration = cell.regionGeneration;
    if (regionGeneration == 0u) return uvec3(0u);
    uint stamp = reference & reflectionFaceStampMask;
    uint recordGeneration = regionGeneration;
    if (stamp != ((regionGeneration << 22u) & reflectionFaceStampMask)) {
        #if defined SHADOW && defined VERTEX_SHADER
            #if WORLD_SPACE_SHAPES > 0
                recordGeneration = shapeDataSSBO.previousRegionGeneration;
            #else
            recordGeneration = regionGeneration - 1u;
            #endif
            if (stamp != ((recordGeneration << 22u) & reflectionFaceStampMask)) return uvec3(0u);
        #else
            return uvec3(0u);
        #endif
    }
    #if defined SHADOW && defined VERTEX_SHADER
        memoryBarrier();
    #endif
    #if WORLD_SPACE_SHAPES > 0
        uint index = pointer - 1u;
    #else
        uint index = (recordGeneration & 1u) * reflectionFaceCapacity + pointer - 1u;
    #endif
    uvec4 record = blockDataSSBO.faces[index];
    return record.w == recordGeneration ? record.xyz : uvec3(0u);
}

 faceData GetFaceData(reflectionCellHandle cellRef, vec3 normal, out uint orientation) {
    faceData face = UnpackReflectionFaceData(ReadReflectionFace(cellRef, normal), orientation);
    orientation ^= GetDefaultReflectionFaceOrientation(normal);
    return face;
}

faceData GetFaceData(reflectionCellHandle cellRef, vec3 normal) {
    uint orientation;
    return GetFaceData(cellRef, normal, orientation);
}

faceData GetFaceData(ivec3 cell, vec3 normal) {
    return GetFaceData(GetReflectionCellHandle(cell), normal);
}

int GetShapeStateWordIndex(int voxelIndex) {
    return lavaCornerCount + voxelIndex;
}

faceData GetLavaFaceData(reflectionCellHandle cellRef, out mat2 textureRotation) {
    uvec3 data = ReadReflectionFace(cellRef, vec3(0.0, 1.0, 0.0));
    uint origin = data.x;
    uint bits = data.y;
    float angle = float((bits >> 16u) & 255u) * (6.28318530718 / 256.0);
    vec2 rotation = vec2(cos(angle), sin(angle));
    textureRotation = mat2(rotation, vec2(-rotation.y, rotation.x));
    return faceData(vec3(1.0),
                    vec2((bits >> 24u) & 15u, bits >> 28u) / 15.0,
                    vec3(origin >> 16u, origin & 65535u, bits & 65535u) / 65536.0);
}

int GetLavaCornerIndex(ivec3 corner) {
    return corner.x + (sceneVoxelVolumeSize.x + 1) * (corner.y + sceneVoxelVolumeSize.y * corner.z);
}

uint GetLavaFrameStamp() {
    #if WORLD_SPACE_SHAPES > 0
        return blockDataSSBO.lavaRefreshFrame << 12u;
    #else
        return uint(frameCounter + 1) << 12u;
    #endif
}

float GetLavaCornerHeight(ivec3 corner) {
    if (!ReflectionStorageAvailable()) return 1.0;
    uint data = blockDataSSBO.metadata[GetLavaCornerIndex(corner)];
    return (data & 0xfffff000u) == GetLavaFrameStamp() ? float(data & 4095u) / 4095.0 : 1.0;
}

float GetReflectionLightBlend() {
    #if WORLD_SPACE_SHAPES > 0
        return 1.0 - pow(0.99, float(reflectionActiveRegionCount));
    #else
        return 0.01;
    #endif
}

#if defined SHADOW && defined VERTEX_SHADER
void MergeStampedWord(int index, uint payload, uint stamp, bool keepMax) {
    if (!ReflectionStorageAvailable()) return;
    uint newData = stamp | payload;
    uint oldData = atomicAdd(blockDataSSBO.metadata[index], 0u);
    while (true) {
        uint updated = newData;
        if ((oldData & 0xfffff000u) == stamp) updated = keepMax ? max(oldData, newData) : oldData | newData;
        if (updated == oldData) break;
        uint previous = atomicCompSwap(blockDataSSBO.metadata[index], oldData, updated);
        if (previous == oldData) break;
        oldData = previous;
    }
}

void StoreLavaCorner(ivec3 corner, float height) {
    MergeStampedWord(GetLavaCornerIndex(corner), uint(round(height * 4095.0)), GetLavaFrameStamp(), true);
}

uint CaptureReflectionFace(uvec3 data) {
    if (!ReflectionStorageAvailable()) return 0u;
    uint slot = atomicAdd(blockDataSSBO.faceAllocationAttempts, 1u);
    #if WORLD_SPACE_SHAPES > 0
        uint capacity = 2u * reflectionFaceCapacity;
        if (slot >= blockDataSSBO.allocationCapacity) {
            return 0u;
        }
        uint generation = shapeDataSSBO.captureFrame;
        uint index = GetReflectionRingIndex(blockDataSSBO.allocationStartIndex, slot, capacity);
        slot = index;
    #else
    if (slot >= reflectionFaceCapacity) {
        return 0u;
    }
    uint generation = blockDataSSBO.faceGeneration;
    uint index = (generation & 1u) * reflectionFaceCapacity + slot;
    #endif
    blockDataSSBO.faces[index] = uvec4(data, generation);
    memoryBarrier();
    return ((generation << 22u) & reflectionFaceStampMask) | (slot + 1u);
}

void PublishReflectionFace(ivec3 voxelPos, vec3 normal, uint reference) {
    if (reference != 0u) atomicExchange(blockDataSSBO.faceRefs[GetFaceRecordSlot(voxelPos, normal)], reference);
}

void StoreLavaFaceData(ivec3 voxelPos, vec2 origin, float textureRad, float textureRotation) {
    uvec3 uv = uvec3(clamp(round(vec3(origin, textureRad) * 65536.0), 0.0, 65535.0));
    uvec2 lightmap = uvec2(round(clamp(vec2(lmCoord.x * 0.99 + 0.001, lmCoord.y), 0.0, 1.0) * 15.0));
    uint angle = uint(round(fract(textureRotation / 6.28318530718) * 256.0)) & 255u;
    uvec3 data = uvec3((uv.x << 16u) | uv.y,
                     uv.z | (angle << 16u) | (lightmap.x << 24u) | (lightmap.y << 28u), 0u);
    PublishReflectionFace(voxelPos, vec3(0.0, 1.0, 0.0), CaptureReflectionFace(data));
}

void StoreReflectionFace(ivec3 voxelPos, vec3 normal, uvec3 data) {
    PublishReflectionFace(voxelPos, normal, CaptureReflectionFace(data));
}

void StoreFaceData(ivec3 voxelPos, vec3 normal, vec2 origin, float textureRad, uint orientation,
                   bool storeToAllFaces, bool storeToAllFacesExceptTop, vec3 playerPos) {
    vec2 lmCoordM = lmCoord;

    if (storeToAllFaces || storeToAllFacesExceptTop) {
        #if WORLD_SPACE_SHAPES > 0
            vec3 voxelPosPrevious = vec3(voxelPos);
        #else
            vec3 playerPosPrevious = playerPos - previousCameraPosition + cameraPosition;
            vec3 voxelPosPrevious = PlayerToPreviousSceneVoxel(playerPosPrevious);
        #endif
        if (CheckInsideSceneVoxelVolume(voxelPosPrevious)) {
            faceData oldFaceData = GetFaceData(ivec3(voxelPosPrevious), normal);
            float lightBlend = GetReflectionLightBlend();
            lmCoordM = mix(max(lmCoord, oldFaceData.lightmap), lmCoord, lightBlend);
        }
    }

    vec2 faceLightmap = vec2(lmCoordM.x * 0.99 + 0.001, lmCoordM.y);
    uvec3 newData = PackReflectionFaceData(faceData(glColor.rgb, faceLightmap, vec3(origin, textureRad)), orientation);
    uint reference = CaptureReflectionFace(newData);

    if (storeToAllFaces || storeToAllFacesExceptTop) {
        vec3 faceOffsets[6] = vec3[6](
            vec3( 0.0,  1.0,  0.0),
            vec3( 0.0,  0.0,  1.0),
            vec3( 1.0,  0.0,  0.0),
            vec3( 0.0,  0.0, -1.0),
            vec3( 0.0, -1.0,  0.0),
            vec3(-1.0,  0.0,  0.0)
        );

        int start = 0 + int(storeToAllFacesExceptTop);
        for(int i = start; i < 6; i++) {
            PublishReflectionFace(voxelPos, faceOffsets[i], reference);
        }
    } else {
        PublishReflectionFace(voxelPos, normal, reference);
    }
}
#endif
