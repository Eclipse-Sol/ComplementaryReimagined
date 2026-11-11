#ifdef WSR_TRACE_PREPASS
    vec2 wsrLavaGradient;
#endif

vec4 GetLavaCornerHeights(ivec3 voxelPos) {
    return vec4(
        GetLavaCornerHeight(voxelPos),
        GetLavaCornerHeight(voxelPos + ivec3(1, 0, 0)),
        GetLavaCornerHeight(voxelPos + ivec3(0, 0, 1)),
        GetLavaCornerHeight(voxelPos + ivec3(1, 0, 1))
    );
}

float IntersectLavaSurface(vec3 localPos, vec3 rayDir, vec4 heights, float maxDist, out vec3 surfaceNormal) {
    vec2 slope = vec2(heights.y - heights.x, heights.z - heights.x);
    float twist = heights.x - heights.y - heights.z + heights.w;
    float height = heights.x + dot(slope, localPos.xz) + twist * localPos.x * localPos.z;
    vec2 gradient = slope + twist * localPos.zx;

    float c = localPos.y - height;
    float distance = 0.0;
    if (c > 0.00001) {
        float a = -twist * rayDir.x * rayDir.z;
        float b = rayDir.y - dot(gradient, rayDir.xz);
        if (abs(a) < 1e-7) {
            if (b >= -1e-7) return -1.0;
            distance = -c / b;
        } else {
            float discriminant = b * b - 4.0 * a * c;
            if (discriminant < 0.0) return -1.0;
            float root = sqrt(discriminant);
            distance = b < 0.0 ? 2.0 * c / (-b + root) : (-b - root) / (2.0 * a);
        }
        if (distance < 0.0 || distance > maxDist) return -1.0;
    }

    gradient += twist * distance * rayDir.zx;
    #ifdef WSR_TRACE_PREPASS
        wsrLavaGradient = gradient;
    #endif
    surfaceNormal = normalize(vec3(-gradient.x, 1.0, -gradient.y));
    return distance;
}
