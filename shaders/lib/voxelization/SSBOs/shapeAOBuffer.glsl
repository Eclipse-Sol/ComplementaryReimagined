layout(std430, binding = 7) SSBO_QUALIFIER buffer shapeAOBuffer {
    #if WORLD_SPACE_SMOOTH_LIGHTING > 0
        uvec4 corners[];
    #else
        uint corners[];
    #endif
} shapeAOSSBO;
