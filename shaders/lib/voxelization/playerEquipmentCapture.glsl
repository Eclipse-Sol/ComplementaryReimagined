uniform writeonly image2D playerEquipment_img;

void capturePlayerEquipment() {
    if (entityId != 50017 || currentRenderedItemId <= 0) return;
    ivec2 sourceSize = textureSize(tex, 0);

    vec3 p0 = playerShadowPosition[0].xyz - 0.2 * playerLookVector;
    vec3 p1 = playerShadowPosition[1].xyz - 0.2 * playerLookVector;
    vec3 p2 = playerShadowPosition[2].xyz - 0.2 * playerLookVector;
    vec3 n = cross(p1 - p0, p2 - p0);
    if (dot(n, n) < 1e-14) return;

    uint slot = atomicAdd(playerVerticesSSBO.equipmentCount, 1u);
    if (slot >= uint(PLAYER_EQUIPMENT_CAPACITY)) {
        atomicOr(playerVerticesSSBO.equipmentOverflow, 1u);
        atomicMin(playerVerticesSSBO.equipmentCount, uint(PLAYER_EQUIPMENT_CAPACITY));
        return;
    }

    vec2 uv0 = playerShadowTexCoord[0], uv1 = playerShadowTexCoord[1], uv2 = playerShadowTexCoord[2];
    vec2 firstTexel = floor(min(uv0, min(uv1, uv2)) * vec2(sourceSize) + 0.001);
    vec2 endTexel = ceil(max(uv0, max(uv1, uv2)) * vec2(sourceSize) - 0.001);
    vec2 texelRectSize = max(endTexel - firstTexel, vec2(1.0));
    ivec2 tileSize = ivec2(min(texelRectSize, vec2(PLAYER_EQUIPMENT_TILE_SIZE)));
    ivec2 tileOrigin = getEquipmentTileOrigin(slot);

    uvec3 tileUVs = uvec3(
        packUnorm2x16(clamp((uv0 * vec2(sourceSize) - firstTexel) / texelRectSize, 0.0, 1.0)),
        packUnorm2x16(clamp((uv1 * vec2(sourceSize) - firstTexel) / texelRectSize, 0.0, 1.0)),
        packUnorm2x16(clamp((uv2 * vec2(sourceSize) - firstTexel) / texelRectSize, 0.0, 1.0))
    );
    // Large tiles copy only texels within half a texel of the UV triangle,
    // using the packed UVs the tracer samples.
    vec2 tileUV0 = unpackUnorm2x16(tileUVs.x) * vec2(tileSize);
    vec2 tileUV1 = unpackUnorm2x16(tileUVs.y) * vec2(tileSize);
    vec2 tileUV2 = unpackUnorm2x16(tileUVs.z) * vec2(tileSize);
    float uvArea = (tileUV1.x - tileUV0.x) * (tileUV2.y - tileUV0.y) - (tileUV1.y - tileUV0.y) * (tileUV2.x - tileUV0.x);
    bool clipRows = tileSize.x * tileSize.y >= 256;
    vec3 edgeStepX = vec3(tileUV0.y - tileUV1.y, tileUV1.y - tileUV2.y, tileUV2.y - tileUV0.y);
    vec3 edgeStepY = vec3(tileUV1.x - tileUV0.x, tileUV2.x - tileUV1.x, tileUV0.x - tileUV2.x);
    vec3 edgeOffset = vec3(tileUV0.x * tileUV1.y - tileUV0.y * tileUV1.x,
                           tileUV1.x * tileUV2.y - tileUV1.y * tileUV2.x,
                           tileUV2.x * tileUV0.y - tileUV2.y * tileUV0.x);
    if (uvArea < 0.0) { edgeStepX = -edgeStepX; edgeStepY = -edgeStepY; edgeOffset = -edgeOffset; }
    vec3 edgeMargin = 0.501 * (abs(edgeStepX) + abs(edgeStepY)) + 0.001;
    bvec3 horizontalEdge = lessThan(abs(edgeStepX), vec3(1e-8));
    vec3 invEdgeStepX = 1.0 / mix(edgeStepX, vec3(1.0), horizontalEdge);
    vec2 texelStep = texelRectSize / vec2(tileSize);
    for (int y = 0; y < tileSize.y; y++) {
        int firstX = 0, lastX = tileSize.x - 1;
        if (clipRows) {
            vec3 rowEdgeValue = edgeStepY * (float(y) + 0.5) + edgeOffset + edgeMargin;
            if (any(bvec3(horizontalEdge.x && rowEdgeValue.x < 0.0,
                          horizontalEdge.y && rowEdgeValue.y < 0.0,
                          horizontalEdge.z && rowEdgeValue.z < 0.0))) continue;
            vec3 edgeCrossX = -rowEdgeValue * invEdgeStepX - 0.5;
            for (int edge = 0; edge < 3; edge++) {
                if (edgeStepX[edge] > 1e-8) firstX = max(firstX, int(ceil(edgeCrossX[edge])));
                if (edgeStepX[edge] < -1e-8) lastX = min(lastX, int(floor(edgeCrossX[edge])));
            }
        }
        for (int x = firstX; x <= lastX; x++) {
            vec2 sourceTexel = firstTexel + (vec2(x, y) + 0.5) * texelStep;
            ivec2 sourceTexelCoord = clamp(ivec2(floor(sourceTexel)), ivec2(0), sourceSize - 1);
            imageStore(playerEquipment_img, tileOrigin + ivec2(x, y), texelFetch(tex, sourceTexelCoord, 0));
        }
    }

    playerEquipmentTriangle triangle;
    vec3 edge1 = p1 - p0, edge2 = p2 - p0;
    n = cross(edge1, edge2);
    float invNormalLengthSq = 1.0 / dot(n, n);
    vec3 rowU = cross(edge2, n) * invNormalLengthSq;
    vec3 rowV = cross(n, edge1) * invNormalLengthSq;
    playerVerticesSSBO.equipmentPlanes[slot] = vec4(n, dot(n, p0));
    triangle.barycentricU = vec4(rowU, -dot(rowU, p0));
    triangle.barycentricV = vec4(rowV, -dot(rowV, p0));
    triangle.tileUVs = uvec4(tileUVs, uint(tileSize.x) | (uint(tileSize.y) << 8u));
    triangle.vertexColors = uvec4(packUnorm4x8(playerShadowColor[0]),
                                  packUnorm4x8(playerShadowColor[1]),
                                  packUnorm4x8(playerShadowColor[2]), uint(max(playerShadowVertexID[0], max(playerShadowVertexID[1], playerShadowVertexID[2]))));
    playerVerticesSSBO.equipmentTriangles[slot] = triangle;

    uint group = slot / uint(PLAYER_EQUIPMENT_GROUP_SIZE);
    ivec3 boundsMin = ivec3(floor(min(p0, min(p1, p2)) * 1000.0)) - 1;
    ivec3 boundsMax = ivec3(ceil(max(p0, max(p1, p2)) * 1000.0)) + 1;
    for (int axis = 0; axis < 3; axis++) {
        atomicMin(playerVerticesSSBO.equipmentMin[axis], boundsMin[axis]);
        atomicMax(playerVerticesSSBO.equipmentMax[axis], boundsMax[axis]);
        atomicMin(playerVerticesSSBO.equipmentGroupMin[group][axis], boundsMin[axis]);
        atomicMax(playerVerticesSSBO.equipmentGroupMax[group][axis], boundsMax[axis]);
    }
}
