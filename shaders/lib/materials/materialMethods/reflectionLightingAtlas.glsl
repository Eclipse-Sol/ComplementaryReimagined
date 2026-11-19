uniform sampler2D wsrBlockLight_sampler;
uniform sampler2D wsrLightDetail_sampler;
uniform sampler2D wsrSceneLight_sampler;
uniform sampler2D wsrShadowLight_sampler;

uint GetReflectionLightingFlags(bool noSmoothLighting, bool noDirectionalShading, bool noVanillaAO, bool centerShadowBias) {
    return uint(noSmoothLighting) | (uint(noDirectionalShading) << 1u)
         | (uint(noVanillaAO) << 2u) | (uint(centerShadowBias) << 3u);
}

bool LoadReflectionLightingAtlas(uvec4 key, vec2 uv, uint lightingFlags) {
    if (key.z == 0u || !ReflectionLightingAtlasAvailable()) return false;
    uint tileIndex = GetReflectionLightingTileIndex(key);
    uint currentFrame = GetReflectionFrame();
    bool found = false;
    for (uint way = 0u; way < 2u; way++) {
        reflectionLightingTile tile = reflectionLightingAtlasSSBO.tiles[tileIndex + way];
        if (all(equal(tile.key, key)) && tile.flags == lightingFlags && IsReflectionLightingBakeFresh(tile.bakedFrame, currentFrame)) {
            tileIndex += way;
            found = true;
            break;
        }
    }
    if (!found) return false;
    vec2 pixel = vec2(GetReflectionLightingTileOrigin(tileIndex)) + 0.5 + clamp(uv, 0.0, 1.0) * float(WSR_LIGHTING_RES - 1);
    vec2 coord = pixel / float(64 * WSR_LIGHTING_RES);
    wsrAtlasBlockLight = textureLod(wsrBlockLight_sampler, coord, 0.0);
    wsrAtlasLightDetail = textureLod(wsrLightDetail_sampler, coord, 0.0).rgb;
    wsrAtlasSceneLight = textureLod(wsrSceneLight_sampler, coord, 0.0);
    wsrAtlasShadow = textureLod(wsrShadowLight_sampler, coord, 0.0).rgb;
    return true; // The bake zeroes bad texels and marks the tile invalid.
}

void ApplyReflectionLightingAtlas(inout vec4 color, vec3 playerPos, vec3 viewPos, vec3 geoNormal, vec3 normalM,
                                  vec2 lightmap, float smoothnessG, float highlightMult, float emission) {
    #ifdef LIGHT_COLOR_MULTS
        lightColorMult = GetLightColorMult();
    #endif
    float lightmapY2 = pow2(lightmap.y);
    emission *= 1.0 - 0.25 * smoothstep1(lightmap.y) * invRainFactor * sunVisibility;
    vec3 blockLighting = wsrAtlasBlockLight.rgb
                       + wsrAtlasLightDetail / pow2((1.0 + emission) * (color.rgb + 0.1));
    #if HELD_LIGHTING_MODE >= 1
        blockLighting = sqrt(pow2(blockLighting) + GetHeldLightingGated(playerPos, color.rgb, emission));
    #endif
    #ifdef OVERWORLD
        if (isEyeInWater != 1) {
            float shadowMultFloat = min1(GetLuminance(wsrAtlasShadow));
            blockLighting *= GetBlockLightSkyFade(wsrAtlasBlockLight.a, lightmapY2, shadowMultFloat, emission);
        }
    #endif
    blockLighting *= XLIGHT_I;
    color.rgb *= GetFinalDiffuse(wsrAtlasSceneLight.a, blockLighting + wsrAtlasSceneLight.rgb, emission);

    #ifdef LIGHT_HIGHLIGHT
        float specular = dot(normalM, -viewPos) > 0.0 ? GGX(normalM, normalize(viewPos), lightVec, max0(dot(normalM, lightVec)), smoothnessG, geoNormal) : 0.0;
        color.rgb += GetLightHighlight(wsrAtlasShadow, specular * highlightMult);
    #endif
    color.rgb *= pow2(1.0 - darknessLightFactor);
}
