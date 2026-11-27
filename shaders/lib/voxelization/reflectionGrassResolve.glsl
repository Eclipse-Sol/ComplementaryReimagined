uint GetCapturedReflectionFaceIndex(uint key, out uint generation) {
    generation = 0u;
    uint voxel = key & sceneVoxelIndexMask;
    uint face = key >> sceneVoxelIndexBits;
    if (voxel >= uint(sceneVoxelCount) || face >= 6u) return 0xffffffffu;
    reflectionCellHandle cell = GetReflectionCellHandle(GetSceneVoxelPosition(voxel));
    generation = cell.regionGeneration;
    #ifdef WSR_FACE_LIST
        if (cell.regionGeneration == 0u) return 0xffffffffu;
        uvec4 record;
        return FindReflectionFaceRecord(blockDataSSBO.words[voxel], face, cell.regionGeneration, record);
    #else
    uint reference = blockDataSSBO.words[6u * voxel + face];
    uint pointer = reference & reflectionFacePointerMask;
    if (pointer == 0u || pointer > reflectionFaceCapacity || cell.regionGeneration == 0u
        || (reference & reflectionFaceStampMask) != GetReflectionFaceStamp(cell.regionGeneration)) return 0xffffffffu;
    uint baseIndex = pointer - 1u + (cell.regionGeneration & 1u) * reflectionFaceCapacity;
    if (LoadReflectionFaceRecord(baseIndex).w != cell.regionGeneration) return 0xffffffffu;
    return baseIndex;
    #endif
}

void ResolveGrassSideOverlay(uint index) {
    uvec4 capture = LoadReflectionGrassCapture(index);
    uint generation;
    uint baseIndex = GetCapturedReflectionFaceIndex(capture.w, generation);
    if (baseIndex == 0xffffffffu) return;
    uint word = uint(reflectionFaceRecordBase) + 4u * GetReflectionFaceAuxIndex(baseIndex);
    if (blockDataSSBO.words[word + 3u] != (generation | reflectionFaceAuxFlag)
        || (blockDataSSBO.words[word + 2u] & reflectionFaceAuxLavaFlag) != 0u) return;
    blockDataSSBO.words[word] = capture.x;
    blockDataSSBO.words[word + 1u] = capture.y;
    blockDataSSBO.words[word + 2u] = capture.z | reflectionFaceAuxResolvedFlag;
}

#if WORLD_SPACE_SMOOTH_LIGHTING > 0
void ResolveReflectionCornerLighting(uint index) {
    uint captureWord = uint(reflectionCornerCaptureBase) + 2u * index;
    uint generation;
    uint baseIndex = GetCapturedReflectionFaceIndex(blockDataSSBO.words[captureWord], generation);
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
    uint word = uint(reflectionFaceRecordBase) + 4u * index;
    uint key = blockDataSSBO.words[word + 2u];
    if ((key & reflectionFaceAuxFlagsMask) != reflectionFaceAuxLavaFlag
        || blockDataSSBO.words[word + 3u] != (shapeDataSSBO.captureFrame | reflectionFaceAuxFlag)) return;
    ivec3 cell = GetSceneVoxelPosition(key & sceneVoxelIndexMask);
    uvec4 corners = GetLavaCornerWords(cell);
    if (any(notEqual(corners & uvec4(lavaFrameStampMask), uvec4(GetLavaFrameStamp())))) return;
    corners &= uvec4(4095u);
    blockDataSSBO.words[word] = corners.x | (corners.y << 12u);
    blockDataSSBO.words[word + 1u] = corners.z | (corners.w << 12u);
    blockDataSSBO.words[word + 2u] = key | reflectionFaceAuxResolvedFlag;
}
#endif
