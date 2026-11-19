#include "/lib/misc/reprojection.glsl"
#include "/lib/materials/materialMethods/reflectionValidation.glsl"

#ifdef OVERWORLD
    #include "/lib/atmospherics/sky.glsl"
#endif
#if defined END && defined COMPOSITE
    #include "/lib/atmospherics/volumetricLight/enderBeams.glsl"
#endif

#ifdef ATM_COLOR_MULTS
    #include "/lib/colors/colorMultipliers.glsl"
#endif
#ifdef MOON_PHASE_INF_ATMOSPHERE
    #include "/lib/colors/moonPhaseInfluence.glsl"
#endif

#if WORLD_SPACE_REFLECTIONS_INTERNAL > 0 && defined COMPOSITE
    #include "/lib/voxelization/lightVoxelization.glsl"
    #include "/lib/materials/materialMethods/worldSpaceRef.glsl"
#endif

float GetApproxDistance(float depth) {
    return near * far / (far - depth * far);
}

vec3 nvec3(vec4 pos) {
    return pos.xyz/pos.w;
}

float refDist = far;

#include "/lib/materials/materialMethods/reflectionBackground.glsl"

float GetWSRSurfaceBias(vec3 viewPos) {
    return 0.001 + 3.576278687e-7 * abs(gbufferProjectionInverse[2][3]) * dot(viewPos, viewPos);
}

vec3 GetWSRReflectionStart(vec3 viewPos, vec3 normal, vec3 rayDir, float surfaceBias) {
    return viewPos + rayDir * (surfaceBias / max(dot(rayDir, normal), 0.04));
}

vec3 GetSSRReflectionStart(vec3 viewPos, vec3 normal, vec3 rayDir, float distance, float fresnel) {
    float clearance = distance * 0.025 * (1.0 - fresnel) + 0.05;
    return viewPos + rayDir * (clearance / max(dot(rayDir, normalize(normal)), 0.04));
}

#if WORLD_SPACE_REFLECTIONS_INTERNAL > 0
    float GetSSREdgeFade(vec2 edgeDistance) {
        vec2 fade = 1.0 - smoothstep(0.8, 1.0, edgeDistance);
        return fade.x * fade.y;
    }
#endif

#if (defined COMPOSITE || WATER_REFLECT_QUALITY >= 2) && (WORLD_SPACE_REFLECTIONS_INTERNAL == -1 || WORLD_SPACE_REF_MODE == 2) && !defined WSR_TRACE_PREPASS
    vec3 GetSSRDepthPos(vec2 rayCoord, vec2 sampleCoord, sampler2D depthtex, out float sampleDepth, out bool lodHit) {
        sampleDepth = texture2D(depthtex, sampleCoord).r;
        vec3 depthPos = ScreenToView(vec3(rayCoord, sampleDepth));
        lodHit = false;

        #if defined GBUFFERS_WATER && (defined DISTANT_HORIZONS || defined VOXY)
            if (sampleDepth >= 1.0) {
                #ifdef VOXY
                    sampleDepth = texture2D(vxDepthTexOpaque, sampleCoord).r;
                    if (sampleDepth < 1.0) {
                        depthPos = ScreenToViewVoxy(vec3(rayCoord, sampleDepth));
                        lodHit = true;
                    }
                #endif
                #ifdef DISTANT_HORIZONS
                    sampleDepth = texture2D(dhDepthTex1, sampleCoord).r;
                    if (sampleDepth < 1.0) {
                        depthPos = nvec3(dhProjectionInverse * vec4(vec3(rayCoord, sampleDepth) * 2.0 - 1.0, 1.0));
                        lodHit = true;
                    }
                #endif
            }
        #endif

        return depthPos;
    }

    bool SampleSSRDepth(vec3 viewPos, sampler2D depthtex, vec2 rEdge,
                        out vec3 refPos, out vec3 depthPos, out bool lodHit) {
        refPos = vec3(0.0, 0.0, 1.0);
        depthPos = vec3(0.0);
        lodHit = false;
        vec4 clipPos = gbufferProjection * vec4(viewPos, 1.0);
        if (clipPos.w <= 0.0) return false;

        vec2 rayCoord = clipPos.xy / clipPos.w * 0.5 + 0.5;
        vec2 sampleCoord = rayCoord;
        #ifdef TAA
            sampleCoord = TAAJitter(sampleCoord, 0.5);
        #endif
        if (abs(sampleCoord.x - 0.5) > rEdge.x || abs(sampleCoord.y - 0.5) > rEdge.y) return false;

        float sampleDepth;
        depthPos = GetSSRDepthPos(rayCoord, sampleCoord, depthtex, sampleDepth, lodHit);
        refPos = vec3(sampleCoord, sampleDepth);
        return true;
    }

    void RefineSSRHit(vec3 start, vec3 rayDir, sampler2D depthtex, vec2 rEdge,
                      inout vec3 refPos, inout vec3 rfragpos, inout bool lodHit, inout float err) {
        vec3 viewDir = normalize(rfragpos);
        vec3 crossRayView = cross(rayDir, viewDir);
        float crossLength2 = dot(crossRayView, crossRayView);
        if (crossLength2 < 1e-6) return;

        float s0 = -dot(cross(start, viewDir), crossRayView) / crossLength2;
        float g0 = dot(rfragpos - (start + rayDir * s0), viewDir);
        float s1 = max(dot(rfragpos - start, rayDir), 0.0);

        for (int i = 0; i < 4; i++) {
            vec3 rayPos = start + rayDir * s1;
            vec3 candidateRefPos, depthPos;
            bool candidateLodHit;
            if (!SampleSSRDepth(rayPos, depthtex, rEdge, candidateRefPos, depthPos, candidateLodHit)
                || candidateRefPos.z >= 1.0) break;

            float candidateErr = length(depthPos - rayPos);
            if (candidateErr < err) {
                refPos = candidateRefPos;
                rfragpos = depthPos;
                lodHit = candidateLodHit;
                err = candidateErr;
            }

            if (i == 3) break;
            float g1 = dot(depthPos - rayPos, normalize(rayPos));
            float gDif = g1 - g0;
            if (abs(gDif) < 1e-7) break;
            float s2 = s1 - g1 * (s1 - s0) / gDif;
            s0 = s1;
            g0 = g1;
            s1 = max(s2, 0.0);
        }
    }
#endif

vec4 GetReflection(inout vec3 normalM, vec3 viewPos, vec3 nViewPos, vec3 playerPos, float lViewPos, float z0,
                   sampler2D depthtex, float dither, float skyLightFactor, float fresnel,
                   float smoothness, vec3 geoNormal, vec3 color, vec3 shadowMult, float highlightMult,
                   vec3 normalGradX, vec3 normalGradY) {
    // ============================== Step 1: Prepare ============================== //
    #if WORLD_SPACE_REFLECTIONS_INTERNAL == -1
        vec2 rEdge = vec2(0.6, 0.55);
    #else
        vec2 rEdge = vec2(0.5, 0.5);
    #endif
    vec3 normalMR = normalM;

    #if defined GBUFFERS_WATER && WATER_STYLE == 1 && defined GENERATED_NORMALS
        normalMR = normalize(mix(geoNormal, normalM, 0.05));
    #endif

    WSR_PRECISE vec3 nViewPosR = normalize(reflect(nViewPos, normalMR));
    float RVdotU = dot(nViewPosR, upVec);
    float RVdotS = dot(nViewPosR, sunVec);

    #if defined GBUFFERS_WATER && WATER_STYLE >= 2
        normalMR = normalize(mix(geoNormal, normalM, 0.8));
    #endif

    #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0
        vec3 reflectionOriginNormal = normalize(dot(geoNormal, geoNormal) > 1e-6 ? geoNormal : normalMR);
        float reflectionBias = GetWSRSurfaceBias(viewPos);
        WSR_PRECISE vec3 reflectionStart = GetWSRReflectionStart(viewPos, reflectionOriginNormal, nViewPosR, reflectionBias);
    #endif
    // ============================== End of Step 1 ============================== //

    // ============================== Step 2: Calculate Terrain Reflection and Alpha ============================== //
    // In COMPOSITE, translucents skip SSR and return covered WSR terrain before adding sky.
    #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0 && defined COMPOSITE
        bool wsrTranslucent = z0 != z1;
    #else
        const bool wsrTranslucent = false;
    #endif

    vec4 reflection = vec4(0.0);
    #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0
        float hitConfidence = 1.0;
    #endif
    #if (defined COMPOSITE || WATER_REFLECT_QUALITY >= 1) && (WORLD_SPACE_REFLECTIONS_INTERNAL == -1 || WORLD_SPACE_REF_MODE == 2) && !defined WSR_TRACE_PREPASS
        // Method 1: Ray Marched Reflection //
        #if defined COMPOSITE || WATER_REFLECT_QUALITY >= 2
            if (!wsrTranslucent) {
            // Ray Marching
            #if defined GBUFFERS_WATER && WATER_STYLE >= 2
                vec3 rayDir = normalize(reflect(nViewPos, normalMR)); // Not using nViewPosR because normalMR changed
            #else
                vec3 rayDir = nViewPosR;
            #endif

            vec3 start = GetSSRReflectionStart(viewPos, normalMR, rayDir, lViewPos, fresnel);
            float startLength = length(start - viewPos);

            float dist = 0.0;
            vec3 refPos = vec3(0.0);
            vec3 rfragpos = vec3(0.0);
            float err = 9999999.0;
            bool lodHit = false;

            bool startHidden = SampleSSRDepth(start, depthtex, rEdge, refPos, rfragpos, lodHit)
                               && refPos.z < 1.0 && dot(rfragpos, rfragpos) < dot(start, start);
            if (startHidden) {
                float visibleLength = 0.0;
                float hiddenLength = startLength;
                for (int i = 0; i < 5; i++) {
                    float midLength = 0.5 * (visibleLength + hiddenLength);
                    vec3 rayPos = viewPos + rayDir * midLength;
                    vec3 midRefPos, midDepthPos;
                    bool midLodHit;
                    if (SampleSSRDepth(rayPos, depthtex, rEdge, midRefPos, midDepthPos, midLodHit)
                        && midRefPos.z < 1.0 && dot(midDepthPos, midDepthPos) < dot(rayPos, rayPos)) {
                        hiddenLength = midLength;
                        refPos = midRefPos;
                        rfragpos = midDepthPos;
                        lodHit = midLodHit;
                    } else {
                        visibleLength = midLength;
                    }
                }
                err = length(viewPos + rayDir * hiddenLength - rfragpos);
                startHidden = err < startLength;
            }

            if (!startHidden) {
                vec3 vector = rayDir * 0.5;
                vec3 viewPosRT = start + vector;
                vec3 tvector = vector;

                #if WORLD_SPACE_REFLECTIONS_INTERNAL == -1
                    int sampleCount = 30;
                    int refinementCount = 6;
                #else
                    int sampleCount = 38;
                    int refinementCount = 10;
                #endif

                int sr = 0;
                for (int i = 0; i < sampleCount; i++) {
                    if (!SampleSSRDepth(viewPosRT, depthtex, rEdge, refPos, rfragpos, lodHit)) break;

                    err = length(viewPosRT - rfragpos);
                    if (err * 0.33333 < length(vector)) {
                        sr++;
                        if (sr >= refinementCount) break;
                        tvector -= vector;
                        vector *= 0.1;
                    }
                    vector *= 2.0;
                    tvector += vector * (0.95 + 0.1 * dither);
                    viewPosRT = start + tvector;
                }

                if (sr > 0 && refPos.z < 1.0) {
                    RefineSSRHit(start, rayDir, depthtex, rEdge, refPos, rfragpos, lodHit, err);
                }
            }
            dist = length(rfragpos - viewPos);

            float lViewPosRT = length(rfragpos);

            #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0
                #if !defined COMPOSITE || BLOCK_REFLECT_QUALITY >= 2
                    if (!lodHit && lViewPosRT <= 0.25 * COLORED_LIGHTING_INTERNAL) {
                        float pixelSize = 2.0 * lViewPosRT / (gbufferProjection[1][1] * viewHeight);
                        float depthTolerance = 0.005 + pixelSize;
                        hitConfidence = 1.0 - smoothstep(depthTolerance, 2.0 * depthTolerance, err);
                    }
                #endif
            #endif

            #ifdef COMPOSITE
                bool possibleReflection = true;
            #else
                bool possibleReflection = startHidden || dot(normalize(rfragpos - start), geoNormal) > 0.0;
            #endif

            #ifdef VOXY_PATCH
                if (refPos.x > 0.0 && refPos.x < 1.0 && refPos.y > 0.0 && refPos.y < 1.0)
                {
                    // Previous frame reprojection from Chocapic13
                    // Voxy water needs reflection reprojection due to rendering before deferred
                    vec4 viewPosPrev = vec4(rfragpos, 1.0);
                    viewPosPrev = vxModelViewInv * viewPosPrev;

                    vec4 previousPosition = viewPosPrev + vec4(cameraPosition - previousCameraPosition, 0.0);
                    previousPosition = vxModelViewPrev * previousPosition;
                    previousPosition = vxProjPrev * previousPosition;
                    refPos.xy = previousPosition.xy / previousPosition.w * 0.5 + 0.5;
                    #ifdef TAA
                        refPos.xy = TAAJitter(refPos.xy, 0.5, (int(framemod8) + 7) % 8);
                    #endif
                }
            #endif

            // Finalizing Terrain Reflection and Alpha
            if (
                refPos.z < 1.0
                && (lodHit || refPos.z > 0.56)
                && possibleReflection
                && (err * (1.0 - fresnel) < 1.0 + lViewPosRT * 0.2)
                #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0 && COLORED_LIGHTING_INTERNAL >= 256
                    && (err < 2.0 + pow2(lViewPosRT) * 0.001 || lViewPosRT > 0.25 * COLORED_LIGHTING_INTERNAL)
                #endif
            ) {
                vec2 absPos = abs(refPos.xy - 0.5);
                vec2 cdist = absPos / rEdge;
                #if WORLD_SPACE_REFLECTIONS_INTERNAL == -1
                    float border = clamp(1.0 - pow(max(cdist.x, cdist.y), 50.0), 0.0, 1.0);
                #else
                    float border = GetSSREdgeFade(cdist);
                #endif
                reflection.a = border;

                if (reflection.a > 0.001) {
                    #if WORLD_SPACE_REFLECTIONS_INTERNAL == -1
                        vec2 edgeFactor = pow2(pow2(pow2(cdist)));
                        refPos.y += (dither - 0.5) * (0.05 * (edgeFactor.x + edgeFactor.y));
                    #endif

                    #if defined GBUFFERS_WATER || defined DH_WATER || defined VOXY_PATCH
                        #ifndef VOXY_PATCH
                            reflection.rgb = texture2D(colortex9, refPos.xy).rgb;
                        #else
                            reflection.rgb = texture2D(colortex19, refPos.xy).rgb;
                        #endif
                        #if WORLD_SPACE_REFLECTIONS_INTERNAL == -1
                            reflection.a = 1.0;
                        #endif
                    #else
                        float smoothnessDM = pow2(smoothness);
                        float lodFactor = 1.0 - exp(-0.125 * (1.0 - smoothnessDM) * dist);
                        float lod = log2(viewHeight / 8.0 * (1.0 - smoothnessDM) * lodFactor) * 0.45;
                        if (z0 <= 0.56) lod *= 2.22; // Using more lod to compensate for less roughness noise on held items
                        lod = max(lod - 1.0, 0.0);

                        reflection.rgb = texture2DLod(colortex9, refPos.xy, lod).rgb;
                    #endif

                    float skyFade = 0.0;

                    #if defined GBUFFERS_WATER || defined DH_WATER || defined VOXY_PATCH
                        float reflectionPrevAlpha = reflection.a;
                        DoFog(reflection, skyFade, lViewPosRT, ViewToPlayer(rfragpos.xyz), RVdotU, RVdotS, dither, true, lViewPos);
                        reflection.a = reflectionPrevAlpha;
                        //reflection.a *= 1.0 - skyFade;
                    #endif

                    #if WORLD_SPACE_REFLECTIONS_INTERNAL == -1
                        edgeFactor.x = pow2(edgeFactor.x);
                        edgeFactor = 1.0 - edgeFactor;
                        float refFactor = pow(edgeFactor.x * edgeFactor.y, 2.0 + 3.0 * GetLuminance(reflection.rgb));
                        reflection.a *= refFactor;
                    #endif
                    refDist = dist;
                }

                float rayNearestLength = length(viewPos + rayDir * max(-dot(viewPos, rayDir), 0.0));
                float posDif = lViewPosRT - rayNearestLength;
                reflection.a *= clamp(posDif + 3.0, 0.0, 1.0);
            }
            }
        #endif

        // Method 2: Mirorred Image Reflection //
        #if !defined COMPOSITE && WATER_REFLECT_QUALITY < 2
            #if WATER_REFLECT_QUALITY < 2 && !defined DISTANT_HORIZONS
                float verticalStretch = 0.013;
            #else
                float verticalStretch = 0.0025;
            #endif

            vec4 clipPosR = gbufferProjection * vec4(nViewPosR + verticalStretch * viewPos, 1.0);
            vec3 screenPosR = clipPosR.xyz / clipPosR.w * 0.5 + 0.5;
            #ifdef TAA
                screenPosR.xy = TAAJitter(screenPosR.xy, 0.5);
            #endif
            vec2 screenPosRM = abs(screenPosR.xy - 0.5);

            if (screenPosRM.x < rEdge.x && screenPosRM.y < rEdge.y) {
                #if WORLD_SPACE_REFLECTIONS_INTERNAL == -1
                    vec2 edgeFactor = pow2(pow2(pow2(screenPosRM / rEdge)));
                    screenPosR.y += (dither - 0.5) * (0.03 * (edgeFactor.x + edgeFactor.y) + 0.001);
                #endif
                float z1R = texture2D(depthtex1, screenPosR.xy).x;
                screenPosR.z = z1R;
                vec3 rayScreenPos = screenPosR;
                #ifdef TAA
                    rayScreenPos.xy = TAAJitter(rayScreenPos.xy, -0.5);
                #endif
                vec3 viewPosR = ScreenToView(rayScreenPos);
                float lViewPosR = length(viewPosR);

                #ifdef DISTANT_HORIZONS
                    float z1RDH = texture2D(dhDepthTex, screenPosR.xy).x;
                    vec4 screenPos1DH = vec4(rayScreenPos.xy, z1RDH, 1.0);
                    vec4 viewPos1DH = dhProjectionInverse * (screenPos1DH * 2.0 - 1.0);
                    viewPos1DH /= viewPos1DH.w;
                    lViewPosR = min(lViewPosR, length(viewPos1DH.xyz));

                    z1R = min(z1R, z1RDH);
                #endif

                if (z1R < 0.9999 && lViewPos <= 2.0 + lViewPosR) {
                    reflection.rgb = texture2D(colortex9, screenPosR.xy).rgb;

                    #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0
                        reflection.a = GetSSREdgeFade(screenPosRM / rEdge);
                    #else
                        edgeFactor = 1.0 - edgeFactor;
                        reflection.a = edgeFactor.x * pow2(edgeFactor.y);
                    #endif
                    reflection.a *= clamp01((dot(nViewPos, nViewPosR) - 0.45) * 10.0); // Fixes perpendicular ref bug

                    #ifdef BORDER_FOG
                        float fog = lViewPosR / renderDistance;
                        fog = pow2(pow2(fog));
                        #ifndef DISTANT_HORIZONS
                            fog = pow2(pow2(fog));
                        #endif
                        reflection.a *= exp(-3.0 * fog);
                    #endif
                }
            }
        #endif
    #endif
    // ============================== End of Step 2 ============================== //

    // ============================== Step 3: Add Sky or WSR Reflection ============================== //
    #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0
        reflection.a *= hitConfidence;
        #ifdef COMPOSITE
            reflection.rgb *= reflection.a;
        #endif
    #endif
    if (reflection.a <= 0.0) refDist = far;
    #if defined COMPOSITE || WATER_REFLECT_QUALITY >= 1
        if (reflection.a < 1.0)
    #endif
    {
        #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0 && defined COMPOSITE && (BLOCK_REFLECT_QUALITY >= 2 || WATER_REFLECT_QUALITY >= 1)
            #if BLOCK_REFLECT_QUALITY < 2 && WATER_REFLECT_QUALITY < 2
                if (wsrTranslucent)
            #endif
            {
                float traceLength = far;
                vec4 wsrReflection = GetWSR(ViewToPlayer(reflectionStart), nViewPos, normalMR, nViewPosR, normalGradX, normalGradY,
                                            RVdotU, RVdotS, z0, dither, traceLength, wsrTranslucent,
                                            length(reflectionStart - viewPos));
                float wsrWeight = (1.0 - reflection.a) * wsrReflection.a;
                if (wsrWeight > reflection.a) refDist = traceLength;
                reflection.rgb += wsrReflection.rgb * wsrWeight;
                reflection.a += wsrWeight;
            }
        #endif

        #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0 && defined COMPOSITE
            // Translucents replace only covered background.
            if (wsrTranslucent) return SanitizeReflection(reflection);
        #endif

        #ifdef WSR_TRACE_PREPASS
            return vec4(0.0);
        #endif

        AddBackgroundReflection(reflection, color, playerPos, normalM, normalMR, nViewPos, nViewPosR,
                                shadowMult, RVdotU, RVdotS, z0, dither, skyLightFactor, smoothness, highlightMult);
    }
    // ============================== End of Step 3 ============================== //

    // Tweak for wsr water ref normals to look correct
    #if WORLD_SPACE_REFLECTIONS_INTERNAL > 0 && WATER_REFLECT_QUALITY >= 1
        normalM = normalMR;
    #endif

    return SanitizeReflection(reflection);
}
