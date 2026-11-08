void mergePlayerBounds() {
    ivec3 boundsMin = playerVerticesSSBO.headMin, boundsMax = playerVerticesSSBO.headMax;
    boundsMin = min(boundsMin, playerVerticesSSBO.torsoMin); boundsMax = max(boundsMax, playerVerticesSSBO.torsoMax);
    boundsMin = min(boundsMin, playerVerticesSSBO.leftLegMin); boundsMax = max(boundsMax, playerVerticesSSBO.leftLegMax);
    boundsMin = min(boundsMin, playerVerticesSSBO.rightLegMin); boundsMax = max(boundsMax, playerVerticesSSBO.rightLegMax);
    boundsMin = min(boundsMin, playerVerticesSSBO.leftHandMin); boundsMax = max(boundsMax, playerVerticesSSBO.leftHandMax);
    boundsMin = min(boundsMin, playerVerticesSSBO.rightHandMin); boundsMax = max(boundsMax, playerVerticesSSBO.rightHandMax);
    if (playerVerticesSSBO.equipmentOverflow == 0u && playerVerticesSSBO.equipmentCount != 0u) {
        boundsMin = min(boundsMin, playerVerticesSSBO.equipmentMin.xyz);
        boundsMax = max(boundsMax, playerVerticesSSBO.equipmentMax.xyz);
    }
    if (any(lessThan(boundsMax, boundsMin))) { boundsMin = ivec3(0); boundsMax = ivec3(0); }
    playerVerticesSSBO.playerMin = ivec4(boundsMin, 0);
    playerVerticesSSBO.playerMax = ivec4(boundsMax, 0);
}
