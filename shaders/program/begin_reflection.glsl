#include "/lib/common.glsl"
#if WORLD_SPACE_SHAPES > 0
#include "/lib/voxelization/reflectionVoxelVolume.glsl"
#define SSBO_QUALIFIER
#include "/lib/voxelization/SSBOs/blockDataBuffer.glsl"
#include "/lib/voxelization/SSBOs/shapeDataBuffer.glsl"

layout(local_size_x = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);

void main() {
    if (!ReflectionStorageAvailable()) return;
    uint captureFrame = shapeDataSSBO.captureFrame;
    bool firstCapture = captureFrame == 0u;
    if (firstCapture) {
        shapeDataSSBO.nextRegionStart = 0u;
        blockDataSSBO.nextRegionStart = 0u;
        for (int i = 0; i < WSR_MAX_REGIONS; i++) {
            shapeDataSSBO.regionGenerations[i] = 0u;
            shapeDataSSBO.regionStartIndices[i] = 0u;
            blockDataSSBO.regionStartIndices[i] = 0u;
        }
    }
    uint regionCount = uint(reflectionActiveRegionCount);
    uint selectedRegion = captureFrame % regionCount;
    uint oldestRetainedRegion = (selectedRegion + 1u) % regionCount;
    uint writeStart = shapeDataSSBO.nextRegionStart;
    uint oldestLiveStart = shapeDataSSBO.regionStartIndices[oldestRetainedRegion];
    if (regionCount == 1u) oldestLiveStart = writeStart;
    shapeDataSSBO.allocationStartIndex = writeStart;
    shapeDataSSBO.allocationCapacity = GetReflectionRingFreeCount(writeStart, oldestLiveStart, shapeRecordCapacity);
    shapeDataSSBO.regionStartIndices[selectedRegion] = writeStart;
    shapeDataSSBO.previousRegionGeneration = shapeDataSSBO.regionGenerations[selectedRegion];
    shapeDataSSBO.regionGenerations[selectedRegion] = captureFrame + 1u;
    shapeDataSSBO.selectedRegion = selectedRegion;
    shapeDataSSBO.capturedRecordCount = 0u;
    shapeDataSSBO.frozenRecordCount = 0u;
    shapeDataSSBO.haloRecordCount = 0u;
    shapeDataSSBO.frozenHaloRecordCount = 0u;
    shapeDataSSBO.allocationAttempts = 0u;
    shapeDataSSBO.previousVolumeOrigin = shapeDataSSBO.volumeOrigin;
    ivec3 origin = GetReflectionVolumeOrigin();
    if (firstCapture || origin != shapeDataSSBO.previousVolumeOrigin.xyz || IsReflectionLavaRefreshFrame(frameCounter))
        blockDataSSBO.lavaRefreshFrame = uint(frameCounter + 1);
    shapeDataSSBO.volumeOrigin = ivec4(origin, 0);
    shapeDataSSBO.captureFrame = captureFrame + 1u;

    // Keep this region's previous faces alive during capture for light blending.
    uint capacity = 2u * reflectionFaceCapacity;
    writeStart = blockDataSSBO.nextRegionStart;
    oldestLiveStart = blockDataSSBO.regionStartIndices[selectedRegion];
    blockDataSSBO.allocationStartIndex = writeStart;
    blockDataSSBO.allocationCapacity = GetReflectionRingFreeCount(writeStart, oldestLiveStart, capacity);
    blockDataSSBO.regionStartIndices[selectedRegion] = writeStart;
    blockDataSSBO.faceAllocationAttempts = 0u;
    blockDataSSBO.grassCaptureCount = 0u;
}
#else
#include "/lib/voxelization/reflectionVoxelVolume.glsl"
#define SSBO_QUALIFIER
#include "/lib/voxelization/SSBOs/blockDataBuffer.glsl"
layout(local_size_x = 256) in;
const ivec3 workGroups = ivec3(64, 1, 1);
shared uint sweepGeneration;

void main() {
    if (!ReflectionStorageAvailable()) return;
    if (gl_LocalInvocationID.x == 0u) {
        if (gl_WorkGroupID == uvec3(0u)) {
            blockDataSSBO.faceAllocationAttempts = 0u;
            blockDataSSBO.grassCaptureCount = 0u;
            sweepGeneration = atomicAdd(blockDataSSBO.faceGeneration, 1u) + 1u;
        } else {
            sweepGeneration = atomicAdd(blockDataSSBO.faceGeneration, 0u);
        }
    }
    barrier();
    uint chunk = (uint(reflectionFaceCount) + 1023u) / 1024u;
    uint group = gl_WorkGroupID.x + gl_NumWorkGroups.x * (gl_WorkGroupID.y + gl_NumWorkGroups.y * gl_WorkGroupID.z);
    uint stride = gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z * gl_WorkGroupSize.x;
    for (uint step = 0u; step < 2u; step++) {
        uint chunkStart = ((sweepGeneration + step) & 1023u) * chunk;
        for (uint i = group * gl_WorkGroupSize.x + gl_LocalInvocationID.x; i < chunk; i += stride) {
            uint index = chunkStart + i;
            if (index < uint(reflectionFaceCount)) blockDataSSBO.words[index] = 0u;
        }
    }
}
#endif
