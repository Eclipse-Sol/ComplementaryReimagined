uint GetCapturedReflectionFaceIndex(uint key) {
    uint voxel = key & 0xffffffu;
    uint face = key >> 24u;
    if (voxel >= uint(sceneVoxelCount) || face >= 6u) return 0xffffffffu;
    reflectionCellHandle cell = GetReflectionCellHandle(GetSceneVoxelPosition(voxel));
    uint reference = blockDataSSBO.words[6u * voxel + face];
    uint pointer = reference & reflectionFacePointerMask;
    #if WORLD_SPACE_SHAPES > 0
        const uint capacity = 2u * reflectionFaceCapacity;
    #else
        const uint capacity = reflectionFaceCapacity;
    #endif
    if (pointer == 0u || pointer > capacity || cell.regionGeneration == 0u
        || (reference & reflectionFaceStampMask) != ((cell.regionGeneration << 22u) & reflectionFaceStampMask)) return 0xffffffffu;
    uint baseIndex = pointer - 1u;
    #if WORLD_SPACE_SHAPES <= 0
        baseIndex += (cell.regionGeneration & 1u) * reflectionFaceCapacity;
    #endif
    if (LoadReflectionFaceRecord(baseIndex).w != cell.regionGeneration) return 0xffffffffu;
    return baseIndex;
}

void ResolveGrassSideOverlay(uint index) {
    uvec4 capture = LoadReflectionGrassCapture(index);
    uint baseIndex = GetCapturedReflectionFaceIndex(capture.w);
    if (baseIndex == 0xffffffffu) return;
    uint generation = LoadReflectionFaceRecord(baseIndex).w;
    uint word = uint(reflectionFaceAuxBase) + 4u * baseIndex;
    blockDataSSBO.words[word] = capture.x;
    blockDataSSBO.words[word + 1u] = capture.y;
    blockDataSSBO.words[word + 2u] = capture.z;
    blockDataSSBO.words[word + 3u] = generation;
}

#if WORLD_SPACE_SMOOTH_LIGHTING > 0
void ResolveReflectionCornerLighting(uint index) {
    uint captureWord = uint(reflectionCornerCaptureBase) + 2u * index;
    uint baseIndex = GetCapturedReflectionFaceIndex(blockDataSSBO.words[captureWord]);
    if (baseIndex == 0xffffffffu) return;
    uint value = blockDataSSBO.words[captureWord + 1u];
    uint corner = (value >> 28u) & 3u;
    uint word = uint(reflectionFaceCornersBase) + 4u * baseIndex + corner;
    // Duplicate model quads can address the same corner.
    atomicMax(blockDataSSBO.words[word], value);
}
#endif

#if WORLD_SPACE_SHAPES > 0
void ResolveReflectionLavaHeights(uint offset) {
    uint count = min(blockDataSSBO.faceAllocationAttempts, blockDataSSBO.allocationCapacity);
    if (offset >= count) return;
    uint index = GetReflectionRingIndex(blockDataSSBO.allocationStartIndex, offset, 2u * reflectionFaceCapacity);
    uint word = uint(reflectionFaceAuxBase) + 4u * index;
    uint key = blockDataSSBO.words[word + 2u];
    if ((key & 0x80000000u) == 0u || blockDataSSBO.words[word + 3u] != shapeDataSSBO.captureFrame) return;
    ivec3 cell = GetSceneVoxelPosition(key & 0xffffffu);
    uvec4 corners = GetLavaCornerWords(cell);
    if (any(notEqual(corners & uvec4(0xfffff000u), uvec4(GetLavaFrameStamp())))) return;
    corners &= uvec4(4095u);
    blockDataSSBO.words[word] = corners.x | (corners.y << 12u);
    blockDataSSBO.words[word + 1u] = corners.z | (corners.w << 12u);
    blockDataSSBO.words[word + 2u] = key | 0x40000000u;
}
#endif
