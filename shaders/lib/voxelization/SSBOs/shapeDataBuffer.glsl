#extension GL_ARB_shader_storage_buffer_object : enable

// Keep in sync with bufferObject.4 and .7
#if COLORED_LIGHTING >= 256
    const uint shapeSurfaceCapacity = 2097151u; // 64 MiB
#elif COLORED_LIGHTING >= 192
    const uint shapeSurfaceCapacity = 1048575u; // 32 MiB
#else
    const uint shapeSurfaceCapacity = 524288u;  // 16 MiB
#endif
struct shapeSurface {
    uvec4 shading;
    uvec4 mapping;
};
layout(std430, binding = 4) SSBO_QUALIFIER buffer shapeDataBuffer {
    uint count;         // surfaces recorded this rebuild
    uint unused;        // padding
    uint resolvedCount; // count snapshot taken by the resolve pass for the scatter pass
    uint epoch;         // rebuild counter
    shapeSurface surfaces[];
} shapeDataSSBO;
