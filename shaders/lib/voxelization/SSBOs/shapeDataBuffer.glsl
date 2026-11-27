#extension GL_ARB_shader_storage_buffer_object : enable

// Keep in sync with bufferObject.4, .6 and .7.
// Rules for each size set:
// - shapeRecordCapacity + 1 must fit in shapeRecordPointerBits.
// - shapeCellCapacity == shapeCellCapacityFactor << (32 - shapeCellHashShift).
// - shapeClaimLogCapacity must be a power of two.
const uint shapeRecordPointerBits = 24u;
#if COLORED_LIGHTING >= 256 && WSR_VOLUME_HEIGHT == 256 && defined WSR_TALL_VOLUME
    const uint shapeRecordCapacity = 8388607u; // 256 MiB
    const uint shapeCellCapacity = 16777216u;
    const uint shapeCellHashShift = 8u;
    const uint shapeCellCapacityFactor = 1u;
    const uint shapeClaimLogCapacity = 4194304u;
    const uint shapeHaloClaimLogCapacity = 524288u;
#elif COLORED_LIGHTING >= 256 && defined WSR_TALL_VOLUME
    const uint shapeRecordCapacity = 6291455u; // 192 MiB
    const uint shapeCellCapacity = 12582912u;
    const uint shapeCellHashShift = 10u;
    const uint shapeCellCapacityFactor = 3u;
    const uint shapeClaimLogCapacity = 4194304u;
    const uint shapeHaloClaimLogCapacity = 524288u;
#elif COLORED_LIGHTING >= 256 || COLORED_LIGHTING >= 192 && WSR_VOLUME_HEIGHT == 256 && defined WSR_TALL_VOLUME
    const uint shapeRecordCapacity = 4194303u; // 128 MiB
    const uint shapeCellCapacity = 8388608u;
    const uint shapeCellHashShift = 9u;
    const uint shapeCellCapacityFactor = 1u;
    const uint shapeClaimLogCapacity = 2097152u;
    const uint shapeHaloClaimLogCapacity = 262144u;
#elif COLORED_LIGHTING >= 192 && defined WSR_TALL_VOLUME
    const uint shapeRecordCapacity = 3145727u; // 96 MiB
    const uint shapeCellCapacity = 6291456u;
    const uint shapeCellHashShift = 11u;
    const uint shapeCellCapacityFactor = 3u;
    const uint shapeClaimLogCapacity = 2097152u;
    const uint shapeHaloClaimLogCapacity = 262144u;
#elif COLORED_LIGHTING >= 192 || WSR_VOLUME_HEIGHT == 256 && defined WSR_TALL_VOLUME
    const uint shapeRecordCapacity = 2097151u; // 64 MiB
    const uint shapeCellCapacity = 4194304u;
    const uint shapeCellHashShift = 10u;
    const uint shapeCellCapacityFactor = 1u;
    const uint shapeClaimLogCapacity = 1048576u;
    const uint shapeHaloClaimLogCapacity = 131072u;
#elif defined WSR_TALL_VOLUME
    const uint shapeRecordCapacity = 1572863u; // 48 MiB
    const uint shapeCellCapacity = 3145728u;
    const uint shapeCellHashShift = 12u;
    const uint shapeCellCapacityFactor = 3u;
    const uint shapeClaimLogCapacity = 1048576u;
    const uint shapeHaloClaimLogCapacity = 131072u;
#else
    const uint shapeRecordCapacity = 1048575u; // 32 MiB
    const uint shapeCellCapacity = 2097152u;
    const uint shapeCellHashShift = 11u;
    const uint shapeCellCapacityFactor = 1u;
    const uint shapeClaimLogCapacity = 524288u;
    const uint shapeHaloClaimLogCapacity = 65536u;
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
