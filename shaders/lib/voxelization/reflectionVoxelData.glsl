#extension GL_ARB_gpu_shader5 : enable
#extension GL_ARB_shading_language_packing : enable

#include "/lib/voxelization/reflectionTextureMapping.glsl"
#include "/lib/voxelization/reflectionFaceGeometry.glsl"
#include "/lib/voxelization/reflectionCornerLighting.glsl"

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

uvec3 PackReflectionTextureBounds(vec3 bounds) {
    return uvec3(clamp(round(bounds * 65536.0), 0.0, 65535.0));
}

uvec3 PackFaceData(faceData data) {
    uvec3 uv = PackReflectionTextureBounds(data.textureBounds);
    uvec2 lightmap = uvec2(round(clamp(data.lightmap, 0.0, 1.0) * 4095.0));
    return uvec3((uv.x << 16u) | uv.y,
                 uv.z | (lightmap.x << 16u) | ((lightmap.y & 15u) << 28u),
                 packUnorm4x8(vec4(data.glColor, 0.0)) | ((lightmap.y >> 4u) << 24u));
}

vec2 UnpackFaceLightmap(uvec3 data) {
    return vec2((data.y >> 16u) & 4095u, (data.y >> 28u) | ((data.z >> 24u) << 4u)) / 4095.0;
}

uvec3 PackReflectionFaceData(faceData face, uint orientation) {
    uvec3 data = PackFaceData(face);
    uint blocklight = uint(round(clamp(face.lightmap.x, 0.0, 1.0) * 511.0));
    data.y = (data.y & 0xf000ffffu) | (blocklight << 16u) | (orientation << 25u);
    return data;
}

faceData UnpackReflectionFaceData(uvec3 data, out uint orientation) {
    orientation = (data.y >> 25u) & 7u;
    vec2 lightmap = vec2((data.y >> 16u) & 511u, (data.y >> 28u) | ((data.z >> 24u) << 4u)) / vec2(511.0, 4095.0);
    return faceData(unpackUnorm4x8(data.z).xyz, lightmap,
                    vec3(data.x >> 16u, data.x & 65535u, data.y & 65535u) / 65536.0);
}

uvec3 ReadReflectionFace(reflectionCellHandle cell, vec3 normal, out uint faceIndex) {
    faceIndex = 0xffffffffu;
    if (!ReflectionStorageAvailable()) return uvec3(0u);
    #ifdef WSR_FACE_LIST
        #if defined SHADOW && defined VERTEX_SHADER
            uint head = atomicAdd(blockDataSSBO.words[cell.storageIndex], 0u);
        #else
            uint head = blockDataSSBO.words[cell.storageIndex];
        #endif
        if (cell.regionGeneration == 0u) return uvec3(0u);
        uint recordGeneration = cell.regionGeneration;
        #if defined SHADOW && defined VERTEX_SHADER
            if ((head & reflectionFaceStampMask) != GetReflectionFaceStamp(recordGeneration))
                recordGeneration = shapeDataSSBO.previousRegionGeneration;
            memoryBarrier();
        #endif
        uvec4 record;
        faceIndex = FindReflectionFaceRecord(head, uint(GetReflectionFaceIndex(normal)), recordGeneration, record);
        return record.xyz;
    #else
    int face = 6 * cell.storageIndex + GetReflectionFaceIndex(normal);
    #if defined SHADOW && defined VERTEX_SHADER
        uint reference = atomicAdd(blockDataSSBO.words[face], 0u);
    #else
        uint reference = blockDataSSBO.words[face];
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
    if (stamp != GetReflectionFaceStamp(regionGeneration)) {
        #if defined SHADOW && defined VERTEX_SHADER
            #if WORLD_SPACE_SHAPES > 0
                recordGeneration = shapeDataSSBO.previousRegionGeneration;
            #else
            recordGeneration = regionGeneration - 1u;
            #endif
            if (stamp != GetReflectionFaceStamp(recordGeneration)) return uvec3(0u);
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
    uvec4 record = LoadReflectionFaceRecord(index);
    if (record.w != recordGeneration) return uvec3(0u);
    faceIndex = index;
    return record.xyz;
    #endif
}

uvec3 ReadReflectionFace(reflectionCellHandle cell, vec3 normal) {
    uint faceIndex;
    return ReadReflectionFace(cell, normal, faceIndex);
}

faceData GetFaceData(reflectionCellHandle cellRef, vec3 normal, out uint orientation, out uint faceIndex) {
    faceData face = UnpackReflectionFaceData(ReadReflectionFace(cellRef, normal, faceIndex), orientation);
    orientation ^= GetDefaultReflectionFaceOrientation(normal);
    return face;
}

faceData GetFaceData(reflectionCellHandle cellRef, vec3 normal, out uint orientation) {
    uint faceIndex;
    return GetFaceData(cellRef, normal, orientation, faceIndex);
}

faceData GetFaceData(reflectionCellHandle cellRef, vec3 normal) {
    uint orientation;
    return GetFaceData(cellRef, normal, orientation);
}

faceData GetFaceData(ivec3 cell, vec3 normal) {
    return GetFaceData(GetReflectionCellHandle(cell), normal);
}

faceData GetLavaFaceData(reflectionCellHandle cellRef, out mat2 textureRotation, out uint faceIndex) {
    uvec3 data = ReadReflectionFace(cellRef, vec3(0.0, 1.0, 0.0), faceIndex);
    uint origin = data.x;
    uint bits = data.y;
    float angle = float((bits >> 16u) & 255u) * (6.28318530718 / 256.0);
    vec2 rotation = vec2(cos(angle), sin(angle));
    textureRotation = mat2(rotation, vec2(-rotation.y, rotation.x));
    return faceData(vec3(1.0),
                    vec2((bits >> 24u) & 15u, bits >> 28u) / 15.0,
                    vec3(origin >> 16u, origin & 65535u, bits & 65535u) / 65536.0);
}

const uint lavaFrameStampMask = 0xfffff000u;

uint GetLavaFrameStamp() {
    return (GetReflectionFrame() % 0xfffffu + 1u) << 12u;
}

#if WORLD_SPACE_SHAPES > 0
    const uint lavaCornerTagShift = 28u;
    const uint lavaCornerTagMask = 0xfu << lavaCornerTagShift;
    const uint lavaCornerMaxProbes = 1024u;

    uint GetLavaCornerTag() {
        return (GetReflectionFrame() % 15u + 1u) << lavaCornerTagShift;
    }

    uint GetLavaCornerKey(ivec3 corner) {
        return uint(corner.x) | (uint(corner.z) << 10u) | (uint(corner.y) << 20u);
    }

    // Fibonacci hashing!!
    uint GetLavaCornerHomeSlot(uint key) {
        return (key * 2654435761u) >> (32u - lavaCornerHashBits);
    }

    uint GetLavaCornerWord(ivec3 corner) {
        uint key = GetLavaCornerKey(corner), tag = GetLavaCornerTag();
        uint slot = GetLavaCornerHomeSlot(key);
        key |= tag;
        for (uint probe = 0u; probe < lavaCornerMaxProbes; probe++) {
            int word = reflectionLavaBase + 2 * int(slot);
            uint current = blockDataSSBO.words[word];
            if ((current & lavaCornerTagMask) != tag) return 0u;
            if (current == key) {
                uint value = blockDataSSBO.words[word + 1];
                return (value & lavaFrameStampMask) == GetLavaFrameStamp() ? value : 0u;
            }
            slot = (slot + 1u) & (lavaCornerHashCapacity - 1u);
        }
        return 0u;
    }

    uvec4 GetLavaCornerWords(ivec3 cell) {
        return uvec4(GetLavaCornerWord(cell), GetLavaCornerWord(cell + ivec3(1, 0, 0)),
                     GetLavaCornerWord(cell + ivec3(0, 0, 1)), GetLavaCornerWord(cell + ivec3(1, 0, 1)));
    }

    vec4 GetCapturedLavaCornerHeights(ivec3 cell) {
        reflectionCellHandle cellRef = GetReflectionCellHandle(cell);
        uint faceIndex;
        ReadReflectionFace(cellRef, vec3(0.0, 1.0, 0.0), faceIndex);
        if (faceIndex == 0xffffffffu) return vec4(1.0);
        uvec4 data = LoadReflectionFaceAux(faceIndex);
        if (data.w != (cellRef.regionGeneration | reflectionFaceAuxFlag)
            || (data.z & reflectionFaceAuxFlagsMask) != reflectionFaceAuxFlagsMask)
            return vec4(-1.0);
        return vec4(data.x & 4095u, data.x >> 12u, data.y & 4095u, data.y >> 12u) / 4095.0;
    }
#else
    int GetLavaCornerIndex(ivec3 corner) {
        return corner.x + (sceneVoxelVolumeSize.x + 1) * (corner.y + sceneVoxelVolumeSize.y * corner.z);
    }

    float GetLavaCornerHeight(ivec3 corner) {
        if (!ReflectionStorageAvailable()) return 1.0;
        uint data = blockDataSSBO.words[reflectionLavaBase + GetLavaCornerIndex(corner)];
        return (data & lavaFrameStampMask) == GetLavaFrameStamp() ? float(data & 4095u) / 4095.0 : 1.0;
    }
#endif

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
    uint oldData = atomicAdd(blockDataSSBO.words[reflectionLavaBase + index], 0u);
    while (true) {
        uint updated = newData;
        if ((oldData & lavaFrameStampMask) == stamp) updated = keepMax ? max(oldData, newData) : oldData | newData;
        if (updated == oldData) break;
        uint previous = atomicCompSwap(blockDataSSBO.words[reflectionLavaBase + index], oldData, updated);
        if (previous == oldData) break;
        oldData = previous;
    }
}

#if WORLD_SPACE_SHAPES > 0
void StoreLavaCorner(ivec3 corner, float height) {
    if (!ReflectionStorageAvailable()) return;
    uint key = GetLavaCornerKey(corner), tag = GetLavaCornerTag();
    uint slot = GetLavaCornerHomeSlot(key);
    key |= tag;
    for (uint probe = 0u; probe < lavaCornerMaxProbes; probe++) {
        int word = reflectionLavaBase + 2 * int(slot);
        uint current = atomicAdd(blockDataSSBO.words[word], 0u);
        if ((current & lavaCornerTagMask) != tag) {
            uint previous = atomicCompSwap(blockDataSSBO.words[word], current, key);
            current = previous == current ? key : previous;
        }
        if (current == key) {
            MergeStampedWord(2 * int(slot) + 1, uint(round(height * 4095.0)), GetLavaFrameStamp(), true);
            return;
        }
        slot = (slot + 1u) & (lavaCornerHashCapacity - 1u);
    }
}
#else
void StoreLavaCorner(ivec3 corner, float height) {
    MergeStampedWord(GetLavaCornerIndex(corner), uint(round(height * 4095.0)), GetLavaFrameStamp(), true);
}
#endif

#ifdef MC_GL_ARB_shader_draw_parameters
    #extension GL_ARB_shader_draw_parameters : enable
#endif
// Sodium sub-allocates sections
int GetShapeQuadCorner() {
    #ifdef MC_GL_ARB_shader_draw_parameters
        return (gl_VertexID - gl_BaseVertexARB) & 3;
    #else
        return gl_VertexID & 3;
    #endif
}


#if WORLD_SPACE_SMOOTH_LIGHTING > 0
uint GetCapturedReflectionCornerLighting(vec3 normal) {
    vec2 uv = texCoord - mc_midTexCoord.xy;
    if (mat == 10068) {
        vec3 center = PlayerToSceneVoxel(ModelToScenePos(GetBlockCenterModelPos()));
        vec3 local = PlayerToSceneVoxel(ModelToScenePos(gl_Vertex.xyz)) - floor(center);
        uv = 0.5 - ProjectToFace(local, normal);
    }
    uint corner = uint(uv.x > 0.0) | (uint(uv.y > 0.0) << 1u);
    bool oppositeDiagonal = (((corner ^ (corner >> 1u)) ^ uint(GetShapeQuadCorner())) & 1u) != 0u;
    return PackReflectionCornerLighting(lmCoord, glColor.a, corner, oppositeDiagonal);
}
#endif

uint CaptureReflectionFace(uvec3 data, vec3 normal, bool withAux) {
    if (!ReflectionStorageAvailable()) return 0u;
    uint size = withAux ? 2u : 1u;
    uint slot = atomicAdd(blockDataSSBO.faceAllocationAttempts, size);
    #if WORLD_SPACE_SHAPES > 0
        uint capacity = 2u * reflectionFaceCapacity;
        if (slot + size > blockDataSSBO.allocationCapacity) {
            return 0u;
        }
        uint generation = shapeDataSSBO.captureFrame;
        uint index = GetReflectionRingIndex(blockDataSSBO.allocationStartIndex, slot, capacity);
        slot = index;
    #else
    if (slot + size > reflectionFaceCapacity) {
        return 0u;
    }
    uint generation = blockDataSSBO.faceGeneration;
    uint index = (generation & 1u) * reflectionFaceCapacity + slot;
    #endif
    uint word = uint(reflectionFaceRecordBase) + 4u * index;
    blockDataSSBO.words[word] = data.x;
    blockDataSSBO.words[word + 1u] = data.y;
    blockDataSSBO.words[word + 2u] = data.z;
    #ifndef WSR_FACE_LIST
        blockDataSSBO.words[word + 3u] = generation;
    #endif
    if (withAux) {
        uint auxWord = uint(reflectionFaceRecordBase) + 4u * GetReflectionFaceAuxIndex(index);
        blockDataSSBO.words[auxWord] = 0u;
        blockDataSSBO.words[auxWord + 1u] = 0u;
        blockDataSSBO.words[auxWord + 2u] = 0u;
        blockDataSSBO.words[auxWord + 3u] = generation | reflectionFaceAuxFlag;
    }
    #if WORLD_SPACE_SMOOTH_LIGHTING > 0
        uint lightingWord = uint(reflectionFaceCornersBase) + 4u * index;
        uint firstCorner = GetCapturedReflectionCornerLighting(normal);
        uint firstIndex = (firstCorner >> 28u) & 3u;
        for (uint corner = 0u; corner < 4u; corner++)
            blockDataSSBO.words[lightingWord + corner] = corner == firstIndex ? firstCorner : 0u;
    #endif
    memoryBarrier();
    return GetReflectionFaceStamp(generation) | (slot + 1u);
}

#ifdef WSR_FACE_LIST
void PublishReflectionFaces(ivec3 voxelPos, uint faceMask, uint reference) {
    if (reference == 0u) return;
    uint linkWord = uint(reflectionFaceRecordBase) + 4u * ((reference & reflectionFacePointerMask) - 1u) + 3u;
    blockDataSSBO.words[linkWord] = faceMask << reflectionFaceMaskShift;
    memoryBarrier();
    uint previous = atomicExchange(blockDataSSBO.words[GetSceneVoxelIndex(voxelPos)], reference);
    if ((previous & reflectionFaceStampMask) == (reference & reflectionFaceStampMask))
        atomicOr(blockDataSSBO.words[linkWord], previous & reflectionFacePointerMask);
}

void PublishReflectionFace(ivec3 voxelPos, vec3 normal, uint reference) {
    PublishReflectionFaces(voxelPos, 1u << uint(GetReflectionFaceIndex(normal)), reference);
}
#else
void PublishReflectionFace(ivec3 voxelPos, vec3 normal, uint reference) {
    if (reference != 0u) atomicExchange(blockDataSSBO.words[GetFaceRecordSlot(voxelPos, normal)], reference);
}
#endif

void StoreLavaFaceData(ivec3 voxelPos, vec2 origin, float textureRad, float textureRotation) {
    uvec3 uv = PackReflectionTextureBounds(vec3(origin, textureRad));
    uvec2 lightmap = uvec2(round(clamp(lmCoord, 0.0, 1.0) * 15.0));
    uint angle = uint(round(fract(textureRotation / 6.28318530718) * 256.0)) & 255u;
    uvec3 data = uvec3((uv.x << 16u) | uv.y,
                     uv.z | (angle << 16u) | (lightmap.x << 24u) | (lightmap.y << 28u), 0u);
    uint reference = CaptureReflectionFace(data, vec3(0.0, 1.0, 0.0), WORLD_SPACE_SHAPES > 0);
    #if WORLD_SPACE_SHAPES > 0
        if (reference != 0u) {
            uint index = (reference & reflectionFacePointerMask) - 1u;
            uint auxWord = uint(reflectionFaceRecordBase) + 4u * GetReflectionFaceAuxIndex(index);
            // shadowcomp freezes the four corner heights after all vertices have been captured.
            blockDataSSBO.words[auxWord + 2u] = reflectionFaceAuxLavaFlag | uint(GetSceneVoxelIndex(voxelPos));
            memoryBarrier();
        }
    #endif
    PublishReflectionFace(voxelPos, vec3(0.0, 1.0, 0.0), reference);
}

void StoreReflectionFace(ivec3 voxelPos, vec3 normal, uvec3 data) {
    PublishReflectionFace(voxelPos, normal, CaptureReflectionFace(data, normal, false));
}

void StoreGrassSideOverlay(ivec3 voxelPos, vec3 normal, vec2 origin, float textureRad, uint orientation) {
    uint index = atomicAdd(blockDataSSBO.grassCaptureCount, 1u);
    if (index >= grassCaptureCapacity) return;
    uvec3 uv = PackReflectionTextureBounds(vec3(origin, textureRad));
    uint key = uint(GetSceneVoxelIndex(voxelPos)) | (uint(GetReflectionFaceIndex(normal)) << sceneVoxelIndexBits);
    uint word = uint(reflectionGrassCaptureBase) + 4u * index;
    blockDataSSBO.words[word] = (uv.x << 16u) | uv.y;
    blockDataSSBO.words[word + 1u] = uv.z | (orientation << 16u);
    blockDataSSBO.words[word + 2u] = packUnorm4x8(vec4(glColor.rgb, 0.0));
    blockDataSSBO.words[word + 3u] = key;
}

void StoreFaceData(ivec3 voxelPos, vec3 normal, vec2 origin, float textureRad, uint orientation,
                   bool storeToAllFaces, bool storeToAllFacesExceptTop, vec3 playerPos, bool grassSide) {
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

    uvec3 newData = PackReflectionFaceData(faceData(glColor.rgb, lmCoordM, vec3(origin, textureRad)), orientation);
    uint reference = CaptureReflectionFace(newData, normal, grassSide);

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
        #ifdef WSR_FACE_LIST
            PublishReflectionFaces(voxelPos, storeToAllFacesExceptTop ? reflectionAllFacesMask & ~(1u << reflectionTopFace)
                                                                      : reflectionAllFacesMask, reference);
        #else
        for(int i = start; i < 6; i++) {
            PublishReflectionFace(voxelPos, faceOffsets[i], reference);
        }
        #endif
    } else {
        PublishReflectionFace(voxelPos, normal, reference);
    }
}
#endif
