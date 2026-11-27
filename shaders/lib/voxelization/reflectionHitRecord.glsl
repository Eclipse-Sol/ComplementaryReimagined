#ifndef INCLUDE_REFLECTION_HIT_RECORD
#define INCLUDE_REFLECTION_HIT_RECORD

struct reflectionHitRecord {
    uvec4 ids;
};
#ifdef WSR_HIT_BUFFER_READONLY
    layout(std430, binding = 5) readonly buffer reflectionHitBuffer {
#else
    layout(std430, binding = 5) buffer reflectionHitBuffer {
#endif
    reflectionHitRecord hits[];
} hitBuffer;

// ids.x = voxel index | face << reflectionHitCellBits | reflectionHitLavaFlag
const uint reflectionHitCellBits = 26u;
const uint reflectionHitCellMask = (1u << reflectionHitCellBits) - 1u;
const uint reflectionHitLavaFlag = 0x20000000u;

bool IsReflectionHitLava(uvec4 ids) { return (ids.x & reflectionHitLavaFlag) != 0u; }
uint GetReflectionHitMaterial(uvec4 ids) { return IsReflectionHitLava(ids) ? 10068u : ids.y; }
uint GetReflectionHitSurface(uvec4 ids) { return IsReflectionHitLava(ids) ? 0u : ids.w; }
vec2 GetReflectionHitLavaGradient(uvec4 ids) { return uintBitsToFloat(ids.yw); }

uvec4 PackReflectionHit(uint cellIndex, uint faceIndex, uint material, uint surface, float traceLength, vec2 lavaGradient) {
    uint cellFace = cellIndex | (faceIndex << reflectionHitCellBits);
    if (material == 10068u)
        return uvec4(cellFace | reflectionHitLavaFlag, floatBitsToUint(lavaGradient.x), floatBitsToUint(traceLength),
                     floatBitsToUint(lavaGradient.y));
    return uvec4(cellFace, material, floatBitsToUint(traceLength), surface);
}

uint GetReflectionHitFace(uvec4 ids) { return (ids.x >> reflectionHitCellBits) & 7u; }
uint GetReflectionHitCell(uvec4 ids) { return ids.x & reflectionHitCellMask; }

#endif
