#extension GL_ARB_shader_storage_buffer_object : enable

#if defined SHADOW && defined VERTEX_SHADER
    #define BLOCK_DATA_QUALIFIER coherent
#else
    #define BLOCK_DATA_QUALIFIER SSBO_QUALIFIER
#endif

layout(std430, binding = 0) BLOCK_DATA_QUALIFIER buffer blockDataBuffer {
    uint faceCount;
    uint faceEpoch;
    uint faceOverflow;
    uint reserved;
    uint faceRefs[reflectionFaceCount];
    uint metadata[lavaCornerCount + sceneVoxelCount];
    uvec4 faces[2u * reflectionFaceCapacity];
    uint storageEnd[];
} blockDataSSBO;

#undef BLOCK_DATA_QUALIFIER

bool reflectionStorageAvailable() {
    return blockDataSSBO.storageEnd.length() >= 4;
}
