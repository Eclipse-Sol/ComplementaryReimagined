#ifndef INCLUDE_REFLECTION_CORNER_LIGHTING
#define INCLUDE_REFLECTION_CORNER_LIGHTING

uint PackReflectionCornerLighting(vec2 lightmap, float ao, uint corner, bool oppositeDiagonal) {
    uvec2 lightmapBits = uvec2(round(clamp(lightmap, 0.0, 1.0) * 1023.0));
    uint aoBits = uint(round(clamp(ao < 0.1 ? 1.0 : ao, 0.0, 1.0) * 255.0));
    return lightmapBits.x | (lightmapBits.y << 10u) | (aoBits << 20u) | (corner << 28u)
         | (uint(oppositeDiagonal) << 30u) | 0x80000000u;
}

vec3 UnpackReflectionCornerLighting(uint data) {
    return vec3(float(data & 1023u) / 1023.0, float((data >> 10u) & 1023u) / 1023.0,
                float((data >> 20u) & 255u) / 255.0);
}

vec3 InterpolateReflectionCornerLighting(uvec4 data, vec2 uv, bool oppositeDiagonal, vec3 fallback) {
    vec3 a = (data.x & 0x80000000u) != 0u ? UnpackReflectionCornerLighting(data.x) : fallback;
    vec3 b = (data.y & 0x80000000u) != 0u ? UnpackReflectionCornerLighting(data.y) : fallback;
    vec3 c = (data.z & 0x80000000u) != 0u ? UnpackReflectionCornerLighting(data.z) : fallback;
    vec3 d = (data.w & 0x80000000u) != 0u ? UnpackReflectionCornerLighting(data.w) : fallback;
    uv = clamp(uv, 0.0, 1.0);
    if (!oppositeDiagonal)
        return uv.x >= uv.y ? a + (b - a) * uv.x + (d - b) * uv.y
                            : a + (d - c) * uv.x + (c - a) * uv.y;
    return uv.x + uv.y <= 1.0 ? a + (b - a) * uv.x + (c - a) * uv.y
                             : d + (c - d) * (1.0 - uv.x) + (b - d) * (1.0 - uv.y);
}
#endif
