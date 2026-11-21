#ifndef INCLUDE_ACT_STATE
#define INCLUDE_ACT_STATE
#extension GL_ARB_shader_storage_buffer_object : enable

// [0-1]    number of bricks to compute
// [2-13]   floodfill camera block for the last 4 frames
// [14-25]  view direction for the last 4 frames, same slots
// [26]     frameCounter + 1 of the last brick list, 0 after allocation
// [27-28]  clear list length, one counter per frame parity
// [29]     how many previous frames are usable, max 3
// [30]     frameTimeCounter of the last brick list
// [31]     unused
// [32...]  brick list: bricks to compute this frame
// then     brick hashes: per parity and brick, 2 hashes of what the shadow pass wrote, plus a flag for
//          conflicting IDs and item/entity lights
// then     clear list: bricks the shadow pass wrote, begin3 clears them next frame
layout(std430, binding = 8)
#if !defined SHADOWCOMP && !defined ACT_VOXEL_CLEAR && !(defined SHADOW && defined VERTEX_SHADER)
readonly
#endif
buffer actStateBuffer {
    uint actState[];
};
const uint actBrickListStart = 32u;
const uint actLastFrameWord = 26u;
const uint actClearCountWord = 27u;
const uint actHistoryLengthWord = 29u;
const uint actLastFrameTimeWord = 30u;

uint BrickToLinearIndex(ivec3 storageBrick) {
    return uint(storageBrick.x + brickGrid.x * (storageBrick.y + brickGrid.y * storageBrick.z));
}

ivec3 LinearIndexToBrick(uint index) {
    return ivec3(index % uint(brickGrid.x), (index / uint(brickGrid.x)) % uint(brickGrid.y), index / uint(brickGrid.x * brickGrid.y));
}

uint GetBrickHashIndex(ivec3 storageBrick, int frameParity) {
    return actBrickListStart + volumeBrickCount + 3u * (uint(frameParity) * volumeBrickCount + BrickToLinearIndex(storageBrick));
}

uint GetClearListIndex(uint entry) {
    return actBrickListStart + 7u * volumeBrickCount + entry;
}

uint PackBrick(ivec3 brick) {
    return uint(brick.x) | (uint(brick.y) << 10u) | (uint(brick.z) << 20u);
}

ivec3 UnpackBrick(uint packedBrick) {
    return ivec3(packedBrick & 1023u, (packedBrick >> 10u) & 1023u, (packedBrick >> 20u) & 1023u);
}

// funky hash function! Needed some ai help for this...
#if defined SHADOW && defined VERTEX_SHADER
    // lowbias32 (hash-prospector)
    uint HashMix(uint x) {
        x ^= x >> 16u; x *= 0x7feb352du; x ^= x >> 15u; x *= 0x846ca68bu; x ^= x >> 16u;
        return x;
    }

    void HashVoxelWrite(ivec3 storagePos, uint value) {
        uint key = uint(storagePos.x + voxelVolumeSize.x * (storagePos.y + voxelVolumeSize.y * storagePos.z));
        uint i = GetBrickHashIndex(storagePos >> 3, int(framemod2));
        uint h = HashMix(key * 0x9e3779b1u ^ value);
        atomicAdd(actState[i], h);
        atomicAdd(actState[i + 1u], HashMix(h));
    }

    void MarkConflictingBrick(ivec3 storagePos) {
        atomicOr(actState[GetBrickHashIndex(storagePos >> 3, int(framemod2)) + 2u], 1u);
    }
#endif

#if defined SHADOWCOMP || defined ACT_VOXEL_CLEAR
    void ClearBrickHash(ivec3 storageBrick, int frameParity) {
        uint i = GetBrickHashIndex(storageBrick, frameParity);
        actState[i] = 0u; actState[i + 1u] = 0u; actState[i + 2u] = 0u;
    }
#endif

#if defined SHADOWCOMP || defined ACT_VOXEL_CLEAR || defined ACT_TRACK_CAMERA_DELTA
    uint HistorySlot(int framesAgo) {
        return uint((frameCounter - framesAgo) & 3);
    }

    ivec3 GetHistoryCameraBlock(int framesAgo) {
        uint i = 2u + 3u * HistorySlot(framesAgo);
        return ivec3(actState[i], actState[i + 1u], actState[i + 2u]);
    }
#endif

#ifdef ACT_VOXEL_CLEAR
    void SetHistoryCameraBlock(ivec3 cameraBlock) {
        uint i = 2u + 3u * HistorySlot(0);
        actState[i] = uint(cameraBlock.x); actState[i + 1u] = uint(cameraBlock.y); actState[i + 2u] = uint(cameraBlock.z);
    }
#endif

#ifdef SHADOWCOMP
    vec3 GetHistoryViewDirection(int framesAgo) {
        uint i = 14u + 3u * HistorySlot(framesAgo);
        return uintBitsToFloat(uvec3(actState[i], actState[i + 1u], actState[i + 2u]));
    }

    void SetHistoryViewDirection(vec3 viewDirection) {
        uint j = 14u + 3u * HistorySlot(0);
        uvec3 d = floatBitsToUint(viewDirection);
        actState[j] = d.x; actState[j + 1u] = d.y; actState[j + 2u] = d.z;
    }

    vec3 GetFloodfillViewDirection() {
        vec4 viewPos = gbufferProjectionInverse * vec4(0.0, 0.0, 1.0, 1.0);
        viewPos /= viewPos.w;
        return normalize(mat3(gbufferModelViewInverse) * viewPos.xyz);
    }
#endif

#endif
