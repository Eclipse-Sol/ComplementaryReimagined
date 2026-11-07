#extension GL_ARB_shader_image_load_store : enable

#include "/lib/voxelization/reflectionVoxelization.glsl"
#include "/lib/lighting/minimumLighting.glsl"
#include "/lib/materials/materialMethods/lavaRayTrace.glsl"
#if WORLD_SPACE_SHAPES > 0
    #include "/lib/materials/materialMethods/shapeRayTrace.glsl"
    #include "/lib/materials/materialMethods/shapeSurfaceTrace.glsl"
#endif

#if WORLD_SPACE_PLAYER_REF == 1 && !defined WSR_TRACE_PREPASS
    #include "/lib/materials/materialMethods/playerRayTracer.glsl"
#endif

#if defined OVERWORLD || defined END
    #ifndef GBUFFERS_WATER
        #include "/lib/lighting/shadowSampling.glsl"
        #if defined DO_PIXELATION_EFFECTS && defined PIXELATED_SHADOWS
            #include "/lib/misc/pixelation.glsl"
        #endif
    #endif

    #if SHADOW_SMOOTHING == 4 || SHADOW_QUALITY == 0
        const float offset = 0.00098;
    #elif SHADOW_SMOOTHING == 3
        const float offset = 0.00075;
    #elif SHADOW_SMOOTHING == 2
        const float offset = 0.0005;
    #elif SHADOW_SMOOTHING == 1
        const float offset = 0.0003;
    #endif
#endif

#if HELD_LIGHTING_MODE >= 1
    #include "/lib/lighting/heldLighting.glsl"
#endif

#ifdef CLOUD_SHADOWS
    #include "/lib/lighting/cloudShadows.glsl"
#endif

#ifdef LIGHT_COLOR_MULTS
    #include "/lib/colors/colorMultipliers.glsl"
#endif
#ifdef MOON_PHASE_INF_LIGHT
    #include "/lib/colors/moonPhaseInfluence.glsl"
#endif

vec2 getLocalTexCoord(vec3 local, vec3 normal) {
    return 1.0 - projectToFace(local, normal);
}

void getReflectionTexGrads(vec3 rayDir, vec3 positionGradX, vec3 positionGradY, vec3 normal, vec3 surfaceNormal,
                           out vec2 textureGradX, out vec2 textureGradY) {
    vec3 faceRayDir = rayDir / min(dot(surfaceNormal, rayDir), -1e-6);
    positionGradX -= faceRayDir * dot(surfaceNormal, positionGradX);
    positionGradY -= faceRayDir * dot(surfaceNormal, positionGradY);
    textureGradX = -projectToFace(positionGradX, normal);
    textureGradY = -projectToFace(positionGradY, normal);
}

vec3 getWSRNormalGrad(vec3 normalDiff, float pixelStep) {
    float diffLength = length(normalDiff);
    if (diffLength > 0.5) return vec3(0.0);
    return normalDiff * (max0(diffLength - 0.014) / max(diffLength, 1e-6) / pixelStep);
}

float getVoxelSpaceAO(ivec3 voxelPos, ivec3 normal, vec2 localTexCoord) {
    ivec3 absNormal = abs(normal);
    ivec3 hrz = ivec3(0, 0, 1) * absNormal.x + ivec3(1, 0, 0) * absNormal.y + ivec3(1, 0, 0) * absNormal.z;
    ivec3 vrt = ivec3(0, 1, 0) * absNormal.x + ivec3(0, 0, 1) * absNormal.y + ivec3(0, 1, 0) * absNormal.z;

    vec2 dir = 1.0 - 2.0 * localTexCoord;

    ivec2 signDir = ivec2(sign(dir));
    ivec3 voxelHrz = voxelPos + normal + signDir.x * hrz;
    ivec3 voxelVrt = voxelPos + normal + signDir.y * vrt;

    vec2 factor = pow2(dir);
    int matHrz = int(texelFetch(wsr_sampler, voxelHrz, 0).r & 32767u);
    int matVrt = int(texelFetch(wsr_sampler, voxelVrt, 0).r & 32767u);
    float occHrz = mix(1.0, float(matHrz == 0 || isReflectionShapeId(matHrz)), factor.x);
    float occVrt = mix(1.0, float(matVrt == 0 || isReflectionShapeId(matVrt)), factor.y);

    return 0.3 * (occHrz + occVrt) + 0.4;
}

#ifdef WSR_SPLIT_ENABLED
    // ids.x: bits 0-23 voxel index, 24-26 face index (6 = none), 27-31 low material bits.
    // ids.y: bits 0-9 high material bits, 10-30 captured-surface index.
    // ids.z: hit distance as float bits.
    //
    // Lava blocks set ids.y[31] and imply material 10068, so they reuse the material and surface
    // bits (and ids.w) to store the lava surface gradient instead
    struct reflectionHitRecord {
        uvec4 ids;
    };
    layout(std430, binding = 5) buffer reflectionHitBuffer {
        reflectionHitRecord hits[];
    } hitBuffer;

    uint reflectionPixelIndex() {
        ivec2 size = ivec2(vec2(viewWidth, viewHeight) * WSR_REFLECTION_SCALE);
        return uint(ivec2(gl_FragCoord.xy).x + size.x * ivec2(gl_FragCoord.xy).y);
    }
#endif

#ifdef WSR_LDS_GRADIENTS
    const uint wsrGradientWidth = gl_WorkGroupSize.x * gl_WorkGroupSize.y * gl_WorkGroupSize.z;
    shared uint wsrGradientStorage[12u * wsrGradientWidth];

    void storeReflectionGradient(uint slot, vec3 value) {
        uint lane = gl_LocalInvocationIndex;
        for (uint component = 0u; component < 3u; component++)
            wsrGradientStorage[(3u * slot + component) * wsrGradientWidth + lane] = floatBitsToUint(value[component]);
    }

    // Atomic reads stop a compiler forwarding the stored values into registers across traces
    vec3 loadReflectionGradient(uint slot) {
        uint lane = gl_LocalInvocationIndex;
        return uintBitsToFloat(uvec3(
            atomicAdd(wsrGradientStorage[(3u * slot) * wsrGradientWidth + lane], 0u),
            atomicAdd(wsrGradientStorage[(3u * slot + 1u) * wsrGradientWidth + lane], 0u),
            atomicAdd(wsrGradientStorage[(3u * slot + 2u) * wsrGradientWidth + lane], 0u)));
    }
#endif

vec4 getShadedReflection(ivec3 voxelPos, vec3 oldPlayerPos, vec3 playerPos, vec3 rayDir, vec3 rayGradX, vec3 rayGradY,
                         vec3 curvatureGradX, vec3 curvatureGradY, vec3 normal, vec3 surfaceNormal, uint mat, float dither,
                         uint surfaceIndex) {
    faceData faceData;
    vec2 faceTexCoord = getLocalTexCoord(fract(playerPos + cameraPositionBestFract), normal);
    vec2 localTexCoord = faceTexCoord;
    uint faceOrientation = 0u;
    bool lavaTop = mat == 10068u && normal.y > 0.99;
    mat2 lavaTextureRotation;
    vec2 textureSizeAtlas = textureSize(textureAtlas, 0);
    #if WORLD_SPACE_SHAPES > 0
        int family = getReflectionShapeFamily(int(mat));
        uint textureAxes = 0u;
        vec2 textureAxisScale = vec2(0.0);
        if (family != WSR_FAMILY_NONE) {
            if (surfaceIndex >= shapeSurfaceCapacity) return vec4(-1.0);
            vec3 local = playerToSceneVoxel(playerPos) - vec3(voxelPos);
            if ((shapeDataSSBO.surfaces[surfaceIndex].shading.w & shapeFlagPlane) != 0u)
                local = playerToSceneVoxel(playerPos) - vec3(getShapeSurfaceOwner(shapeDataSSBO.surfaces[surfaceIndex], voxelPos));
            if (!getReflectionShapeSurface(surfaceIndex, local, textureSizeAtlas, faceData, localTexCoord,
                                           textureAxes, textureAxisScale))
                return vec4(-1.0);
            mat = uint(getReflectionMaterial(int(mat)));
        } else
    #endif
    if (lavaTop) {
        #ifdef WSR_TRACE_PREPASS
            return vec4(1.0);
        #else
            faceData = getLavaFaceData(voxelPos, lavaTextureRotation);
            localTexCoord = 0.5 + lavaTextureRotation * (localTexCoord - 0.5);
        #endif
    } else {
        if (isReflectionCutoutCube(int(mat)) && dot(normal, normal) < 0.5) return vec4(-1.0);
        faceData = getFaceData(voxelPos, normal, faceOrientation);
        localTexCoord = getLocalTexCoord(playerToSceneVoxel(playerPos) - vec3(voxelPos), normal);
        localTexCoord = clamp(0.5 + orientReflectionFaceVector(localTexCoord - 0.5, faceOrientation), 0.0, 1.0);
    }
    if (faceData.textureBounds.z < 1e-6) return vec4(-1.0);

    vec2 textureRadVec2 = faceData.textureBounds.z * vec2(1.0, textureSizeAtlas.x / textureSizeAtlas.y);
    vec2 textureCoord = faceData.textureBounds.xy + 2.0 * textureRadVec2 * localTexCoord;

    #ifdef WSR_LDS_GRADIENTS
        rayGradX = loadReflectionGradient(0u);
        rayGradY = loadReflectionGradient(1u);
        curvatureGradX = loadReflectionGradient(2u);
        curvatureGradY = loadReflectionGradient(3u);
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
                vec3 axisU = getShapePlaneVector(int(textureAxes & 63u));
                vec3 axisV = getShapePlaneVector(int((textureAxes >> 6u) & 63u));
                vec2 gradScale = 2.0 * textureRadVec2 * textureAxisScale;
                textureGradX = gradScale * vec2(dot(gradX, axisU), dot(gradX, axisV));
                textureGradY = gradScale * vec2(dot(gradY, axisU), dot(gradY, axisV));
            } else {
                uint codeU = textureAxes & 7u, codeV = (textureAxes >> 3u) & 7u;
                vec2 gradScale = 2.0 * textureRadVec2 * textureAxisScale
                               * vec2(getShapeCodeSign(codeU), getShapeCodeSign(codeV));
                textureGradX = gradScale * vec2(gradX[codeU >> 1u], gradX[codeV >> 1u]);
                textureGradY = gradScale * vec2(gradY[codeU >> 1u], gradY[codeV >> 1u]);
            }
        } else
    #endif
    {
        getReflectionTexGrads(
            rayDir, virtualDist * rayGradX + hitDist * curvatureGradX, virtualDist * rayGradY + hitDist * curvatureGradY,
            normal, surfaceNormal, textureGradX, textureGradY
        );
        textureGradX = 2.0 * textureRadVec2 * orientReflectionFaceVector(textureGradX, faceOrientation);
        textureGradY = 2.0 * textureRadVec2 * orientReflectionFaceVector(textureGradY, faceOrientation);
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

    #if MC_VERSION >= 12111 && IRIS_VERSION < 11005 && !defined WSR_TRACE_PREPASS
        // stupid fake lods because custom texture lods broke with Iris in newer mc versions
        vec2 texelGradX = textureGradX * textureSizeAtlas;
        vec2 texelGradY = textureGradY * textureSizeAtlas;
        float lod = 0.5 * log2(max(max(dot(texelGradX, texelGradX), dot(texelGradY, texelGradY)), 1e-12));
        float fakeLod = 0.5 * lod;
        float lodMix = clamp01(fakeLod - 0.75 + 0.25 * dither);
        if (lodMix > 0.0) {
            vec2 lodCoordSpan = localTexCoord / pow(2.0, int(1.5 + pow2(max0(fakeLod)) + 0.0 * dither));

            vec2 lodCoord1 = faceData.textureBounds.xy + 2.0 * textureRadVec2 * (0.5 + lodCoordSpan);
            vec2 lodCoord2 = faceData.textureBounds.xy + 2.0 * textureRadVec2 * (0.25 + lodCoordSpan);
            vec2 lodCoord3 = faceData.textureBounds.xy + 2.0 * textureRadVec2 * lodCoordSpan;
            vec4 lodColor1 = texture2DLod(textureAtlas, lodCoord1, fakeLod) * vec4(faceData.glColor, 1.0);
            vec4 lodColor2 = texture2DLod(textureAtlas, lodCoord2, fakeLod) * vec4(faceData.glColor, 1.0);
            vec4 lodColor3 = texture2DLod(textureAtlas, lodCoord3, fakeLod) * vec4(faceData.glColor, 1.0);

            vec4 sharpColor = color;
            color = mix(color, 0.333333 * (lodColor1 + lodColor2 + lodColor3), lodMix);
            if (dot(color.rgb, vec3(0.333333)) - 0.5 < 0.49) color.a = mix(color.a, 1.0, lodMix);
            #ifdef WSR_SPLIT_ENABLED
                if (color.a < 0.0041) color = sharpColor;
            #else
                if (color.a < 0.0041) return vec4(-1.0);
            #endif
        }
    #endif

    #ifdef WSR_TRACE_PREPASS
        return vec4(1.0);
    #else
        bool noSmoothLighting = false, noDirectionalShading = false;
        int subsurfaceMode = 0;
        float emission = 0.0, NdotU = normal.y, NdotE = normal.x, snowMinNdotU = 0.0;
        vec2 lmCoordM = vec2(1.0);
        vec3 shadowMult = vec3(1.0), maRecolor = vec3(0.0);
        #ifdef IPBR
            float lViewPos = length(playerPos);
            vec4 glColor = vec4(faceData.glColor, 1.0);
            vec2 absMidCoordPos = vec2(textureRadVec2);
            vec2 midCoord = faceData.textureBounds.xy + 2.0 * textureRadVec2 * vec2(0.5);
            vec2 signMidCoordPos = localTexCoord * 2.0 - 1.0;
            bool noVanillaAO = false, centerShadowBias = false, noGeneratedNormals = false, doTileRandomisation = true;
            float smoothnessD = 0.0, materialMask = 0.0;
            float smoothnessG = 0.0, highlightMult = 1.0, noiseFactor = 1.0, snowFactor = 1.0, noPuddles = 0.0;
            vec2 lmCoord = faceData.lightmap;
            vec3 normalM = normal, geoNormal = normal;

            #define DURING_WORLDSPACE_REF
                #ifndef IPBR_COMPAT_MODE
                    #define IPBR_COMPAT_MODE
                #endif
                #undef DISTANT_LIGHT_BOKEH
                #include "/lib/materials/materialHandling/terrainIPBR.glsl"
            #undef DURING_WORLDSPACE_REF
        #else
            if (mat == 10009) { // Leaves
                #include "/lib/materials/specificMaterials/terrain/leaves.glsl"
            }
        #endif

        float NdotL = dot(normal, mat3(gbufferModelViewInverse) * lightVec);
        #ifdef SIDE_SHADOWING
            float lightingNdotL = max0(NdotL + 0.4) * 0.714;

            #ifdef END
                lightingNdotL = sqrt3(lightingNdotL);
            #endif
        #else
            float lightingNdotL = max0(NdotL);
        #endif

        #ifndef NETHER
            vec3 shadow = shadowMult;
            if (lightingNdotL > 0.0001) {
                float shadowLength = shadowDistance * 0.9166667 - length(playerPos); //consistent08JJ622
                if (shadowLength > 0.000001) {
                    float distanceBias = 0.12 + 0.0008 * pow(dot(playerPos, playerPos), 0.75);
                    vec3 bias = normal * distanceBias * (2.0 - 0.95 * max0(NdotL));
                    int shadowSamples = 2;

                    shadow = GetShadow(GetShadowPos(playerPos + bias), faceData.lightmap.y, offset, shadowSamples, false, playerPos);
                }
            }
            shadow *= dot(shadow, vec3(0.33333));
        #else
            vec3 shadow = vec3(1.0);
        #endif

        #ifdef CLOUD_SHADOWS
            shadow *= GetCloudShadow(playerPos);
        #endif

        faceData.lightmap = pow2(pow2(faceData.lightmap));
        float AO;
        #if WORLD_SPACE_SHAPES > 0
            if (family != WSR_FAMILY_NONE) {
                #if VANILLAAO_I > 0
                    ivec3 owner = getShapeSurfaceOwner(shapeDataSSBO.surfaces[surfaceIndex], voxelPos);
                    AO = pow(getReflectionShapeAO(surfaceIndex, playerToSceneVoxel(playerPos) - vec3(owner)), VANILLAAO_I * 0.01);
                    #ifdef IPBR
                        if (noVanillaAO) AO = 1.0;
                    #endif
                #else
                    AO = 1.0;
                #endif
            } else
        #endif
        AO = getVoxelSpaceAO(voxelPos, ivec3(normal), faceTexCoord);
        float directionalShading = noDirectionalShading ? 1.0 : (NdotU + 1.0) * 0.25 + 0.5;

        vec3 centerPlayerPos = floor(playerPos + cameraPosition + normal * 0.01) - cameraPosition + 0.5;
        vec3 playerPosM = mix(centerPlayerPos, playerPos, (AO - 0.8) / 0.2);
        vec3 voxelPosM = SceneToVoxel(playerPosM);
             voxelPosM = clamp01(voxelPosM / vec3(voxelVolumeSize));
        vec4 lightVolume = GetLightVolume(voxelPosM);
             lightVolume = max(lightVolume, vec4(0.000001));
        vec3 specialLighting = 0.8 * pow(GetLuminance(lightVolume.rgb), 0.25) * DoLuminanceCorrection(pow(lightVolume.rgb, vec3(0.3)));
        if (noSmoothLighting == true) specialLighting *= 0.6;

        vec3 minLighting = 0.8 * sqrt(GetMinimumLighting(faceData.lightmap.y));

        #if HELD_LIGHTING_MODE >= 1
            vec3 heldLighting = GetHeldLighting(playerPos, color.rgb, emission);
            specialLighting = sqrt(pow2(specialLighting) + sqrt(heldLighting));
        #endif

        #ifdef OVERWORLD
            float ambientMult = 0.9 * faceData.lightmap.y;
            float lightMult = (1.1 + 0.25 * subsurfaceMode) * lightingNdotL * shadowTime;
            lightMult *= 1.0 + abs(NdotE) * 0.25;
            specialLighting *= 1.0 - faceData.lightmap.y * sunFactor;
        #else
            float ambientMult = 1.0;
            float lightMult = 1.0 * lightingNdotL * shadowTime;
        #endif

        vec3 sceneLighting = ambientMult * ambientColor + lightMult * lightColor * shadow;
        #ifdef LIGHT_COLOR_MULTS
            lightColorMult = GetLightColorMult();
            sceneLighting *= lightColorMult;
        #endif
        #ifdef MOON_PHASE_INF_LIGHT
            sceneLighting *= moonPhaseInfluence;
        #endif

        vec3 lighting = sceneLighting + specialLighting * XLIGHT_I + minLighting;
        lighting = lighting * AO * directionalShading + emission * 0.8;

        vec3 fadeout = smoothstep(0.0, 32.0, 0.5 * sceneVoxelVolumeSize - abs(playerPos));
        float alphaFade = sqrt3(minOf(fadeout)) * 0.9 + 0.1;

        return vec4(color.rgb * lighting + maRecolor, alphaFade);
    #endif
}

float getLastOccupiedReflectionDistance(vec3 voxelPos, vec3 rayDir) {
    if (all(equal(rayDir, vec3(0.0)))) return -1.0;
    bvec3 parallel = equal(rayDir, vec3(0.0));
    vec3 farSide = mix(vec3(0.0), vec3(sceneVoxelVolumeSize), greaterThan(rayDir, vec3(0.0)));
    vec3 exitTimes = mix((farSide - voxelPos) / rayDir, vec3(1e30), parallel);
    float exitTime = max(0.0, minOf(exitTimes));
    vec3 stepDir = -sign(rayDir);
    vec3 stepSizes = mix(1.0 / abs(rayDir), vec3(1e30), parallel);
    vec3 start = clamp(voxelPos + max(0.0, exitTime - 0.001) * rayDir,
                       vec3(0.0), vec3(sceneVoxelVolumeSize) - 0.001);
    vec3 coarsePos = start * 0.0625;
    vec3 nextDistance = (stepDir * 0.5 + 0.5 - fract(coarsePos)) / -rayDir;
    nextDistance = mix(nextDistance, vec3(1e30), parallel);
    float travel = 0.0;
    const vec3 gridSize = vec3(sceneVoxelVolumeSize / 16);
    while (travel <= exitTime + 0.001 && all(greaterThanEqual(coarsePos, vec3(0.0))) && all(lessThan(coarsePos, gridSize))) {
        if (texelFetch(wsr_coarse_sampler, ivec3(coarsePos), 0).r != 0u)
            return max(0.0, exitTime - travel);
        float next = minOf(nextDistance);
        vec3 stepAxis = vec3(equal(nextDistance, vec3(next)));
        travel = 16.0 * next;
        nextDistance += stepAxis * stepSizes;
        coarsePos += stepAxis * stepDir;
    }
    return -1.0;
}

vec4 finishWorldSpaceReflection(vec4 reflection, vec3 intersection, vec3 playerPos,
                                float RVdotU, float RVdotS, float dither) {
    vec3 fadeout = smoothstep(0.0, 32.0, 0.5 * sceneVoxelVolumeSize - abs(playerPos));
    reflection *= sqrt3(minOf(fadeout)) * 0.9 + 0.1;

    float skyFade = 0.0;
    float reflectionPrevAlpha = reflection.a;

    DoFog(reflection, skyFade, length(intersection), intersection, RVdotU, RVdotS, dither, true, length(playerPos));

    reflection.a = reflectionPrevAlpha * (1.0 - skyFade);

    return reflection;
}

vec4 voxelRayTrace(vec3 playerPos, vec3 voxelPos, vec3 rayDir, vec3 rayGradX, vec3 rayGradY, vec3 curvatureGradX, vec3 curvatureGradY,
                   float RVdotU, float RVdotS, float dither, out float traceLength) {
    #if defined WSR_SPLIT_ENABLED && !defined WSR_TRACE_PREPASS
        uint pixel = reflectionPixelIndex();
        reflectionHitRecord record = hitBuffer.hits[pixel];
        bool lava = (record.ids.y & 0x80000000u) != 0u;
        uint material = lava ? 10068u : (record.ids.x >> 27u) | ((record.ids.y & 1023u) << 5u);
        uint surfaceIndex = lava ? 0u : record.ids.y >> 10u;
        traceLength = uintBitsToFloat(record.ids.z);
        if (material == 0u) {
            traceLength = 999999.0;
            return vec4(0.0);
        }
        ivec3 cell = getShapeVoxelPosition(record.ids.x & shapeVoxelIndexMask);
        uint faceIndex = (record.ids.x >> 24u) & 7u;
        vec3 normal = faceIndex == 6u ? vec3(0.0) : getShapeFaceNormal(int(faceIndex));
        vec3 surfaceNormal = normal;
        int family = getReflectionShapeFamily(int(material));
        if (family == WSR_FAMILY_CAPTURED) {
            shapeSurface face = shapeDataSSBO.surfaces[surfaceIndex];
            uint codeU = face.mapping.z & 63u, codeV = (face.mapping.z >> 6u) & 63u;
            uint faceCode = getShapeFaceCode(face.shading.w), normalAxis = faceCode >> 1u;
            if (isShapeAxisBasis(codeU, codeV, normalAxis))
                normal = getShapeFaceNormal(int(faceCode));
            else {
                vec3 axisU, axisV;
                getShapePlaneBasis(face.shading.w, codeU, codeV, axisU, axisV, normal);
            }
            surfaceNormal = normal;
        } else if (lava && normal.y > 0.5) {
            uint gx = (record.ids.y & 0x7fffffffu) | (((record.ids.x >> 27u) & 1u) << 31u);
            vec2 gradient = vec2(uintBitsToFloat(gx), uintBitsToFloat(record.ids.w));
            surfaceNormal = normalize(vec3(-gradient.x, 1.0, -gradient.y));
        }
        float positionDistance = traceLength
                               - (family == WSR_FAMILY_NONE && material != 10068u
                                  && !isReflectionCutoutCube(int(material)) ? 0.001 : 0.0);
        vec3 position = playerPos + positionDistance * rayDir;
        vec4 reflection = getShadedReflection(cell, playerPos, position, rayDir, rayGradX, rayGradY,
                                              curvatureGradX, curvatureGradY, normal, surfaceNormal, material,
                                              dither, surfaceIndex);
        if (reflection.a < -0.5) {
            traceLength = 999999.0;
            return vec4(0.0);
        }
        return finishWorldSpaceReflection(reflection, position, playerPos, RVdotU, RVdotS, dither);
    #else
        #if WORLD_SPACE_SHAPES > 0
            ivec3 selectedCell;
            vec3 selectedNormal;
            uint selectedMaterial, selectedSurface;
            bool selectedHit = false;
        #endif
        vec3 stepDir = sign(rayDir);
        float maxOccupiedDistance = -1.0;

        float startDist = 0.0;
        uint startAxis = 0u;
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
                            float occupiedDistance = getLastOccupiedReflectionDistance(voxelPos, rayDir);
                            maxOccupiedDistance = occupiedDistance < 0.0 ? 0.0 : occupiedDistance + 4.0;
                        }
                        if (startDist + 4.0 * dist1 > maxOccupiedDistance) break;
                    }
                    if (texelFetch(wsr_lod_sampler, ivec3(voxelPosRT1), 0).r > 0u) {
                        float dist0 = 0.0;
                        vec3 voxelPosRT0 = basePos + (4.0 * dist1 - 0.001) * rayDir; // consistency59SMG32: 0.001 offset to fix rare wsr glitches
                        vec3 nextDist0 = (stepDir * 0.5 + 0.5 - fract(voxelPosRT0)) / rayDir;

                        vec3 lodVoxelMin = floor(voxelPosRT1) * 4.0;
                        vec3 lodVoxelMax = lodVoxelMin + 4.0;

                        float maxDist0 = minOf((mix(lodVoxelMin, lodVoxelMax, stepDir * 0.5 + 0.5) - voxelPosRT0) / rayDir);

                        if (CheckInsideSceneVoxelVolume(voxelPosRT0)) {
                            while (dist0 < maxDist0) {
                                ivec3 fetchCell = clamp(ivec3(voxelPosRT0), ivec3(0), sceneVoxelVolumeSize - 1);
                                uint cellMat = texelFetch(wsr_sampler, fetchCell, 0).r;
                                if (cellMat > 0u) {
                                    found = true;
                                    mat = cellMat;
                                    cell = fetchCell;
                                    hitStepAxis = uint(stepAxis.x) | (uint(stepAxis.y) << 1u) | (uint(stepAxis.z) << 2u);
                                    hitDist = startDist + 4.0 * dist1 + dist0;
                                    float cellExit = minOf(nextDist0);
                                    cellExitDist = startDist + 4.0 * dist1 + cellExit - 0.001;
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

            float cellEntryDist = max(0.0, hitDist - (hitDist == startDist ? 0.003 : 0.001));

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
            vec3 intersection = playerPos + (traceLength - (isReflectionCutoutCube(int(mat)) ? 0.0 : 0.001)) * rayDir;
            vec3 surfaceNormal = normal;
            bool hit = true;
            uint surfaceIndex = 0u;

            #if WORLD_SPACE_SHAPES > 0
                int family = getReflectionShapeFamily(int(mat));
                if (family == WSR_FAMILY_CAPTURED || mat == 0u) hit = false;
                else if (family != WSR_FAMILY_NONE) {
                    vec3 local = voxelPos + cellEntryDist * rayDir - vec3(cell);
                    int model = family >= WSR_FAMILY_FIRST_MODEL ? getReflectionShapeModel(int(mat)) : 0;
                    float shapeDist = intersectReflectionShapeBoxes(
                        local, rayDir, family, model, getShapeState(cell), max(0.0, cellExitDist - cellEntryDist), normal
                    );
                    hit = shapeDist >= 0.0;
                    if (hit) {
                        traceLength = cellEntryDist + shapeDist;
                        intersection = playerPos + traceLength * rayDir;
                        surfaceNormal = normal;
                        vec3 surfaceLocal = playerToSceneVoxel(intersection) - vec3(cell);
                        surfaceIndex = selectReflectionShapeSurface(cell, surfaceLocal, normal);
                        hit = surfaceIndex < shapeSurfaceCapacity;
                    }
                }
            #endif

            if (mat == 10068u) {
                vec3 localPos = voxelPos + cellEntryDist * rayDir - vec3(cell);
                vec3 lavaNormal;
                float lavaDist = intersectLavaSurface(localPos, rayDir, getLavaCornerHeights(cell),
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
            if (hit)
                reflection = getShadedReflection(cell, playerPos, intersection, rayDir, rayGradX, rayGradY,
                                                 curvatureGradX, curvatureGradY, normal, surfaceNormal, mat, dither,
                                                 surfaceIndex);
            #if WORLD_SPACE_SHAPES > 0
                if (hasSurfaces) {
                    float limit = reflection.a > -0.5 ? traceLength : cellExitDist;
                    vec3 planeNormal;
                    uint planeIndex, planeMaterial;
                    float virtualEntry = cellEntryDist + length(playerPos);
                    #ifdef WSR_LDS_GRADIENTS
                        vec3 surfaceRayX = loadReflectionGradient(0u), surfaceRayY = loadReflectionGradient(1u);
                        vec3 surfaceCurvatureX = loadReflectionGradient(2u), surfaceCurvatureY = loadReflectionGradient(3u);
                    #else
                        vec3 surfaceRayX = rayGradX, surfaceRayY = rayGradY;
                        vec3 surfaceCurvatureX = curvatureGradX, surfaceCurvatureY = curvatureGradY;
                    #endif
                    float distance = intersectReflectionCapturedSurfaces(
                        cell, voxelPos + cellEntryDist * rayDir, rayDir, max(0.0, limit - cellEntryDist), textureAtlas,
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
                    selectedCell = cell;
                    selectedNormal = normal;
                    selectedMaterial = mat;
                    selectedSurface = surfaceIndex;
                    selectedHit = true;
                    break;
                #else
                    return finishWorldSpaceReflection(reflection, intersection, playerPos, RVdotU, RVdotS, dither);
                #endif
            }

            startDist = cellExitDist + 0.003;
            startAxis = exitAxis;
        }

        #if WORLD_SPACE_SHAPES > 0
            if (selectedHit) {
                #ifdef WSR_SPLIT_ENABLED
                    uint pixel = reflectionPixelIndex();
                    uint cell = uint(getSceneVoxelIndex(selectedCell));
                    uint faceIndex = all(equal(selectedNormal, vec3(0.0))) ? 6u : uint(getShapeFaceIndex(selectedNormal));
                    uvec4 ids = uvec4(
                        cell | (faceIndex << 24u) | ((selectedMaterial & 31u) << 27u),
                        (selectedMaterial >> 5u) | (selectedSurface << 10u), floatBitsToUint(traceLength), 0u
                    );
                    if (selectedMaterial == 10068u) {
                        uint gx = floatBitsToUint(wsrLavaGradient.x);
                        ids = uvec4(
                            cell | (faceIndex << 24u) | ((gx >> 31u) << 27u), 0x80000000u | (gx & 0x7fffffffu),
                            ids.z, floatBitsToUint(wsrLavaGradient.y)
                        );
                    }
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
vec4 getWSR(vec3 playerPos, vec3 nViewPos, vec3 normalMR, vec3 nViewPosR, vec3 normalGradX, vec3 normalGradY,
            float RVdotU, float RVdotS, float z0, float dither, out float wsrTraceLength, bool isTranslucent) {
    WSR_PRECISE vec3 worldNormal = normalize(mat3(gbufferModelViewInverse) * normalMR);

    WSR_PRECISE vec3 rayDir = mat3(gbufferModelViewInverse) * nViewPosR;
    WSR_PRECISE vec3 voxelPos = playerToSceneVoxel(playerPos);

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
            storeReflectionGradient(0u, rayGradX);
            storeReflectionGradient(1u, rayGradY);
            storeReflectionGradient(2u, curvatureGradX);
            storeReflectionGradient(3u, curvatureGradY);
            vec4 wsrResult = voxelRayTrace(playerPos, voxelPos, rayDir, vec3(0), vec3(0), vec3(0), vec3(0),
                                           RVdotU, RVdotS, dither, wsrTraceLength);
        #else
            vec4 wsrResult = voxelRayTrace(playerPos, voxelPos, rayDir, rayGradX, rayGradY, curvatureGradX, curvatureGradY,
                                           RVdotU, RVdotS, dither, wsrTraceLength);
        #endif

        #if WORLD_SPACE_PLAYER_REF == 1 && !defined WSR_TRACE_PREPASS
            if (!is_invisible && z0 > 0.56) {
                vec3 albedo;
                vec3 normal;

                if (rayTracePlayer(playerPos - 0.01 * rayDir, rayDir, wsrTraceLength, albedo, normal)) {
                    vec2 lmCoord = eyeBrightness / 240.0;

                    #ifdef OVERWORLD
                        float ambientMult = 1.5 * lmCoord.y;
                        float lightMult = 0.2 * pow2(pow2(lmCoord.y));
                    #else
                        float ambientMult = 1.5;
                        float lightMult = 0.0;
                    #endif

                    vec3 voxelPosM = SceneToVoxel(vec3(0.0));
                        voxelPosM = clamp01(voxelPosM / vec3(voxelVolumeSize));
                    vec4 lightVolume = GetLightVolume(voxelPosM);
                        lightVolume = max(lightVolume, vec4(0.000001));
                    vec3 specialLighting = pow(GetLuminance(lightVolume.rgb), 0.25) * DoLuminanceCorrection(pow(lightVolume.rgb, vec3(0.25)));

                    #if HELD_LIGHTING_MODE >= 1
                        vec3 heldLighting = GetHeldLighting(playerPos, vec3(999999.0), 0.0);
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

                    vec3 lighting = sceneLighting + specialLighting * (1.0 - lmCoord.y * sunFactor) * XLIGHT_I + minLighting;

                    vec3 fadeout = smoothstep(0.0, 32.0, 0.5 * sceneVoxelVolumeSize - abs(playerPos));
                    float alphaFade = sqrt3(minOf(fadeout)) * 0.9 + 0.1;

                    return vec4(albedo * lighting, alphaFade);
                }
            }
        #endif

        return wsrResult;
    }

    return vec4(0.0);
}
#endif
