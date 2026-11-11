#extension GL_ARB_shader_storage_buffer_object : enable

// Keep in sync with bufferObject.4 and .7
#if COLORED_LIGHTING >= 256
    const uint shapeRecordCapacity = 2097151u; // 64 MiB
#elif COLORED_LIGHTING >= 192
    const uint shapeRecordCapacity = 1048575u; // 32 MiB
#else
    const uint shapeRecordCapacity = 524288u;  // 16 MiB
#endif
struct shapeRecord {
    uvec4 shading;
    uvec4 mapping;
};
layout(std430, binding = 4) SSBO_QUALIFIER buffer shapeDataBuffer {
    uint capturedRecordCount;
    uint headerPadding;
    uint frozenRecordCount;
    uint captureFrame;
    uint allocationStartIndex;
    uint allocationCapacity;
    uint nextRegionStart;
    uint selectedRegion;
    uint previousRegionGeneration;
    uint regionStartIndices[reflectionMaxRegionCount];
    uint regionGenerations[reflectionMaxRegionCount];
    uint haloRecordCount;
    uint frozenHaloRecordCount;
    uint allocationAttempts;
    ivec4 previousVolumeOrigin;
    ivec4 volumeOrigin;
    shapeRecord records[];
} shapeDataSSBO;

bool IsReflectionCellSelected(ivec3 cell) {
    return GetReflectionCellRegion(cell) == int(shapeDataSSBO.selectedRegion);
}

uint GetCapturedShapeRecordCount() {
    return min(shapeDataSSBO.capturedRecordCount, shapeDataSSBO.allocationCapacity);
}

uint GetShapeRecordIndex(uint offset) {
    return GetReflectionRingIndex(shapeDataSSBO.allocationStartIndex, offset, shapeRecordCapacity);
}

uint GetHaloShapeRecordIndex(uint offset) {
    return GetShapeRecordIndex(shapeDataSSBO.allocationCapacity - 1u - offset);
}

uint GetShapeBuildInputIndex(uint offset, uint capturedRecordCount) {
    return offset < capturedRecordCount ? GetShapeRecordIndex(offset) : GetHaloShapeRecordIndex(offset - capturedRecordCount);
}

#if defined SHADOW && defined VERTEX_SHADER || defined SHAPE_SCATTER
    uint AllocateShapeRecord(bool halo) {
        if (atomicAdd(shapeDataSSBO.allocationAttempts, 1u) >= shapeDataSSBO.allocationCapacity) return shapeRecordCapacity;
        if (halo) return GetHaloShapeRecordIndex(atomicAdd(shapeDataSSBO.haloRecordCount, 1u));
        return GetShapeRecordIndex(atomicAdd(shapeDataSSBO.capturedRecordCount, 1u));
    }
#endif
