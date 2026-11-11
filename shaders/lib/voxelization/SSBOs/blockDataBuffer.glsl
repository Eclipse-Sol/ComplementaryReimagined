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
    uint allocationPadding;
    uint lavaRefreshFrame;
    #if WORLD_SPACE_SHAPES > 0
        uint regionStartIndices[reflectionMaxRegionCount];
        uint allocationStartIndex;
        uint allocationCapacity;
        uint nextRegionStart;
    #endif
    uint faceRefs[reflectionFaceCount];
    uint metadata[lavaCornerCount + sceneVoxelCount];
    uvec4 faces[2u * reflectionFaceCapacity];
    uint storageEnd[];
} blockDataSSBO;

#undef BLOCK_DATA_QUALIFIER

bool ReflectionStorageAvailable() {
    return blockDataSSBO.storageEnd.length() >= 4;
}
