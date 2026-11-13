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
    uint lavaRefreshFrame;
    #if WORLD_SPACE_SHAPES > 0
        uint regionStartIndices[reflectionMaxRegionCount];
        uint allocationStartIndex;
        uint allocationCapacity;
        uint nextRegionStart;
    #endif
    // One array because Intel's Windows driver truncates block member offsets past 64 MiB
    uint words[];
} blockDataSSBO;

#undef BLOCK_DATA_QUALIFIER

#if WORLD_SPACE_SHAPES > 0
    const int reflectionHeaderWordCount = 7 + reflectionMaxRegionCount;
#else
    const int reflectionHeaderWordCount = 4;
#endif
const int reflectionMetadataBase = reflectionFaceCount;
const int reflectionFaceRecordBase = ((reflectionHeaderWordCount + reflectionMetadataBase + lavaCornerCount + sceneVoxelCount + 3) & ~3)
                                   - reflectionHeaderWordCount;
const int reflectionGrassOverlayBase = reflectionFaceRecordBase + 8 * int(reflectionFaceCapacity);
const int reflectionGrassCaptureBase = reflectionGrassOverlayBase + 8 * int(reflectionFaceCapacity);
const int reflectionStorageWordCount = reflectionGrassCaptureBase + 4 * int(grassCaptureCapacity);

bool ReflectionStorageAvailable() {
    return blockDataSSBO.words.length() >= reflectionStorageWordCount;
}

uvec4 LoadReflectionFaceRecord(uint index) {
    uint word = uint(reflectionFaceRecordBase) + 4u * index;
    return uvec4(blockDataSSBO.words[word], blockDataSSBO.words[word + 1u],
                 blockDataSSBO.words[word + 2u], blockDataSSBO.words[word + 3u]);
}

uvec4 LoadReflectionGrassOverlay(uint index) {
    uint word = uint(reflectionGrassOverlayBase) + 4u * index;
    return uvec4(blockDataSSBO.words[word], blockDataSSBO.words[word + 1u],
                 blockDataSSBO.words[word + 2u], blockDataSSBO.words[word + 3u]);
}

uvec4 LoadReflectionGrassCapture(uint index) {
    uint word = uint(reflectionGrassCaptureBase) + 4u * index;
    return uvec4(blockDataSSBO.words[word], blockDataSSBO.words[word + 1u],
                 blockDataSSBO.words[word + 2u], blockDataSSBO.words[word + 3u]);
}
