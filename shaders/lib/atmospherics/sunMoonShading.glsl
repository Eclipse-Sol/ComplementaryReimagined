#ifndef INCLUDE_SUN_MOON_SHADING
#define INCLUDE_SUN_MOON_SHADING

#ifdef CAVE_FOG
    #include "/lib/atmospherics/fog/caveFactor.glsl"
#endif

void ShadeSunMoon(inout vec3 color, bool isSun, bool isMoon, float VdotU) {
    if (isSun) {
        color = vec3(pow(dot(color, color) * 0.45, 6.0 - 5.0 * rainFactor));
        color *= mix(vec3(1.1, 0.55, 0.0), vec3(0.35), rainFactor * 0.75) * 4.5;
        color *= 0.25 + 0.75 * sunVisibility2 + 0.5 * noonFactor;
    }

    if (isMoon) {
        color *= smoothstep1(min1(length(color))) * 1.3;
    }

    color *= GetHorizonFactor(VdotU);

    #ifdef CAVE_FOG
        color *= 1.0 - 0.75 * GetCaveFactor();
    #endif
}

void FadeSkyTextured(inout vec4 color) {
    if (isEyeInWater == 1) color.rgb *= 0.25;

    #ifdef SUN_MOON_DURING_RAIN
        color.a *= 1.0 - 0.8 * rainFactor;
    #else
        color.a *= 1.0 - rainFactor;
    #endif
}

#endif
