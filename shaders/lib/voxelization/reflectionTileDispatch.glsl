#if COLORED_LIGHTING_INTERNAL == 128
    const ivec3 workGroups = ivec3(8, 4, 8);
#elif COLORED_LIGHTING_INTERNAL == 192
    const ivec3 workGroups = ivec3(12, 4, 12);
#elif COLORED_LIGHTING_INTERNAL == 256
    const ivec3 workGroups = ivec3(16, 4, 16);
#elif COLORED_LIGHTING_INTERNAL == 384
    const ivec3 workGroups = ivec3(24, 4, 24);
#else
    const ivec3 workGroups = ivec3(32, 4, 32);
#endif
