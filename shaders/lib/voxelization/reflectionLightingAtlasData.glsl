#ifndef INCLUDE_REFLECTION_LIGHTING_ATLAS_DATA
#define INCLUDE_REFLECTION_LIGHTING_ATLAS_DATA

#include "/lib/voxelization/reflectionVoxelVolume.glsl"

const uint reflectionLightingTileCount = 4096u;
const uint reflectionLightingInvalid = 0xffffffffu;
struct reflectionLightingTile {
    uvec4 key;
    uint claim;
    uint requestedFrame;
    uint bakedFrame;
    uint flags;
};
layout(std430, binding = 2) coherent buffer reflectionLightingAtlasBuffer {
    reflectionLightingTile tiles[];
} reflectionLightingAtlasSSBO;

bool ReflectionLightingAtlasAvailable() {
    // At 100% every tile rebakes each frame, so no point to cache....yeet!
    return reflectionActiveRegionCount > 1 && reflectionLightingAtlasSSBO.tiles.length() >= reflectionLightingTileCount;
}

bool IsReflectionLightingBakeFresh(uint bakedFrame, uint currentFrame) {
    return bakedFrame != 0u && currentFrame - bakedFrame < uint(reflectionActiveRegionCount);
}

uint GetReflectionLightingTileIndex(uvec4 key) {
    uint hash = key.x * 1597334677u ^ key.y * 3812015801u;
    return 2u * ((hash ^ (hash >> 16u)) & (reflectionLightingTileCount / 2u - 1u));
}

uvec4 GetReflectionLightingKey(uint cellIndex, uint material, uint face, uint generation) {
    // Leaving or jumping into water should invalidate immeditely.
    return uvec4(cellIndex, (material << 3u) | face, generation, floatBitsToUint(nightVision) | (uint(isEyeInWater) << 30u));
}

ivec2 GetReflectionLightingTileOrigin(uint tileIndex) {
    return ivec2(tileIndex & 63u, tileIndex >> 6u) * WSR_LIGHTING_RES;
}
#endif
