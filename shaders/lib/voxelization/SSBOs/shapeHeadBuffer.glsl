#extension GL_ARB_shader_storage_buffer_object : enable
const uint shapeHeadPointerMask = (1u << shapeRecordPointerBits) - 1u;
const uint shapeHeadStampMask = ~shapeHeadPointerMask;

// Shapes cell table
// Linear probing hash, key = voxel index + 1 (| shapeCellHaloFlag)
//
// words[] holds key slots, then (head, head, two 16-bit states) per slot pair, then claim logs and corner lighting.
// Removed keys become retired so probe chains past them stay intact. Reusing a retired slot can't
// duplicate a key since begin_shapes first retires every key a frame can insert (selected and halo cells).
// Claim logs list claimed slots, so begin_shapes can retire one region without scanning the table.
const uint shapeCellEmpty = 0u;
const uint shapeCellRetired = 0x80000000u;
const uint shapeCellHaloFlag = 0x08000000u;
const uint shapeCellKeyMask = 0x0fffffffu;
const uint shapeCellMaxProbes = 1024u;
const uint shapeCellStateLaneMask = 0xffffu;
const uint shapeStateMask = 4095u;
const uint shapeClaimLogBase = shapeCellCapacity + 3u * (shapeCellCapacity / 2u);
const uint shapeHaloClaimLogBase = shapeClaimLogBase + shapeClaimLogCapacity;
const uint shapeCornerLightingBase = shapeHaloClaimLogBase + shapeHaloClaimLogCapacity;
const uint shapeCornerLightingCapacity = shapeRecordCapacity;
const uint shapeCornerLightingHaloFlag = 1u << 27u;
const uint shapeCornerLightingCorner3Flag = 1u << 28u;
const uint shapeDistanceBucketCount = 32u;
const float shapeDistanceBucketSize = 12.0;
const uint shapeDistanceHaloRow = uint(WSR_MAX_REGIONS);
layout(std430, binding = 6) SSBO_QUALIFIER buffer shapeHeadBuffer {
    uint shapeCellProbeLimit;
    uint shapeClaimLogEnd;
    uint shapeHaloClaimLogCount;
    uint previousHaloLogCount;
    uint captureLogStart;
    uint shapeCornerLightingCount;
    uint shapeDistanceCutoff;
    uint shapeCellHeaderPadding;
    uint regionLogStart[WSR_MAX_REGIONS];
    uint regionLogEnd[WSR_MAX_REGIONS];
    uint shapeDistanceDemand[(WSR_MAX_REGIONS + 1) * int(shapeDistanceBucketCount)];
    uint words[];
} shapeHeadSSBO;

uint GetShapeHeadStamp(uint generation) {
    return (generation << shapeRecordPointerBits) & shapeHeadStampMask;
}

uint GetShapeHeadStamp() {
    return GetShapeHeadStamp(shapeDataSSBO.captureFrame);
}

uint GetShapeCellKey(int index, bool halo) {
    return uint(index + 1) | (halo ? shapeCellHaloFlag : 0u);
}

uint GetShapeCellVoxelIndex(uint key) {
    return (key & (shapeCellHaloFlag - 1u)) - 1u;
}

// floor(hash * shapeCellCapacity / 2^32) without 64-bit math, so the capacity can be 3 * 2^n.
// Needs shapeCellCapacity == shapeCellCapacityFactor << (32 - shapeCellHashShift);
// otherwise home slots land past the key slots and into the head words.
uint GetShapeCellHomeSlot(uint key) {
    uint hash = key * 2654435761u;
    uint scaled = shapeCellCapacityFactor * (hash & ((1u << shapeCellHashShift) - 1u));
    return shapeCellCapacityFactor * (hash >> shapeCellHashShift) + (scaled >> shapeCellHashShift);
}

uint GetShapeCellNextSlot(uint slot) {
    return slot + 1u == shapeCellCapacity ? 0u : slot + 1u;
}

uint GetShapeCellHeadWord(uint slot) {
    return shapeCellCapacity + 3u * (slot >> 1u) + (slot & 1u);
}

uint GetShapeCellStateWord(uint slot) {
    return shapeCellCapacity + 3u * (slot >> 1u) + 2u;
}

uint GetShapeCellStateShift(uint slot) {
    return (slot & 1u) << 4u;
}

uint GetShapeClaimLogWord(uint position) {
    return shapeClaimLogBase + (position & (shapeClaimLogCapacity - 1u));
}

uint GetShapeHaloClaimLogWord(uint index) {
    return shapeHaloClaimLogBase + index;
}

uint FindShapeCell(int index, bool halo) {
    uint key = GetShapeCellKey(index, halo);
    uint slot = GetShapeCellHomeSlot(key);
    uint limit = min(shapeHeadSSBO.shapeCellProbeLimit, shapeCellMaxProbes);
    uint slotKey = shapeHeadSSBO.words[slot];
    uint probe = 1u;
    while ((slotKey & shapeCellKeyMask) != key && slotKey != shapeCellEmpty && probe < limit) {
        slot = GetShapeCellNextSlot(slot);
        slotKey = shapeHeadSSBO.words[slot];
        probe++;
    }
    return (slotKey & shapeCellKeyMask) == key ? slot : shapeCellCapacity;
}

#if defined SHADOW && defined VERTEX_SHADER || defined SHAPE_SCATTER
    void LogShapeCellClaim(uint slot, bool halo) {
        if (halo) {
            uint index = atomicAdd(shapeHeadSSBO.shapeHaloClaimLogCount, 1u);
            if (index < shapeHaloClaimLogCapacity) shapeHeadSSBO.words[GetShapeHaloClaimLogWord(index)] = slot;
        } else {
            shapeHeadSSBO.words[GetShapeClaimLogWord(atomicAdd(shapeHeadSSBO.shapeClaimLogEnd, 1u))] = slot;
        }
    }

    uint InsertShapeCell(int index, bool halo) {
        uint key = GetShapeCellKey(index, halo);
        uint slot = GetShapeCellHomeSlot(key);
        for (uint probe = 0u; probe < shapeCellMaxProbes; probe++) {
            uint previous = atomicCompSwap(shapeHeadSSBO.words[slot], shapeCellEmpty, key);
            if (previous == shapeCellRetired)
                previous = atomicCompSwap(shapeHeadSSBO.words[slot], shapeCellRetired, key);
            if (previous == shapeCellEmpty || previous == shapeCellRetired) LogShapeCellClaim(slot, halo);
            if (previous == shapeCellEmpty || previous == shapeCellRetired || (previous & shapeCellKeyMask) == key) {
                if (probe >= shapeHeadSSBO.shapeCellProbeLimit) atomicMax(shapeHeadSSBO.shapeCellProbeLimit, probe + 1u);
                return slot;
            }
            slot = GetShapeCellNextSlot(slot);
        }
        return shapeCellCapacity;
    }

    void StoreShapeState(uint slot, uint bits) {
        if (slot != shapeCellCapacity && bits != 0u)
            atomicOr(shapeHeadSSBO.words[GetShapeCellStateWord(slot)], bits << GetShapeCellStateShift(slot));
    }
#endif

#if defined SHAPE_BUILD || defined SHADOW && defined VERTEX_SHADER
    uint ReadShapeCaptureHead(int index, bool halo) {
        uint slot = FindShapeCell(index, halo);
        if (slot == shapeCellCapacity) return 0u;
        uint word = shapeHeadSSBO.words[GetShapeCellHeadWord(slot)];
        return (word & shapeHeadStampMask) == GetShapeHeadStamp() ? word & shapeHeadPointerMask : 0u;
    }
#endif

void ReadShapeCell(reflectionCellHandle cell, out uint head, out uint state) {
    head = 0u;
    state = 0u;
    uint regionGeneration = cell.regionGeneration;
    if (regionGeneration == 0u) return;
    uint slot = FindShapeCell(cell.storageIndex, false);
    if (slot == shapeCellCapacity) return;
    uint word = shapeHeadSSBO.words[GetShapeCellHeadWord(slot)];
    if ((word & shapeHeadStampMask) == GetShapeHeadStamp(regionGeneration)) head = word & shapeHeadPointerMask;
    state = (shapeHeadSSBO.words[GetShapeCellStateWord(slot)] >> GetShapeCellStateShift(slot)) & shapeStateMask;
}

#if defined SHADOW && defined VERTEX_SHADER || defined SHAPE_SCATTER
    uint PushShapeHead(uint slot, uint pointer) {
        if (slot == shapeCellCapacity) return 0u;
        uint stamp = GetShapeHeadStamp();
        uint previous = atomicExchange(shapeHeadSSBO.words[GetShapeCellHeadWord(slot)], stamp | pointer);
        return (previous & shapeHeadStampMask) == stamp ? previous & shapeHeadPointerMask : 0u;
    }
#endif
