#if WORLD_SPACE_SHAPES > 0 && WSR_VOLUME_HEIGHT == 256
    #define WSR_TILE_GROUPS_Y 16
#elif WORLD_SPACE_SHAPES > 0 && WSR_VOLUME_HEIGHT == 128
    #define WSR_TILE_GROUPS_Y 8
#else
    #define WSR_TILE_GROUPS_Y 4
#endif
#if COLORED_LIGHTING_INTERNAL == 128
    const ivec3 workGroups = ivec3(8, WSR_TILE_GROUPS_Y, 8);
#elif COLORED_LIGHTING_INTERNAL == 192
    const ivec3 workGroups = ivec3(12, WSR_TILE_GROUPS_Y, 12);
#elif COLORED_LIGHTING_INTERNAL == 256
    const ivec3 workGroups = ivec3(16, WSR_TILE_GROUPS_Y, 16);
#elif COLORED_LIGHTING_INTERNAL == 384
    const ivec3 workGroups = ivec3(24, WSR_TILE_GROUPS_Y, 24);
#else
    const ivec3 workGroups = ivec3(32, WSR_TILE_GROUPS_Y, 32);
#endif
