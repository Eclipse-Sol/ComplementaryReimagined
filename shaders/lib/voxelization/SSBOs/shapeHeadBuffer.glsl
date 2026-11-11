#extension GL_ARB_shader_storage_buffer_object : enable

const uint shapeHeadPointerMask = 2097151u;
const uint shapeHeadStampMask = 0xffe00000u;
const uint shapeHaloHeadCapacity = 1u << uint(findMSB(shapeRecordCapacity - 1u) + 1);
layout(std430, binding = 6) SSBO_QUALIFIER buffer shapeHeadBuffer {
    uint heads[sceneVoxelCount];
    uint haloCellKeys[shapeHaloHeadCapacity]; // storage cell index + 1
    uint haloHeads[];
} shapeHeadSSBO;

uint GetShapeHeadStamp() {
    return (shapeDataSSBO.captureFrame & 2047u) << 21u;
}

#if defined SHAPE_BUILD || defined SHADOW && defined VERTEX_SHADER
    uint FindShapeHaloSlot(int index) {
        uint key = uint(index) + 1u;
        uint slot = (uint(index) * 2654435761u) & (shapeHaloHeadCapacity - 1u);
        for (uint probe = 0u; probe < shapeHaloHeadCapacity; probe++) {
            #if defined SHADOW && defined VERTEX_SHADER
                uint previous = atomicCompSwap(shapeHeadSSBO.haloCellKeys[slot], 0u, key);
                if (previous == 0u || previous == key) return slot;
            #else
                uint previous = shapeHeadSSBO.haloCellKeys[slot];
                if (previous == key) return slot;
                if (previous == 0u) return shapeHaloHeadCapacity;
            #endif
            slot = (slot + 1u) & (shapeHaloHeadCapacity - 1u);
        }
        return shapeHaloHeadCapacity;
    }

    uint ReadShapeCaptureHead(int index, bool halo) {
        uint word;
        if (halo) {
            uint slot = FindShapeHaloSlot(index);
            if (slot == shapeHaloHeadCapacity) return 0u;
            word = shapeHeadSSBO.haloHeads[slot];
        } else word = shapeHeadSSBO.heads[index];
        return (word & shapeHeadStampMask) == GetShapeHeadStamp() ? word & shapeHeadPointerMask : 0u;
    }
#endif

uint ReadShapeHead(reflectionCellHandle cell) {
    uint word = shapeHeadSSBO.heads[cell.storageIndex];
    uint regionGeneration = cell.regionGeneration;
    if (regionGeneration == 0u) return 0u;
    return (word & shapeHeadStampMask) == ((regionGeneration & 2047u) << 21u) ? word & shapeHeadPointerMask : 0u;
}

#if defined SHADOW && defined VERTEX_SHADER || defined SHAPE_SCATTER
    uint PushShapeHead(int index, uint pointer, bool halo) {
        uint stamp = GetShapeHeadStamp();
        uint previous;
        #if defined SHADOW && defined VERTEX_SHADER
            if (halo) {
                uint slot = FindShapeHaloSlot(index);
                previous = atomicExchange(shapeHeadSSBO.haloHeads[slot], stamp | pointer);
            } else
        #endif
        previous = atomicExchange(shapeHeadSSBO.heads[index], stamp | pointer);
        return (previous & shapeHeadStampMask) == stamp ? previous & shapeHeadPointerMask : 0u;
    }
#endif
