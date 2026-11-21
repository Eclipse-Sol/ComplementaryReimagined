#extension GL_ARB_shader_image_load_store : enable

#include "/lib/voxelization/reflectionVoxelization.glsl"
#include "/lib/materials/materialMethods/lavaRayTrace.glsl"
#if WORLD_SPACE_SHAPES > 0
    #include "/lib/materials/materialMethods/shapeRayTrace.glsl"
    #include "/lib/materials/materialMethods/shapeSurfaceTrace.glsl"
#endif

#ifdef WSR_LIGHTING_ATLAS_ACTIVE
    #include "/lib/voxelization/reflectionLightingAtlasData.glsl"
#endif
#ifndef WSR_TRACE_PREPASS
    #ifdef WSR_LIGHTING_ATLAS_ACTIVE
        bool wsrAtlasLoaded = false;
        bool wsrAtlasCacheable = false;
        uint wsrAtlasFlags = 0u;
        vec4 wsrAtlasBlockLight;
        vec3 wsrAtlasLightDetail;
        vec4 wsrAtlasSceneLight;
        vec3 wsrAtlasShadow;

        void ResetReflectionLightingAtlasState() {
            wsrAtlasLoaded = false;
            wsrAtlasCacheable = false;
            wsrAtlasBlockLight = vec4(0.0);
            wsrAtlasLightDetail = vec3(0.0);
            wsrAtlasSceneLight = vec4(0.0);
            wsrAtlasShadow = vec3(1.0);
        }
    #endif
    #define WSR_HIT_LIGHTING
    #include "/lib/lighting/mainLighting.glsl"
    #undef WSR_HIT_LIGHTING

    #ifdef WSR_LIGHTING_ATLAS_ACTIVE
        #include "/lib/materials/materialMethods/reflectionLightingAtlas.glsl"
    #endif

    #if WORLD_SPACE_PLAYER_REF == 1
        #include "/lib/materials/materialMethods/playerRayTracer.glsl"
    #endif
    #if defined WSR_PLAYER_EQUIPMENT && defined IPBR
        #include "/lib/materials/materialMethods/playerEquipmentEmission.glsl"
    #endif
#endif

vec2 GetLocalTexCoord(vec3 local, vec3 normal) {
    return 1.0 - ProjectToFace(local, normal);
}

void GetReflectionTexGrads(vec3 rayDir, vec3 positionGradX, vec3 positionGradY, vec3 normal, vec3 surfaceNormal,
                           out vec2 textureGradX, out vec2 textureGradY) {
    vec3 faceRayDir = rayDir / min(dot(surfaceNormal, rayDir), -1e-6);
    positionGradX -= faceRayDir * dot(surfaceNormal, positionGradX);
    positionGradY -= faceRayDir * dot(surfaceNormal, positionGradY);
    textureGradX = -ProjectToFace(positionGradX, normal);
    textureGradY = -ProjectToFace(positionGradY, normal);
}

vec3 GetWSRNormalGrad(vec3 normalDiff, float pixelStep) {
    float diffLength = length(normalDiff);
    if (diffLength > 0.5) return vec3(0.0);
    return normalDiff * (max0(diffLength - 0.014) / max(diffLength, 1e-6) / pixelStep);
}

#if MC_VERSION >= 12111 && IRIS_VERSION < 11005 && !defined WSR_TRACE_PREPASS
    #define WSR_LEGACY_LOD
#endif

#ifdef WSR_LEGACY_LOD
vec4 BlendReflectionLod(vec4 color, vec3 bounds, vec2 local, vec2 gradX, vec2 gradY,
                       vec2 atlasSize, vec3 tint, float dither, bool opaque) {
    vec2 texelGradX = gradX * atlasSize, texelGradY = gradY * atlasSize;
    float lod = 0.5 * log2(max(max(dot(texelGradX, texelGradX), dot(texelGradY, texelGradY)), 1e-12));
    float fakeLod = 0.5 * lod;
    float lodMix = clamp01(fakeLod - 0.75 + 0.25 * dither);
    if (lodMix > 0.0) {
        #ifdef WSR_SPLIT_ENABLED
            vec4 sharpColor = color;
        #endif
        vec2 span = local / pow(2.0, int(1.5 + pow2(max0(fakeLod))));
        vec2 scale = GetReflectionTextureScale(bounds.z, atlasSize);
        vec4 lodColor1 = texture2DLod(textureAtlas, bounds.xy + scale * (0.5 + span), fakeLod);
        vec4 lodColor2 = texture2DLod(textureAtlas, bounds.xy + scale * (0.25 + span), fakeLod);
        vec4 lodColor3 = texture2DLod(textureAtlas, bounds.xy + scale * span, fakeLod);
        if (!opaque) {
            color.rgb *= color.a;
            lodColor1.rgb *= lodColor1.a;
            lodColor2.rgb *= lodColor2.a;
            lodColor3.rgb *= lodColor3.a;
        }
        color = mix(color, 0.333333 * (lodColor1 + lodColor2 + lodColor3) * vec4(tint, 1.0), lodMix);
        if (!opaque) color.rgb = color.a > 1e-6 ? color.rgb / color.a : vec3(0.0);
        else {
            if (dot(color.rgb, vec3(0.333333)) - 0.5 < 0.49) color.a = mix(color.a, 1.0, lodMix);
            #ifdef WSR_SPLIT_ENABLED
                if (color.a < 0.0041) return sharpColor;
            #else
                if (color.a < 0.0041) return vec4(-1.0);
            #endif
        }
    }
    return color;
}
#endif

#ifndef WSR_TRACE_PREPASS
vec2 ApplyGrassSideOverlay(inout vec4 color, uvec3 data, vec2 local, float baseRadius, uint baseOrientation,
                            vec3 normal, vec2 gradX, vec2 gradY, vec2 atlasSize, float dither) {
    vec3 bounds = vec3(data.x >> 16u, data.x & 65535u, data.y & 65535u) / 65536.0;
    vec3 tint = unpackUnorm4x8(data.z).rgb;
    uint orientation = ((data.y >> 16u) & 7u) ^ GetDefaultReflectionFaceOrientation(normal);
    vec2 uv = 0.5 + OrientReflectionFaceVector(UnorientReflectionFaceVector(local - 0.5, baseOrientation), orientation);
    vec2 scale = GetReflectionTextureScale(bounds.z, atlasSize);
    vec2 baseScale = GetReflectionTextureScale(baseRadius, atlasSize);
    gradX = scale * OrientReflectionFaceVector(UnorientReflectionFaceVector(gradX / baseScale, baseOrientation), orientation);
    gradY = scale * OrientReflectionFaceVector(UnorientReflectionFaceVector(gradY / baseScale, baseOrientation), orientation);
    vec4 overlayColor = textureGrad(textureAtlas, bounds.xy + scale * clamp(uv, 0.0, 1.0), gradX, gradY);
    #ifdef WSR_LEGACY_LOD
        overlayColor = BlendReflectionLod(overlayColor, bounds, uv, gradX, gradY, atlasSize, vec3(1.0), dither, false);
    #endif
    float grassGreen = overlayColor.g * tint.g;
    float smoothness = mix(color.r * 0.1 + 0.1, pow2(grassGreen), overlayColor.a);
    float snowMin = 0.0;
    #if defined IPBR && defined SNOWY_WORLD
        snowMin = min(pow2(pow2(grassGreen)) * 1.9, 0.1) * overlayColor.a;
        // Remove tint from the grass layer before compositing it over untinted dirt.
        overlayColor.rgb *= 0.5 * (tint + 1.0);
    #else
        overlayColor.rgb *= tint;
    #endif
    color.rgb = mix(color.rgb, overlayColor.rgb, overlayColor.a);
    return vec2(smoothness, snowMin);
}
#endif

int GetReflectionMaterialAt(ivec3 cell, ivec3 storageOrigin) {
    if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, sceneVoxelVolumeSize))) return 0;
    return int(texelFetch(wsr_sampler, WrapReflectionStoragePosition(cell, storageOrigin, sceneVoxelVolumeSize), 0).r & 32767u);
}

float GetVoxelSpaceAO(ivec3 voxelPos, ivec3 normal, vec2 localTexCoord, ivec3 storageOrigin) {
    ivec3 absNormal = abs(normal);
    ivec3 hrz = ivec3(0, 0, 1) * absNormal.x + ivec3(1, 0, 0) * absNormal.y + ivec3(1, 0, 0) * absNormal.z;
    ivec3 vrt = ivec3(0, 1, 0) * absNormal.x + ivec3(0, 0, 1) * absNormal.y + ivec3(0, 1, 0) * absNormal.z;

    vec2 dir = 1.0 - 2.0 * localTexCoord;

    ivec2 signDir = ivec2(sign(dir));
    ivec3 voxelHrz = voxelPos + normal + signDir.x * hrz;
    ivec3 voxelVrt = voxelPos + normal + signDir.y * vrt;

    vec2 factor = pow2(dir);
    int matHrz = GetReflectionMaterialAt(voxelHrz, storageOrigin);
    int matVrt = GetReflectionMaterialAt(voxelVrt, storageOrigin);
    float occHrz = mix(1.0, float(matHrz == 0 || IsReflectionShapeId(matHrz)), factor.x);
    float occVrt = mix(1.0, float(matVrt == 0 || IsReflectionShapeId(matVrt)), factor.y);

    return 0.3 * (occHrz + occVrt) + 0.4;
}

#ifdef WSR_SPLIT_ENABLED
    #include "/lib/voxelization/reflectionHitRecord.glsl"

    uint GetReflectionPixelIndex() {
        ivec2 pixel = ivec2(gl_FragCoord.xy);
        return uint(pixel.x + GetReflectionBufferSize().x * pixel.y);
    }
#endif

#ifdef WSR_LDS_GRADIENTS
    const uint wsrGradientWidth = gl_WorkGroupSize.x * gl_WorkGroupSize.y * gl_WorkGroupSize.z;
    shared uint wsrGradientStorage[12u * wsrGradientWidth];

    void StoreReflectionGradient(uint slot, vec3 value) {
        uint lane = gl_LocalInvocationIndex;
        for (uint component = 0u; component < 3u; component++)
            wsrGradientStorage[(3u * slot + component) * wsrGradientWidth + lane] = floatBitsToUint(value[component]);
    }

    // Atomic reads stop a compiler forwarding the stored values into registers across traces
    vec3 LoadReflectionGradient(uint slot) {
        uint lane = gl_LocalInvocationIndex;
        return uintBitsToFloat(uvec3(
            atomicAdd(wsrGradientStorage[(3u * slot) * wsrGradientWidth + lane], 0u),
            atomicAdd(wsrGradientStorage[(3u * slot + 1u) * wsrGradientWidth + lane], 0u),
            atomicAdd(wsrGradientStorage[(3u * slot + 2u) * wsrGradientWidth + lane], 0u)));
    }
#endif

vec4 GetShadedReflection(ivec3 voxelPos, vec3 oldPlayerPos, vec3 playerPos, vec3 rayDir, vec3 rayGradX, vec3 rayGradY,
                         vec3 curvatureGradX, vec3 curvatureGradY, vec3 normal, vec3 surfaceNormal, uint mat, float dither,
                         uint surfaceIndex, reflectionCellHandle cellRef, ivec3 storageOrigin) {
    faceData faceData;
    vec2 faceTexCoord = GetLocalTexCoord(fract(playerPos + cameraPositionBestFract), normal);
    vec2 localTexCoord = faceTexCoord;
    uint faceOrientation = 0u;
    #ifndef WSR_TRACE_PREPASS
        uint faceIndex = 0xffffffffu;
    #endif
    bool lavaTop = mat == 10068u && normal.y > 0.99;
    mat2 lavaTextureRotation;
    vec2 textureSizeAtlas = textureSize(textureAtlas, 0);
    #if WORLD_SPACE_SHAPES > 0
        int family = GetReflectionShapeFamily(int(mat));
        uint textureAxes = 0u;
        vec2 textureAxisScale = vec2(0.0);
        if (family != WSR_FAMILY_NONE) {
            if (surfaceIndex >= shapeRecordCapacity) return vec4(-1.0);
            vec3 local = PlayerToSceneVoxel(playerPos) - vec3(voxelPos);
            if ((shapeDataSSBO.records[surfaceIndex].shading.w & shapeFlagPlane) != 0u)
                local = PlayerToSceneVoxel(playerPos) - vec3(GetShapeOwnerCell(shapeDataSSBO.records[surfaceIndex], voxelPos, storageOrigin));
            if (!UnpackShapeSurface(surfaceIndex, local, textureSizeAtlas, faceData, localTexCoord,
                                           textureAxes, textureAxisScale))
                return vec4(-1.0);
            mat = uint(GetReflectionMaterial(int(mat)));
        } else
    #endif
    if (lavaTop) {
        #ifdef WSR_TRACE_PREPASS
            return vec4(1.0);
        #else
            faceData = GetLavaFaceData(cellRef, lavaTextureRotation, faceIndex);
            localTexCoord = 0.5 + lavaTextureRotation * (localTexCoord - 0.5);
        #endif
    } else {
        if (IsReflectionCutoutCube(int(mat)) && dot(normal, normal) < 0.5) return vec4(-1.0);
        #ifdef WSR_TRACE_PREPASS
            faceData = GetFaceData(cellRef, normal, faceOrientation);
        #else
            faceData = GetFaceData(cellRef, normal, faceOrientation, faceIndex);
        #endif
        localTexCoord = GetLocalTexCoord(PlayerToSceneVoxel(playerPos) - vec3(voxelPos), normal);
        localTexCoord = clamp(0.5 + OrientReflectionFaceVector(localTexCoord - 0.5, faceOrientation), 0.0, 1.0);
    }
    if (faceData.textureBounds.z < 1e-6) return vec4(-1.0);

    #ifdef WAVING_LAVA
        if (mat == 10068u) faceData.glColor = min(faceData.glColor, vec3(0.9));
    #endif

    vec2 textureRadVec2 = 0.5 * GetReflectionTextureScale(faceData.textureBounds.z, textureSizeAtlas);
    vec2 textureCoord = faceData.textureBounds.xy + 2.0 * textureRadVec2 * localTexCoord;

    #ifdef WSR_LDS_GRADIENTS
        rayGradX = LoadReflectionGradient(0u);
        rayGradY = LoadReflectionGradient(1u);
        curvatureGradX = LoadReflectionGradient(2u);
        curvatureGradY = LoadReflectionGradient(3u);
    #endif
    float hitDist = length(playerPos - oldPlayerPos);
    float virtualDist = hitDist + length(oldPlayerPos);
    vec2 textureGradX, textureGradY;
    #if WORLD_SPACE_SHAPES > 0
        if (family != WSR_FAMILY_NONE) {
            vec3 gradX = virtualDist * rayGradX + hitDist * curvatureGradX;
            vec3 gradY = virtualDist * rayGradY + hitDist * curvatureGradY;
            vec3 faceRayDir = rayDir / min(dot(normal, rayDir), -1e-6);
            gradX -= faceRayDir * dot(normal, gradX);
            gradY -= faceRayDir * dot(normal, gradY);
            if ((textureAxes & 4096u) != 0u) {
                vec3 axisU = GetShapePlaneVector(int(textureAxes & 63u));
                vec3 axisV = GetShapePlaneVector(int((textureAxes >> 6u) & 63u));
                vec2 gradScale = 2.0 * textureRadVec2 * textureAxisScale;
                textureGradX = gradScale * vec2(dot(gradX, axisU), dot(gradX, axisV));
                textureGradY = gradScale * vec2(dot(gradY, axisU), dot(gradY, axisV));
            } else {
                uint codeU = textureAxes & 7u, codeV = (textureAxes >> 3u) & 7u;
                vec2 gradScale = 2.0 * textureRadVec2 * textureAxisScale
                               * vec2(GetShapeCodeSign(codeU), GetShapeCodeSign(codeV));
                textureGradX = gradScale * vec2(gradX[codeU >> 1u], gradX[codeV >> 1u]);
                textureGradY = gradScale * vec2(gradY[codeU >> 1u], gradY[codeV >> 1u]);
            }
        } else
    #endif
    {
        GetReflectionTexGrads(
            rayDir, virtualDist * rayGradX + hitDist * curvatureGradX, virtualDist * rayGradY + hitDist * curvatureGradY,
            normal, surfaceNormal, textureGradX, textureGradY
        );
        textureGradX = 2.0 * textureRadVec2 * OrientReflectionFaceVector(textureGradX, faceOrientation);
        textureGradY = 2.0 * textureRadVec2 * OrientReflectionFaceVector(textureGradY, faceOrientation);
        if (lavaTop) {
            textureGradX = (lavaTextureRotation * (textureGradX * textureSizeAtlas)) / textureSizeAtlas;
            textureGradY = (lavaTextureRotation * (textureGradY * textureSizeAtlas)) / textureSizeAtlas;
        }
    }

    vec4 color = textureGrad(textureAtlas, textureCoord, textureGradX, textureGradY) * vec4(faceData.glColor, 1.0);

    // The prepass owns this test: split composite cannot trace past a miss, so a repeat shows sky.
    #if !defined WSR_SPLIT_ENABLED || defined WSR_TRACE_PREPASS
        if (color.a <= 0.5) return vec4(-1.0);
    #endif

    #ifdef WSR_LEGACY_LOD
        color = BlendReflectionLod(color, faceData.textureBounds, localTexCoord, textureGradX, textureGradY,
                                   textureSizeAtlas, faceData.glColor, dither, true);
        if (color.a < 0.0) return color;
    #endif

    #ifdef WSR_TRACE_PREPASS
        return vec4(1.0);
    #else
        vec2 grassSideMaterial = vec2(-1.0, 0.0);
        if (faceIndex != 0xffffffffu && IsReflectionGrassSide(int(mat), normal)) {
            uvec4 overlay = LoadReflectionGrassOverlay(faceIndex);
            if (overlay.w == cellRef.regionGeneration)
                grassSideMaterial = ApplyGrassSideOverlay(color, overlay.xyz, localTexCoord, faceData.textureBounds.z,
                                                         faceOrientation, normal, textureGradX, textureGradY, textureSizeAtlas, dither);
        }

        float AO = 1.0;
        #if WORLD_SPACE_SMOOTH_LIGHTING > 0
            uvec4 reflectionCorners = uvec4(0u);
            bool needsVoxelAO = true;
            if (faceIndex != 0xffffffffu) {
                reflectionCorners = LoadReflectionFaceCorners(faceIndex);
                needsVoxelAO = (reflectionCorners.x & reflectionCorners.y & reflectionCorners.z & reflectionCorners.w & 0x80000000u) == 0u;
            }
        #endif
        #if VANILLAAO_I > 0 || WORLD_SPACE_SMOOTH_LIGHTING > 0
            #if WORLD_SPACE_SHAPES > 0
                if (family != WSR_FAMILY_NONE) {
                    ivec3 owner = GetShapeOwnerCell(shapeDataSSBO.records[surfaceIndex], voxelPos, storageOrigin);
                    #if WORLD_SPACE_SMOOTH_LIGHTING > 0
                        vec3 cornerLighting = GetReflectionShapeLighting(surfaceIndex, PlayerToSceneVoxel(playerPos) - vec3(owner), vec3(faceData.lightmap, 1.0));
                        faceData.lightmap = cornerLighting.xy;
                        AO = cornerLighting.z;
                    #else
                        AO = GetReflectionShapeAO(surfaceIndex, PlayerToSceneVoxel(playerPos) - vec3(owner));
                    #endif
                } else
            #endif
            #if WORLD_SPACE_SMOOTH_LIGHTING > 0
                if (needsVoxelAO)
            #endif
            AO = GetVoxelSpaceAO(voxelPos, ivec3(normal), faceTexCoord, storageOrigin);
        #endif
        #if WORLD_SPACE_SMOOTH_LIGHTING > 0
            if (faceIndex != 0xffffffffu) {
                uint cornerBits = reflectionCorners.x | reflectionCorners.y | reflectionCorners.z | reflectionCorners.w;
                vec3 cornerLighting = InterpolateReflectionCornerLighting(reflectionCorners, mat == 10068u ? faceTexCoord : localTexCoord,
                                                                          (cornerBits & 0x40000000u) != 0u, vec3(faceData.lightmap, AO));
                faceData.lightmap = cornerLighting.xy;
                AO = cornerLighting.z;
            }
        #endif

        bool noSmoothLighting = false, noDirectionalShading = false, noVanillaAO = false, centerShadowBias = false;
        int subsurfaceMode = 0;
        float emission = 0.0, NdotU = normal.y, NdotE = normal.x, snowMinNdotU = 0.0;
        float smoothnessG = 0.0, highlightMult = 1.0;
        vec2 lmCoordM = faceData.lightmap;
        vec3 normalM = normalize(mat3(gbufferModelView) * normal), geoNormal = normalM;
        float lViewPos = length(playerPos);
        vec3 nViewPos = normalize(mat3(gbufferModelView) * rayDir);
        vec3 viewPos = nViewPos * max(lViewPos, 1e-6);
        vec2 signMidCoordPos = localTexCoord * 2.0 - 1.0;
        vec3 shadowMult = vec3(1.0), maRecolor = vec3(0.0);
        vec4 glColor = vec4(faceData.glColor, AO);
        #ifdef IPBR
            vec2 atlasSize = textureSizeAtlas;
            vec2 texCoord = textureCoord;
            vec2 absMidCoordPos = vec2(textureRadVec2);
            vec2 midCoord = faceData.textureBounds.xy + 2.0 * textureRadVec2 * vec2(0.5);
            bool noGeneratedNormals = false, doTileRandomisation = true;
            float smoothnessD = 0.0, materialMask = 0.0;
            float noiseFactor = 1.0, snowFactor = 1.0, noPuddles = 0.0;
            vec2 lmCoord = faceData.lightmap;

            #define DURING_WORLDSPACE_REF
            #define WSR_TERRAIN_SHADING
                #define tex textureAtlas
                #undef DISTANT_LIGHT_BOKEH
                #include "/lib/materials/materialHandling/terrainIPBR.glsl"
                #undef tex
            #undef DURING_WORLDSPACE_REF
            #undef WSR_TERRAIN_SHADING
        #else
            if (mat == 10001) {
                noDirectionalShading = true;
            } else if (mat == 10009 || mat == 10011) { // Leaves
                #include "/lib/materials/specificMaterials/terrain/leaves.glsl"
            } else if (mat == 10005 || mat == 10017 || mat == 10021) { // Foliage
                subsurfaceMode = 1, noSmoothLighting = true, noDirectionalShading = true;
            } else if (mat == 11009) { // Vine, Pale Hanging Moss
                subsurfaceMode = 3, centerShadowBias = true, noSmoothLighting = true;
            } else if (mat == 10028) { // Modded light sources
                noSmoothLighting = true, noDirectionalShading = true;
                emission = GetLuminance(color.rgb) * 2.5;
            } else if (lmCoordM.x > 0.99999) lmCoordM.x = 0.95;
        #endif

        #ifdef WSR_LIGHTING_ATLAS_ACTIVE
            wsrAtlasLoaded = false;
            wsrAtlasFlags = GetReflectionLightingFlags(noSmoothLighting, noDirectionalShading, noVanillaAO, centerShadowBias);
            wsrAtlasCacheable = subsurfaceMode == 0 && all(equal(shadowMult, vec3(1.0)))
                               && all(equal(normalM, geoNormal));
            #ifndef WSR_ATLAS_BAKE
                if (family == WSR_FAMILY_NONE && wsrAtlasCacheable) {
                    uvec4 key = GetReflectionLightingKey(uint(cellRef.storageIndex), mat,
                        uint(GetReflectionFaceIndex(normal)), cellRef.regionGeneration);
                    wsrAtlasLoaded = LoadReflectionLightingAtlas(key, faceTexCoord, wsrAtlasFlags);
                }
            #endif
        #endif
        #if defined WSR_LIGHTING_ATLAS_ACTIVE && !defined WSR_ATLAS_BAKE
            if (wsrAtlasLoaded) {
                ApplyReflectionLightingAtlas(color, playerPos, viewPos, geoNormal, normalM, lmCoordM,
                                             smoothnessG, highlightMult, emission);
            } else
        #endif
        DoWorldSpaceLighting(color, shadowMult, playerPos, viewPos, lViewPos, geoNormal, normalM, dither,
                             normal, lmCoordM, noSmoothLighting, noDirectionalShading, noVanillaAO,
                             centerShadowBias, subsurfaceMode, smoothnessG, highlightMult, emission,
                             glColor, signMidCoordPos);
        return vec4(color.rgb + maRecolor, GetReflectionVolumeFade(playerPos));
    #endif
}

float GetFarthestOccupiedDistance(vec3 voxelPos, vec3 rayDir, ivec3 storageOrigin) {
    if (all(equal(rayDir, vec3(0.0)))) return -1.0;
    bvec3 parallel = equal(rayDir, vec3(0.0));
    vec3 farSide = mix(vec3(0.0), vec3(sceneVoxelVolumeSize), greaterThan(rayDir, vec3(0.0)));
    vec3 exitTimes = mix((farSide - voxelPos) / rayDir, vec3(1e30), parallel);
    float exitTime = max(0.0, minOf(exitTimes));
    vec3 stepDir = -sign(rayDir);
    const vec3 coarseSize = vec3(sceneVoxelCoarseCellSize);
    vec3 stepSizes = mix(coarseSize / abs(rayDir), vec3(1e30), parallel);
    vec3 start = clamp(voxelPos + max(0.0, exitTime - 0.001) * rayDir,
                       vec3(0.0), vec3(sceneVoxelVolumeSize) - 0.001);
    vec3 coarsePos = start / coarseSize;
    vec3 nextDistance = (stepDir * 0.5 + 0.5 - fract(coarsePos)) * coarseSize / -rayDir;
    nextDistance = mix(nextDistance, vec3(1e30), parallel);
    float travel = 0.0;
    const vec3 gridSize = vec3(sceneVoxelCoarseVolumeSize);
    while (travel <= exitTime + 0.001 && all(greaterThanEqual(coarsePos, vec3(0.0))) && all(lessThan(coarsePos, gridSize))) {
        ivec3 coarseStorage = WrapReflectionStoragePosition(ivec3(coarsePos), storageOrigin / sceneVoxelCoarseCellSize,
                                                            sceneVoxelCoarseVolumeSize);
        if (texelFetch(wsr_coarse_sampler, coarseStorage, 0).r != 0u)
            return max(0.0, exitTime - travel);
        float next = minOf(nextDistance);
        vec3 stepAxis = vec3(equal(nextDistance, vec3(next)));
        travel = next;
        nextDistance += stepAxis * stepSizes;
        coarsePos += stepAxis * stepDir;
    }
    return -1.0;
}

vec4 ApplyWorldSpaceReflectionFog(vec4 reflection, vec3 intersection, vec3 playerPos,
                                float RVdotU, float RVdotS, float dither) {
    reflection *= GetReflectionVolumeFade(playerPos);

    float skyFade = 0.0;
    float reflectionPrevAlpha = reflection.a;

    DoFog(reflection, skyFade, length(intersection), intersection, RVdotU, RVdotS, dither, true, length(playerPos));

    reflection.a = reflectionPrevAlpha * (1.0 - skyFade);

    return reflection;
}

float GetCellEntryDistance(vec3 origin, vec3 rayDir, ivec3 cell, out uint entryAxis) {
    vec3 dir = mix(vec3(1e-12), rayDir, greaterThanEqual(abs(rayDir), vec3(1e-12)));
    vec3 t0 = (vec3(cell) - origin) / dir;
    vec3 t1 = (vec3(cell) + 1.0 - origin) / dir;
    vec3 tNear = min(t0, t1);
    float entry = maxOf(tNear);
    entryAxis = tNear.x == entry ? 1u : tNear.y == entry ? 2u : 4u;
    return entry >= 0.0 && entry <= minOf(max(t0, t1)) ? entry : -1.0;
}

vec4 VoxelRayTrace(vec3 playerPos, vec3 voxelPos, vec3 rayDir, vec3 rayGradX, vec3 rayGradY, vec3 curvatureGradX, vec3 curvatureGradY,
                   float RVdotU, float RVdotS, float dither, out float traceLength, float startOffset) {
    const float boundaryOverlap = 0.001;
    #if WORLD_SPACE_SHAPES > 0
        ivec3 storageOrigin = PositiveModulo(GetReflectionVolumeOrigin(), sceneVoxelVolumeSize);
        int packedRegionOrigin = GetPackedRegionTileOffset();
    #else
        const ivec3 storageOrigin = ivec3(0);
        const int packedRegionOrigin = 0;
    #endif
    #if defined WSR_SPLIT_ENABLED && !defined WSR_TRACE_PREPASS
        uint pixel = GetReflectionPixelIndex();
        reflectionHitRecord record = hitBuffer.hits[pixel];
        bool lava = IsReflectionHitLava(record.ids);
        uint material = GetReflectionHitMaterial(record.ids);
        uint surfaceIndex = GetReflectionHitSurface(record.ids);
        traceLength = uintBitsToFloat(record.ids.z);
        if (material == 0u) {
            traceLength = 999999.0;
            return vec4(0.0);
        }
        ivec3 cell = GetSceneVoxelPosition(record.ids.x & shapeVoxelIndexMask, storageOrigin);
        reflectionCellHandle cellRef = reflectionCellHandle(int(record.ids.x & shapeVoxelIndexMask),
                                                            GetReflectionCellGeneration(cell, packedRegionOrigin));
        uint faceIndex = GetReflectionHitFace(record.ids);
        vec3 normal = faceIndex == 6u ? vec3(0.0) : GetShapeFaceNormal(int(faceIndex));
        vec3 surfaceNormal = normal;
        int family = GetReflectionShapeFamily(int(material));
        if (family == WSR_FAMILY_CAPTURED) {
            shapeRecord face = shapeDataSSBO.records[surfaceIndex];
            uint codeU = face.mapping.z & 63u, codeV = (face.mapping.z >> 6u) & 63u;
            uint faceCode = GetShapeFaceCode(face.shading.w), normalAxis = faceCode >> 1u;
            if (IsShapeAxisBasis(codeU, codeV, normalAxis))
                normal = GetShapeFaceNormal(int(faceCode));
            else {
                vec3 axisU, axisV;
                GetShapePlaneBasis(face.shading.w, codeU, codeV, axisU, axisV, normal);
            }
            surfaceNormal = normal;
        } else if (lava && normal.y > 0.5) {
            uint gx = (record.ids.y & 0x7fffffffu) | (((record.ids.x >> 27u) & 1u) << 31u);
            vec2 gradient = vec2(uintBitsToFloat(gx), uintBitsToFloat(record.ids.w));
            surfaceNormal = normalize(vec3(-gradient.x, 1.0, -gradient.y));
        }
        float positionDistance = traceLength
                               - (family == WSR_FAMILY_NONE && material != 10068u
                                  && !IsReflectionCutoutCube(int(material)) ? boundaryOverlap : 0.0);
        vec3 position = playerPos + positionDistance * rayDir;
        vec4 reflection = GetShadedReflection(cell, playerPos, position, rayDir, rayGradX, rayGradY,
                                              curvatureGradX, curvatureGradY, normal, surfaceNormal, material,
                                              dither, surfaceIndex, cellRef, storageOrigin);
        if (reflection.a < -0.5) {
            traceLength = 999999.0;
            return vec4(0.0);
        }
        return ApplyWorldSpaceReflectionFog(reflection, position, playerPos, RVdotU, RVdotS, dither);
    #else
        #if WORLD_SPACE_SHAPES > 0
            uint selectedCellIndex;
            vec3 selectedNormal;
            uint selectedMaterial, selectedSurface;
            bool selectedHit = false;
        #endif
        vec3 stepDir = sign(rayDir);
        float maxOccupiedDistance = -1.0;

        float startDist = 0.0;
        uint startAxis = 0u;
        ivec3 startCell = ivec3(floor(voxelPos));
        if (texelFetch(wsr_sampler, WrapReflectionStoragePosition(startCell, storageOrigin, sceneVoxelVolumeSize), 0).r != 0u) {
            uint entryAxis;
            float entryDist = GetCellEntryDistance(voxelPos - startOffset * rayDir, rayDir, startCell, entryAxis);
            if (entryDist >= 0.0) {
                startDist = max(entryDist - 0.001, 0.0015) - startOffset;
                startAxis = entryAxis;
            }
        }
        float traceStart = startDist;
        for (int attempt = 0; attempt < 1024; attempt++) {
            bool found = false;
            uint mat = 0u;
            ivec3 cell = ivec3(0);
            float hitDist = 0.0, cellExitDist = 0.0;
            uint hitStepAxis = 0u, exitAxis = 0u;
            {
                vec3 stepSizes = 1.0 / abs(rayDir);
                vec3 stepAxis = vec3(float(startAxis & 1u), float((startAxis >> 1u) & 1u), float((startAxis >> 2u) & 1u));
                vec3 basePos = voxelPos + startDist * rayDir;

                float dist1 = 0.0;
                vec3 voxelPosRT1 = basePos * 0.25;
                vec3 nextDist1 = (stepDir * 0.5 + 0.5 - fract(voxelPosRT1)) / rayDir;

                while (CheckInsideLodVoxelVolume(voxelPosRT1)) {
                    if (startDist + 4.0 * dist1 > 32.0) {
                        if (maxOccupiedDistance < 0.0) {
                            float occupiedDistance = GetFarthestOccupiedDistance(voxelPos, rayDir, storageOrigin);
                            maxOccupiedDistance = occupiedDistance < 0.0 ? 0.0 : occupiedDistance + 4.0;
                        }
                        if (startDist + 4.0 * dist1 > maxOccupiedDistance) break;
                    }
                    ivec3 lodStorage = WrapReflectionStoragePosition(ivec3(voxelPosRT1), storageOrigin / 4, sceneVoxelLodVolumeSize);
                    if (texelFetch(wsr_lod_sampler, lodStorage, 0).r > 0u) {
                        float dist0 = 0.0;
                        float backstep = min(boundaryOverlap, (startDist - traceStart) + 4.0 * dist1);
                        vec3 voxelPosRT0 = basePos + (4.0 * dist1 - backstep) * rayDir;
                        vec3 nextDist0 = (stepDir * 0.5 + 0.5 - fract(voxelPosRT0)) / rayDir;

                        vec3 lodVoxelMin = floor(voxelPosRT1) * 4.0;
                        vec3 lodVoxelMax = lodVoxelMin + 4.0;

                        float maxDist0 = minOf((mix(lodVoxelMin, lodVoxelMax, stepDir * 0.5 + 0.5) - voxelPosRT0) / rayDir);

                        if (CheckInsideSceneVoxelVolume(voxelPosRT0)) {
                            while (dist0 < maxDist0) {
                                ivec3 fetchCell = clamp(ivec3(voxelPosRT0), ivec3(0), sceneVoxelVolumeSize - 1);
                                ivec3 fetchStorage = WrapReflectionStoragePosition(fetchCell, storageOrigin, sceneVoxelVolumeSize);
                                uint cellMat = texelFetch(wsr_sampler, fetchStorage, 0).r;
                                if (cellMat > 0u) {
                                    found = true;
                                    mat = cellMat;
                                    cell = fetchCell;
                                    hitStepAxis = uint(stepAxis.x) | (uint(stepAxis.y) << 1u) | (uint(stepAxis.z) << 2u);
                                    hitDist = startDist + 4.0 * dist1 + dist0 + (boundaryOverlap - backstep);
                                    float cellExit = minOf(nextDist0);
                                    cellExitDist = startDist + 4.0 * dist1 + cellExit - backstep;
                                    uvec3 exitStep = uvec3(equal(nextDist0, vec3(cellExit)));
                                    exitAxis = exitStep.x | (exitStep.y << 1u) | (exitStep.z << 2u);
                                    break;
                                }

                                dist0 = minOf(nextDist0);
                                stepAxis = vec3(equal(nextDist0, vec3(dist0)));

                                nextDist0 += stepAxis * stepSizes;
                                voxelPosRT0 += stepAxis * stepDir;
                            }
                        }
                        if (found) break;
                    }

                    dist1 = minOf(nextDist1);
                    stepAxis = vec3(equal(nextDist1, vec3(dist1)));

                    nextDist1 += stepAxis * stepSizes;
                    voxelPosRT1 += stepAxis * stepDir;
                }
            }
            if (!found) break;
            reflectionCellHandle cellRef = GetReflectionCellHandle(cell, storageOrigin, packedRegionOrigin);

            float cellEntryDist = max(traceStart, hitDist - (hitDist == startDist ? 0.003 : 0.001));

            #if WORLD_SPACE_SHAPES > 0
                bool hasSurfaces = (mat & 32768u) != 0u;
                mat &= 32767u;
            #endif

            traceLength = hitDist;

            vec3 hitStep = vec3(float(hitStepAxis & 1u), float((hitStepAxis >> 1u) & 1u), float((hitStepAxis >> 2u) & 1u));
            vec3 hitWeight = hitStep * abs(rayDir);
            vec3 hitAxis = hitStep * vec3(equal(hitWeight, vec3(maxOf(hitWeight))));
            hitAxis *= vec3(1.0, 1.0 - hitAxis.x, (1.0 - hitAxis.x) * (1.0 - hitAxis.y));
            vec3 normal = -hitAxis * stepDir;
            vec3 intersection = playerPos + (traceLength - (IsReflectionCutoutCube(int(mat)) ? 0.0 : boundaryOverlap)) * rayDir;
            vec3 surfaceNormal = normal;
            bool hit = true;
            uint surfaceIndex = 0u;

            #if WORLD_SPACE_SHAPES > 0
                int family = GetReflectionShapeFamily(int(mat));
                if (family == WSR_FAMILY_CAPTURED || mat == 0u) hit = false;
                else if (family != WSR_FAMILY_NONE) {
                    vec3 local = voxelPos + cellEntryDist * rayDir - vec3(cell);
                    int model = family >= WSR_FAMILY_FIRST_MODEL ? GetReflectionShapeModel(int(mat)) : 0;
                    float shapeDist = IntersectReflectionShapeBoxes(
                        local, rayDir, family, model, GetShapeState(cellRef), max(0.0, cellExitDist - cellEntryDist), normal
                    );
                    hit = shapeDist >= 0.0;
                    if (hit) {
                        traceLength = cellEntryDist + shapeDist;
                        intersection = playerPos + traceLength * rayDir;
                        surfaceNormal = normal;
                        vec3 surfaceLocal = PlayerToSceneVoxel(intersection) - vec3(cell);
                        surfaceIndex = SelectShapeRecord(surfaceLocal, normal, cellRef, shapeRecordCapacity);
                        hit = surfaceIndex < shapeRecordCapacity;
                    }
                }
            #endif

            if (mat == 10068u) {
                vec3 localPos = voxelPos + cellEntryDist * rayDir - vec3(cell);
                vec3 lavaNormal;
                float lavaDist = IntersectLavaSurface(localPos, rayDir, GetLavaCornerHeights(cell),
                                                      max(0.0, cellExitDist - cellEntryDist), lavaNormal);
                hit = lavaDist >= 0.0;
                if (hit) {
                    traceLength = cellEntryDist + lavaDist;
                    intersection = playerPos + traceLength * rayDir;
                    if (lavaDist > 0.0 || normal.y > 0.5) {
                        normal = vec3(0.0, 1.0, 0.0);
                        surfaceNormal = lavaNormal;
                    }
                }
            }

            vec4 reflection = vec4(-1.0);
            for (int pick = 0; pick < 2 && hit; pick++) {
                reflection = GetShadedReflection(cell, playerPos, intersection, rayDir, rayGradX, rayGradY,
                                                 curvatureGradX, curvatureGradY, normal, surfaceNormal, mat, dither,
                                                 surfaceIndex, cellRef, storageOrigin);
                #if WORLD_SPACE_SHAPES > 0
                    if (reflection.a > -0.5 || family == WSR_FAMILY_NONE) break;
                    surfaceIndex = SelectShapeRecord(PlayerToSceneVoxel(intersection) - vec3(cell), normal, cellRef, surfaceIndex);
                    hit = surfaceIndex < shapeRecordCapacity;
                #else
                    break;
                #endif
            }
            #if WORLD_SPACE_SHAPES > 0
                if (hasSurfaces) {
                    float limit = reflection.a > -0.5 ? traceLength : cellExitDist;
                    vec3 planeNormal;
                    uint planeIndex, planeMaterial;
                    float virtualEntry = cellEntryDist + length(playerPos);
                    #ifdef WSR_LDS_GRADIENTS
                        vec3 surfaceRayX = LoadReflectionGradient(0u), surfaceRayY = LoadReflectionGradient(1u);
                        vec3 surfaceCurvatureX = LoadReflectionGradient(2u), surfaceCurvatureY = LoadReflectionGradient(3u);
                    #else
                        vec3 surfaceRayX = rayGradX, surfaceRayY = rayGradY;
                        vec3 surfaceCurvatureX = curvatureGradX, surfaceCurvatureY = curvatureGradY;
                    #endif
                    float distance = IntersectReflectionCapturedSurfaces(
                        cell, cellRef, storageOrigin, voxelPos + cellEntryDist * rayDir, rayDir, max(0.0, limit - cellEntryDist), textureAtlas,
                        virtualEntry * surfaceRayX + cellEntryDist * surfaceCurvatureX,
                        virtualEntry * surfaceRayY + cellEntryDist * surfaceCurvatureY,
                        surfaceRayX + surfaceCurvatureX, surfaceRayY + surfaceCurvatureY, planeNormal, planeIndex, planeMaterial
                    );
                    if (distance >= 0.0) {
                        float planeDist = cellEntryDist + distance;
                        reflection = vec4(1.0);
                        intersection = playerPos + planeDist * rayDir;
                        traceLength = planeDist;
                        normal = planeNormal;
                        surfaceNormal = planeNormal;
                        mat = planeMaterial;
                        surfaceIndex = planeIndex;
                    }
                }
            #endif
            if (reflection.a > -0.5) {
                #if WORLD_SPACE_SHAPES > 0
                    selectedCellIndex = uint(cellRef.storageIndex);
                    selectedNormal = normal;
                    selectedMaterial = mat;
                    selectedSurface = surfaceIndex;
                    selectedHit = true;
                    break;
                #else
                    return ApplyWorldSpaceReflectionFog(reflection, intersection, playerPos, RVdotU, RVdotS, dither);
                #endif
            }

            startDist = cellExitDist + 0.003;
            startAxis = exitAxis;
        }

        #if WORLD_SPACE_SHAPES > 0
            if (selectedHit) {
                #ifdef WSR_SPLIT_ENABLED
                    uint pixel = GetReflectionPixelIndex();
                    uint cell = selectedCellIndex;
                    uint faceIndex = all(equal(selectedNormal, vec3(0.0))) ? 6u : uint(GetReflectionFaceIndex(selectedNormal));
                    uvec4 ids = PackReflectionHit(cell, faceIndex, selectedMaterial, selectedSurface, traceLength, wsrLavaGradient);
                    hitBuffer.hits[pixel].ids = ids;
                    return vec4(0.0);
                #endif
            }
        #endif

        traceLength = 999999.0;
        return vec4(0.0);
    #endif
}

#if WORLD_SPACE_SHAPES <= 0 || defined WSR_SPLIT_ENABLED
vec4 GetWSR(vec3 playerPos, vec3 nViewPos, vec3 normalMR, vec3 nViewPosR, vec3 normalGradX, vec3 normalGradY,
            float RVdotU, float RVdotS, float z0, float dither, out float wsrTraceLength, bool isTranslucent,
            float startOffset) {
    if (!ReflectionStorageAvailable()) return vec4(0.0);
    WSR_PRECISE vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * normalMR);

    WSR_PRECISE vec3 rayDir = mat3(gbufferModelViewInverse) * nViewPosR;
    WSR_PRECISE vec3 voxelPos = PlayerToSceneVoxel(playerPos);

    if (CheckInsideSceneVoxelVolume(voxelPos)) {
        vec2 projScale = vec2(gbufferProjection[0][0], gbufferProjection[1][1]);
        vec2 pixelAngle = 2.0 * abs(nViewPos.z) / (projScale * vec2(viewWidth, viewHeight));
        vec3 rayGradX = reflect(gbufferModelViewInverse[0].xyz, worldNormal) * pixelAngle.x;
        vec3 rayGradY = reflect(gbufferModelViewInverse[1].xyz, worldNormal) * pixelAngle.y;
        vec3 curvatureGradX = vec3(0.0), curvatureGradY = vec3(0.0);

        if (isTranslucent) {
            vec3 incidentDir = mat3(gbufferModelViewInverse) * nViewPos;
            float VdotN = dot(incidentDir, worldNormal);
            curvatureGradX = -2.0 * (dot(incidentDir, normalGradX) * worldNormal + VdotN * normalGradX);
            curvatureGradY = -2.0 * (dot(incidentDir, normalGradY) * worldNormal + VdotN * normalGradY);

            curvatureGradX *= min(1.0, 3.0 * pixelAngle.x / max(length(curvatureGradX), 1e-12));
            curvatureGradY *= min(1.0, 3.0 * pixelAngle.y / max(length(curvatureGradY), 1e-12));
        }

        #ifdef WSR_LDS_GRADIENTS
            StoreReflectionGradient(0u, rayGradX);
            StoreReflectionGradient(1u, rayGradY);
            StoreReflectionGradient(2u, curvatureGradX);
            StoreReflectionGradient(3u, curvatureGradY);
            vec4 wsrResult = VoxelRayTrace(playerPos, voxelPos, rayDir, vec3(0), vec3(0), vec3(0), vec3(0),
                                           RVdotU, RVdotS, dither, wsrTraceLength, startOffset);
        #else
            vec4 wsrResult = VoxelRayTrace(playerPos, voxelPos, rayDir, rayGradX, rayGradY, curvatureGradX, curvatureGradY,
                                           RVdotU, RVdotS, dither, wsrTraceLength, startOffset);
        #endif

        #if WORLD_SPACE_PLAYER_REF == 1 && !defined WSR_TRACE_PREPASS
            if (!is_invisible && z0 > 0.56) {
                vec3 albedo;
                vec3 normal;
                playerEquipmentHit equipmentHit;

                if (rayTracePlayer(playerPos - 0.01 * rayDir, rayDir, wsrTraceLength, albedo, normal, equipmentHit)) {
                    float emission = 0.0;
                    #if defined WSR_PLAYER_EQUIPMENT && defined IPBR
                        emission = getPlayerEquipmentEmission(equipmentHit, normal, dither, albedo);
                    #endif
                    vec2 lmCoord = eyeBrightness / 240.0;

                    #ifdef OVERWORLD
                        float ambientMult = 1.5 * lmCoord.y;
                        float lightMult = 0.2 * pow2(pow2(lmCoord.y));
                    #else
                        float ambientMult = 1.5;
                        float lightMult = 0.0;
                    #endif

                    vec3 voxelPosM = SceneToVoxel(vec3(-relativeEyePosition));
                         voxelPosM = clamp01(voxelPosM / vec3(voxelVolumeSize));
                    vec4 lightVolume = GetLightVolume(voxelPosM);
                         lightVolume = max(lightVolume, vec4(0.000001));
                    vec3 specialLighting = pow(GetLuminance(lightVolume.rgb), 0.25) * DoLuminanceCorrection(pow(lightVolume.rgb, vec3(0.25)));

                    #if HELD_LIGHTING_MODE >= 1
                        vec3 heldLighting = GetHeldLighting(playerPos, vec3(999999.0), emission);
                        specialLighting = sqrt(pow2(specialLighting) + sqrt(heldLighting));
                    #endif

                    vec3 minLighting = 0.8 * sqrt(GetMinimumLighting(lmCoord.y));

                    vec3 sceneLighting = ambientMult * ambientColor + lightMult * lightColor;
                    #ifdef LIGHT_COLOR_MULTS
                        lightColorMult = GetLightColorMult();
                        sceneLighting *= lightColorMult;
                    #endif
                    #ifdef MOON_PHASE_INF_LIGHT
                        sceneLighting *= moonPhaseInfluence;
                    #endif

                    #ifdef OVERWORLD
                        specialLighting *= 1.0 - lmCoord.y * sunFactor;
                    #endif

                    vec3 lighting = sceneLighting + specialLighting * XLIGHT_I + minLighting;
                    lighting += emission * 0.8;

                    return vec4(albedo * lighting, GetReflectionVolumeFade(playerPos));
                }
            }
        #endif

        return wsrResult;
    }

    return vec4(0.0);
}
#endif
