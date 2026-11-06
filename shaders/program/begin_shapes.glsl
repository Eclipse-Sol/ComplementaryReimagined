#include "/lib/common.glsl"
#define SSBO_QUALIFIER
#include "/lib/voxelization/SSBOs/shapeDataBuffer.glsl"
#include "/lib/voxelization/SSBOs/shapeHeadBuffer.glsl"
#include "/lib/voxelization/reflectionVoxelVolume.glsl"

layout(local_size_x = 256) in;
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
layout(r16ui) writeonly uniform uimage3D wsr_img;
layout(r8ui) writeonly uniform uimage3D wsr_lod_img;
layout(r8ui) uniform uimage3D wsr_coarse_img;
shared bool tileOccupied;
shared uint epoch;

void main() {
    uint lane = gl_LocalInvocationID.x;
    bool refresh = isReflectionVoxelRefreshDue();
    // New images are undefined, so clear them until the first rebuild...
    if (!refresh && shapeDataSSBO.epoch != 0u) return;
    ivec3 tile = ivec3(gl_WorkGroupID);
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
}
