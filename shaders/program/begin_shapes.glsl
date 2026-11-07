#include "/lib/common.glsl"
#include "/lib/voxelization/reflectionVoxelVolume.glsl"
#define SSBO_QUALIFIER
#include "/lib/voxelization/SSBOs/blockDataBuffer.glsl"
#if WORLD_SPACE_SHAPES > 0
    #include "/lib/voxelization/SSBOs/shapeDataBuffer.glsl"
    #include "/lib/voxelization/SSBOs/shapeHeadBuffer.glsl"
#endif

layout(local_size_x = 256) in;
#if WORLD_SPACE_SHAPES <= 0
    const ivec3 workGroups = ivec3(64, 1, 1);
#elif COLORED_LIGHTING_INTERNAL == 128
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
#if WORLD_SPACE_SHAPES > 0
layout(r16ui) writeonly uniform uimage3D wsr_img;
layout(r8ui) writeonly uniform uimage3D wsr_lod_img;
layout(r8ui) uniform uimage3D wsr_coarse_img;
shared bool tileOccupied;
shared uint epoch;
#endif

shared uint reflectionPrepareEpoch;

void prepareReflectionFaces(bool refresh) {
    if (!refresh) return;
    if (gl_LocalInvocationID.x == 0u) {
        if (gl_WorkGroupID == uvec3(0u)) {
            blockDataSSBO.faceCount = 0u;
            blockDataSSBO.faceOverflow = 0u;
            reflectionPrepareEpoch = atomicAdd(blockDataSSBO.faceEpoch, 1u) + 1u;
        } else {
            reflectionPrepareEpoch = atomicAdd(blockDataSSBO.faceEpoch, 0u);
        }
    }
    barrier();
    uint slice = (uint(reflectionFaceCount) + 2047u) / 2048u;
    uint group = gl_WorkGroupID.x + gl_NumWorkGroups.x * (gl_WorkGroupID.y + gl_NumWorkGroups.y * gl_WorkGroupID.z);
    uint stride = gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z * gl_WorkGroupSize.x;
    for (uint step = 0u; step < 2u; step++) {
        uint start = ((reflectionPrepareEpoch + step) & 2047u) * slice;
        for (uint i = group * gl_WorkGroupSize.x + gl_LocalInvocationID.x; i < slice; i += stride) {
            uint index = start + i;
            if (index < uint(reflectionFaceCount)) blockDataSSBO.faceRefs[index] = 0u;
        }
    }
}

void main() {
    if (!reflectionStorageAvailable()) return;
    uint lane = gl_LocalInvocationID.x;
    bool refresh = isReflectionVoxelRefreshDue();
    ivec3 tile = ivec3(gl_WorkGroupID);
    prepareReflectionFaces(refresh);
    #if WORLD_SPACE_SHAPES > 0
        // New images are undefined, so clear them until the first rebuild...
        if (!refresh && shapeDataSSBO.epoch != 0u) return;
        if (lane == 0u) tileOccupied = imageLoad(wsr_coarse_img, tile).r != 0u || shapeDataSSBO.epoch < 2u;
        barrier();
        if (tileOccupied) {
            ivec3 base = tile * 16 + ivec3(lane & 15u, lane >> 4u, 0);
            for (int z = 0; z < 16; z++)
                imageStore(wsr_img, base + ivec3(0, 0, z), uvec4(0u));
            if (lane < 64u)
                imageStore(wsr_lod_img, tile * 4 + ivec3(lane & 3u, (lane >> 2u) & 3u, lane >> 4u), uvec4(0u));
            if (lane == 0u) imageStore(wsr_coarse_img, tile, uvec4(0u));
        }
        if (!refresh || gl_WorkGroupID != uvec3(0u)) return;
        if (lane == 0u) epoch = ++shapeDataSSBO.epoch;
        barrier();

        uint slice = (uint(sceneVoxelCount) + 2047u) / 2048u;
        uint start = (epoch & 2047u) * slice;
        for (uint i = lane; i < slice; i += 256u) {
            uint index = start + i;
            if (index < uint(sceneVoxelCount)) shapeHeadSSBO.heads[index] = 0u;
        }
    #endif
}
