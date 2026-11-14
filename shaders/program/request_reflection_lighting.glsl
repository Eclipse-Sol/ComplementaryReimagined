#include "/lib/common.glsl"
#ifdef WSR_LIGHTING_ATLAS_ACTIVE
#include "/lib/voxelization/reflectionVoxelVolume.glsl"
#include "/lib/voxelization/reflectionVoxelData.glsl"
#include "/lib/voxelization/reflectionLightingAtlasData.glsl"
#define WSR_HIT_BUFFER_READONLY
#include "/lib/voxelization/reflectionHitRecord.glsl"

layout(local_size_x = 8, local_size_y = 8) in;
const vec2 workGroupsRender = vec2(0.125 * WSR_REFLECTION_SCALE);

bool RequestReflectionLightingTile(uint tileIndex, uvec4 key, uint currentFrame) {
    uint published = currentFrame << 1u, busy = published | 1u;
    uint previous = atomicAdd(reflectionLightingAtlasSSBO.tiles[tileIndex].claim, 0u);
    if (previous == busy) return true;
    if (previous == published)
        return all(equal(reflectionLightingAtlasSSBO.tiles[tileIndex].key, key));
    if (atomicCompSwap(reflectionLightingAtlasSSBO.tiles[tileIndex].claim, previous, busy) != previous) return true;
    uvec4 oldKey = reflectionLightingAtlasSSBO.tiles[tileIndex].key;
    uint oldBake = reflectionLightingAtlasSSBO.tiles[tileIndex].bakedFrame;
    bool recent = IsReflectionLightingBakeFresh(oldBake, currentFrame);
    bool accepted = all(equal(oldKey, key)) && recent;
    if (!accepted && (!recent || all(equal(oldKey.xy, key.xy)))) {
        reflectionLightingAtlasSSBO.tiles[tileIndex].key = key;
        reflectionLightingAtlasSSBO.tiles[tileIndex].requestedFrame = currentFrame;
        reflectionLightingAtlasSSBO.tiles[tileIndex].flags = reflectionLightingInvalid;
        accepted = true;
    }
    // Publish once per frame. Ready entries *should* not change during this.
    memoryBarrierBuffer();
    atomicExchange(reflectionLightingAtlasSSBO.tiles[tileIndex].claim, published);
    return accepted;
}

void main() {
    ivec2 size = GetReflectionBufferSize();
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy) * 8 + 4;
    if (any(greaterThanEqual(pixel, size)) || !ReflectionLightingAtlasAvailable()) return;
    uvec4 hit = hitBuffer.hits[pixel.x + size.x * pixel.y].ids;
    uint material = GetReflectionHitMaterial(hit);
    uint face = GetReflectionHitFace(hit);
    if (material == 0u || face >= 6u || GetReflectionShapeFamily(int(material)) != WSR_FAMILY_NONE) return;
    uint cellIndex = hit.x & 0xffffffu;
    ivec3 cell = GetSceneVoxelPosition(cellIndex, PositiveModulo(GetReflectionVolumeOrigin(), sceneVoxelVolumeSize));
    if (!IsReflectionCellSelected(cell)) return;
    uint generation = GetReflectionCellGeneration(cell, GetPackedRegionTileOffset());
    if (generation == 0u) return;
    uvec4 key = GetReflectionLightingKey(cellIndex, material, face, generation);
    uint tileIndex = GetReflectionLightingTileIndex(key), currentFrame = GetReflectionFrame();
    if (!RequestReflectionLightingTile(tileIndex, key, currentFrame))
        RequestReflectionLightingTile(tileIndex + 1u, key, currentFrame);
}
#endif
