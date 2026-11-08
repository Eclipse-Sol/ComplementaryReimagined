/////////////////////////////////////
// Complementary Shaders by EminGT //
/////////////////////////////////////

//Common//
#include "/lib/common.glsl"

//////////Fragment Shader//////////Fragment Shader//////////Fragment Shader//////////
#ifdef FRAGMENT_SHADER

in vec2 texCoord;

flat in vec4 glColor;

#ifdef OVERWORLD
    flat in vec3 upVec, sunVec;
#endif

//Pipeline Constants//

//Common Variables//
#ifdef OVERWORLD
    float SdotU = dot(sunVec, upVec);
    float sunVisibility = clamp(SdotU + 0.0625, 0.0, 0.125) / 0.125;
    float sunVisibility2 = sunVisibility * sunVisibility;
#endif

//Common Functions//

//Includes//
#include "/lib/colors/lightAndAmbientColors.glsl"

#ifdef OVERWORLD
    #include "/lib/atmospherics/sunMoonShading.glsl"
#endif

#ifdef COLOR_CODED_PROGRAMS
    #include "/lib/misc/colorCodedPrograms.glsl"
#endif

//Program//
void main() {
    #ifdef OVERWORLD
        vec2 tSize = textureSize(tex, 0);
        vec4 color = texture2D(tex, texCoord);
        color.rgb *= glColor.rgb;

        vec4 screenPos = vec4(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z, 1.0);
        vec4 viewPos = gbufferProjectionInverse * (screenPos * 2.0 - 1.0);
        viewPos /= viewPos.w;
        vec3 nViewPos = normalize(viewPos.xyz);

        float VdotS = dot(nViewPos, sunVec);
        float VdotU = dot(nViewPos, upVec);
        bool sunSideCheck = VdotS > 0.0;

        #ifdef IS_IRIS
            bool isSun = renderStage == MC_RENDER_STAGE_SUN;
            bool isMoon = renderStage == MC_RENDER_STAGE_MOON;
            #if IRIS_VERSION < 10814
                if (sunSideCheck) isSun = true; // Workaround for sun rendering as MC_RENDER_STAGE_MOON in some Iris versions
            #endif
        #else
            bool tSizeCheck = abs(tSize.y - 264.0) < 248.5; //tSize.y must range from 16 to 512
            bool isSun = tSizeCheck && sunSideCheck;
            bool isMoon = tSizeCheck && !sunSideCheck;
        #endif

        if (isSun || isMoon) {
            #if SUN_MOON_STYLE >= 2
                discard;
            #endif

            ShadeSunMoon(color.rgb, isSun, isMoon, VdotU);
        } else { // Custom Sky
            #if MC_VERSION >= 11300
                color.rgb *= color.rgb * smoothstep1(sqrt1(max0(VdotU)));
            #else
                discard;
                // Old mc custom skyboxes are weirdly broken, so we discard.
            #endif
        }

        FadeSkyTextured(color);
    #endif

    #ifdef NETHER
        vec4 color = vec4(0.0);
    #endif

    #ifdef END
        vec4 color = vec4(endSkyColor, 1.0);
    #endif

    #ifdef COLOR_CODED_PROGRAMS
        ColorCodeProgram(color, -1);
    #endif

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = color;
}

#endif

//////////Vertex Shader//////////Vertex Shader//////////Vertex Shader//////////
#ifdef VERTEX_SHADER

out vec2 texCoord;

flat out vec4 glColor;

#ifdef OVERWORLD
    flat out vec3 upVec, sunVec;
#endif

//Attributes//

//Common Variables//

//Common Functions//

//Includes//
#if defined OVERWORLD && defined WSR_SKY_OBJECTS
    #define CELESTIAL_BUFFER_QUALIFIER
    #include "/lib/voxelization/SSBOs/celestialQuadBuffer.glsl"

    void StoreSunMoonCorner() {
        vec3 viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
        vec3 nViewPos = normalize(viewPos);
        float VdotS = dot(nViewPos, sunVec);
        if (abs(VdotS) < 0.85) return;

        int body = VdotS > 0.0 ? 0 : 1;
        vec3 orbitNormal = mat3(gbufferModelView) * vec3(0.0, -SUN_ROTATION_DATA.y, SUN_ROTATION_DATA.x);
        vec3 orbitTangent = cross(sunVec, orbitNormal);
        int corner = body * 4 + int(dot(nViewPos, orbitTangent) > 0.0) + 2 * int(dot(nViewPos, orbitNormal) > 0.0);

        celestialQuads.corners[corner] = vec4(viewPos, 1.0);
        celestialQuads.texCoords[corner] = texCoord;
        celestialQuads.colors[body] = gl_Color;
        celestialQuads.frames[body] = frameCounter;
    }
#endif

//Program//
void main() {
    gl_Position = ftransform();
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    glColor = gl_Color;

    #ifdef OVERWORLD
        upVec = normalize(gbufferModelView[1].xyz);
        sunVec = GetSunVector();

        #ifdef WSR_SKY_OBJECTS
            StoreSunMoonCorner();
        #endif
    #endif
}

#endif
