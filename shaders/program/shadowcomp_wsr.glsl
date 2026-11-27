/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

//Common//
#include "/lib/common.glsl"

//////////Shadowcomp 1 WSR//////////Shadowcomp 1 WSR//////////Shadowcomp 1 WSR//////////
#ifdef SHADOWCOMP

#if WORLD_SPACE_REFLECTIONS_INTERNAL > 0
    #include "/lib/voxelization/reflectionVoxelVolume.glsl"
    #define SHAPE_BUILD
    #include "/lib/voxelization/reflectionVoxelData.glsl"
    #undef SHAPE_BUILD
    #include "/lib/voxelization/reflectionGrassResolve.glsl"
#endif

#if defined WSR_PLAYER_EQUIPMENT && WORLD_SPACE_SHAPES <= 0
    #include "/lib/voxelization/playerCaptureBounds.glsl"
#endif

layout (local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
#if WORLD_SPACE_REFLECTIONS_INTERNAL > 0
    #if WORLD_SPACE_SHAPES > 0 && (WORLD_SPACE_SMOOTH_LIGHTING <= 0 || WSR_REBUILD_PERCENT <= 13)
        #if COLORED_LIGHTING_INTERNAL >= 384 && WSR_VOLUME_HEIGHT == 256
            const ivec3 workGroups = ivec3(32768, 1, 1);
        #elif COLORED_LIGHTING_INTERNAL >= 384 && WSR_VOLUME_HEIGHT == 128
            const ivec3 workGroups = ivec3(24576, 1, 1);
        #elif COLORED_LIGHTING_INTERNAL >= 384
            const ivec3 workGroups = ivec3(16384, 1, 1);
        #elif COLORED_LIGHTING_INTERNAL >= 256 && WSR_VOLUME_HEIGHT == 256
            const ivec3 workGroups = ivec3(16384, 1, 1);
        #elif COLORED_LIGHTING_INTERNAL >= 256 && WSR_VOLUME_HEIGHT == 128
            const ivec3 workGroups = ivec3(12288, 1, 1);
        #elif COLORED_LIGHTING_INTERNAL >= 256
            const ivec3 workGroups = ivec3(8192, 1, 1);
        #elif COLORED_LIGHTING_INTERNAL >= 192 && WSR_VOLUME_HEIGHT == 256
            const ivec3 workGroups = ivec3(8192, 1, 1);
        #elif COLORED_LIGHTING_INTERNAL >= 192 && WSR_VOLUME_HEIGHT == 128
            const ivec3 workGroups = ivec3(6144, 1, 1);
        #elif COLORED_LIGHTING_INTERNAL >= 192
            const ivec3 workGroups = ivec3(4096, 1, 1);
        #elif WSR_VOLUME_HEIGHT == 256
            const ivec3 workGroups = ivec3(4096, 1, 1);
        #elif WSR_VOLUME_HEIGHT == 128
            const ivec3 workGroups = ivec3(3072, 1, 1);
        #else
            const ivec3 workGroups = ivec3(2048, 1, 1);
        #endif
    #elif COLORED_LIGHTING_INTERNAL >= 384 && WORLD_SPACE_SHAPES > 0 && WSR_VOLUME_HEIGHT == 256
        const ivec3 workGroups = ivec3(49152, 1, 1);
    #elif COLORED_LIGHTING_INTERNAL >= 384 && WORLD_SPACE_SHAPES > 0 && WSR_VOLUME_HEIGHT == 128
        const ivec3 workGroups = ivec3(36864, 1, 1);
    #elif COLORED_LIGHTING_INTERNAL >= 256 && WORLD_SPACE_SHAPES > 0 && WSR_VOLUME_HEIGHT == 256
        const ivec3 workGroups = ivec3(24576, 1, 1);
    #elif COLORED_LIGHTING_INTERNAL >= 256 && WORLD_SPACE_SHAPES > 0 && WSR_VOLUME_HEIGHT == 128
        const ivec3 workGroups = ivec3(18432, 1, 1);
    #elif COLORED_LIGHTING_INTERNAL >= 192 && WORLD_SPACE_SHAPES > 0 && WSR_VOLUME_HEIGHT == 256
        const ivec3 workGroups = ivec3(12288, 1, 1);
    #elif COLORED_LIGHTING_INTERNAL >= 192 && WORLD_SPACE_SHAPES > 0 && WSR_VOLUME_HEIGHT == 128
        const ivec3 workGroups = ivec3(9216, 1, 1);
    #elif COLORED_LIGHTING_INTERNAL > 0 && WORLD_SPACE_SHAPES > 0 && WSR_VOLUME_HEIGHT == 256
        const ivec3 workGroups = ivec3(6144, 1, 1);
    #elif COLORED_LIGHTING_INTERNAL > 0 && WORLD_SPACE_SHAPES > 0 && WSR_VOLUME_HEIGHT == 128
        const ivec3 workGroups = ivec3(4608, 1, 1);
    #elif COLORED_LIGHTING_INTERNAL >= 384
        const ivec3 workGroups = ivec3(24576, 1, 1);
    #elif COLORED_LIGHTING_INTERNAL >= 256
        const ivec3 workGroups = ivec3(12288, 1, 1);
    #elif COLORED_LIGHTING_INTERNAL >= 192
        const ivec3 workGroups = ivec3(6144, 1, 1);
    #else
        const ivec3 workGroups = ivec3(3072, 1, 1);
    #endif
#else
    const ivec3 workGroups = ivec3(1, 1, 1);
#endif

//Includes//
#if COLORED_LIGHTING_INTERNAL > 0
    #include "/lib/voxelization/lightVoxelization.glsl"
#endif

//Program//
void main() {
    #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0
        uint captureIndex = gl_GlobalInvocationID.x;
        if (ReflectionStorageAvailable() && captureIndex < min(blockDataSSBO.grassCaptureCount, grassCaptureCapacity))
            ResolveGrassSideOverlay(captureIndex);
        #if WORLD_SPACE_SHAPES > 0
            if (ReflectionStorageAvailable()) ResolveReflectionLavaHeights(captureIndex);
        #endif
        #if WORLD_SPACE_SMOOTH_LIGHTING > 0
            if (ReflectionStorageAvailable() && captureIndex < min(blockDataSSBO.cornerCaptureCount, reflectionCornerCaptureCapacity))
                ResolveReflectionCornerLighting(captureIndex);
        #endif
    #endif
    #if defined WSR_PLAYER_EQUIPMENT && WORLD_SPACE_SHAPES <= 0
        if (gl_GlobalInvocationID.x == 0u)
            mergePlayerBounds();
    #endif
}

#endif
