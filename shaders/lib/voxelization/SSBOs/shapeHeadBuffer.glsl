#extension GL_ARB_shader_storage_buffer_object : enable

const uint shapeHeadPointerMask = 2097151u;
const uint shapeHeadEpochMask = 0xffe00000u;
layout(std430, binding = 6) SSBO_QUALIFIER buffer shapeHeadBuffer {
    uint heads[];
} shapeHeadSSBO;

uint getShapeHeadEpochBits() {
    return (shapeDataSSBO.epoch & 2047u) << 21u;
}

uint readShapeHead(int index) {
    uint word = shapeHeadSSBO.heads[index];
    return (word & shapeHeadEpochMask) == getShapeHeadEpochBits() ? word & shapeHeadPointerMask : 0u;
}

#if defined SHADOW && defined VERTEX_SHADER || defined SHAPE_SCATTER
    uint pushShapeHead(int index, uint pointer) {
        uint stamp = getShapeHeadEpochBits();
        uint old = atomicExchange(shapeHeadSSBO.heads[index], stamp | pointer);
        return (old & shapeHeadEpochMask) == stamp ? old & shapeHeadPointerMask : 0u;
    }
#endif
