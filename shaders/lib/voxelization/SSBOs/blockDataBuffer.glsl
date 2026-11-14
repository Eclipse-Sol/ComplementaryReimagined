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
const int reflectionMetadataBase = reflectionFaceCount;
const int reflectionFaceRecordBase = ((reflectionHeaderWordCount + reflectionMetadataBase + lavaCornerCount + sceneVoxelCount + 3) & ~3)
                                   - reflectionHeaderWordCount;
const int reflectionFaceAuxBase = reflectionFaceRecordBase + 8 * int(reflectionFaceCapacity);
const int reflectionGrassCaptureBase = reflectionFaceAuxBase + 8 * int(reflectionFaceCapacity);
#if WORLD_SPACE_SMOOTH_LIGHTING > 0
    const int reflectionFaceCornersBase = reflectionGrassCaptureBase + 4 * int(grassCaptureCapacity);
    const int reflectionCornerCaptureBase = reflectionFaceCornersBase + 8 * int(reflectionFaceCapacity);
    const uint reflectionCornerCaptureCapacity = 3u * reflectionFaceCapacity;
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

uvec4 LoadReflectionFaceAux(uint index) {
    uint word = uint(reflectionFaceAuxBase) + 4u * index;
    return uvec4(blockDataSSBO.words[word], blockDataSSBO.words[word + 1u],
                 blockDataSSBO.words[word + 2u], blockDataSSBO.words[word + 3u]);
}

uvec4 LoadReflectionGrassOverlay(uint index) {
    return LoadReflectionFaceAux(index);
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
