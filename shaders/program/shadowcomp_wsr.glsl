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
    // A fixed grid loops over the captures. A grid sized to capacity spent most of the pass on idle waves.
    const ivec3 workGroups = ivec3(2048, 1, 1);
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
    if (ReflectionStorageAvailable()) {
        uint grassCount = min(blockDataSSBO.grassCaptureCount, grassCaptureCapacity);
        #if WORLD_SPACE_SHAPES > 0
            uint lavaCount = min(blockDataSSBO.faceAllocationAttempts, blockDataSSBO.allocationCapacity);
            uint lavaStart = blockDataSSBO.allocationStartIndex;
            uint captureFrame = shapeDataSSBO.captureFrame;
        #else
            uint lavaCount = 0u;
        #endif
        #if WORLD_SPACE_SMOOTH_LIGHTING > 0
            uint cornerCount = min(blockDataSSBO.cornerCaptureCount, reflectionCornerCaptureCapacity);
        #else
            uint cornerCount = 0u;
        #endif
        uint count = max(grassCount, max(lavaCount, cornerCount));
        uint stride = gl_NumWorkGroups.x * gl_WorkGroupSize.x;
        for (uint captureIndex = gl_GlobalInvocationID.x; captureIndex < count; captureIndex += stride) {
            if (captureIndex < grassCount) ResolveGrassSideOverlay(captureIndex);
            #if WORLD_SPACE_SHAPES > 0
                if (captureIndex < lavaCount) ResolveReflectionLavaHeights(captureIndex, lavaStart, captureFrame);
            #endif
            #if WORLD_SPACE_SMOOTH_LIGHTING > 0
                if (captureIndex < cornerCount) ResolveReflectionCornerLighting(captureIndex);
            #endif
        }
    }
    #endif
    #if defined WSR_PLAYER_EQUIPMENT && WORLD_SPACE_SHAPES <= 0
        if (gl_GlobalInvocationID.x == 0u)
            mergePlayerBounds();
    #endif
}

#endif
