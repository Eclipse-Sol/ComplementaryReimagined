void ResolveGrassSideOverlay(uint index) {
    uvec4 capture = LoadReflectionGrassCapture(index);
    uint voxel = capture.w & 0xffffffu;
    uint face = capture.w >> 24u;
    if (voxel >= uint(sceneVoxelCount) || face >= 6u) return;
    reflectionCellHandle cell = GetReflectionCellHandle(GetSceneVoxelPosition(voxel));
    uint reference = blockDataSSBO.words[6u * voxel + face];
    uint pointer = reference & reflectionFacePointerMask;
    #if WORLD_SPACE_SHAPES > 0
        const uint capacity = 2u * reflectionFaceCapacity;
    #else
        const uint capacity = reflectionFaceCapacity;
    #endif
    if (pointer == 0u || pointer > capacity || cell.regionGeneration == 0u
        || (reference & reflectionFaceStampMask) != ((cell.regionGeneration << 22u) & reflectionFaceStampMask)) return;
    uint baseIndex = pointer - 1u;
    #if WORLD_SPACE_SHAPES <= 0
        baseIndex += (cell.regionGeneration & 1u) * reflectionFaceCapacity;
    #endif
    if (LoadReflectionFaceRecord(baseIndex).w != cell.regionGeneration) return;
    uint word = uint(reflectionGrassOverlayBase) + 4u * baseIndex;
    blockDataSSBO.words[word] = capture.x;
    blockDataSSBO.words[word + 1u] = capture.y;
    blockDataSSBO.words[word + 2u] = capture.z;
    blockDataSSBO.words[word + 3u] = cell.regionGeneration;
}
