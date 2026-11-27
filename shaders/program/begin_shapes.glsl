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

// A retired slot just before an empty slot ends every probe chain that reaches it, so it can be emptied.
void EmptyRetiredShapeCells(uint slot) {
    if (atomicAdd(shapeHeadSSBO.words[GetShapeCellNextSlot(slot)], 0u) != shapeCellEmpty) return;
    for (uint i = 0u; i < shapeCellMaxProbes; i++) {
        if (atomicCompSwap(shapeHeadSSBO.words[slot], shapeCellRetired, shapeCellEmpty) != shapeCellRetired) return;
        slot = slot == 0u ? shapeCellCapacity - 1u : slot - 1u;
    }
}

void RetireShapeCell(uint slot, bool checkExposed, ivec3 volumeMove) {
    uint key = shapeHeadSSBO.words[slot];
    if (key == shapeCellEmpty) return;
    if (key == shapeCellRetired) {
        EmptyRetiredShapeCells(slot);
        return;
    }
    bool retire = (key & shapeCellHaloFlag) != 0u;
    ivec3 cell = GetSceneVoxelPosition(GetShapeCellVoxelIndex(key));
    if (!retire) retire = IsReflectionCellSelected(cell);
    if (!retire && checkExposed) {
        ivec3 previousPosition = cell / sceneVoxelCoarseCellSize * sceneVoxelCoarseCellSize + volumeMove;
        retire = shapeDataSSBO.captureFrame == 1u || any(lessThan(previousPosition, ivec3(0)))
            || any(greaterThanEqual(previousPosition, sceneVoxelVolumeSize));
    }
    if (retire) {
        shapeHeadSSBO.words[GetShapeCellHeadWord(slot)] = 0u;
        atomicAnd(shapeHeadSSBO.words[GetShapeCellStateWord(slot)], ~(shapeCellStateLaneMask << GetShapeCellStateShift(slot)));
        atomicExchange(shapeHeadSSBO.words[slot], shapeCellRetired);
        memoryBarrierBuffer();
        EmptyRetiredShapeCells(slot);
    }
}
const uint slicesPerGroup = 16u / uint(sceneVoxelCoarseCellSize.y);
const uint threadsPerSlice = 256u / slicesPerGroup;
shared bool tilesToClear[slicesPerGroup];
shared uint distanceDemand[shapeDistanceBucketCount];

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
            #ifdef WSR_FACE_LIST
                if (newlyExposed) blockDataSSBO.words[index] = 0u;
            #else
            if (newlyExposed) for (int face = 0; face < 6; face++)
                blockDataSSBO.words[6 * index + face] = 0u;
            #endif
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
    ivec3 volumeMove = shapeDataSSBO.volumeOrigin.xyz - shapeDataSSBO.previousVolumeOrigin.xyz;
    bool checkExposed = shapeDataSSBO.captureFrame == 1u || any(notEqual(volumeMove, ivec3(0)));
    uint regionLogStart = shapeHeadSSBO.regionLogStart[shapeDataSSBO.selectedRegion];
    uint regionLogCount = shapeHeadSSBO.regionLogEnd[shapeDataSSBO.selectedRegion] - regionLogStart;
    uint haloLogCount = shapeHeadSSBO.previousHaloLogCount;
    bool logsComplete = shapeHeadSSBO.shapeClaimLogEnd - regionLogStart <= shapeClaimLogCapacity
                 && haloLogCount <= shapeHaloClaimLogCapacity;
    // Usually only the slots claimed the last time this region was captured plus last frame's halo claims, can need retiring.
    if (checkExposed || !logsComplete) {
        for (uint slot = invocation; slot < shapeCellCapacity; slot += stride) RetireShapeCell(slot, checkExposed, volumeMove);
    } else {
        for (uint i = invocation; i < regionLogCount; i += stride)
            RetireShapeCell(shapeHeadSSBO.words[GetShapeClaimLogWord(regionLogStart + i)], false, volumeMove);
        for (uint i = invocation; i < haloLogCount; i += stride)
            RetireShapeCell(shapeHeadSSBO.words[GetShapeHaloClaimLogWord(i)], false, volumeMove);
    }
    const uint faceSweepPeriod = reflectionFaceStampPeriod - 1u - uint(reflectionActiveRegionCount);
    uint faceSlice = (uint(reflectionFaceRefCount) + faceSweepPeriod - 1u) / faceSweepPeriod;
    uint threadOffset = group * gl_WorkGroupSize.x + threadIndex;
    uint faceIndex = (shapeDataSSBO.captureFrame % faceSweepPeriod) * faceSlice + threadOffset;
    if (threadOffset < faceSlice && faceIndex < uint(reflectionFaceRefCount)) {
        uint reference = blockDataSSBO.words[faceIndex];
        if (reference != 0u) {
            #ifdef WSR_FACE_LIST
                int region = GetReflectionCellRegion(GetSceneVoxelPosition(faceIndex));
            #else
            int region = GetReflectionCellRegion(GetSceneVoxelPosition(faceIndex / 6u));
            #endif
            uint regionGeneration = shapeDataSSBO.regionGenerations[region];
            uint stamp = reference & reflectionFaceStampMask;
            bool live = regionGeneration != 0u && stamp == GetReflectionFaceStamp(regionGeneration);
            bool previous = uint(region) == shapeDataSSBO.selectedRegion && shapeDataSSBO.previousRegionGeneration != 0u
                && stamp == GetReflectionFaceStamp(shapeDataSSBO.previousRegionGeneration);
            if (!live && !previous) blockDataSSBO.words[faceIndex] = 0u;
        }
    }
    if (group == 0u) {
        uint region = shapeDataSSBO.selectedRegion;
        if (threadIndex < shapeDistanceBucketCount) {
            uint demand = 0u;
            for (uint row = 0u; row <= shapeDistanceHaloRow; row++)
                demand += shapeHeadSSBO.shapeDistanceDemand[row * shapeDistanceBucketCount + threadIndex];
            distanceDemand[threadIndex] = demand;
        }
        barrier();
        if (threadIndex == 0u) {
            uint fitLimit = shapeRecordCapacity - shapeRecordCapacity / 16u;
            uint comfortableLimit = shapeRecordCapacity - shapeRecordCapacity / 8u;
            uint total = 0u, farthestFit = 0u, farthestComfortable = 0u;
            for (uint bucket = 0u; bucket < shapeDistanceBucketCount; bucket++) {
                total += distanceDemand[bucket];
                if (total <= fitLimit) farthestFit = bucket;
                if (total <= comfortableLimit) farthestComfortable = bucket;
            }
            uint previousCutoff = shapeDataSSBO.captureFrame == 1u ? shapeDistanceBucketCount - 1u : shapeHeadSSBO.shapeDistanceCutoff;
            shapeHeadSSBO.shapeDistanceCutoff = clamp(previousCutoff, farthestComfortable, farthestFit);
        }
        barrier();
        if (threadIndex < shapeDistanceBucketCount) {
            shapeHeadSSBO.shapeDistanceDemand[region * shapeDistanceBucketCount + threadIndex] = 0u;
            shapeHeadSSBO.shapeDistanceDemand[shapeDistanceHaloRow * shapeDistanceBucketCount + threadIndex] = 0u;
        }
    }
}
