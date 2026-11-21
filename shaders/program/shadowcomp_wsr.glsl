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
    #if COLORED_LIGHTING_INTERNAL >= 384
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
