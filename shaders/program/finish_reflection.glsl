#include "/lib/common.glsl"
#include "/lib/voxelization/reflectionVoxelVolume.glsl"
#define SSBO_QUALIFIER
#include "/lib/voxelization/SSBOs/blockDataBuffer.glsl"
#include "/lib/voxelization/SSBOs/shapeDataBuffer.glsl"

layout(local_size_x = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);

void main() {
    if (!ReflectionStorageAvailable()) return;
    shapeDataSSBO.nextRegionStart = GetShapeRecordIndex(GetCapturedShapeRecordCount());
    blockDataSSBO.nextRegionStart = GetReflectionRingIndex(blockDataSSBO.allocationStartIndex,
        min(blockDataSSBO.faceAllocationAttempts, blockDataSSBO.allocationCapacity), 2u * reflectionFaceCapacity);
}
