vec2 projectToFace(vec3 v, vec3 normal) {
    vec3 absNormal = abs(normal);
    return v.zy * absNormal.x + v.xz * absNormal.y + v.xy * absNormal.z;
}

vec2 orientReflectionFaceVector(vec2 v, uint orientation) {
    v *= 1.0 - 2.0 * vec2((orientation >> 1u) & 1u, (orientation >> 2u) & 1u);
    return (orientation & 1u) != 0u ? v.yx : v;
}

uint getDefaultReflectionFaceOrientation(vec3 normal) {
    return (uint(normal.x < -0.5 || abs(normal.y) > 0.5 || normal.z > 0.5) << 1u)
         | (uint(normal.y > 0.5) << 2u);
}

vec3 getReflectionTerrainTangent(vec3 normal, vec3 tangent) {
    #if defined IS_IRIS && MC_VERSION >= 12111 && IRIS_VERSION >= 11005
        if (normal.z < 0.0 && normal.z > -0.001) {
            float inv = 1.0 / (1.0 - normal.z);
            vec3 oldU = vec3(1.0 - normal.x * normal.x * inv, -normal.x * normal.y * inv, normal.x);
            vec3 oldV = vec3(normal.x * normal.y * inv, -1.0 + normal.y * normal.y * inv, -normal.y);
            vec2 n = normalize(normal.xy);
            vec3 newU = vec3(1.0 - n.x * n.x, -n.x * n.y, -n.x);
            vec3 newV = vec3(-n.x * n.y, 1.0 - n.y * n.y, -n.y);
            tangent = newU * dot(tangent, oldU) + newV * dot(tangent, oldV);
        }
    #endif
    return tangent;
}

#if defined SHADOW && defined VERTEX_SHADER
void getReflectionTerrainBasis(vec3 terrainNormal, vec4 terrainTangent,
                               out vec3 normal, out vec3 tangent, out vec3 bitangent) {
    mat3 normalToWorld = mat3(shadowModelViewInverse) * gl_NormalMatrix;
    normal = normalize(normalToWorld * terrainNormal);
    tangent = normalize(normalToWorld * getReflectionTerrainTangent(terrainNormal, terrainTangent.xyz));
    bitangent = normalize(cross(tangent, normal)) * terrainTangent.w;
}

uint getReflectionFaceOrientation(vec3 normal, vec4 terrainTangent) {
    if (abs(terrainTangent.w) < 0.5 || dot(terrainTangent.xyz, terrainTangent.xyz) < 1e-6) return 0u;

    vec3 basisNormal, tangent, bitangent;
    getReflectionTerrainBasis(gl_Normal, terrainTangent, basisNormal, tangent, bitangent);
    vec2 u = projectToFace(tangent, normal);
    vec2 v = projectToFace(bitangent, normal);
    bool swap = abs(u.y) > abs(u.x);
    bool flipU = (swap ? u.y : u.x) > 0.0;
    bool flipV = (swap ? v.x : v.y) > 0.0;
    uint orientation = uint(swap) | (uint(swap ? flipV : flipU) << 1u)
                                  | (uint(swap ? flipU : flipV) << 2u);
    return orientation ^ getDefaultReflectionFaceOrientation(normal);
}
#endif
