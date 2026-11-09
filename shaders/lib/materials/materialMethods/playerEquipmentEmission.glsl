float getPlayerEquipmentEmission(playerEquipmentHit hit, vec3 normal, float dither, inout vec3 albedo) {
    if (hit.material <= 0) return 0.0;

    int itemMaterial = hit.material;
    vec3 playerPos = hit.position;
    vec4 color = vec4(albedo, 1.0);
    vec4 glColor = hit.tint;
    float emission = 0.0, NdotU = normal.y, NdotE = normal.x, snowMinNdotU = 0.0;
    float lViewPos = length(playerPos);
    vec2 lmCoord = eyeBrightness / 240.0, lmCoordM = lmCoord;
    vec3 shadowMult = vec3(1.0), maRecolor = vec3(0.0);
    vec3 normalM = normal, geoNormal = normal;
    vec2 equipmentAtlasSize = vec2(textureSize(playerEquipment_sampler, 0));
    vec2 texCoord = hit.texCoord;
    vec2 tileOrigin = floor(texCoord * equipmentAtlasSize / float(PLAYER_EQUIPMENT_TILE_SIZE)) * float(PLAYER_EQUIPMENT_TILE_SIZE);
    vec2 absMidCoordPos = 0.5 * hit.tileSize / equipmentAtlasSize;
    vec2 midCoord = tileOrigin / equipmentAtlasSize + absMidCoordPos;
    vec2 signMidCoordPos = (texCoord - midCoord) / absMidCoordPos;
    bool noSmoothLighting = false, noDirectionalShading = false;
    bool noVanillaAO = false, noGeneratedNormals = false, doTileRandomisation = true;
    float smoothnessD = 0.0, materialMask = 0.0;
    float smoothnessG = 0.0, highlightMult = 1.0, noiseFactor = 1.0, snowFactor = 1.0;

    #define DURING_WORLDSPACE_REF
    #ifndef IPBR_COMPAT_MODE
        #define IPBR_COMPAT_MODE
    #endif
    #undef DISTANT_LIGHT_BOKEH
    #define tex playerEquipment_sampler
    #define atlasSize equipmentAtlasSize
    #define currentRenderedItemId itemMaterial
        #include "/lib/materials/materialHandling/irisIPBR.glsl"
    #undef currentRenderedItemId
    #undef atlasSize
    #undef tex
    #undef DURING_WORLDSPACE_REF

    if (emission > 0.0) albedo = color.rgb;
    return emission;
}
