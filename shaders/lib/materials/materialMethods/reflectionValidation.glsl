#ifndef INCLUDE_REFLECTION_VALIDATION
#define INCLUDE_REFLECTION_VALIDATION

bool IsFiniteReflection(vec4 value) {
    return !any(isnan(value)) && !any(isinf(value));
}

vec4 SanitizeReflection(vec4 value) {
    if (!IsFiniteReflection(value)) return vec4(0.0);
    return vec4(clamp(value.rgb, vec3(0.0), vec3(65504.0)), clamp(value.a, 0.0, 1.0));
}

vec3 BlendReflectionHistory(vec3 current, vec4 previous, float currentWeight) {
    if (!IsFiniteReflection(previous) || isnan(currentWeight) || isinf(currentWeight)) return current;
    return mix(previous.rgb, current, clamp(currentWeight, 0.0, 1.0));
}

#endif
