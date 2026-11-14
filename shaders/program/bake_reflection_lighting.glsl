#include "/lib/materials/materialMethods/reflectionValidation.glsl"

layout(local_size_x = 8, local_size_y = 8) in;
const ivec3 workGroups = ivec3(4096, 1, 1);
layout(rgba16f) writeonly uniform image2D wsrBlockLight_img;
layout(r11f_g11f_b10f) writeonly uniform image2D wsrLightDetail_img;
layout(rgba16f) writeonly uniform image2D wsrSceneLight_img;
layout(r11f_g11f_b10f) writeonly uniform image2D wsrShadowLight_img;
shared uint tileFlags;
shared uint tileInvalid;

bool IsValidBakeTexel(vec4 value, float limit) {
    return IsFiniteReflection(value) && all(lessThanEqual(abs(value), vec4(limit)));
}

void main() {
    if (!ReflectionLightingAtlasAvailable()) return;
    uint tileIndex = gl_WorkGroupID.x, currentFrame = uint(frameCounter + 1);
    reflectionLightingTile tile = reflectionLightingAtlasSSBO.tiles[tileIndex];
    if (tile.requestedFrame != currentFrame) return;
    if (gl_LocalInvocationIndex == 0u) tileInvalid = 0u;
    barrier();

    ivec3 storageOrigin = PositiveModulo(GetReflectionVolumeOrigin(), sceneVoxelVolumeSize);
    ivec3 cell = GetSceneVoxelPosition(tile.key.x, storageOrigin);
    uint material = tile.key.y >> 3u, face = tile.key.y & 7u;
    vec3 normal = GetShapeFaceNormal(int(face));
    for (int offsetY = 0; offsetY < WSR_LIGHTING_RES; offsetY += 8) {
        for (int offsetX = 0; offsetX < WSR_LIGHTING_RES; offsetX += 8) {
            ivec2 samplePixel = ivec2(gl_LocalInvocationID.xy) + ivec2(offsetX, offsetY);
            wsrAtlasBakePixel = vec2(GetReflectionLightingTileOrigin(tileIndex) + samplePixel);
            texelCoord = ivec2(wsrAtlasBakePixel);
            vec2 uv = mix(vec2(0.0005), vec2(0.9995), vec2(samplePixel) / float(WSR_LIGHTING_RES - 1));
            vec2 projected = 1.0 - uv;
            vec3 local = abs(normal.x) > 0.5 ? vec3(0.5, projected.y, projected.x)
                       : abs(normal.y) > 0.5 ? vec3(projected.x, 0.5, projected.y) : vec3(projected, 0.5);
            local[int(face >> 1u)] = (face & 1u) != 0u ? 0.9995 : 0.0005;
            bool lavaHeightsValid = true;
            if (material == 10068u && normal.y > 0.5) {
                vec4 heights = GetLavaCornerHeights(cell);
                lavaHeightsValid = all(greaterThanEqual(heights, vec4(0.0)));
                local.y = mix(mix(heights.x, heights.y, local.x), mix(heights.z, heights.w, local.x), local.z);
            }
            vec3 position = vec3(cell) + local - vec3(cameraPositionBestInt - GetReflectionVolumeOrigin()) - cameraPositionBestFract;
            vec3 ray = -normal;
            ResetReflectionLightingAtlasState();
            vec4 result = GetShadedReflection(cell, position + normal, position, ray, vec3(0.0), vec3(0.0),
                vec3(0.0), vec3(0.0), normal, normal, material, 0.5, 0u,
                reflectionCellHandle(int(tile.key.x), tile.key.z), storageOrigin);
            bool valid = lavaHeightsValid && wsrAtlasCacheable && result.a >= 0.0
                      && IsValidBakeTexel(wsrAtlasBlockLight, 65504.0)
                      && IsValidBakeTexel(vec4(wsrAtlasLightDetail, 0.0), 64000.0)
                      && IsValidBakeTexel(wsrAtlasSceneLight, 65504.0)
                      && IsValidBakeTexel(vec4(wsrAtlasShadow, 0.0), 64000.0);
            if (gl_LocalInvocationIndex == 0u && offsetX == 0 && offsetY == 0) tileFlags = wsrAtlasFlags;
            barrier();
            if (!valid || wsrAtlasFlags != tileFlags) atomicOr(tileInvalid, 1u);
            ivec2 pixel = GetReflectionLightingTileOrigin(tileIndex) + samplePixel;
            imageStore(wsrBlockLight_img, pixel, valid ? wsrAtlasBlockLight : vec4(0.0));
            imageStore(wsrLightDetail_img, pixel, vec4(valid ? wsrAtlasLightDetail : vec3(0.0), 1.0));
            imageStore(wsrSceneLight_img, pixel, valid ? wsrAtlasSceneLight : vec4(0.0));
            imageStore(wsrShadowLight_img, pixel, vec4(valid ? wsrAtlasShadow : vec3(0.0), 1.0));
        }
    }
    barrier();
    if (gl_LocalInvocationIndex == 0u) {
        reflectionLightingAtlasSSBO.tiles[tileIndex].bakedFrame = currentFrame;
        reflectionLightingAtlasSSBO.tiles[tileIndex].flags = tileInvalid == 0u ? tileFlags : reflectionLightingInvalid;
    }
}
