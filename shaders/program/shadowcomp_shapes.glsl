#include "/lib/common.glsl"
layout(local_size_x = 64) in;
const ivec3 workGroups = ivec3(8192, 1, 1);

#if WORLD_SPACE_REFLECTIONS_INTERNAL > 0 && WORLD_SPACE_SHAPES > 0
    #ifdef SHAPE_SCATTER
        layout(r16ui) uniform uimage3D wsr_img;
        layout(r8ui) writeonly uniform uimage3D wsr_lod_img;
        layout(r8ui) writeonly uniform uimage3D wsr_coarse_img;
    #endif
    #define SHAPE_BUILD
    #include "/lib/voxelization/reflectionVoxelization.glsl"
#endif

#if defined WSR_PLAYER_EQUIPMENT && defined SHAPE_RESOLVE && WORLD_SPACE_SHAPES > 0
    #include "/lib/voxelization/playerCaptureBounds.glsl"
#endif

void main() {
    #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0 && WORLD_SPACE_SHAPES > 0
        uint capturedRecordCount = GetCapturedShapeRecordCount();
        uint haloRecordCount = shapeDataSSBO.haloRecordCount;
        #ifdef SHAPE_RESOLVE
            if (gl_GlobalInvocationID.x == 0u) {
                shapeDataSSBO.frozenRecordCount = capturedRecordCount;
                shapeDataSSBO.frozenHaloRecordCount = haloRecordCount;
                #ifdef WSR_PLAYER_EQUIPMENT
                    mergePlayerBounds();
                #endif
            }
        #endif
        #ifdef SHAPE_SCATTER
            capturedRecordCount = shapeDataSSBO.frozenRecordCount;
            haloRecordCount = shapeDataSSBO.frozenHaloRecordCount;
        #endif
        uint stride = gl_NumWorkGroups.x * gl_WorkGroupSize.x;
        for (uint index = gl_GlobalInvocationID.x; index < capturedRecordCount + haloRecordCount; index += stride)
            BuildReflectionShapeSurface(GetShapeBuildInputIndex(index, capturedRecordCount), index >= capturedRecordCount);
    #endif
}
