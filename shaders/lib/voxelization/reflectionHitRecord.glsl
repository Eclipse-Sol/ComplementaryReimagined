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

bool IsReflectionHitLava(uvec4 ids) { return (ids.y & 0x80000000u) != 0u; }
uint GetReflectionHitMaterial(uvec4 ids) {
    return IsReflectionHitLava(ids) ? 10068u : (ids.x >> 27u) | ((ids.y & 1023u) << 5u);
}
uint GetReflectionHitSurface(uvec4 ids) { return IsReflectionHitLava(ids) ? 0u : ids.y >> 10u; }
uint GetReflectionHitFace(uvec4 ids) { return (ids.x >> 24u) & 7u; }

uvec4 PackReflectionHit(uint cellIndex, uint faceIndex, uint material, uint surface, float traceLength, vec2 lavaGradient) {
    if (material == 10068u) {
        uint gx = floatBitsToUint(lavaGradient.x);
        return uvec4(cellIndex | (faceIndex << 24u) | ((gx >> 31u) << 27u), 0x80000000u | (gx & 0x7fffffffu),
                     floatBitsToUint(traceLength), floatBitsToUint(lavaGradient.y));
    }
    return uvec4(cellIndex | (faceIndex << 24u) | ((material & 31u) << 27u),
                 (material >> 5u) | (surface << 10u), floatBitsToUint(traceLength), 0u);
}

#endif
