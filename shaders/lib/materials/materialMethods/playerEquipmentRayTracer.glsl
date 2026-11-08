bool rayHitsBox(vec3 origin, vec3 invDirection, ivec3 boxMin, ivec3 boxMax, float maxDistance) {
    vec3 t0 = (vec3(boxMin) - origin) * invDirection;
    vec3 t1 = (vec3(boxMax) - origin) * invDirection;
    vec3 tNear = min(t0, t1), tFar = max(t0, t1);
    float tEnter = max(max(tNear.x, tNear.y), tNear.z);
    float tExit = min(min(tFar.x, tFar.y), tFar.z);
    return tExit > max(0.0, tEnter) && tEnter <= maxDistance;
}

void rayTracePlayerEquipment(vec3 origin, vec3 direction, inout float nearest,
                             inout vec3 albedo, inout vec3 normal) {
    if (playerVerticesSSBO.equipmentOverflow != 0u) return;
    uint count = min(playerVerticesSSBO.equipmentCount, uint(PLAYER_EQUIPMENT_CAPACITY));
    if (count == 0u) return;
    vec3 fixedPointOrigin = origin * 1000.0;
    vec3 invDirection = safeRcp(direction);
    if (!rayHitsBox(fixedPointOrigin, invDirection,
            playerVerticesSSBO.equipmentMin.xyz, playerVerticesSSBO.equipmentMax.xyz, nearest * 1000.0)) return;
    float rayLength = nearest;
    uint hitIndex = uint(PLAYER_EQUIPMENT_CAPACITY), hitOrder = 0u;
    vec3 hitNormal = vec3(0.0);
    vec3 hitBarycentrics = vec3(0.0), hitTexelColor = vec3(0.0);
    uint groups = (count + uint(PLAYER_EQUIPMENT_GROUP_SIZE - 1)) / uint(PLAYER_EQUIPMENT_GROUP_SIZE);
    for (uint group = 0u; group < groups; group++) {
        if (!rayHitsBox(fixedPointOrigin, invDirection, playerVerticesSSBO.equipmentGroupMin[group].xyz,
                            playerVerticesSSBO.equipmentGroupMax[group].xyz, nearest * 1000.0)) continue;
        uint end = min(count, (group + 1u) * uint(PLAYER_EQUIPMENT_GROUP_SIZE));
        for (uint index = group * uint(PLAYER_EQUIPMENT_GROUP_SIZE); index < end; index++) {
            vec4 plane = playerVerticesSSBO.equipmentPlanes[index];
            float normalDotRay = dot(plane.xyz, direction);
            if (abs(normalDotRay) < 1e-10) continue;
            float rayDistance = (plane.w - dot(plane.xyz, origin)) / normalDotRay;
            if (rayDistance < 0.0 || rayDistance > rayLength) continue;
            if (rayDistance > nearest) {
                if (hitIndex >= uint(PLAYER_EQUIPMENT_CAPACITY)) continue;
                float depthGap = (rayDistance - nearest) * normalDotRay;
                if (depthGap * depthGap > 4e-10 * dot(plane.xyz, plane.xyz)) continue;
            }
            playerEquipmentTriangle triangle = playerVerticesSSBO.equipmentTriangles[index];
            vec3 point = origin + rayDistance * direction;
            float u = dot(triangle.barycentricU.xyz, point) + triangle.barycentricU.w;
            float v = dot(triangle.barycentricV.xyz, point) + triangle.barycentricV.w;
            if (u < 0.0 || v < 0.0 || u + v > 1.0) continue;

            bool coplanar = false;
            if (hitIndex < uint(PLAYER_EQUIPMENT_CAPACITY)) {
                float normalLengthSq = dot(plane.xyz, plane.xyz);
                float depthGap = (rayDistance - nearest) * normalDotRay;
                if (depthGap * depthGap <= 4e-10 * normalLengthSq) {
                    float alignment = dot(plane.xyz, hitNormal);
                    coplanar = alignment * alignment >= 0.99999 * normalLengthSq * dot(hitNormal, hitNormal);
                }
                if (coplanar && triangle.vertexColors.w <= hitOrder) continue;
            }
            if (rayDistance > nearest && !coplanar) continue;

            vec3 barycentrics = vec3(1.0 - u - v, u, v);
            vec2 uv = barycentrics.x * unpackUnorm2x16(triangle.tileUVs.x)
                    + barycentrics.y * unpackUnorm2x16(triangle.tileUVs.y)
                    + barycentrics.z * unpackUnorm2x16(triangle.tileUVs.z);
            ivec2 tileSize = ivec2(triangle.tileUVs.w & 255u, (triangle.tileUVs.w >> 8u) & 255u);
            ivec2 texelCoord = clamp(ivec2(floor(uv * vec2(tileSize))), ivec2(0), tileSize - 1);
            vec4 texelColor = texelFetch(playerEquipment_sampler, getEquipmentTileOrigin(index) + texelCoord, 0);
            float alpha = barycentrics.x * unpackUnorm4x8(triangle.vertexColors.x).a
                        + barycentrics.y * unpackUnorm4x8(triangle.vertexColors.y).a
                        + barycentrics.z * unpackUnorm4x8(triangle.vertexColors.z).a;
            if (texelColor.a * alpha <= 0.2) continue;
            hitIndex = index;
            hitOrder = triangle.vertexColors.w;
            hitNormal = plane.xyz;
            hitBarycentrics = barycentrics;
            hitTexelColor = texelColor.rgb;
            nearest = rayDistance;
        }
    }
    if (hitIndex < uint(PLAYER_EQUIPMENT_CAPACITY)) {
        playerEquipmentTriangle triangle = playerVerticesSSBO.equipmentTriangles[hitIndex];
        vec3 tint = hitBarycentrics.x * unpackUnorm4x8(triangle.vertexColors.x).rgb
                  + hitBarycentrics.y * unpackUnorm4x8(triangle.vertexColors.y).rgb
                  + hitBarycentrics.z * unpackUnorm4x8(triangle.vertexColors.z).rgb;
        albedo = hitTexelColor * tint;
        normal = normalize(hitNormal);
        if (dot(normal, direction) > 0.0) normal = -normal;
    }
}
