#include "/lib/common.glsl"
#include "/lib/voxelization/reflectionVoxelVolume.glsl"
#define SSBO_QUALIFIER
#include "/lib/voxelization/SSBOs/blockDataBuffer.glsl"
#include "/lib/voxelization/SSBOs/shapeDataBuffer.glsl"
#include "/lib/voxelization/SSBOs/shapeHeadBuffer.glsl"

layout(local_size_x = 256) in;
#include "/lib/voxelization/reflectionTileDispatch.glsl"
layout(r16ui) writeonly uniform uimage3D wsr_img;
layout(r8ui) writeonly uniform uimage3D wsr_lod_img;
layout(r8ui) uniform uimage3D wsr_coarse_img;
const uint slicesPerGroup = 16u / uint(sceneVoxelCoarseCellSize.y);
const uint threadsPerSlice = 256u / slicesPerGroup;
shared bool tilesToClear[slicesPerGroup];

void main() {
    if (!ReflectionStorageAvailable()) return;
    uint threadIndex = gl_LocalInvocationID.x;
    uint group = gl_WorkGroupID.x + gl_NumWorkGroups.x * (gl_WorkGroupID.y + gl_NumWorkGroups.y * gl_WorkGroupID.z);
    uint slice = threadIndex / threadsPerSlice;
    uint threadInSlice = threadIndex % threadsPerSlice;
    ivec3 tile = ivec3(gl_WorkGroupID.x, gl_WorkGroupID.y * slicesPerGroup + slice, gl_WorkGroupID.z);
    ivec3 previousVolumePosition = tile * sceneVoxelCoarseCellSize + shapeDataSSBO.volumeOrigin.xyz - shapeDataSSBO.previousVolumeOrigin.xyz;
    bool newlyExposed = shapeDataSSBO.captureFrame == 1u || any(lessThan(previousVolumePosition, ivec3(0)))
        || any(greaterThanEqual(previousVolumePosition, sceneVoxelVolumeSize));
    if (threadInSlice == 0u) {
        bool selected = IsReflectionCellSelected(tile * sceneVoxelCoarseCellSize);
        tilesToClear[slice] = newlyExposed || (selected
            && imageLoad(wsr_coarse_img, GetSceneVoxelCoarseStoragePosition(tile)).r != 0u);
    }
    barrier();
    if (tilesToClear[slice]) {
        const int layerStride = int(threadsPerSlice) / (sceneVoxelCoarseCellSize.x * sceneVoxelCoarseCellSize.y);
        ivec3 local = ivec3(int(threadInSlice) % sceneVoxelCoarseCellSize.x,
            (int(threadInSlice) / sceneVoxelCoarseCellSize.x) % sceneVoxelCoarseCellSize.y,
            int(threadInSlice) / (sceneVoxelCoarseCellSize.x * sceneVoxelCoarseCellSize.y));
        ivec3 base = tile * sceneVoxelCoarseCellSize + local;
        for (int z = 0; z < sceneVoxelCoarseCellSize.z; z += layerStride) {
            ivec3 cell = base + ivec3(0, 0, z);
            ivec3 storage = GetSceneVoxelStoragePosition(cell);
            int index = GetSceneVoxelIndexFromStorage(storage);
            imageStore(wsr_img, storage, uvec4(0u));
            if (newlyExposed) shapeHeadSSBO.heads[index] = 0u;
            blockDataSSBO.words[reflectionMetadataBase + lavaCornerCount + index] = 0u;
            if (newlyExposed) for (int face = 0; face < 6; face++)
                blockDataSSBO.words[6 * index + face] = 0u;
        }
        const ivec3 lodCells = sceneVoxelCoarseCellSize / 4;
        if (int(threadInSlice) < lodCells.x * lodCells.y * lodCells.z) {
            ivec3 lod = ivec3(int(threadInSlice) % lodCells.x, (int(threadInSlice) / lodCells.x) % lodCells.y,
                int(threadInSlice) / (lodCells.x * lodCells.y));
            imageStore(wsr_lod_img, GetSceneVoxelLodStoragePosition(tile * lodCells + lod), uvec4(0u));
        }
        if (threadInSlice == 0u) imageStore(wsr_coarse_img, GetSceneVoxelCoarseStoragePosition(tile), uvec4(0u));
    }
    uint invocation = group * gl_WorkGroupSize.x + threadIndex;
    uint stride = gl_NumWorkGroups.x * gl_NumWorkGroups.y * gl_NumWorkGroups.z * gl_WorkGroupSize.x;
    for (uint i = invocation; i < shapeHaloHeadCapacity; i += stride) {
        shapeHeadSSBO.haloCellKeys[i] = 0u;
        if (shapeDataSSBO.captureFrame == 1u) shapeHeadSSBO.haloHeads[i] = 0u;
    }
    uint haloSlice = (shapeHaloHeadCapacity + 2047u) / 2048u;
    uint haloIndex = (shapeDataSSBO.captureFrame & 2047u) * haloSlice + invocation;
    if (invocation < haloSlice && haloIndex < shapeHaloHeadCapacity)
        shapeHeadSSBO.haloHeads[haloIndex] = 0u;

    const uint headSweepPeriod = uint(2048 - reflectionActiveRegionCount);
    uint headSlice = (uint(sceneVoxelCount) + headSweepPeriod - 1u) / headSweepPeriod;
    uint headIndex = (shapeDataSSBO.captureFrame % headSweepPeriod) * headSlice + invocation;
    if (invocation < headSlice && headIndex < uint(sceneVoxelCount)) {
        uint word = shapeHeadSSBO.heads[headIndex];
        if (word != 0u) {
            int region = GetReflectionCellRegion(GetSceneVoxelPosition(headIndex));
            uint regionGeneration = shapeDataSSBO.regionGenerations[region];
            if (regionGeneration == 0u || (word & shapeHeadStampMask) != ((regionGeneration & 2047u) << 21u))
                shapeHeadSSBO.heads[headIndex] = 0u;
        }
    }
    const uint faceSweepPeriod = uint(1023 - reflectionActiveRegionCount);
    uint faceSlice = (uint(reflectionFaceCount) + faceSweepPeriod - 1u) / faceSweepPeriod;
    uint threadOffset = group * gl_WorkGroupSize.x + threadIndex;
    uint faceIndex = (shapeDataSSBO.captureFrame % faceSweepPeriod) * faceSlice + threadOffset;
    if (threadOffset < faceSlice && faceIndex < uint(reflectionFaceCount)) {
        uint reference = blockDataSSBO.words[faceIndex];
        if (reference != 0u) {
            int region = GetReflectionCellRegion(GetSceneVoxelPosition(faceIndex / 6u));
            uint regionGeneration = shapeDataSSBO.regionGenerations[region];
            uint stamp = reference & reflectionFaceStampMask;
            bool live = regionGeneration != 0u && stamp == ((regionGeneration << 22u) & reflectionFaceStampMask);
            bool previous = uint(region) == shapeDataSSBO.selectedRegion && shapeDataSSBO.previousRegionGeneration != 0u
                && stamp == ((shapeDataSSBO.previousRegionGeneration << 22u) & reflectionFaceStampMask);
            if (!live && !previous) blockDataSSBO.words[faceIndex] = 0u;
        }
    }
}
