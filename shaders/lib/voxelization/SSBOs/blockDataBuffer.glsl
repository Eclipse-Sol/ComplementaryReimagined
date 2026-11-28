#extension GL_ARB_shader_storage_buffer_object : enable

#if defined SHADOW && defined VERTEX_SHADER
    #define BLOCK_DATA_QUALIFIER coherent
#else
    #define BLOCK_DATA_QUALIFIER SSBO_QUALIFIER
#endif

layout(std430, binding = 0) BLOCK_DATA_QUALIFIER buffer blockDataBuffer {
    uint faceAllocationAttempts;
    #if WORLD_SPACE_SHAPES > 0
        uint captureFramePadding;
    #else
        uint faceGeneration;
    #endif
    uint grassCaptureCount;
    uint lavaCapturePadding;
    #if WORLD_SPACE_SHAPES > 0
        uint regionStartIndices[reflectionMaxRegionCount];
        uint allocationStartIndex;
        uint allocationCapacity;
        uint nextRegionStart;
    #endif
    #if WORLD_SPACE_SMOOTH_LIGHTING > 0
        uint cornerCaptureCount;
    #endif
    // One array because Intel's Windows driver truncates block member offsets past 64 MiB
    uint words[];
} blockDataSSBO;

#undef BLOCK_DATA_QUALIFIER

#if WORLD_SPACE_SHAPES > 0
    const int reflectionHeaderWordCount = 7 + reflectionMaxRegionCount + (WORLD_SPACE_SMOOTH_LIGHTING > 0 ? 1 : 0);
#else
    const int reflectionHeaderWordCount = 4 + (WORLD_SPACE_SMOOTH_LIGHTING > 0 ? 1 : 0);
#endif
#if WORLD_SPACE_SHAPES > 0
    const uint lavaCornerHashBits = sceneVoxelVolumeSize.x >= 384 ? 20u : sceneVoxelVolumeSize.x >= 192 ? 18u : 16u;
    const uint lavaCornerHashCapacity = 1u << lavaCornerHashBits;
    const int reflectionLavaWordCount = 2 * int(lavaCornerHashCapacity);
#else
    const int reflectionLavaWordCount = lavaCornerCount;
#endif
const int reflectionLavaBase = reflectionFaceRefCount;
const int reflectionFaceRecordBase = ((reflectionHeaderWordCount + reflectionLavaBase + reflectionLavaWordCount + 3) & ~3)
                                   - reflectionHeaderWordCount;
const int reflectionGrassCaptureBase = reflectionFaceRecordBase + 8 * int(reflectionFaceCapacity);
#if WORLD_SPACE_SMOOTH_LIGHTING > 0
    const int reflectionFaceCornersBase = reflectionGrassCaptureBase + 4 * int(grassCaptureCapacity);
    const int reflectionCornerCaptureBase = reflectionFaceCornersBase + 8 * int(reflectionFaceCapacity);
    #if WORLD_SPACE_SHAPES > 0
        // Each frame captures one of reflectionActiveRegionCount regions, so more regions need fewer corner captures per frame.
        //
        // Keep these thresholds in sync with the WSR_REBUILD_PERCENT checks in shaders.properties (bufferObject.0)
        const uint reflectionCornerCaptureDivisor = reflectionActiveRegionCount >= 20 ? 8u
            : reflectionActiveRegionCount >= 10 ? 4u : reflectionActiveRegionCount >= 8 ? 3u : 1u;
    #else
        const uint reflectionCornerCaptureDivisor = 1u;
    #endif
    const uint reflectionCornerCaptureCapacity = 3u * reflectionFaceCapacity / reflectionCornerCaptureDivisor;
    const int reflectionStorageWordCount = reflectionCornerCaptureBase + 2 * int(reflectionCornerCaptureCapacity);
#else
    const int reflectionStorageWordCount = reflectionGrassCaptureBase + 4 * int(grassCaptureCapacity);
#endif

bool ReflectionStorageAvailable() {
    return blockDataSSBO.words.length() >= reflectionStorageWordCount;
}

uvec4 LoadReflectionFaceRecord(uint index) {
    uint word = uint(reflectionFaceRecordBase) + 4u * index;
    return uvec4(blockDataSSBO.words[word], blockDataSSBO.words[word + 1u],
                 blockDataSSBO.words[word + 2u], blockDataSSBO.words[word + 3u]);
}

const uint reflectionFaceAuxFlag = 0x80000000u;
const uint reflectionFaceAuxLavaFlag = 0x80000000u;
const uint reflectionFaceAuxResolvedFlag = 0x40000000u;
const uint reflectionFaceAuxFlagsMask = reflectionFaceAuxLavaFlag | reflectionFaceAuxResolvedFlag;

uint GetReflectionFaceAuxIndex(uint faceIndex) {
    #if WORLD_SPACE_SHAPES > 0
        // The record ring wraps
        return faceIndex + 1u == 2u * reflectionFaceCapacity ? 0u : faceIndex + 1u;
    #else
        return faceIndex + 1u;
    #endif
}

uvec4 LoadReflectionFaceAux(uint faceIndex) {
    return LoadReflectionFaceRecord(GetReflectionFaceAuxIndex(faceIndex));
}

#ifdef WSR_FACE_LIST
const uint reflectionFaceMaskShift = 25u;
// Keep this bound above 128 so radeonsi skips full unrolling of this loop.
// Lowering the bound increased composite_a's VGPR count from 120 to 144!
const uint reflectionFaceListMaxSteps = 256u;

bool StepReflectionFaceList(inout uint pointer, uint faceBit, inout uint index) {
    if (pointer == 0u || pointer > 2u * reflectionFaceCapacity) return true;
    uint candidate = pointer - 1u;
    uint link = blockDataSSBO.words[uint(reflectionFaceRecordBase) + 4u * candidate + 3u];
    pointer = link & reflectionFacePointerMask;
    if ((link & faceBit) == 0u) return false;
    index = candidate;
    return true;
}

uint FindReflectionFaceRecord(uint head, uint face, uint generation, out uvec4 record) {
    record = uvec4(0u);
    if ((head & reflectionFaceStampMask) != GetReflectionFaceStamp(generation)) return 0xffffffffu;
    uint faceBit = 1u << (reflectionFaceMaskShift + face);
    uint pointer = head & reflectionFacePointerMask;
    uint index = 0xffffffffu;
    for (uint step = 0u; step < reflectionFaceListMaxSteps; step++)
        if (StepReflectionFaceList(pointer, faceBit, index)) break;
    if (index != 0xffffffffu) record = LoadReflectionFaceRecord(index);
    return index;
}
#endif

uvec4 LoadReflectionGrassOverlay(uint faceIndex) {
    return LoadReflectionFaceAux(faceIndex);
}

uvec4 LoadReflectionGrassCapture(uint index) {
    uint word = uint(reflectionGrassCaptureBase) + 4u * index;
    return uvec4(blockDataSSBO.words[word], blockDataSSBO.words[word + 1u],
                 blockDataSSBO.words[word + 2u], blockDataSSBO.words[word + 3u]);
}

#if WORLD_SPACE_SMOOTH_LIGHTING > 0
uvec4 LoadReflectionFaceCorners(uint index) {
    uint word = uint(reflectionFaceCornersBase) + 4u * index;
    return uvec4(blockDataSSBO.words[word], blockDataSSBO.words[word + 1u],
                 blockDataSSBO.words[word + 2u], blockDataSSBO.words[word + 3u]);
}
#endif
