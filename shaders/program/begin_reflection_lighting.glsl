#include "/lib/common.glsl"
#ifdef WSR_LIGHTING_ATLAS_ACTIVE
#include "/lib/voxelization/reflectionLightingAtlasData.glsl"
layout(local_size_x = 256) in;
const ivec3 workGroups = ivec3(16, 1, 1);
void main() {
    if (frameCounter > 1 || !ReflectionLightingAtlasAvailable()) return;
    uint tileIndex = gl_GlobalInvocationID.x;
    reflectionLightingAtlasSSBO.tiles[tileIndex].key = uvec4(reflectionLightingInvalid);
    reflectionLightingAtlasSSBO.tiles[tileIndex].claim = 0u;
    reflectionLightingAtlasSSBO.tiles[tileIndex].requestedFrame = 0u;
    reflectionLightingAtlasSSBO.tiles[tileIndex].bakedFrame = 0u;
    reflectionLightingAtlasSSBO.tiles[tileIndex].flags = 0u;
}
#endif
